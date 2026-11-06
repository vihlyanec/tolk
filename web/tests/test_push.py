import base64
import json
import sys
import tempfile
import unittest
import uuid
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'server'))
from store import Store,Invalid
from push import subscribe,run_once,reminders
class PushTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.store=Store(Path(self.temp.name)/'push.sqlite');self.a=self.store.create_account('QA','synthetic-only-password')['id']
 def tearDown(self):self.temp.cleanup()
 def subscription(self,host='web.push.apple.com'):
  enc=lambda n:base64.urlsafe_b64encode(bytes(n)).rstrip(b'=').decode()
  return {'endpoint':'https://'+host+'/QA-only','keys':{'auth':enc(16),'p256dh':enc(65)}}
 def test_endpoint_scope_and_reminder_receipts_prevent_repeated_notifications(self):
  with self.assertRaises(Invalid):subscribe(self.store,self.a,self.subscription('127.0.0.1'))
  with self.assertRaises(Invalid):subscribe(self.store,self.a,self.subscription('evil.test'))
  subscribe(self.store,self.a,self.subscription())
  task=str(uuid.uuid4());now=1794477600
  ops=[{'id':str(uuid.uuid4()),'kind':'settings','entityID':self.a,'base':0,'patch':{'defaultTimedReminderOffsets':[0]}},{'id':str(uuid.uuid4()),'kind':'task','entityID':task,'base':0,'patch':{'title':'QA напоминание','schedule':{'kind':'timed','instant':now},'completed':False,'deleted':False}}]
  self.store.sync(self.a,ops,0);sent=[]
  sender=lambda subscription,payload:sent.append(payload)
  run_once(self.store,'unused','https://tolk.example.test',now,sender)
  run_once(self.store,'unused','https://tolk.example.test',now+15,sender)
  self.assertEqual(len(sent),1);self.assertEqual(sent[0]['body'],'QA напоминание')
 def test_pause_completion_and_explicit_empty_offsets_do_not_notify(self):
  task={'id':str(uuid.uuid4()),'data':{'title':'Не отправлять','schedule':{'kind':'timed','instant':1000},'timedReminderOffsets':[]}}
  self.assertEqual(list(reminders([task],{},1000)),[])
  task['data']['timedReminderOffsets']=[0];task['data']['completed']=True
  self.assertEqual(list(reminders([task],{},1000)),[])
  self.assertEqual(list(reminders([],{'focusSession':json.dumps({'deadline':None})},1000)),[])
