"""HTTPS deployment adapter; serve behind an origin-pinned, loopback reverse proxy."""
import hmac
import json
import mimetypes
import os
import threading
import time
from collections import defaultdict, deque
from http import HTTPStatus
from http.cookies import SimpleCookie
from pathlib import Path
from urllib.parse import urlparse

from store import Invalid, Store
import capture

PUBLIC = Path(__file__).resolve().parent.parent / 'public'
ASSETS = {name: PUBLIC / name.lstrip('/') for name in (
    '/index.html', '/app.js', '/sync.js', '/model.js', '/smart.js', '/pomodoro.js', '/style.css', '/sw.js', '/manifest.webmanifest',
    '/icon.svg', '/brand.png', '/icon-192.png', '/icon-512.png', '/tolk-add-task.shortcut')}
ASSETS['/'] = PUBLIC / 'index.html'
COOKIE = '__Host-tolk_session'


def create_app(store, origin, setup_secret=''):
    parsed = urlparse(origin)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.path not in ('', '/') or parsed.query or parsed.fragment:
        raise ValueError('An explicit HTTPS origin is required')
    origin = origin.rstrip('/')
    attempts, mutex = defaultdict(deque), threading.Lock()

    def application(environ, start_response):
        path = environ.get('PATH_INFO', '/')
        method = environ.get('REQUEST_METHOD', 'GET')

        def reply(status, data, cookie=None, mime='application/json; charset=utf-8'):
            if path.startswith('/api/capture') and status >= 400 and isinstance(data, dict): data = {'message':data.get('error', 'Не удалось добавить задачу'), **data}
            body = json.dumps(data, ensure_ascii=False).encode() if isinstance(data, dict) else data
            headers = [('Content-Type', mime), ('Content-Length', str(len(body))),
                       ('Cache-Control', 'no-store' if path.startswith('/api/') else 'no-cache'),
                       ('X-Content-Type-Options', 'nosniff'), ('Referrer-Policy', 'same-origin'),
                       ('Strict-Transport-Security', 'max-age=86400'),
                       ('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")]
            if cookie:
                headers.append(('Set-Cookie', cookie))
            start_response(f'{status} {HTTPStatus(status).phrase}', headers)
            return [body]

        if environ.get('HTTP_HOST') != parsed.netloc:
            return reply(403, {'error':'Недопустимый адрес'})
        try:
            cookies = SimpleCookie()
            cookies.load(environ.get('HTTP_COOKIE', ''))
            token = cookies[COOKIE].value if COOKIE in cookies else ''
        except Exception:
            token = ''
        if method == 'GET':
            if path == '/api/session':
                can_setup = bool(setup_secret) and not store.configured()
                return reply(200, {'account':store.account(token), 'canSetup':can_setup, 'activationRequired':can_setup})
            target = ASSETS.get(path)
            if target and target.is_file():
                return reply(200, target.read_bytes(), mime=mimetypes.guess_type(target.name)[0] or 'application/octet-stream')
            return reply(404, {'error':'Не найдено'})
        if method != 'POST':
            return reply(405, {'error':'Метод не поддерживается'})
        capture_request = path in {'/api/capture','/api/capture/options'}
        native = path in {'/api/device/start','/api/device/poll','/api/device/sync','/api/device/logout'} and not environ.get('HTTP_ORIGIN')
        if capture_request and environ.get('HTTP_ORIGIN') not in (None, '', origin):
            return reply(403, {'error':'Недопустимый источник запроса'})
        if not native and not capture_request and environ.get('HTTP_ORIGIN') != origin:
            return reply(403, {'error':'Недопустимый источник запроса'})
        if environ.get('CONTENT_TYPE', '').split(';')[0] != 'application/json':
            return reply(415, {'error':'Ожидается JSON'})
        try:
            length = int(environ.get('CONTENT_LENGTH', '0'))
            if not 0 < length <= 8 * 1024 * 1024:
                return reply(413, {'error':'Слишком большой запрос'})
            body = json.loads(environ['wsgi.input'].read(length))
            if not isinstance(body, dict):
                raise Invalid('Некорректный запрос')
            if path in {'/api/setup', '/api/login','/api/device/start','/api/device/poll'}:
                # Nginx overwrites X-Real-IP and only proxies to a loopback container port.
                remote = environ.get('HTTP_X_REAL_IP', environ.get('REMOTE_ADDR', 'unknown'))
                with mutex:
                    now = time.monotonic()
                    for ip in list(attempts):
                        if not attempts[ip] or attempts[ip][-1] < now - 60:
                            del attempts[ip]
                    history = attempts[(remote,'poll' if path == '/api/device/poll' else 'login')]
                    while history and history[0] < now - 60:
                        history.popleft()
                    if len(history) >= (90 if path == '/api/device/poll' else 10):
                        return reply(429, {'error':'Слишком много попыток. Подождите минуту.'})
                    history.append(now)
                if path == '/api/device/start': return reply(200,store.begin_pairing(body.get('name')))
                if path == '/api/device/poll': return reply(200,store.poll_pairing(body.get('code'),body.get('secret')))
                if path == '/api/setup':
                    code = body.get('setupCode')
                    if not setup_secret or not isinstance(code, str) or not code.isascii() or not hmac.compare_digest(code, setup_secret):
                        return reply(403, {'error':'Неверный код активации'})
                    store.create_account(body.get('name'), body.get('password'))
                result = store.login(body.get('name'), body.get('password'))
                if not result:
                    return reply(401, {'error':'Неверное имя или пароль'})
                token, account = result
                return reply(200, {'account':account}, f'{COOKIE}={token}; Secure; HttpOnly; SameSite=Strict; Path=/; Max-Age=2592000')
            if capture_request:
                remote = environ.get('HTTP_X_REAL_IP', environ.get('REMOTE_ADDR', 'unknown'))
                with mutex:
                    now = time.monotonic()
                    for key in list(attempts):
                        if not attempts[key] or attempts[key][-1] < now - 60: del attempts[key]
                    history = attempts[(remote, 'capture')]
                    while history and history[0] < now - 60: history.popleft()
                    if len(history) >= 60: return reply(429, {'error':'Слишком много запросов. Подождите минуту.'})
                    history.append(now)
                header = environ.get('HTTP_AUTHORIZATION', '')
                token = header[7:].strip() if header.startswith('Bearer ') else ''
                return reply(200, capture.options(store, token) if path == '/api/capture/options' else capture.create_task(store, token, body))
            if native:
                header=environ.get('HTTP_AUTHORIZATION','')
                token=header[7:] if header.startswith('Bearer ') else ''
                account=store.device_account(token)
            else: account = store.account(token)
            if not account:
                return reply(401, {'error':'Войдите в аккаунт'})
            if path == '/api/capture/token': return reply(200, capture.issue(store, account['id'], body.get('name')))
            if path == '/api/capture/tokens': return reply(200, {'tokens':capture.tokens(store, account['id'])})
            if path == '/api/capture/revoke':
                capture.revoke(store, account['id'], body.get('id')); return reply(200, {'ok':True})
            if path == '/api/logout':
                store.logout(token)
                return reply(200, {'ok':True}, f'{COOKIE}=; Secure; HttpOnly; SameSite=Strict; Path=/; Max-Age=0')
            if path == '/api/push/key':
                from push import public_key
                key=os.environ.get('TOLK_VAPID_KEY_FILE','')
                if not key or not Path(key).is_file(): return reply(503,{'error':'Напоминания ещё подготавливаются на сервере'})
                return reply(200,{'key':public_key(key)})
            if path == '/api/push/subscribe':
                from push import subscribe
                subscribe(store,account['id'],body.get('subscription'));return reply(200,{'ok':True})
            if path == '/api/push/unsubscribe':
                from push import unsubscribe
                unsubscribe(store,account['id'],body.get('endpoint'));return reply(200,{'ok':True})
            if path == '/api/device/info': return reply(200,store.pairing_info(body.get('code')))
            if path == '/api/device/approve': return reply(200,store.approve_pairing(account['id'],body.get('code')))
            if path == '/api/devices': return reply(200,{'devices':store.devices(account['id'])})
            if path == '/api/device/revoke':
                store.revoke_device(account['id'],body.get('id'));return reply(200,{'ok':True})
            if path == '/api/device/logout':
                store.revoke_device(account['id'],store.token_hash(token));return reply(200,{'ok':True})
            if path in {'/api/sync','/api/device/sync'}:
                if (body.get('epoch') and body['epoch'] != store.epoch) or store.cursor_ahead(account['id'],body.get('cursor',0)): return reply(409,{'error':'Сервер восстановлен. Проверьте локальные изменения перед отправкой.','serverReset':True,'epoch':store.epoch})
                if native and body.get('operations') and not body.get('epoch'): return reply(409,{'error':'Сначала получите актуальное состояние сервера'})
                return reply(200, store.sync(account['id'], body.get('operations', []), body.get('cursor', 0),body.get('epoch'),native=native))

            return reply(404, {'error':'Не найдено'})
        except capture.Unauthorized as error:
            return reply(401, {'error':str(error)})
        except (Invalid, json.JSONDecodeError, ValueError) as error:
            if isinstance(error,Invalid) and str(error)=='Неизвестная исходная версия': return reply(409,{'error':'Сервер восстановлен. Сверьте версии локальных изменений.','serverReset':True,'epoch':store.epoch})
            return reply(400, {'error':str(error) if isinstance(error, Invalid) else 'Некорректный запрос'})
        except Exception:
            return reply(500, {'error':'Не удалось сохранить изменения. Повторите попытку.'})
    return application


def production_app():
    secret_path = os.environ.get('TOLK_SETUP_SECRET_FILE', '')
    secret = Path(secret_path).read_text().strip() if secret_path else ''
    return create_app(Store(os.environ['TOLK_DATABASE']), os.environ['TOLK_ORIGIN'], secret)
