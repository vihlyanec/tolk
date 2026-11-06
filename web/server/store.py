"""Account-scoped revision protocol. No access to the native application's database."""
import hashlib
import hmac
import json
import secrets
import sqlite3
import time
import uuid
from schema import extras, legacy_schedule, next_recurrence
from push import setup as setup_push
from contextlib import contextmanager


class Invalid(ValueError):
    pass


def identifier(value):
    try:
        return str(uuid.UUID(value))
    except (ValueError, TypeError, AttributeError):
        raise Invalid("Некорректный идентификатор") from None


def validate(kind, patch):
    if not isinstance(patch, dict) or not patch:
        raise Invalid("Неподдерживаемые поля")
    patch = extras(kind, patch, Invalid, identifier)
    if not patch and kind in {"task", "project", "tag", "settings", "event"}: return
    fields = {
        "task": {"title", "body", "completed", "deleted", "date", "time", "projectID", "priority"},
        "project": {"title", "color", "deleted"},
        "settings": {"theme", "timeZone", "startHour", "endHour", "pushEnabled", "focusSession"},
    }
    if kind not in fields or not isinstance(patch, dict) or not patch or patch.keys() - fields[kind]:
        raise Invalid("Неподдерживаемые поля")
    for key, value in patch.items():
        if key in {"completed", "deleted", "pushEnabled"}:
            valid = type(value) is bool
        elif key in {"priority", "startHour", "endHour"}:
            low, high = {"priority": (0, 3), "startHour": (0, 23), "endHour": (1, 24)}[key]
            valid = type(value) is int and low <= value <= high
        else:
            valid = isinstance(value, str) and len(value) <= (5000000 if key == "body" else 64000 if key == "focusSession" else 16000 if key == "title" else 500)
        if not valid:
            raise Invalid("Некорректное значение поля: " + key)
        if key == "focusSession" and value:
            try:
                focus = json.loads(value)
                if not isinstance(focus, dict) or (set(focus) - {"resumeNote"}) != {"taskID", "title", "phase", "completed", "remaining", "deadline"}:
                    raise ValueError()
                if "resumeNote" in focus and (not isinstance(focus["resumeNote"], str) or len(focus["resumeNote"]) > 2000):
                    raise ValueError()
                identifier(focus["taskID"])
                if not isinstance(focus["title"], str) or len(focus["title"]) > 16000:
                    raise ValueError()
                if focus["phase"] not in {"focus", "shortBreak", "longBreak"}:
                    raise ValueError()
                if type(focus["completed"]) is not int or not 0 <= focus["completed"] <= 1000000:
                    raise ValueError()
                import math
                for number, limit in [(focus["remaining"], 1500), (focus["deadline"], 100000000000000)]:
                    if number is None and limit != 1500:
                        continue
                    if type(number) not in {int, float} or not math.isfinite(number) or not 0 <= number <= limit:
                        raise ValueError()
            except (ValueError, TypeError, KeyError, OverflowError):
                raise Invalid("Некорректный сеанс фокуса") from None
        if key == "title" and not value.strip():
            raise Invalid("Введите название")
        if key == "theme" and value not in {"system", "light", "dark"}:
            raise Invalid("Неизвестная тема")
        if key == "timeZone":
            from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
            try:
                ZoneInfo(value)
            except (ZoneInfoNotFoundError, ValueError):
                raise Invalid("Неизвестный часовой пояс") from None
        if key == "color" and (len(value) != 6 or any(c not in "0123456789abcdefABCDEF" for c in value)):
            raise Invalid("Некорректный цвет")
        if key == "projectID" and value:
            identifier(value)
        if key == "date" and value:
            from datetime import date
            try:
                if date.fromisoformat(value).isoformat() != value:
                    raise ValueError()
            except ValueError:
                raise Invalid("Некорректная дата") from None
        if key == "time" and value:
            import re
            if not re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", value):
                raise Invalid("Некорректное время")


