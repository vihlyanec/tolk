"""Account-side task changes for the web client, which can queue edits offline."""
import uuid

from schema import ACTIVITY_LIMIT


def merge_activity(previous, incoming):
    events = {event['id'].lower(): event for event in previous or []}
    for event in incoming or []:
        events.setdefault(event['id'].lower(), event)
    return sorted(events.values(), key=lambda event: (event['date'], event['id'].lower()))[-ACTIVITY_LIMIT:]


def web_task_changes(before, after, project, now):
    changes = {}
    completed = after.get('completed', False)
    if completed != before.get('completed', False):
        changes['completedAt'] = now if completed else None
        sections = project.get('sections', [])
        if completed:
            target = project.get('moveOnCompletion')
            if target in sections and target != after.get('section'):
                changes['sectionBeforeCompletion'] = after.get('section') or 'Без раздела'
                changes['section'] = target
        else:
            target = project.get('moveOnReopen')
            if not target and after.get('section') == project.get('moveOnCompletion'):
                target = before.get('sectionBeforeCompletion')
            if target in sections:
                changes['section'] = target
            changes['sectionBeforeCompletion'] = None
        if completed:
            changes['wontDoAt'] = None
    effective = after | changes
    keys = []
    if completed != before.get('completed', False) or (effective.get('wontDoAt') is not None) != (before.get('wontDoAt') is not None):
        keys.append('completed' if completed else 'wontDo' if effective.get('wontDoAt') is not None else 'reopened')
    if effective.get('deleted', False) != before.get('deleted', False):
        keys.append('deleted' if effective.get('deleted') else 'restored')
    fields = {
        'title': ('title',), 'body': ('body',), 'project': ('projectID',),
        'section': ('section',), 'schedule': ('schedule', 'duration'),
        'priority': ('priority',), 'tags': ('tagIDs',), 'checklist': ('checklist',),
        'recurrence': ('recurrence', 'repeatEveryDays'),
        'reminders': ('reminderMinutes', 'timedReminderOffsets', 'allDayReminders'),
    }
    defaults = {'body': '', 'projectID': '', 'section': 'Без раздела', 'duration': 30,
                'schedule': {'kind': 'none'}, 'priority': 0, 'tagIDs': [],
                'checklist': [], 'recurrence': 'none'}
    def value(data, field):
        result = data.get(field)
        return defaults.get(field) if result is None else result
    keys.extend(key for key, members in fields.items() if any(value(before, field) != value(effective, field) for field in members))
    if keys:
        event = {'id': str(uuid.uuid4()), 'date': now, 'changes': keys}
        changes['taskActivity'] = merge_activity(before.get('taskActivity'), [event])
    return changes
