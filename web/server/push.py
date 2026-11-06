"""Account reminders. Private VAPID material is loaded only by the sender, never returned."""
import base64
import hashlib
import json
import math
import os
import time
from datetime import date,datetime,time as wall_time,timedelta,timezone
from pathlib import Path
from urllib.parse import urlparse
from zoneinfo import ZoneInfo


def setup(db):
    db.executescript('''CREATE TABLE IF NOT EXISTS push_subscriptions(id TEXT PRIMARY KEY,account TEXT,data TEXT,created REAL);
        CREATE TABLE IF NOT EXISTS push_deliveries(subscription TEXT,event TEXT,state TEXT,attempt REAL,PRIMARY KEY(subscription,event));''')


def public_key(path):
    from cryptography.hazmat.primitives import serialization
    key=serialization.load_pem_private_key(Path(path).read_bytes(),password=None)
    raw=key.public_key().public_bytes(serialization.Encoding.X962,serialization.PublicFormat.UncompressedPoint)
    return base64.urlsafe_b64encode(raw).rstrip(b'=').decode()


def create_key(path):
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    target=Path(path)
    if target.exists():return
    data=ec.generate_private_key(ec.SECP256R1()).private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption())
    fd=os.open(target,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'wb') as stream:stream.write(data)


def subscribe(store,account,subscription):
    from store import Invalid
    if not isinstance(subscription,dict):raise Invalid('Некорректная подписка')
    endpoint=subscription.get('endpoint');url=urlparse(endpoint if isinstance(endpoint,str) else '')
    allowed={'web.push.apple.com','fcm.googleapis.com','updates.push.services.mozilla.com','updates-autopush.stage.mozaws.net','wns2-par02p.notify.windows.com'}
    host=url.hostname or ''
    # Push services only. Never let account content turn the sender into an arbitrary HTTP client.
    if url.scheme!='https' or (host not in allowed and not host.endswith('.push.apple.com') and not host.endswith('.notify.windows.com')) or url.port not in (None,443) or url.username or url.password or url.fragment or len(endpoint)>4096:raise Invalid('Неизвестная служба push')
    keys=subscription.get('keys',{})
    if not isinstance(keys,dict):raise Invalid('Некорректная подписка')
    try:
        def decode(v):return base64.urlsafe_b64decode(v+'='*(-len(v)%4)) if isinstance(v,str) and len(v)<256 else b''
        if len(decode(keys.get('p256dh')))!=65 or len(decode(keys.get('auth')))!=16:raise ValueError()
    except (ValueError,TypeError):raise Invalid('Некорректные ключи push') from None
    id=hashlib.sha256(endpoint.encode()).hexdigest()
    with store.connection() as db:db.execute('INSERT OR REPLACE INTO push_subscriptions VALUES(?,?,?,?)',(id,account,json.dumps(subscription),time.time()))
    return id


def unsubscribe(store,account,endpoint):
    if not isinstance(endpoint,str):return
    with store.connection() as db:db.execute('DELETE FROM push_subscriptions WHERE account=? AND id=?',(account,hashlib.sha256(endpoint.encode()).hexdigest()))


