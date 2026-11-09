import {dayAndTime,scheduleFromWall} from './model.js?v=20261109';
// The same unambiguous Russian forms as the Mac quick input; unknown text stays text.
export function parseQuick(text,{projects=[],tags=[],zone='Europe/Moscow',now=Date.now(),metadata=false}={}) {
 let source=text,day='',clock='',duration=30,priority=0,projectID='',tagIDs=[],warnings=[],recognized=[];
 const consume=(regex,action,field)=>{source=source.replace(regex,(...args)=>{const match=args[0];if(!action(args.slice(0,-2)))return match;if(field&&!recognized.includes(field))recognized.push(field);return ' '.repeat(match.length);});};
 consume(/(?<!\S)\/(?:"([^"]+)"|([^\s/]+))(?=\s|$)/giu,v=>{const p=projects.find(p=>p.data.title.toLocaleLowerCase()===(v[1]||v[2]).toLocaleLowerCase());if(!p||projectID)return false;projectID=p.id;return true;},'projectID');
 consume(/(?<![\p{L}\p{N}_/])#(?:"([^"\n]+)"|([\p{L}\p{N}_-]+))/giu,v=>{const t=tags.find(t=>t.data.title.toLocaleLowerCase()===(v[1]||v[2]).toLocaleLowerCase());if(!t)return false;if(!tagIDs.includes(t.id))tagIDs.push(t.id);return true;},'tagIDs');
 consume(/(?<!\S)!([0-3])(?=\s|$)/giu,v=>{priority=Number(v[1]);return true;},'priority');
 consume(/(?<!\S)(важно|срочно|высокий приоритет|средний приоритет|низкий приоритет)(?=\s|$)/giu,v=>{priority=v[1].toLowerCase().startsWith('средний')?2:v[1].toLowerCase().startsWith('низкий')?3:1;return true;},'priority');
 consume(/(?<!\S)на\s+(\d+)\s*(минут(?:у|ы)?|мин\.?|час(?:а|ов)?|ч)(?=\s|$)/giu,v=>{const n=Number(v[1])*(v[2].toLowerCase().startsWith('ч')?60:1);if(n<1||n>10080)return false;duration=n;return true;},'duration');
 const current=dayAndTime(now/1000,zone).date,year=Number(current.slice(0,4));
 const plus=(date,n)=>{const d=new Date(date+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);};
 consume(/(?<!\S)(?:на\s+)?(сегодня|завтра|послезавтра)(?=\s|$)/giu,v=>{day=plus(current,['сегодня','завтра','послезавтра'].indexOf(v[1].toLowerCase()));return true;},'date');
 consume(/(?<!\S)через\s+(\d+)\s*(минут(?:у|ы)?|мин\.?|час(?:а|ов)?|ч|день|дня|дней)(?=\s|$)/giu,v=>{
  const amount=Number(v[1]),unit=v[2].toLowerCase();if(amount<1||amount>3650)return false;
  if(unit.startsWith('д'))day=plus(current,amount);
  else {const wall=dayAndTime(now/1000+amount*(unit.startsWith('ч')?3600:60),zone);day=wall.date;clock=wall.time;if(!recognized.includes('time'))recognized.push('time');}
  return true;
 },'date');
 consume(/(?<!\S)через\s+(полчаса|полтора\s+часа|час)(?=\s|$)/giu,v=>{
  const word=v[1].toLowerCase().replace(/\s+/g,' ');const wall=dayAndTime(now/1000+(word==='полчаса'?1800:word==='час'?3600:5400),zone);day=wall.date;clock=wall.time;if(!recognized.includes('date'))recognized.push('date');return true;
 },'time');
 const checked=(y,m,d)=>{const date=new Date(Date.UTC(y,m-1,d));if(date.getUTCFullYear()!==y||date.getUTCMonth()!==m-1||date.getUTCDate()!==d){warnings.push('Такой даты не существует');return false;}day=date.toISOString().slice(0,10);return true;};
 consume(/(?<!\S)(\d{1,2})\.(\d{1,2})(?:\.(\d{4}))?(?=\s|$)/giu,v=>checked(v[3]?Number(v[3]):year,Number(v[2]),Number(v[1])),'date');
 const months='янв(?:арь|аря)?|фев(?:раль|раля)?|мар(?:т|та)?|апр(?:ель|еля)?|май|мая|июн(?:ь|я)?|июл(?:ь|я)?|авг(?:уст|уста)?|сен(?:т(?:ябрь|ября)?)?|окт(?:ябрь|ября)?|ноя(?:брь|бря)?|дек(?:абрь|абря)?';
 consume(new RegExp('(?<!\\S)(\\d{1,2})\\s+('+months+')\\.?(?:\\s+(\\d{4}))?(?=\\s|$)','giu'),v=>{const month=['янв','фев','мар','апр','ма','июн','июл','авг','сен','окт','ноя','дек'].findIndex(s=>v[2].toLowerCase().startsWith(s))+1;return checked(v[3]?Number(v[3]):year,month,Number(v[1]));},'date');
 const weekdays=['воскресенье','понедельник','вторник','среда','четверг','пятница','суббота'];
 consume(/(?<!\S)(?:в\s+)?(понедельник|вторник|среда|среду|четверг|пятница|пятницу|суббота|субботу|воскресенье)(?=\s|$)/giu,v=>{const name=({'среду':'среда','пятницу':'пятница','субботу':'суббота'})[v[1].toLowerCase()]||v[1].toLowerCase();day=plus(current,(weekdays.indexOf(name)-new Date(current+'T12:00:00Z').getUTCDay()+7)%7);return true;},'date');
 consume(/(?<!\S)(?:в\s+)?([01]?\d|2[0-3]):([0-5]\d)(?=\s|$)/giu,v=>{clock=v[1].padStart(2,'0')+':'+v[2];return true;},'time');
 consume(/(?<!\S)в\s+([01]?\d|2[0-3])(?=\s|$)/giu,v=>{if(clock)return false;clock=v[1].padStart(2,'0')+':00';return true;},'time');
 let schedule=day||clock?scheduleFromWall(day||current,clock,zone):{kind:'none'};
 if(schedule.kind==='timed'&&schedule.instant<now/1000)warnings.push('Распознанное время уже прошло — проверьте дату');
 return {...(metadata?{recognized}:{}),title:source.trim().replace(/\s+/g,' '),schedule,duration,priority,projectID,tagIDs,warnings};
}
