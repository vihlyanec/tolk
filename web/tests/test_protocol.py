import concurrent.futures
import http.client
import json
import sys
import tempfile
import threading
import unittest
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'server'))
from store import Invalid, Store
from main import server


def uid():
    return str(uuid.uuid4())


def operation(entity=None, base=0, patch=None, kind='task', expected=None):
    result = dict(id=uid(), entityID=entity or uid(), base=base, kind=kind,
                  patch=patch or {'title': 'Тестовая задача', 'completed': False})
    if expected is not None:
        result['expected'] = expected
    return result


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.store = Store(Path(self.temp.name) / 'test.sqlite')
        self.account = self.store.create_account('Тест', 'test-only-passphrase')['id']

    def tearDown(self):
        self.temp.cleanup()

    def send(self, *ops, cursor=0):
        return self.store.sync(self.account, list(ops), cursor)

    def test_two_clients_create_edit_complete(self):
        create = operation()
        first = self.send(create)
        second = self.send()
        self.assertEqual(second['changes'][0]['id'], create['entityID'])
        change = operation(create['entityID'], 1, {'completed': True})
        self.send(change, cursor=second['cursor'])
        fetched = self.send(cursor=first['cursor'])
        self.assertTrue(fetched['changes'][0]['data']['completed'])

    def test_retry_is_idempotent_and_survives_restart(self):
        op = operation()
        first = self.send(op)
        self.store = Store(self.store.path)
        second = self.send(op)
        self.assertEqual(first, second)
        self.assertEqual(len(second['changes']), 1)

    def test_reused_operation_id_with_other_payload_is_rejected(self):
        op = operation()
        self.send(op)
        op['patch']['title'] = 'Другой текст'
        with self.assertRaises(Invalid): self.send(op)

    def test_independent_fields_merge(self):
        op = operation()
        self.send(op)
        self.send(operation(op['entityID'], 1, {'title': 'Новый заголовок'}))
        result = self.send(operation(op['entityID'], 1, {'completed': True}))['results'][0]
        self.assertTrue(result['accepted'])
        self.assertEqual({k:v for k,v in result['record']['data'].items() if k!='modified'}, {'title': 'Новый заголовок', 'completed': True})
        self.assertIsInstance(result['record']['data']['modified'], float)

    def test_same_field_conflict_preserves_remote_and_allows_resolution(self):
        op = operation()
        self.send(op)
        self.send(operation(op['entityID'], 1, {'title': 'С Mac'}))
        local = operation(op['entityID'], 1, {'title': 'С телефона'})
        conflict = self.send(local)['results'][0]
        self.assertFalse(conflict['accepted'])
        self.assertEqual(conflict['record']['data']['title'], 'С Mac')
        self.assertEqual(conflict['fields'], ['title'])
        resolved = self.send(operation(op['entityID'], 2, local['patch']))['results'][0]
        self.assertTrue(resolved['accepted'])

    def test_offline_sequential_edits_use_expected_predecessor(self):
        op = operation()
        self.send(op)
        self.send(operation(op['entityID'], 1, {'title': 'Первый ввод'}))
        follow = operation(op['entityID'], 1, {'title': 'Второй ввод'}, expected={'title': 'Первый ввод'})
        self.assertTrue(self.send(follow)['results'][0]['accepted'])

    def test_expected_does_not_overwrite_concurrent_other_field(self):
        op = operation(patch={'title':'Начало', 'body':'До'})
        self.send(op)
        self.send(operation(op['entityID'], 1, {'body':'Правка на другом устройстве'}))
        self.send(operation(op['entityID'], 1, {'title':'Локальный заголовок'}))
        follow = operation(op['entityID'], 1, {'body':'Моя правка'}, expected={'body':'До'})
        self.assertFalse(self.send(follow)['results'][0]['accepted'])

    def test_delete_does_not_silently_destroy_concurrent_edit(self):
        op = operation()
        self.send(op)
        self.send(operation(op['entityID'], 1, {'title':'После правки'}))
        result = self.send(operation(op['entityID'], 1, {'deleted':True}))['results'][0]
        self.assertFalse(result['accepted'])
        deleted = self.send(operation(op['entityID'], 2, {'deleted':True}))['results'][0]
        self.assertTrue(deleted['record']['data']['deleted'])
        self.assertFalse(self.send(operation(op['entityID'], 2, {'title':'Поздняя офлайн-правка'}))['results'][0]['accepted'])

    def test_account_scope_and_settings(self):
        op = operation()
        self.send(op)
        other = uid()
        self.assertEqual(self.store.sync(other, [], 0)['changes'], [])
        pref = operation(self.account, patch={'theme':'dark','timeZone':'Europe/Moscow'}, kind='settings')
        self.send(pref)
        loaded = [r for r in self.send()['changes'] if r['kind'] == 'settings']
        self.assertEqual(loaded[0]['data']['theme'], 'dark')
        pref['entityID'] = other
        with self.assertRaises(Invalid): self.send(pref)

    def test_invalid_batch_rolls_back_every_record(self):
        good, bad = operation(), operation(patch={'title': '  '})
        with self.assertRaises(Invalid): self.send(good, bad)
        self.assertEqual(self.send()['changes'], [])
        self.assertTrue(self.send(good)['results'][0]['accepted'])

    def test_project_scope_dates_and_setting_validation(self):
        for patch in ({'title':'x','date':'2026-02-30'}, {'title':'x','time':'15:99'}, {'title':'x','time':'10:00'},
                      {'title':'x','projectID':uid()}, {'title':'x','priority':True}, {'title':'x','unknown':'x'}):
            with self.assertRaises(Invalid): self.send(operation(patch=patch))
        for patch in ({'theme':'wrong'}, {'timeZone':'not-a-zone'}, {'startHour':23,'endHour':7}):
            with self.assertRaises(Invalid): self.send(operation(self.account,patch=patch,kind='settings'))
        project = operation(patch={'title':'Работа','color':'598BFF'},kind='project')
        self.send(project)
        self.assertTrue(self.send(operation(patch={'title':'Задача','projectID':project['entityID']}))['results'][0]['accepted'])

    def test_concurrent_retries_create_one_record(self):
        op = operation()
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
            results = list(pool.map(lambda _: self.send(op), range(10)))
        self.assertTrue(all(r['results'][0]['accepted'] for r in results))
        self.assertEqual(len(self.send()['changes']), 1)

    def test_cursor_pagination_does_not_skip_changes(self):
        for _ in range(6): self.send(*(operation() for _ in range(100)))
        first = self.send()
        self.assertTrue(first['more'])
        second = self.send(cursor=first['cursor'])
        self.assertEqual(len(first['changes']) + len(second['changes']), 600)
        self.assertEqual(len({r['id'] for r in first['changes'] + second['changes']}), 600)

    def test_credentials_and_session_revocation(self):
        self.assertIsNone(self.store.login('Тест', 'wrong-password'))
        self.assertIsNone(self.store.login('Другой', 'test-only-passphrase'))
        token, account = self.store.login('Тест', 'test-only-passphrase')
        self.assertEqual(self.store.account(token), account)
        self.store.logout(token)
        self.assertIsNone(self.store.account(token))
        with self.assertRaises(Invalid): self.store.create_account('Другой', 'test-only-passphrase')


