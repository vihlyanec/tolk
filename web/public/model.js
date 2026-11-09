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
