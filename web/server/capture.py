"""Revocable, append-only credentials for iPhone Shortcuts. No task-reading scope."""
import json
import re
import secrets
import time
import uuid
from schema import legacy_schedule


class Unauthorized(ValueError):
    pass


def token_account(store, db, token):
    row = db.execute('SELECT account FROM capture_tokens WHERE hash=?', (store.token_hash(token),)).fetchone()
    if not row:
        raise Unauthorized('Ключ команды недействителен. Создайте новый в настройках Толка и вставьте его в первый блок «Текст» команды.')
    return row['account']


def setup(db):
    db.executescript('''
        CREATE TABLE IF NOT EXISTS capture_tokens(hash TEXT PRIMARY KEY,account TEXT,name TEXT,created INTEGER,seen INTEGER);
        CREATE TABLE IF NOT EXISTS capture_requests(account TEXT,id TEXT,request TEXT,result TEXT,PRIMARY KEY(account,id));
    ''')


def issue(store, account, name, token=None):
    from store import Invalid
    if not isinstance(name, str) or not 1 <= len(name.strip()) <= 80:
        raise Invalid('Укажите название команды')
    if token is None:
        token = secrets.token_urlsafe(32)
    elif not isinstance(token, str) or not re.fullmatch(r'[A-Za-z0-9_-]{43}', token):
        raise Invalid('Не удалось подготовить ключ. Обновите страницу и повторите.')
    token_hash = store.token_hash(token)
    with store.connection() as db:
        db.execute('BEGIN IMMEDIATE')
        prior = db.execute('SELECT account FROM capture_tokens WHERE hash=?', (token_hash,)).fetchone()
        if prior:
            if prior['account'] != account:
                raise Invalid('Этот ключ недоступен. Обновите страницу и повторите.')
            return {'token': token}
        if db.execute('SELECT COUNT(*) FROM capture_tokens WHERE account=?', (account,)).fetchone()[0] >= 20:
            raise Invalid('Удалите один из прежних ключей перед созданием нового')
        db.execute('INSERT INTO capture_tokens VALUES(?,?,?,?,?)', (token_hash, account, name.strip(), int(time.time()), 0))
    return {'token': token}


def tokens(store, account):
    with store.connection() as db:
        return [dict(r) for r in db.execute('SELECT hash AS id,name,created,seen FROM capture_tokens WHERE account=? ORDER BY created', (account,))]


def revoke(store, account, key):
    from store import Invalid
    if not isinstance(key, str): raise Invalid('Выберите ключ')
    with store.connection() as db:
        db.execute('DELETE FROM capture_tokens WHERE account=? AND hash=?', (account, key))


def options(store, token):
    with store.connection() as db:
        account = token_account(store, db, token)
        projects, tags = {'Входящие': ''}, {'Без тега': ''}
        for record in db.execute("SELECT id,kind,data FROM entities WHERE account=? AND kind IN ('project','tag')", (account,)):
            data = json.loads(record['data'])
            if data.get('deleted') or data.get('archived'): continue
            if record['kind'] == 'project' and data.get('itemKind', 'task') != 'task': continue
            title = data.get('title', '')
            label = title + ' · ' + record['id'][:8]
            (projects if record['kind'] == 'project' else tags)[label] = record['id']
        return {'requestID': str(uuid.uuid4()), 'projects': projects, 'projectNames': list(projects), 'tags': tags, 'tagNames': list(tags)}