class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.store = Store(Path(self.temp.name) / 'http.sqlite')
        self.http = server(self.store, 0, setup=True)
        self.thread = threading.Thread(target=self.http.serve_forever, daemon=True)
        self.thread.start()
        self.origin = f'http://localhost:{self.http.server_port}'

    def tearDown(self):
        self.http.shutdown(); self.http.server_close(); self.thread.join(); self.temp.cleanup()

    def request(self, path, body=None, cookie='', origin=None, host=None):
        connection = http.client.HTTPConnection('localhost', self.http.server_port)
        headers = {'Origin': self.origin if origin is None else origin, 'Content-Type':'application/json', 'Cookie':cookie}
        if host: headers['Host'] = host
        connection.request('GET' if body is None else 'POST', path, body=None if body is None else json.dumps(body), headers=headers)
        response = connection.getresponse()
        status, response_headers, data = response.status, dict(response.getheaders()), response.read()
        connection.close()
        return status, response_headers, data

    def test_auth_boundary_setup_csrf_and_logout(self):
        self.assertEqual(self.request('/api/sync', {})[0], 401)
        credentials = {'name':'QA','password':'test-only-passphrase'}
        self.assertEqual(self.request('/api/setup', credentials, origin='https://evil.example')[0], 403)
        self.assertEqual(self.request('/api/session', host='evil.example')[0], 403)
        status, headers, _ = self.request('/api/setup', credentials)
        self.assertEqual(status, 200)
        cookie = headers['Set-Cookie'].split(';')[0]
        self.assertIn('HttpOnly', headers['Set-Cookie'])
        self.assertIn('SameSite=Strict', headers['Set-Cookie'])
        self.assertEqual(self.request('/api/sync', {'operations':[operation()], 'cursor':0}, cookie)[0], 200)
        self.assertEqual(self.request('/api/logout', {}, cookie)[0], 200)
        self.assertEqual(self.request('/api/sync', {}, cookie)[0], 401)
        self.assertEqual(self.request('/api/setup', credentials)[0], 400)

    def test_static_allowlist_no_secrets_and_correct_cache(self):
        for path in ('/', '/app.js', '/sync.js', '/style.css', '/sw.js', '/manifest.webmanifest', '/icon-192.png', '/icon-512.png'):
            self.assertEqual(self.request(path)[0], 200, path)
        for path in ('/../server/store.py', '/server/main.py', '/.local/account.sqlite'):
            self.assertEqual(self.request(path)[0], 404)
        status, headers, data = self.request('/api/session')
        self.assertEqual(headers['Cache-Control'], 'no-store')
        self.assertNotIn(b'password', data)


if __name__ == '__main__': unittest.main()
