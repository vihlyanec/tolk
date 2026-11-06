"""Called only by Swift tests; all data is synthetic and uses a temporary SQLite."""
import json,sys,tempfile,uuid
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'server'))
from store import Store
source=json.loads(Path(sys.argv[1]).read_text())
with tempfile.TemporaryDirectory() as directory:
 store=Store(Path(directory)/'interop.sqlite');account=store.create_account('Interop','synthetic-only-password')['id']
 operations=[]
 for record in source:
  operations.append({'id':str(uuid.uuid4()),'entityID':account if record['kind']=='settings' else record['id'],'kind':record['kind'],'base':0,'patch':record['data']})
 first=store.sync(account,operations,0,native=True)
 task=next(r for r in first['changes'] if r['kind']=='task')
 op={'id':str(uuid.uuid4()),'kind':'task','entityID':task['id'],'base':task['version'],'patch':{'body':'Изменено на iPhone','completed':True},'expected':{'body':task['data'].get('body'),'completed':False}}
 store.sync(account,[op],0)
 response=store.sync(account,[],0)
 response['changes']=[r for r in response['changes'] if r['kind']!='settings']
 Path(sys.argv[2]).write_text(json.dumps(response,ensure_ascii=False))
