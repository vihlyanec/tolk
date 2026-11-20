// Account wire dates: a calendar day or an absolute instant, never an ambiguous clock.
const formatters = new Map();
export function dayAndTime(instant, zone) {
  if(!formatters.has(zone))formatters.set(zone,new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}));
  const parts = formatters.get(zone).formatToParts(new Date(instant * 1000));
  const p = Object.fromEntries(parts.map(v=>[v.type,v.value]));
  return {date:`${p.year}-${p.month}-${p.day}`,time:`${p.hour}:${p.minute}`};
}
export function scheduleFromWall(date,time,zone) {
  if (!date) { if(time) throw new Error('Выберите дату для времени.'); return {kind:'none'}; }
  if (!time) return {kind:'day',day:date};
  const desired=Date.parse(`${date}T${time}:00Z`);
  if (!Number.isFinite(desired)) throw new Error('Проверьте дату и время.');
  let instant=desired;
  for(let i=0;i<4;i++) {
    const wall=dayAndTime(instant/1000,zone);
    const actual=Date.parse(`${wall.date}T${wall.time}:00Z`);
    const delta=desired-actual;if(!delta) break;instant+=delta;
  }
  const check=dayAndTime(instant/1000,zone);
  if(check.date!==date || check.time!==time) throw new Error('Такого времени нет в выбранном часовом поясе.');
  return {kind:'timed',instant:instant/1000};
}
export function projectRecord(record, zone='Europe/Moscow') {
  const r=structuredClone(record);
  if(r.kind==='task' && r.data.schedule) {
    const s=r.data.schedule;
    Object.assign(r.data,s.kind==='timed'?dayAndTime(s.instant,zone):{date:s.kind==='day'?s.day:'',time:''});
  }
  return r;
}
export function canonicalPatch(kind, patch, baseline, zone='Europe/Moscow') {
  patch=structuredClone(patch);
  if(kind==='task' && ('date' in patch || 'time' in patch)) {
    const before=projectRecord(baseline || {kind:'task',data:{}},zone).data;
    patch.schedule=scheduleFromWall(patch.date ?? before.date ?? '',patch.time ?? before.time ?? '',zone);
    delete patch.date;delete patch.time;
  }
  return patch;
}

export const referenceDate = value => typeof value === 'number' ? new Date((value + 978307200) * 1000) : null;