class Store:
    def __init__(self, path):
        self.path = str(path)
        with self.connection() as db:
            db.executescript("""
              PRAGMA journal_mode=WAL;
              CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value TEXT);
              CREATE TABLE IF NOT EXISTS devices(hash TEXT PRIMARY KEY,account TEXT,name TEXT,created INTEGER,seen INTEGER);
              CREATE TABLE IF NOT EXISTS pairing(code TEXT PRIMARY KEY,secret TEXT,expires INTEGER,account TEXT,device_name TEXT);
              CREATE TABLE IF NOT EXISTS accounts(id TEXT PRIMARY KEY,name TEXT NOT NULL UNIQUE,salt BLOB,hash BLOB);
              CREATE TABLE IF NOT EXISTS sessions(hash TEXT PRIMARY KEY,account TEXT,expires INTEGER);
              CREATE TABLE IF NOT EXISTS entities(account TEXT,kind TEXT,id TEXT,version INTEGER,data TEXT,fields TEXT,
                PRIMARY KEY(account,kind,id));
              CREATE TABLE IF NOT EXISTS changes(seq INTEGER PRIMARY KEY AUTOINCREMENT,account TEXT,record TEXT);
              CREATE TABLE IF NOT EXISTS operations(account TEXT,id TEXT,request TEXT,result TEXT,PRIMARY KEY(account,id));
            """)

        with self.connection() as db:
            setup_push(db)
            db.execute("INSERT OR IGNORE INTO metadata VALUES('epoch',?)",(str(uuid.uuid4()),))

    @property
    def epoch(self):
        with self.connection() as db: return db.execute("SELECT value FROM metadata WHERE key='epoch'").fetchone()[0]

    @contextmanager
    def connection(self):
        db = sqlite3.connect(self.path, timeout=15)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def configured(self):
        with self.connection() as db:
            return db.execute("SELECT 1 FROM accounts LIMIT 1").fetchone() is not None

    def create_account(self, name, password):
        if not isinstance(name, str) or not 1 <= len(name.strip()) <= 80:
            raise Invalid("Введите имя аккаунта")
        if not isinstance(password, str) or not 12 <= len(password) <= 256:
            raise Invalid("Пароль должен содержать от 12 до 256 символов")
        salt = secrets.token_bytes(16)
        digest = hashlib.scrypt(password.encode(), salt=salt, n=16384, r=8, p=1)
        account = str(uuid.uuid4())
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            if db.execute("SELECT 1 FROM accounts LIMIT 1").fetchone():
                raise Invalid("Аккаунт уже создан")
            db.execute("INSERT INTO accounts VALUES(?,?,?,?)", (account, name.strip(), salt, digest))
        return {"id": account, "name": name.strip()}

    def login(self, name, password):
        if not isinstance(name, str) or not isinstance(password, str) or len(password) > 256:
            return None
        with self.connection() as db:
            row = db.execute("SELECT * FROM accounts WHERE name=?", (name,)).fetchone()
            salt = row["salt"] if row else bytes(16)
            digest = hashlib.scrypt(password.encode(), salt=salt, n=16384, r=8, p=1)
            if row is None or not hmac.compare_digest(row["hash"], digest):
                return None
            token = secrets.token_urlsafe(32)
            db.execute("DELETE FROM sessions WHERE expires < ?", (time.time(),))
            db.execute("INSERT INTO sessions VALUES(?,?,?)", (self.token_hash(token), row["id"], int(time.time()) + 30 * 86400))
            return token, {"id": row["id"], "name": row["name"]}

    @staticmethod
    def token_hash(token):
        return hashlib.sha256(token.encode()).hexdigest()

    def account(self, token):
        with self.connection() as db:
            row = db.execute("SELECT a.id,a.name FROM sessions s JOIN accounts a ON a.id=s.account WHERE s.hash=? AND s.expires>?",
                             (self.token_hash(token), time.time())).fetchone()
            return dict(row) if row else None

    def logout(self, token):
        with self.connection() as db:
            db.execute("DELETE FROM sessions WHERE hash=?", (self.token_hash(token),))

    def cursor_ahead(self, account, cursor):
        if type(cursor) is not int:return False
        with self.connection() as db:return cursor > db.execute('SELECT COALESCE(MAX(seq),0) FROM changes WHERE account=?',(account,)).fetchone()[0]

    def sync(self, account, operations, cursor, epoch=None, native=False):
        if epoch is not None and epoch != self.epoch:
            raise Invalid("Сервер восстановлен из резервной копии. Требуется проверка локальных изменений.")
        if type(cursor) is not int or cursor < 0 or not isinstance(operations, list) or len(operations) > 100:
            raise Invalid("Некорректный запрос синхронизации")
        results = []
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            for op in operations:
                if not isinstance(op, dict):
                    raise Invalid("Некорректная операция")
                operation_id, entity_id = identifier(op.get("id")), identifier(op.get("entityID"))
                kind, base, patch = op.get("kind"), op.get("base"), op.get("patch")
                if type(base) is not int or base < 0:
                    raise Invalid("Некорректная версия")
                validate(kind, patch)
                if kind == "settings" and entity_id != account:
                    raise Invalid("Настройки принадлежат аккаунту")
                request = json.dumps(op, sort_keys=True, ensure_ascii=False)
                prior = db.execute("SELECT request,result FROM operations WHERE account=? AND id=?", (account, operation_id)).fetchone()
                if prior:
                    if prior["request"] != request:
                        raise Invalid("Идентификатор операции уже использован")
                    results.append(json.loads(prior["result"]))
                    continue
                row = db.execute("SELECT * FROM entities WHERE account=? AND kind=? AND id=?", (account, kind, entity_id)).fetchone()
                current = dict(id=entity_id, kind=kind, version=row["version"] if row else 0,
                               data=json.loads(row["data"]) if row else {})
                field_versions = json.loads(row["fields"]) if row else {}
                expected = op.get("expected", {})
                if not isinstance(expected, dict) or expected.keys() - patch.keys():
                    raise Invalid("Некорректная исходная запись")
                conflicts = [key for key, value in patch.items()
                             if key != "modified" and field_versions.get(key, 0) > base and current["data"].get(key) != value
                             and (key not in expected or current["data"].get(key) != expected[key])]
                # Deleting an edited record and editing a deleted record require explicit resolution.
                if base > current["version"] or (not row and base != 0):
                    raise Invalid("Неизвестная исходная версия")
                if row and current["version"] > base and (patch.get("deleted") is True or current["data"].get("deleted")):
                    conflicts = sorted(set(conflicts) | {"deleted"})
                if kind == 'task' and ('date' in patch or 'time' in patch) and field_versions.get('schedule',0)>base:
                    conflicts=sorted(set(conflicts)|{'schedule'})
                if conflicts:
                    results.append({"id": operation_id, "accepted": False, "fields": conflicts, "record": current})
                    continue
                if not row and kind in {"task", "project", "tag"} and "title" not in patch:
                    raise Invalid("Новая запись должна иметь название")
                merged = current["data"] | patch
                if kind == 'task' and ('date' in patch or 'time' in patch):
                    prefs=db.execute("SELECT data FROM entities WHERE account=? AND kind='settings' AND id=?",(account,account)).fetchone()
                    zone=json.loads(prefs[0]).get('timeZone','Europe/Moscow') if prefs else 'Europe/Moscow'
                    try: merged['schedule']=legacy_schedule(merged,zone)
                    except ValueError as e: raise Invalid(str(e)) from None
                    patch = patch | {'schedule':merged['schedule']}

                if kind == 'tag' and merged.get('parentID'):
                    parent=identifier(merged['parentID']);seen={entity_id}
                    while parent:
                        if parent in seen:raise Invalid('Недопустимая вложенность меток')
                        seen.add(parent)
                        linked=db.execute("SELECT data FROM entities WHERE account=? AND kind='tag' AND id=?",(account,parent)).fetchone()
                        if not linked or json.loads(linked[0]).get('deleted'):raise Invalid('Родительская метка недоступна')
                        parent=json.loads(linked[0]).get('parentID')
                        if parent:parent=identifier(parent)
                if kind == "task":
                    if merged.get("time") and not merged.get("date"):
                        raise Invalid("Для времени нужна дата")
                    for tag in merged.get('tagIDs',[]):
                        linked=db.execute("SELECT data FROM entities WHERE account=? AND kind='tag' AND id=?",(account,identifier(tag))).fetchone()
                        if not linked or json.loads(linked[0]).get('deleted'):raise Invalid('Метка недоступна')
                    project = merged.get("projectID")
                    if project:
                        linked = db.execute("SELECT data FROM entities WHERE account=? AND kind='project' AND id=?", (account, project)).fetchone()
                        if not linked or json.loads(linked[0]).get("deleted"):
                            raise Invalid("Проект недоступен")
                if kind == "settings" and merged.get("startHour", 7) >= merged.get("endHour", 23):
                    raise Invalid("Конец дня должен быть позже начала")
                if kind == 'task' and not native:
                    merged['modified']=time.time()-978307200
                    patch=patch|{'modified':merged['modified']}
                was_completed=current['data'].get('completed',False)
                current["data"] = merged
                current["version"] += 1
                field_versions.update({key: current["version"] for key in patch})
                encoded = json.dumps(current, ensure_ascii=False)
                db.execute("INSERT OR REPLACE INTO entities VALUES(?,?,?,?,?,?)", (account, kind, entity_id, current["version"], json.dumps(merged), json.dumps(field_versions)))
                db.execute("INSERT INTO changes(account,record) VALUES(?,?)", (account, encoded))
                if kind in {'tag','project'} and patch.get('deleted') is True:
                    affected=list(db.execute("SELECT * FROM entities WHERE account=? AND kind IN ('task','tag')",(account,)))
                    for linked in affected:
                        payload=json.loads(linked['data']);changes={}
                        if linked['kind']=='task' and kind=='project' and (payload.get('projectID') or '').lower()==entity_id:
                            changes={'projectID':'','section':'Без раздела'}
                        if linked['kind']=='task' and kind=='tag' and any(t.lower()==entity_id for t in payload.get('tagIDs',[])):
                            changes={'tagIDs':[t for t in payload['tagIDs'] if t.lower()!=entity_id]}
                        if linked['kind']=='tag' and kind=='tag' and (payload.get('parentID') or '').lower()==entity_id:changes={'parentID':None}
                        if changes:
                            version=linked['version']+1;payload.update(changes);field_map=json.loads(linked['fields']);field_map.update({k:version for k in changes})
                            db.execute('UPDATE entities SET version=?,data=?,fields=? WHERE account=? AND kind=? AND id=?',(version,json.dumps(payload),json.dumps(field_map),account,linked['kind'],linked['id']))
                            db.execute('INSERT INTO changes(account,record) VALUES(?,?)',(account,json.dumps({'id':linked['id'],'kind':linked['kind'],'version':version,'data':payload})))
                if kind == 'task' and not native and patch.get('completed') is True and not was_completed:
                    rows=[{'id':r['id'],'data':json.loads(r['data'])} for r in db.execute("SELECT id,data FROM entities WHERE account=? AND kind='task'",(account,))]
                    prefs=db.execute("SELECT data FROM entities WHERE account=? AND kind='settings' AND id=?",(account,account)).fetchone()
                    zone=json.loads(prefs[0]).get('timeZone','Europe/Moscow') if prefs else 'Europe/Moscow'
                    next_item=next_recurrence(merged|{'id':entity_id},rows,zone)
                    if next_item:
                        child_id,child=next_item
                        child_record={'id':child_id,'kind':'task','version':1,'data':child}
                        db.execute('INSERT INTO entities VALUES(?,?,?,?,?,?)',(account,'task',child_id,1,json.dumps(child),json.dumps({k:1 for k in child})))
                        db.execute('INSERT INTO changes(account,record) VALUES(?,?)',(account,json.dumps(child_record)))
                result = {"id": operation_id, "accepted": True, "record": current}
                db.execute("INSERT INTO operations VALUES(?,?,?,?)", (account, operation_id, request, json.dumps(result)))
                results.append(result)
            changes=[];size=0;more=False
            for row in db.execute("SELECT seq,record FROM changes WHERE account=? AND seq>? ORDER BY seq", (account, cursor)):
                count=len(row['record'])
                if changes and (len(changes)>=500 or size+count>2000000):more=True;break
                changes.append(row);size+=count
            return {"epoch": self.epoch, "results": results, "changes": [json.loads(row["record"]) for row in changes],
                    "cursor": changes[-1]["seq"] if changes else cursor, "more": more}

    def begin_pairing(self, name):
        if not isinstance(name,str) or not 1<=len(name.strip())<=80: raise Invalid('Укажите имя устройства')
        code=secrets.token_urlsafe(18);secret=secrets.token_urlsafe(32)
        with self.connection() as db:
            db.execute('DELETE FROM pairing WHERE expires<?',(time.time(),))
            db.execute('INSERT INTO pairing VALUES(?,?,?,?,?)',(code,self.token_hash(secret),int(time.time())+600,None,name.strip()))
        return {'code':code,'secret':secret,'expiresIn':600}

    def approve_pairing(self, account, code):
        with self.connection() as db:
            db.execute('BEGIN IMMEDIATE')
            row=db.execute('SELECT * FROM pairing WHERE code=? AND expires>?',(code,time.time())).fetchone()
            if not row or row['account']: raise Invalid('Ссылка уже использована или устарела. Начните подключение на Mac заново.')
            db.execute('UPDATE pairing SET account=? WHERE code=?',(account,code))
            return {'name':row['device_name']}

    def pairing_info(self, code):
        with self.connection() as db:
            row=db.execute('SELECT device_name FROM pairing WHERE code=? AND expires>? AND account IS NULL',(code,time.time())).fetchone()
            if not row: raise Invalid('Ссылка подключения устарела или уже использована')
            return {'name':row['device_name']}

    def poll_pairing(self, code, secret):
        if not isinstance(secret,str): raise Invalid('Некорректное подключение')
        with self.connection() as db:
            db.execute('BEGIN IMMEDIATE')
            row=db.execute('SELECT * FROM pairing WHERE code=? AND expires>?',(code,time.time())).fetchone()
            if not row or not hmac.compare_digest(row['secret'],self.token_hash(secret)): raise Invalid('Подключение устарело. Начните заново.')
            if not row['account']: return {'pending':True}
            token=secrets.token_urlsafe(32);now=int(time.time())
            db.execute('INSERT INTO devices VALUES(?,?,?,?,?)',(self.token_hash(token),row['account'],row['device_name'],now,now))
            db.execute('DELETE FROM pairing WHERE code=?',(code,))
            account=db.execute('SELECT id,name FROM accounts WHERE id=?',(row['account'],)).fetchone()
            return {'token':token,'account':dict(account)}

    def device_account(self, token):
        with self.connection() as db:
            row=db.execute('SELECT a.id,a.name FROM devices d JOIN accounts a ON a.id=d.account WHERE d.hash=?',(self.token_hash(token),)).fetchone()
            if row: db.execute('UPDATE devices SET seen=? WHERE hash=?',(int(time.time()),self.token_hash(token)))
            return dict(row) if row else None

    def devices(self, account):
        with self.connection() as db:
            return [dict(r) for r in db.execute('SELECT hash AS id,name,created,seen FROM devices WHERE account=?',(account,))]

    def revoke_device(self, account, device):
        with self.connection() as db: db.execute('DELETE FROM devices WHERE account=? AND hash=?',(account,device))
