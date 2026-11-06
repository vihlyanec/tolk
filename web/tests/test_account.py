import io
import json
import sys
import tempfile
import unittest
import uuid
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'server'))
from store import Store,Invalid
from wsgi import create_app

class AccountProtocolTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.store=Store(Path(self.temp.name)/'account.sqlite')
        self.account=self.store.create_account('QA','synthetic-only-password')
        self.token,_=self.store.login('QA','synthetic-only-password')
        self.app=create_app(self.store,'https://tolk.example.test')
    def tearDown(self):self.temp.cleanup()
    def request(self,path,body,web=False,token=None,origin=None):
        data=json.dumps(body).encode();e={'PATH_INFO':path,'REQUEST_METHOD':'POST','HTTP_HOST':'tolk.example.test','CONTENT_TYPE':'application/json','CONTENT_LENGTH':str(len(data)),'wsgi.input':io.BytesIO(data)}
        if web:e.update(HTTP_ORIGIN='https://tolk.example.test',HTTP_COOKIE='__Host-tolk_session='+self.token)
        if origin:e['HTTP_ORIGIN']=origin
        if token:e['HTTP_AUTHORIZATION']='Bearer '+token
        result={}
        def reply(s,h):result['status']=int(s[:3])
        result['body']=json.loads(b''.join(self.app(e,reply)));return result
    def operation(self,kind,id,patch,base=0,expected=None):
        return {'id':str(uuid.uuid4()),'kind':kind,'entityID':id,'patch':patch,'base':base,'expected':expected or {k:None for k in patch}}
    def test_pairing_is_explicit_single_use_and_device_access_can_be_revoked(self):
        pair=self.request('/api/device/start',{'name':'QA Mac'})['body']
        self.assertTrue(self.request('/api/device/poll',pair)['body']['pending'])
        self.assertEqual(self.request('/api/device/approve',{'code':pair['code']})['status'],403)
        self.assertEqual(self.request('/api/device/approve',{'code':pair['code']},web=True)['status'],200)
        self.assertEqual(self.request('/api/device/poll',pair|{'secret':'wrong'})['status'],400)
        approved=self.request('/api/device/poll',pair)['body'];token=approved['token']
        self.assertEqual(approved['account'],self.account)
        self.assertEqual(self.request('/api/device/poll',pair)['status'],400)
        self.assertEqual(self.request('/api/device/sync',{},token=token)['status'],200)
        self.assertEqual(self.request('/api/device/sync',{},token=token,origin='https://other.example')['status'],403)
        self.assertEqual(self.request('/api/sync',{},token=token)['status'],403)
        self.store.revoke_device(self.account['id'],self.store.token_hash(token))
        self.assertEqual(self.request('/api/device/sync',{},token=token)['status'],401)
    def test_full_native_fields_and_disjoint_web_edit_merge_without_loss(self):
        project,tag,item=map(str,[uuid.uuid4(),uuid.uuid4(),uuid.uuid4()])
        reminder={'id':str(uuid.uuid4()),'daysBefore':1,'minuteOfDay':540}
        ops=[self.operation('project',project,{'title':'Заметки','itemKind':'note','color':'598BFF','folder':'Рабочее','sections':['Без раздела'],'archived':False,'kanban':False,'deleted':False}),
             self.operation('tag',tag,{'title':'Важно','parentID':None,'color':'AD94E8','deleted':False}),
             self.operation('task',item,{'title':'Полная запись','body':'# Markdown','itemKind':'note','projectID':project,'tagIDs':[tag],'duration':95,'section':'Без раздела','recurrence':'weekly','allDayReminders':[reminder],'checklist':[{'id':str(uuid.uuid4()),'title':'Шаг','done':False}], 'schedule':{'kind':'timed','instant':1794477600},'stickyOpen':False,'deleted':False})]
        response=self.store.sync(self.account['id'],ops,0)
        original=response['results'][-1]['record']
        title=self.operation('task',item,{'title':'С Mac'},1,{'title':'Полная запись'})
        body=self.operation('task',item,{'body':'С iPhone'},1,{'body':'# Markdown'})
        self.assertTrue(self.store.sync(self.account['id'],[title],0)['results'][0]['accepted'])
        final=self.store.sync(self.account['id'],[body],0)['results'][0]['record']
        self.assertEqual({k:v for k,v in final['data'].items() if k!='modified'},{k:v for k,v in (original['data']|{'title':'С Mac','body':'С iPhone'}).items() if k!='modified'})
        conflicting=self.operation('task',item,{'title':'Другая версия'},1,{'title':'Полная запись'})
        self.assertFalse(self.store.sync(self.account['id'],[conflicting],0)['results'][0]['accepted'])
        self.assertEqual(self.store.sync(self.account['id'],[body],0)['results'][0]['record'],final)
    def test_wrong_server_epoch_never_applies_operations(self):
        item=str(uuid.uuid4());op=self.operation('task',item,{'title':'Не применять'})
        with self.assertRaises(Invalid):self.store.sync(self.account['id'],[op],0,'old-server')
        self.assertEqual(self.store.sync(self.account['id'],[],0)['changes'],[])
    def test_named_schedule_rejects_impossible_clock_and_keeps_instant(self):
        item=str(uuid.uuid4())
        with self.assertRaises(Invalid):self.store.sync(self.account['id'],[self.operation('task',item,{'title':'Плохо','schedule':{'kind':'day','day':'2026-02-31'}})],0)
        with self.assertRaises(Invalid):self.store.sync(self.account['id'],[self.operation('task',item,{'title':'Плохо','schedule':{'kind':'timed','instant':float('nan')}})],0)
    def test_completion_materializes_one_repeat_and_keeps_native_identifiers(self):
        from schema import next_recurrence
        item=str(uuid.uuid4());instant=1794477600
        created=self.store.sync(self.account['id'],[self.operation('task',item,{'title':'Повтор','recurrence':'daily','schedule':{'kind':'timed','instant':instant},'completed':False,'deleted':False,'created':800000000,'modified':800000000})],0,native=True)
        original=created['results'][0]['record']
        completed=self.operation('task',item,{'completed':True},1,{'completed':False})
        response=self.store.sync(self.account['id'],[completed],0)
        children=[r for r in response['changes'] if r['kind']=='task' and r['id']!=item]
        self.assertEqual(len(children),1)
        self.assertEqual(children[0]['data']['schedule']['instant'],instant+86400)
        self.assertEqual(children[0]['data']['recurrenceSourceID'],item)
        self.store.sync(self.account['id'],[completed],0)
        self.assertEqual(len([r for r in self.store.sync(self.account['id'],[],0)['changes'] if r['kind']=='task' and r['id']!=item]),1)
    def test_deleting_project_and_tag_updates_all_references_atomically(self):
        project,tag,item=map(str,[uuid.uuid4(),uuid.uuid4(),uuid.uuid4()])
        self.store.sync(self.account['id'],[self.operation('project',project,{'title':'Удалить','color':'598BFF'}),self.operation('tag',tag,{'title':'Метка','color':'AD94E8'}),self.operation('task',item,{'title':'Сохранить задачу','projectID':project,'tagIDs':[tag]})],0)
        self.store.sync(self.account['id'],[self.operation('project',project,{'deleted':True},1),self.operation('tag',tag,{'deleted':True},1)],0)
        task=[r for r in self.store.sync(self.account['id'],[],0)['changes'] if r['id']==item][-1]
        self.assertEqual(task['data']['projectID'],'');self.assertEqual(task['data']['tagIDs'],[])
        self.assertEqual(task['data']['title'],'Сохранить задачу')