def create_task(store, token, body):
    from store import Invalid, identifier, validate
    # A failed options request leaves old shortcuts with an empty requestID.
    # Report the credential failure before validating the resulting form.
    with store.connection() as db:
        token_account(store, db, token)
    if set(body) - {'requestID', 'title', 'body', 'date', 'time', 'projectID', 'priority', 'duration', 'tagID'}:
        raise Invalid('Неподдерживаемые поля быстрого добавления')
    try:
        request_id = identifier(body.get('requestID'))
    except Invalid:
        raise Invalid('Не удалось получить идентификатор запроса. Скачайте обновлённую команду в настройках Толка.') from None
    patch = {'title': body.get('title'), 'body': body.get('body', ''), 'date': body.get('date', ''),
             'time': body.get('time', ''), 'projectID': body.get('projectID', ''),
             'priority': body.get('priority', 0), 'duration': body.get('duration', 30)}
    for key in ('date','time','projectID'):
        if patch[key] is None: patch[key] = ''
    priorities = {'Без приоритета':0, 'Высокий':1, 'Средний':2, 'Низкий':3}
    if isinstance(patch['priority'], str): patch['priority'] = priorities.get(patch['priority'], patch['priority'])
    tag = body.get('tagID', '')
    if tag is None: tag = ''
    if not isinstance(tag, str): raise Invalid('Выберите тег')
    patch['tagIDs'] = [identifier(tag)] if tag else []
    validate('task', patch)
    if patch['time'] and not patch['date']: raise Invalid('Для времени нужна дата')
    patch['title'] = patch['title'].strip()
    if patch['projectID']: patch['projectID'] = identifier(patch['projectID'])
    request = json.dumps(patch, sort_keys=True, ensure_ascii=False)
    with store.connection() as db:
        db.execute('BEGIN IMMEDIATE')
        account = token_account(store, db, token)
        prior = db.execute('SELECT request,result FROM capture_requests WHERE account=? AND id=?', (account, request_id)).fetchone()
        if prior:
            if prior['request'] != request: raise Invalid('Повтор запроса содержит другие данные')
            return json.loads(prior['result'])
        if db.execute("SELECT 1 FROM entities WHERE account=? AND kind='task' AND id=?", (account, request_id)).fetchone():
            raise Invalid('Этот идентификатор уже занят. Создайте новый запрос.')
        if patch['projectID']:
            project = db.execute("SELECT data FROM entities WHERE account=? AND kind='project' AND id=?", (account, patch['projectID'])).fetchone()
            project = json.loads(project['data']) if project else None
            if not project or project.get('deleted') or project.get('archived') or project.get('itemKind', 'task') != 'task':
                raise Invalid('Проект недоступен. Выберите другой или оставьте Входящие.')
        for tag in patch['tagIDs']:
            row = db.execute("SELECT data FROM entities WHERE account=? AND kind='tag' AND id=?", (account, tag)).fetchone()
            if not row or json.loads(row['data']).get('deleted'): raise Invalid('Тег недоступен. Выберите другой или оставьте Без тега.')
        prefs = db.execute("SELECT data FROM entities WHERE account=? AND kind='settings' AND id=?", (account, account)).fetchone()
        zone = json.loads(prefs['data']).get('timeZone', 'Europe/Moscow') if prefs else 'Europe/Moscow'
        try: schedule = legacy_schedule(patch, zone)
        except ValueError as error: raise Invalid(str(error)) from None
        order = db.execute("SELECT COALESCE(MAX(CAST(json_extract(data,'$.order') AS REAL)),0)+1 FROM entities WHERE account=? AND kind='task'", (account,)).fetchone()[0]
        now = time.time() - 978307200
        data = {k: v for k, v in patch.items() if k not in {'date', 'time'}}
        data.update(itemKind='task', schedule=schedule, section='Без раздела', checklist=[],
                    recurrence='none', completed=False, deleted=False, stickyOpen=False, created=now, modified=now, order=order)
        record = {'id': request_id, 'kind': 'task', 'version': 1, 'data': data}
        result = {'ok': True, 'id': request_id, 'message': 'Задача добавлена в Толк'}
        db.execute('INSERT INTO entities VALUES(?,?,?,?,?,?)', (account, 'task', request_id, 1, json.dumps(data), json.dumps({k: 1 for k in data})))
        db.execute('INSERT INTO changes(account,record) VALUES(?,?)', (account, json.dumps(record)))
        db.execute('INSERT INTO capture_requests VALUES(?,?,?,?)', (account, request_id, request, json.dumps(result)))
        db.execute('UPDATE capture_tokens SET seen=? WHERE hash=?', (int(time.time()), store.token_hash(token)))
    return result
