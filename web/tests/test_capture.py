import io
import json
import sys
import tempfile
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'server'))
from store import Store
from wsgi import create_app
import capture


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.store = Store(Path(self.temp.name) / 'capture.sqlite')
        self.account = self.store.create_account('Capture QA', 'synthetic-only-password')
        self.cookie = self.store.login('Capture QA', 'synthetic-only-password')[0]
        self.app = create_app(self.store, 'https://tolk.example.test')
        self.token = capture.issue(self.store, self.account['id'], 'iPhone QA')['token']

    def tearDown(self): self.temp.cleanup()

    def request(self, path, body, token=None, web=False, origin=None):
        data = json.dumps(body).encode()
        env = dict(PATH_INFO=path, REQUEST_METHOD='POST', HTTP_HOST='tolk.example.test',
                   CONTENT_TYPE='application/json', CONTENT_LENGTH=str(len(data)), **{'wsgi.input':io.BytesIO(data)})
        if token: env['HTTP_AUTHORIZATION'] = 'Bearer ' + token
        if web: env.update(HTTP_COOKIE='__Host-tolk_session=' + self.cookie, HTTP_ORIGIN='https://tolk.example.test')
        if origin: env['HTTP_ORIGIN'] = origin
        result = {}
        def reply(status, headers): result.update(status=int(status[:3]), headers=dict(headers))
        result['body'] = json.loads(b''.join(self.app(env, reply)))
        return result

    def task(self, **fields): return dict(requestID=str(uuid.uuid4()), title='Новая задача', **fields)

    def test_append_only_scope_authentication_and_revocation(self):
        body = self.task()
        self.assertEqual(self.request('/api/capture', body)['status'], 401)
        self.assertEqual(self.request('/api/capture', body, web=True)['status'], 401)
        self.assertEqual(self.request('/api/capture', body, token=self.token, origin='https://other.example')['status'], 403)
        for route in ['/api/device/sync', '/api/device/logout', '/api/capture/token', '/api/capture/tokens']:
            self.assertIn(self.request(route, {}, token=self.token)['status'], (401, 403))
        result = self.request('/api/capture', body, token=self.token)
        self.assertEqual(result['status'], 200)
        self.assertEqual(set(result['body']), {'ok', 'id', 'message'})
        self.assertEqual(result['headers']['Cache-Control'], 'no-store')
        listing = self.request('/api/capture/tokens', {}, web=True)['body']['tokens']
        self.assertNotIn(self.token, json.dumps(listing))
        self.request('/api/capture/revoke', {'id':listing[0]['id']}, web=True)
        self.assertEqual(self.request('/api/capture', self.task(), token=self.token)['status'], 401)

    def test_native_schedule_sync_and_retry_are_atomic(self):
        body = self.task(body='Текст с "кавычками"\nи новой строкой', date='2026-12-12', time='10:00')
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: capture.create_task(self.store, self.token, body), range(2)))
        self.assertEqual(results[0], results[1])
        changes = self.store.sync(self.account['id'], [], 0)['changes']
        self.assertEqual(len(changes), 1)
        self.assertEqual(changes[0]['id'], body['requestID'])
        self.assertEqual(changes[0]['data']['body'], body['body'])
        self.assertEqual(changes[0]['data']['schedule'], {'kind':'timed', 'instant':1797058800.0})
        self.assertEqual(self.request('/api/capture', body | {'title':'Другой текст'}, token=self.token)['status'], 400)
        self.assertEqual(len(self.store.sync(self.account['id'], [], 0)['changes']), 1)

    def test_invalid_fields_dates_and_unavailable_projects_never_create_records(self):
        for fields in [{'date':'2026-02-31'}, {'time':'10:00'}, {'date':'2026-12-12','time':'25:00'},
                       {'priority':True}, {'duration':10081}, {'projectID':str(uuid.uuid4())}, {'completed':True}, {'schedule':{'kind':'none'}}]:
            self.assertEqual(self.request('/api/capture', self.task(**fields), token=self.token)['status'], 400)
        self.assertEqual(self.store.sync(self.account['id'], [], 0)['changes'], [])

    def test_token_management_is_cookie_bound_and_tasks_belong_to_token_account(self):
        self.assertEqual(self.request('/api/capture/token', {'name':'Phone'}, token=self.token)['status'], 403)
        token = self.request('/api/capture/token', {'name':'Phone'}, web=True)['body']['token']
        self.assertEqual(self.request('/api/capture', self.task(date='2026-12-12'), token=token)['status'], 200)
        record = self.store.sync(self.account['id'], [], 0)['changes'][0]
        self.assertEqual(record['data']['schedule'], {'kind':'day','day':'2026-12-12'})
        self.assertEqual(record['data']['projectID'], '')
        self.assertTrue(record['data']['created'] > 0)
        self.assertEqual(self.request('/api/capture', self.task(date=None, projectID=None, tagID=None), token=token)['status'], 200)

    def test_options_and_tag_project_validation_are_account_scoped(self):
        project, tag = str(uuid.uuid4()), str(uuid.uuid4())
        ops = [{'id':str(uuid.uuid4()), 'entityID':id, 'kind':kind, 'base':0, 'patch':patch} for kind,id,patch in [
            ('project',project,{'title':'Работа','color':'598BFF'}), ('tag',tag,{'title':'Важно','color':'AD94E8'})]]
        self.store.sync(self.account['id'],ops,0)
        options = self.request('/api/capture/options',{},token=self.token)['body']
        self.assertIn(project, options['projects'].values())
        self.assertIn(tag, options['tags'].values())
        self.assertNotIn('tasks', options)
        result = self.request('/api/capture',self.task(projectID=project,tagID=tag,priority='Высокий'),token=self.token)
        self.assertEqual(result['status'],200)
        data = self.store.sync(self.account['id'],[],0)['changes'][-1]['data']
        self.assertEqual((data['projectID'],data['tagIDs'],data['priority']),(project,[tag],1))
        self.assertEqual(self.request('/api/capture',self.task(tagID=str(uuid.uuid4())),token=self.token)['status'],400)

    def test_capture_rate_limit(self):
        body = self.task()
        for _ in range(60): self.assertEqual(self.request('/api/capture', body, token=self.token)['status'], 200)
        self.assertEqual(self.request('/api/capture', body, token=self.token)['status'], 429)

    def test_failed_options_credentials_are_not_masked_by_empty_request_id(self):
        for token in [None, 'invalid-shortcut-key']:
            options = self.request('/api/capture/options', {}, token=token)
            capture_result = self.request('/api/capture', {'requestID':'', 'title':'Не сохранять'}, token=token)
            self.assertEqual((options['status'], capture_result['status']), (401,401))
            self.assertEqual(options['body']['message'], capture_result['body']['message'])
            self.assertIn('Ключ команды недействителен', capture_result['body']['message'])
        self.assertEqual(self.store.sync(self.account['id'], [], 0)['changes'], [])

    def test_capture_credentials_allow_http_optional_whitespace(self):
        options = self.request('/api/capture/options', {}, token=self.token+' ')
        self.assertEqual(options['status'], 200)
        uuid.UUID(options['body']['requestID'])
        result = self.request('/api/capture', {'requestID':options['body']['requestID'], 'title':'HTTP OWS'}, token=self.token+' ')
        self.assertEqual(result['status'], 200)
        self.assertEqual(len(self.store.sync(self.account['id'], [], 0)['changes']), 1)

if __name__ == '__main__': unittest.main()
