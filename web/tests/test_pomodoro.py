import json
import sys
import unittest
import uuid
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'server'))
from store import validate, Invalid

class PomodoroValidationTests(unittest.TestCase):
    def setUp(self):
        self.session = dict(taskID=str(uuid.uuid4()), title='Фокус', phase='focus', completed=0, remaining=1500, deadline=1900000000000)
    def test_valid_running_paused_and_cleared(self):
        validate('settings', {'focusSession':json.dumps(self.session)})
        self.session['resumeNote'] = 'Начать с третьего пункта'
        validate('settings', {'focusSession':json.dumps(self.session)})
        self.session['resumeNote'] = ''
        self.session['deadline'] = None
        validate('settings', {'focusSession':json.dumps(self.session)})
        validate('settings', {'focusSession':''})
    def test_reject_invalid_sessions(self):
        for key, value in [('deadline',float('nan')),('deadline',-1),('deadline',10**400),('remaining',1501),('completed',True),('taskID','bad'),('phase','bad'),('resumeNote',42),('resumeNote','x'*2001)]:
            with self.subTest(key=key,value=value), self.assertRaises(Invalid):
                validate('settings', {'focusSession':json.dumps({**self.session,key:value})})
        for value in ['null','{}','[]','oops']:
            with self.assertRaises(Invalid): validate('settings', {'focusSession':value})

    def test_timer_is_one_atomic_field_with_explicit_concurrent_resolution(self):
        import tempfile
        from store import Store
        with tempfile.TemporaryDirectory() as folder:
            store = Store(Path(folder) / 'test.sqlite')
            account = store.create_account('Тест', 'test-only-passphrase')['id']
            def send(base, patch):
                return store.sync(account, [dict(id=str(uuid.uuid4()),entityID=account,kind='settings',base=base,patch=patch)],0)['results'][0]
            initial = json.dumps(self.session)
            self.assertTrue(send(0, {'focusSession':initial})['accepted'])
            paused = json.dumps({**self.session, 'deadline':None, 'remaining':1200})
            self.assertTrue(send(1, {'focusSession':paused})['accepted'])
            # A second device's stale stop cannot silently replace the pause.
            rejected = send(1, {'focusSession':''})
            self.assertFalse(rejected['accepted'])
            self.assertEqual(rejected['record']['data']['focusSession'],paused)
            # An unrelated appearance edit still merges with the running session.
            self.assertTrue(send(1, {'theme':'dark'})['accepted'])
            self.assertTrue(send(3, {'focusSession':''})['accepted'])
