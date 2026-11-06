import {test} from 'node:test';import assert from 'node:assert/strict';
import {scheduleFromWall,projectRecord} from '../public/model.js';
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
