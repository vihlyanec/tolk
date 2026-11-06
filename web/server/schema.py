"""Lossless native fields shared by Mac and web; credentials stay on the device."""
import math
import re
from datetime import date, datetime, timezone
from zoneinfo import ZoneInfo

ITEM_OPTIONAL = {'repeatEveryDays', 'recurrenceSourceID', 'recurrenceEndDate', 'recurrenceOriginalDate',
                 'repeatParentID', 'externalRecurrence', 'reminderMinutes', 'timedReminderOffsets',
                 'allDayReminders', 'stickyFrame', 'stickyCollapsed', 'stickyExpandedHeight'}
ITEM_FIELDS = ITEM_OPTIONAL | {'itemKind','section','tagIDs','duration','created','modified','checklist','recurrence',
                               'stickyOpen','stickyPinned','stickyColor','schedule','order'}
PROJECT_FIELDS = {'itemKind','folder','sections','archived','kanban','order'}
SETTINGS_FIELDS = {'hourHeight','calendarUXVersion','showCompleted','shiftedShortcuts','completionSoundEnabled',
 'completionHapticsEnabled','quickDraft','quickDraftBody','quickDraftDescriptionExpanded','quickDraftLiterals',
 'defaultTimedReminderOffsets','defaultAllDayReminders','grouping','sorting','integrations','calendarEvents'}


def extras(kind, patch, invalid, identifier):
    allowed = {'task':ITEM_FIELDS, 'project':PROJECT_FIELDS, 'tag':{'title','color','parentID','deleted','order'}, 'settings':SETTINGS_FIELDS, 'event':{'title','notes','location','url','start','end','allDay','timeZone','calendarID','sourceID','eventID','externalID','occurrence','deleted','day','owner'}}.get(kind,set())
    selected = {k:v for k,v in patch.items() if k in allowed}
    for key, value in selected.items():
        if value is None and (key in ITEM_OPTIONAL or key in SETTINGS_FIELDS or key in {'parentID','url','externalID'}): continue
        if key == 'schedule':
            if not isinstance(value,dict) or value.get('kind') not in {'none','day','timed'}: raise invalid('Некорректная дата')
            if value['kind']=='day':
                if set(value)!={'kind','day'} or not isinstance(value['day'],str): raise invalid('Некорректная дата')
                try:
                    if date.fromisoformat(value['day']).isoformat()!=value['day']: raise ValueError()
                except ValueError: raise invalid('Некорректная дата') from None
            elif value['kind']=='timed':
                n=value.get('instant')
                if set(value)!={'kind','instant'} or type(n) not in (int,float) or not math.isfinite(n) or not -62135596800<=n<=253402300799: raise invalid('Некорректное время')
            elif set(value)!={'kind'}: raise invalid('Некорректная дата')
        elif key in {'itemKind','recurrence'}:
            if value not in ({'task','note'} if key=='itemKind' else {'none','daily','weekdays','weekly','monthly','intervalDays'}): raise invalid('Неизвестный вид записи')
        elif key in {'duration','repeatEveryDays','reminderMinutes','hourHeight','created','modified','recurrenceEndDate','recurrenceOriginalDate','stickyExpandedHeight','calendarUXVersion','order','start','end','occurrence'}:
            if type(value) not in (int,float) or not math.isfinite(value): raise invalid('Некорректное число')
            if key=='duration' and (type(value) is not int or not 1<=value<=10080): raise invalid('Некорректная длительность')
            if key=='repeatEveryDays' and (type(value) is not int or not 1<=value<=3650): raise invalid('Некорректный повтор')
            if key=='hourHeight' and not 36<=value<=180: raise invalid('Некорректный масштаб')
            if key=='reminderMinutes' and (type(value) is not int or not 0<=value<=525600): raise invalid('Некорректное напоминание')
        elif key in {'stickyOpen','stickyPinned','stickyCollapsed','externalRecurrence','archived','kanban','deleted','showCompleted','shiftedShortcuts','completionSoundEnabled','completionHapticsEnabled','quickDraftDescriptionExpanded','allDay'}:
            if type(value) is not bool: raise invalid('Ожидается переключатель')
        elif key in {'recurrenceSourceID','repeatParentID','parentID','owner'}:
            if value: identifier(value)
        elif key in {'tagIDs','sections','timedReminderOffsets','allDayReminders','defaultTimedReminderOffsets','defaultAllDayReminders','checklist','stickyFrame','quickDraftLiterals'}:
            if not isinstance(value,list) or len(value)>10000: raise invalid('Некорректный список')
            if key=='tagIDs':
                for entry in value: identifier(entry)
            if key=='sections' and any(not isinstance(v,str) or not v.strip() or len(v)>500 for v in value): raise invalid('Некорректный этап')
            if key in {'timedReminderOffsets','defaultTimedReminderOffsets'} and any(type(v) is not int or not 0<=v<=525600 for v in value): raise invalid('Некорректное напоминание')
            if key in {'allDayReminders','defaultAllDayReminders'}:
                for v in value:
                    if not isinstance(v,dict) or type(v.get('daysBefore')) is not int or not 0<=v['daysBefore']<=365 or type(v.get('minuteOfDay')) is not int or not 0<=v['minuteOfDay']<1440: raise invalid('Некорректное напоминание')
                    identifier(v.get('id'))
            if key=='checklist':
                for v in value:
                    if not isinstance(v,dict) or not isinstance(v.get('title'),str) or len(v['title'])>50000 or type(v.get('done')) is not bool: raise invalid('Некорректный чек-лист')
                    identifier(v.get('id'))
            if key=='stickyFrame' and (len(value)!=4 or any(type(n) not in (int,float) or not math.isfinite(n) for n in value)): raise invalid('Некорректное окно заметки')
        elif key in {'grouping','sorting','integrations','calendarEvents'}:
            if not isinstance(value,dict): raise invalid('Некорректные настройки')
        elif not isinstance(value,str) or len(value)> (50000 if key.startswith('quickDraft') else 50000 if key=='notes' else 4000 if key=='url' else 500): raise invalid('Некорректное поле: '+key)
        if key=='timeZone':
            try:ZoneInfo(value)
            except (ValueError,KeyError):raise invalid('Неизвестный часовой пояс') from None
        if key in {'grouping','sorting'} and (len(value)>1000 or any(not isinstance(k,str) or not isinstance(v,str) or len(k)>500 or len(v)>500 for k,v in value.items())):raise invalid('Некорректный вид списка')
        if key in {'color','stickyColor'} and not re.fullmatch('[0-9a-fA-F]{6}',value): raise invalid('Некорректный цвет')
        if key=='title' and not value.strip(): raise invalid('Введите название')
    return {k:v for k,v in patch.items() if k not in selected}