export function taskDescriptionParts(text) {
  const pattern = /(^[ \t]*(?:```|~~~)[^\n]*(?:\n[\s\S]*?^[ \t]*(?:```|~~~)[^\n]*|[\s\S]*$))|(?<!`)`([^`\r\n]+)`(?!`)|https?:\/\/[^\s<>]+|(?<![\p{L}\p{N}_.@/])@([a-zA-Z0-9_]{1,32})(?![\p{L}\p{N}_])/gmu;
  const parts = [];
  let start = 0;
  for (const match of text.matchAll(pattern)) {
    if (match.index > start) parts.push({kind: 'text', value: text.slice(start, match.index)});
    if (match[2]) parts.push({kind: 'code', value: match[2]});
    else if (match[3]) parts.push({kind: 'telegram', value: '@' + match[3], url: 'https://t.me/' + match[3]});
    else parts.push({kind: 'text', value: match[0]});
    start = match.index + match[0].length;
  }
  if (start < text.length) parts.push({kind: 'text', value: text.slice(start)});
  return parts;
}

export function taskStatistics(records, days, zone, today, tagIDs) {
  const dates = Array.from({length: days}, (_, index) => {
    const day = new Date(today + 'T00:00:00Z');
    day.setUTCDate(day.getUTCDate() + index + 1 - days);
    return day.toISOString().slice(0, 10);
  });
  const buckets = new Map(dates.map(day => [day, {day, completed: 0, wontDo: 0}]));
  const bucket = value => typeof value === 'number' ? buckets.get(dayAndTime(value + 978307200, zone).date) : undefined;
  const result = {buckets: [...buckets.values()], created: 0, active: 0, completed: 0, wontDo: 0, undated: false, outcomes: []};
  for (const record of records) {
    const data = record.data;
    if (data.deleted || data.itemKind === 'note' || (tagIDs && !data.tagIDs?.some(id => tagIDs.has(id.toLowerCase())))) continue;
    if (bucket(data.created)) result.created++;
    if (data.completed || data.wontDoAt != null) {
      const outcome = data.completed ? 'completed' : 'wontDo';
      const date = data.completed ? data.completedAt : data.wontDoAt;
      const day = bucket(date);
      if (date == null && data.completed) result.undated = true;
      if (!day) continue;
      day[outcome]++;
      result[outcome]++;
      result.outcomes.push({record, date, outcome});
    } else {
      result.active++;
    }
  }
  result.outcomes.sort((a, b) => b.date - a.date);
  return result;
}

// Each group shares columns until all its intervals end; touching edges start a new group.
function overlapGroups(slots) {
  const groups = [];
  const sorted = [...slots].sort((a, b) => a.start - b.start || b.end - a.end || a.record.id.localeCompare(b.record.id));
  let activeEnd = -1, group, columnEnds;
  for (const slot of sorted) {
    if (slot.start >= activeEnd) {
      group = [];
      groups.push(group);
      columnEnds = [];
    }
    let column = columnEnds.findIndex(end => end <= slot.start);
    if (column < 0) column = columnEnds.length;
    columnEnds[column] = slot.end;
    activeEnd = Math.max(activeEnd, slot.end);
    group.push({...slot, column});
  }
  return groups.map(group => {
    const columns = Math.max(...group.map(slot => slot.column)) + 1;
    return group.map(slot => ({...slot, columns}));
  });
}

export function calendarDayLayout(slots) {
  const backgrounds = overlapGroups(slots.filter(slot => slot.record.kind === 'event')).flat();
  const foreground = overlapGroups(slots.filter(slot => slot.record.kind !== 'event'));
  return backgrounds.concat(foreground.flatMap(group => {
    const start = group[0].start, end = Math.max(...group.map(slot => slot.end));
    // Leave the colored rails selectable even if a task covers the entire background.
    const rails = backgrounds.reduce((count, slot) =>
      slot.start < end && start < slot.end ? Math.max(count, slot.columns) : count, 0);
    return group.map(slot => ({...slot, rails}));
  }));
}

const minutesOfDay = wall => Number(wall.time.slice(0,2)) * 60 + Number(wall.time.slice(3,5));
const civilInstant = wall => Date.parse(wall.date + 'T' + wall.time + ':00Z') / 1000;

export function calendarWeekLayout(records, days, zone) {
  const slots = new Map(days.map(day => [day, []]));
  const earliestPossible = Date.parse(days[0] + 'T00:00:00Z') / 1000 - 86400;
  for (const record of records) {
    const data = record.data;
    if (!data.time || data.date > days.at(-1)) continue;
    const first = {date:data.date, time:data.time};
    const isEvent = record.kind === 'event';
    const instant = isEvent ? data.start : data.schedule?.instant;
    // Legacy tasks without a timed wire schedule retain their stored civil clock.
    const hasInstant = Number.isFinite(instant);
    const startInstant = hasInstant ? instant : civilInstant(first);
    if (!Number.isFinite(startInstant)) continue;
    const endInstant = isEvent && Number.isFinite(data.end) ? data.end : startInstant + (data.duration || 30) * 60;
    if (endInstant < earliestPossible) continue;
    const last = dayAndTime(endInstant, hasInstant ? zone : 'UTC');
    if (last.date < days[0]) continue;
    const overnight = first.date !== last.date;
    const startOffset = civilInstant(first) / 60 - Math.floor(startInstant / 60);
    const endOffset = civilInstant(last) / 60 - Math.floor(endInstant / 60);
    function endpoint(wall, offset) {
      const date = overnight ? wall.date.split('-').reverse().join('.') + ' ' : '';
      if (startOffset === endOffset) return date + wall.time;
      const hours = Math.floor(Math.abs(offset) / 60), minutes = Math.abs(offset) % 60;
      return date + wall.time + ' UTC' + (offset < 0 ? '−' : '+') + hours + (minutes ? ':' + String(minutes).padStart(2,'0') : '');
    }
    const intervalLabel = endpoint(first,startOffset) + '–' + endpoint(last,endOffset);
    for (const [day, daySlots] of slots) {
      if (day < first.date || day > last.date) continue;
      const start = day === first.date ? minutesOfDay(first) : 0;
      let end = day === last.date ? minutesOfDay(last) : 1440;
      // A repeated hour has only one row in the grid. Keep the real endpoints in the label.
      if (end <= start && day === first.date) end = Math.min(1440, start + Math.max(1, (endInstant - startInstant) / 60));
      if (end > start) daySlots.push({record, start, end, intervalLabel, timeLabel:first.time + '–' + last.time});
    }
  }
  return new Map(Array.from(slots, ([day, daySlots]) => [day, calendarDayLayout(daySlots)]));
}
