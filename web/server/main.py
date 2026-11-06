"""Loopback-only development server. A public deployment needs a production server/TLS."""
import argparse
import json
import mimetypes
import time
from collections import defaultdict, deque
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from store import Invalid, Store

PUBLIC = Path(__file__).resolve().parent.parent / "public"


def server(store, port=8787, setup=False):
    attempts = defaultdict(deque)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass  # Request bodies, account names and session material never enter logs.

        def reply(self, status, data, cookie=None, content_type="application/json; charset=utf-8"):
            body = json.dumps(data, ensure_ascii=False).encode() if isinstance(data, dict) else data
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store" if self.path.startswith("/api/") else "no-cache")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "same-origin")
            self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
            if cookie:
                self.send_header("Set-Cookie", cookie)
            self.end_headers()
            self.wfile.write(body)

        def trusted_host(self):
            return self.headers.get("Host") in {f"localhost:{self.server.server_port}", f"127.0.0.1:{self.server.server_port}"}

        def token(self):
            cookie = SimpleCookie()
            try:
                cookie.load(self.headers.get("Cookie", ""))
                return cookie["tolk_session"].value if "tolk_session" in cookie else ""
            except Exception:
                return ""

        def do_GET(self):
            if not self.trusted_host():
                return self.reply(403, {"error": "Недопустимый адрес"})
            path = urlparse(self.path).path
            if path == "/api/session":
                return self.reply(200, {"account": store.account(self.token()), "canSetup": setup and not store.configured()})
            allowed = {"/": "index.html", "/index.html": "index.html", "/app.js": "app.js", "/sync.js": "sync.js", "/model.js": "model.js", "/smart.js": "smart.js", "/pomodoro.js": "pomodoro.js", "/style.css": "style.css", "/sw.js": "sw.js", "/manifest.webmanifest": "manifest.webmanifest", "/icon.svg": "icon.svg", "/brand.png": "brand.png", "/icon-192.png": "icon-192.png", "/icon-512.png": "icon-512.png"}
            target = PUBLIC / allowed.get(path, "__missing__")
            if not target.is_file():
                return self.reply(404, {"error": "Не найдено"})
            mime = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
            self.reply(200, target.read_bytes(), content_type=mime)

        def do_POST(self):
            if not self.trusted_host() or self.headers.get("Origin") != "http://" + self.headers.get("Host", ""):
                return self.reply(403, {"error": "Недопустимый источник запроса"})
            if self.headers.get("Content-Type", "").split(";")[0] != "application/json":
                return self.reply(415, {"error": "Ожидается JSON"})
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 8 * 1024 * 1024:
                    return self.reply(413, {"error": "Слишком большой запрос"})
                body = json.loads(self.rfile.read(length))
                if not isinstance(body, dict):
                    raise Invalid("Некорректный запрос")
                path = urlparse(self.path).path
                if path in {"/api/login", "/api/setup"}:
                    now = time.monotonic()
                    history = attempts[self.client_address[0]]
                    while history and history[0] < now - 60:
                        history.popleft()
                    if len(history) >= 10:
                        return self.reply(429, {"error": "Слишком много попыток. Подождите минуту."})
                    history.append(now)
                    if path == "/api/setup":
                        if not setup:
                            return self.reply(403, {"error": "Создание аккаунта выключено"})
                        store.create_account(body.get("name"), body.get("password"))
                    result = store.login(body.get("name"), body.get("password"))
                    if not result:
                        return self.reply(401, {"error": "Неверное имя или пароль"})
                    token, account = result
                    return self.reply(200, {"account": account}, f"tolk_session={token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=2592000")
                account = store.account(self.token())
                if not account:
                    return self.reply(401, {"error": "Войдите в аккаунт"})
                if path == "/api/logout":
                    store.logout(self.token())
                    return self.reply(200, {"ok": True}, "tolk_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0")
                if path == "/api/sync":
                    return self.reply(200, store.sync(account["id"], body.get("operations", []), body.get("cursor", 0)))
                return self.reply(404, {"error": "Не найдено"})
            except (Invalid, json.JSONDecodeError, ValueError) as error:
                return self.reply(400, {"error": str(error) if isinstance(error, Invalid) else "Некорректный запрос"})
            except Exception:
                return self.reply(500, {"error": "Не удалось сохранить изменения. Повторите попытку."})

    return ThreadingHTTPServer(("127.0.0.1", port), Handler)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=str(Path(__file__).resolve().parent.parent / ".local" / "account.sqlite"))
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--setup", action="store_true", help="Allow creating the first local account")
    args = parser.parse_args()
    Path(args.db).parent.mkdir(parents=True, exist_ok=True)
    instance = server(Store(args.db), args.port, args.setup)
    print(f"Толк · локальная разработка: http://localhost:{instance.server_port}", flush=True)
    instance.serve_forever()
