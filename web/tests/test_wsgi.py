import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'server'))
from store import Store
from wsgi import create_app
from backup import backup


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.store = Store(Path(self.temp.name) / 'production.sqlite')
        self.app = create_app(self.store, 'https://tolk.example.test', 'test-activation-only')

    def tearDown(self): self.temp.cleanup()

    def request(self, path, body=None, **headers):
        data = json.dumps(body).encode() if body is not None else b''
        environ = {'PATH_INFO':path, 'REQUEST_METHOD':'POST' if body is not None else 'GET',
                   'HTTP_HOST':'tolk.example.test', 'HTTP_ORIGIN':'https://tolk.example.test',
                   'CONTENT_TYPE':'application/json', 'CONTENT_LENGTH':str(len(data)),
                   'wsgi.input':io.BytesIO(data), **headers}
        result = {}
        def response(status, response_headers):
            result.update(status=int(status[:3]), headers=dict(response_headers))
        raw = b''.join(self.app(environ, response))
        result['body'] = json.loads(raw) if result['headers']['Content-Type'].startswith('application/json') else raw
        return result

    def test_activation_protects_first_account_and_cookie_is_secure(self):
        state = self.request('/api/session')['body']
        self.assertTrue(state['activationRequired'])
        credentials = {'name':'QA','password':'production-test-only'}
        self.assertEqual(self.request('/api/setup',credentials)['status'],403)
        self.assertFalse(self.store.configured())
        result = self.request('/api/setup', credentials | {'setupCode':'test-activation-only'})
        self.assertEqual(result['status'],200)
        cookie = result['headers']['Set-Cookie']
        self.assertTrue(cookie.startswith('__Host-tolk_session='))
        self.assertIn('; Secure;',cookie)
        self.assertIn('; HttpOnly;',cookie)
        self.assertFalse(self.request('/api/session')['body']['canSetup'])
        self.assertEqual(self.request('/api/session',HTTP_COOKIE=cookie.split(';')[0])['body']['account']['name'],'QA')

    def test_origin_host_and_unauthenticated_requests(self):
        self.assertEqual(self.request('/api/sync',{})['status'],401)
        self.assertEqual(self.request('/api/login',{},HTTP_ORIGIN='https://other.example')['status'],403)
        self.assertEqual(self.request('/',HTTP_HOST='other.example')['status'],403)
        self.assertEqual(self.request('/api/login',{},CONTENT_TYPE='text/plain')['status'],415)
        self.assertEqual(self.request('/api/login',{},CONTENT_LENGTH='8388609')['status'],413)

    def test_login_rate_limit_and_public_files(self):
        for _ in range(10): self.assertEqual(self.request('/api/login',{'name':'x','password':'x'})['status'],401)
        self.assertEqual(self.request('/api/login',{'name':'x','password':'x'})['status'],429)
        self.assertEqual(self.request('/')['status'],200)
        self.assertEqual(self.request('/../server/store.py')['status'],404)
        self.assertEqual(self.request('/secrets/activation')['status'],404)
        self.assertIn('frame-ancestors',self.request('/')['headers']['Content-Security-Policy'])

    def test_https_origin_is_mandatory(self):
        for origin in ('http://tolk.example.test', '', 'https://tolk.example.test/path'):
            with self.assertRaises(ValueError): create_app(self.store,origin)

    def test_online_backup_restores_account_and_restricts_file(self):
        original = self.store.create_account('Backup QA', 'test-only-passphrase')
        name = backup(self.store.path)
        path = Path(self.store.path).parent / 'backups' / name
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        recovered = Store(path)
        self.assertEqual(recovered.login('Backup QA','test-only-passphrase')[1],original)


if __name__ == '__main__': unittest.main()