def legacy_schedule(data, zone='Europe/Moscow'):
    day, clock = data.get('date'),data.get('time')
    if not day: return {'kind':'none'}
    if not clock: return {'kind':'day','day':day}
    local=datetime.fromisoformat(day+'T'+clock).replace(tzinfo=ZoneInfo(zone))
    # Reject non-existent wall times in a DST gap rather than silently moving them.
    if local.astimezone(timezone.utc).astimezone(ZoneInfo(zone)).replace(tzinfo=None)!=local.replace(tzinfo=None): raise ValueError('Такого времени нет в выбранном часовом поясе')
    return {'kind':'timed','instant':local.timestamp()}


def next_recurrence(current, records, zone):
    import calendar as month_calendar
    import copy
    import hashlib
    import uuid
    from datetime import timedelta
    rule=current.get('recurrence','none')
    schedule=current.get('schedule') or legacy_schedule(current,zone)
    if rule=='none' or current.get('itemKind')=='note' or current.get('externalRecurrence') or schedule['kind']=='none':return None
    by_id={r['id'].lower():r['data'] for r in records}
    def source(id,data):
        seen={id.lower()}
        while data.get('recurrenceSourceID') or data.get('repeatParentID'):
            parent=(data.get('recurrenceSourceID') or data['repeatParentID']).lower()
            if parent in seen:break
            seen.add(parent)
            if parent not in by_id:return parent
            id,data=parent,by_id[parent]
        return id.lower()
    root=source(current['id'],current)
    tz=ZoneInfo(zone)
    original=current.get('recurrenceOriginalDate')
    if isinstance(original,(int,float)):base=datetime.fromtimestamp(original+978307200,tz)
    elif schedule['kind']=='timed':base=datetime.fromtimestamp(schedule['instant'],tz)
    else:base=datetime.combine(date.fromisoformat(schedule['day']),datetime.min.time(),tzinfo=tz)
    if rule=='monthly':
        month=base.month%12+1;year=base.year+(base.month==12)
        target=base.replace(year=year,month=month,day=min(base.day,month_calendar.monthrange(year,month)[1]))
    else:
        days=7 if rule=='weekly' else max(1,min(3650,current.get('repeatEveryDays') or 3)) if rule=='intervalDays' else 1
        target=base+timedelta(days=days)
        if rule=='weekdays':
            while target.weekday()>4:target+=timedelta(days=1)
    cutoffs=[r['data']['recurrenceEndDate']+978307200 for r in records if isinstance(r['data'].get('recurrenceEndDate'),(int,float)) and source(r['id'],r['data'])==root]
    if cutoffs and target.timestamp()>=min(cutoffs):return None
    digest=bytearray(hashlib.sha256((root.upper()+':'+str(int(target.timestamp()))).encode()).digest()[:16]);digest[6]=(digest[6]&15)|80;digest[8]=(digest[8]&63)|128
    id=str(uuid.UUID(bytes=bytes(digest)))
    if id in by_id or any((r['data'].get('repeatParentID') or '').lower()==current['id'].lower() for r in records):return None
    result=copy.deepcopy(current);result.pop('id',None)
    result.update(completed=False,deleted=False,stickyOpen=False,stickyFrame=None,recurrenceSourceID=root,repeatParentID=current['id'],recurrenceOriginalDate=target.timestamp()-978307200)
    result['schedule']={'kind':'timed','instant':target.timestamp()} if schedule['kind']=='timed' else {'kind':'day','day':target.date().isoformat()}
    result['checklist']=[{'id':str(uuid.uuid4()),'title':c['title'],'done':False} for c in result.get('checklist',[])]
    result['order']=max([r['data'].get('order',0) for r in records]+[0])+1
    return id,result