def reminders(records,prefs,now):
    zone=ZoneInfo(prefs.get('timeZone','Europe/Moscow'))
    for record in records:
        d=record['data'];id=record['id'];schedule=d.get('schedule')
        if d.get('deleted') or d.get('completed') or d.get('itemKind')=='note':continue
        if not schedule:
            from schema import legacy_schedule
            try:schedule=legacy_schedule(d,str(zone))
            except ValueError:continue
        candidates=[]
        if schedule.get('kind')=='timed':
            instant=schedule.get('instant')
            offsets=d.get('timedReminderOffsets')
            if offsets is None:offsets=[d['reminderMinutes']] if d.get('reminderMinutes') is not None else prefs.get('defaultTimedReminderOffsets') or []
            for offset in offsets:candidates.append((instant-offset*60,f'timed:{instant}:{offset}'))
        elif schedule.get('kind')=='day':
            for reminder in d.get('allDayReminders') if d.get('allDayReminders') is not None else prefs.get('defaultAllDayReminders') or []:
                day=date.fromisoformat(schedule['day'])-timedelta(days=reminder['daysBefore'])
                minute=reminder['minuteOfDay'];instant=datetime.combine(day,wall_time(minute//60,minute%60),tzinfo=zone).timestamp()
                candidates.append((instant,f'day:{schedule["day"]}:{reminder["daysBefore"]}:{minute}'))
        for due,key in candidates:
            if now-120<=due<=now:
                yield id+':'+key,{'title':'Толк · напоминание','body':(d.get('title') or 'Задача')[:180],'tag':'tolk-'+id,'url':'/?task='+id}
    try:focus=json.loads(prefs.get('focusSession') or 'null')
    except (ValueError,TypeError):focus=None
    if focus and isinstance(focus.get('deadline'),(int,float)) and now-120<=focus['deadline']/1000<=now:
        yield 'focus:'+str(focus['deadline']),{'title':'Фокус завершён' if focus.get('phase')=='focus' else 'Перерыв завершён','body':focus.get('title','Толк')[:180],'tag':'tolk-focus','url':'/?focus=1'}


def run_once(store,key_path,subject,now=None,sender=None):
    now=time.time() if now is None else now
    if sender is None:
        from pywebpush import webpush
        import requests
        class NoRedirects(requests.Session):
            def request(self,*args,**kwargs):
                kwargs['allow_redirects']=False
                return super().request(*args,**kwargs)
        session=NoRedirects()
        sender=lambda subscription,payload:webpush(subscription_info=subscription,data=json.dumps(payload,ensure_ascii=False),vapid_private_key=key_path,vapid_claims={'sub':subject},ttl=120,timeout=10,requests_session=session)
    with store.connection() as db:
        subscriptions=[dict(r) for r in db.execute('SELECT * FROM push_subscriptions')]
    for subscription in subscriptions:
        account=subscription['account']
        with store.connection() as db:
            prefs=db.execute("SELECT data FROM entities WHERE account=? AND kind='settings' AND id=?",(account,account)).fetchone()
            prefs=json.loads(prefs[0]) if prefs else {}
            records=[{'id':r['id'],'data':json.loads(r['data'])} for r in db.execute("SELECT id,data FROM entities WHERE account=? AND kind='task'",(account,))]
        for event,payload in reminders(records,prefs,now):
            with store.connection() as db:
                db.execute('BEGIN IMMEDIATE')
                previous=db.execute('SELECT state,attempt FROM push_deliveries WHERE subscription=? AND event=?',(subscription['id'],event)).fetchone()
                if previous and (previous['state']=='sent' or previous['attempt']>now-30):continue
                db.execute('INSERT OR REPLACE INTO push_deliveries VALUES(?,?,?,?)',(subscription['id'],event,'sending',now))
            try:
                sender(json.loads(subscription['data']),payload)
                with store.connection() as db:db.execute("UPDATE push_deliveries SET state='sent' WHERE subscription=? AND event=?",(subscription['id'],event))
            except Exception as error:
                response=getattr(error,'response',None)
                if response is not None and response.status_code in (404,410):
                    with store.connection() as db:db.execute('DELETE FROM push_subscriptions WHERE id=?',(subscription['id'],))
                # Endpoints, subscription keys and reminder text never enter logs.
                print('Push delivery will retry',flush=True)
    with store.connection() as db:db.execute('DELETE FROM push_deliveries WHERE attempt<?',(now-35*86400,))

if __name__=='__main__':
    from store import Store
    store=Store(os.environ['TOLK_DATABASE'])
    key=os.environ['TOLK_VAPID_KEY_FILE'];subject=os.environ.get('TOLK_VAPID_SUBJECT',os.environ['TOLK_ORIGIN'])
    while True:
        try:run_once(store,key,subject)
        except Exception:print('Reminder worker is waiting to retry',flush=True)
        time.sleep(15)
