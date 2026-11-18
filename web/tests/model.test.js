import {test} from 'node:test';import assert from 'node:assert/strict';
import {calendarDayLayout,calendarWeekLayout,scheduleFromWall,projectRecord} from '../public/model.js';
test('absolute instants and civil days preserve meaning across time zones',()=>{
 const schedule=scheduleFromWall('2026-12-12','10:00','Europe/Moscow');
 assert.equal(schedule.kind,'timed');
 assert.equal(new Date(schedule.instant*1000).toISOString(),'2026-12-12T07:00:00.000Z');
 const record={kind:'task',data:{schedule,body:'Полное описание',duration:95}};
 assert.equal(projectRecord(record,'Asia/Dubai').data.time,'11:00');
 assert.equal(projectRecord({kind:'task',data:{schedule:{kind:'day',day:'2026-12-12'}}},'Pacific/Honolulu').data.date,'2026-12-12');
 assert.equal(record.data.time,undefined);
});
test('DST gaps are rejected rather than silently scheduled an hour later',()=>{
 assert.throws(()=>scheduleFromWall('2026-03-29','02:30','Europe/Berlin'));
 assert.equal(scheduleFromWall('2026-03-29','03:30','Europe/Berlin').kind,'timed');
});
test('Apple events reserve selectable rails without narrowing the task into a separate column',()=>{
 const slot=(kind,id,start,end)=>({record:{kind,id},start,end});
 const result=calendarDayLayout([
  slot('task','one',19,22),slot('event','shift',15,23),
  slot('task','two',20,21),slot('event','visiting',19,22),slot('task','later',23,24),
 ]);
 assert.deepEqual(result.map(({record,column,columns,rails})=>[record.id,column,columns,rails]),[
  ['shift',0,2,undefined],['visiting',1,2,undefined],['one',0,2,2],['two',1,2,2],['later',0,1,0],
 ]);
 const [background,task]=calendarDayLayout([slot('task','t',15,23),slot('event','e',15,23)]);
 assert.equal(background.columns,1);assert.equal(task.columns,1);assert.equal(task.rails,1);
});
test('overnight task and background keep their real interval and continue into the next day',()=>{
 const days=['2026-11-17','2026-11-18'];
 const instant=Date.parse('2026-11-17T23:00Z')/1000;
 const task={kind:'task',id:'planned',data:{date:days[0],time:'23:00',schedule:{kind:'timed',instant},duration:180}};
 const event={kind:'event',id:'night',data:{date:days[0],time:'23:00',start:instant,end:instant+7200}};
 const midnight={...task,id:'midnight',data:{...task.data,duration:60}};
 const legacy={kind:'task',id:'legacy',data:{date:days[0],time:'23:30',duration:60}};
 const slots=calendarWeekLayout([task,event,midnight,legacy],days,'UTC').get(days[1]);
 assert.deepEqual(slots.map(s=>[s.record.id,s.start,s.end]),[['night',0,60],['planned',0,120],['legacy',0,30]]);
 assert.equal(slots[1].rails,1);assert.equal(slots[1].intervalLabel,'17.11.2026 23:00–18.11.2026 02:00');
});
test('a repeated clock hour keeps both UTC offsets readable in the calendar',()=>{
 const instant=Date.parse('2026-10-25T00:30Z')/1000, day='2026-10-25';
 const task={kind:'task',id:'dst',data:{date:day,time:'02:30',schedule:{kind:'timed',instant},duration:45}};
 const [slot]=calendarWeekLayout([task],[day],'Europe/Berlin').get(day);
 assert.equal(slot.end-slot.start,45);assert.equal(slot.intervalLabel,'02:30 UTC+2–02:15 UTC+1');
});
test('sub-minute EventKit timestamps retain the correct time zone and minute labels',()=>{
 const day='2026-11-18', start=Date.parse(day+'T13:00:55Z')/1000, end=Date.parse(day+'T14:00:10Z')/1000;
 const record={kind:'event',id:'seconds',data:{date:day,time:'16:00',start,end}};
 const [slot]=calendarWeekLayout([record],[day],'Europe/Moscow').get(day);
 assert.equal(slot.intervalLabel,'16:00–17:00');
});
