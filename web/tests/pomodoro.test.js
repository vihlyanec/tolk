import {test} from 'node:test';
import assert from 'node:assert/strict';
import {start, decode, seconds, transition, clock} from '../public/pomodoro.js';
test('deadline survives reload, background sleep and waits for the next phase', () => {
  const value = decode(JSON.stringify(start('task','Задача',1000)));
  assert.equal(seconds(value,1500999),1);
  assert.equal(seconds(value,9000000),0);
  assert.equal(value.phase,'focus'); assert.equal(value.completed,0);
  assert.equal(clock(65),'01:05');
});
test('pause, long sleep and idempotent resume retain remaining time', () => {
  let value = transition(start('task','Задача',0),'pause',100000);
  assert.equal(seconds(value,9000000),1400);
  value = transition(value,'resume',9000000);
  value = transition(value,'resume',9100000);
  assert.equal(seconds(value,9100000),1300);
});
test('four focus rounds give three short breaks and a long break', () => {
  let value = start('task','Задача',0);
  assert.deepEqual(transition(value,'next',0),value);
  for (let round = 1; round <= 4; round++) {
    value = transition(value,'next',value.deadline);
    assert.equal(value.completed,round);
    assert.equal(value.phase,round === 4 ? 'longBreak' : 'shortBreak');
    assert.equal(seconds(value,value.deadline - 1),1);
    value = transition(value,'next',value.deadline);
    assert.equal(value.phase,'focus');
  }
});
test('invalid cached timer cannot break the page', () => {
  for (const value of ['broken','null','{}',JSON.stringify({...start('t','title'),remaining:-1}),JSON.stringify({...start('t','title'),phase:'bad'})]) assert.equal(decode(value),null);
});
test('optional continuation note survives pause and resume, old sessions remain valid', () => {
  const original = start('task','Задача',0);
  assert.ok(decode(JSON.stringify(original)));
  const paused = {...transition(original,'pause',100000),resumeNote:'Начать с третьего пункта'};
  assert.equal(decode(JSON.stringify(paused)).resumeNote,paused.resumeNote);
  assert.equal(transition(paused,'resume',200000).resumeNote,paused.resumeNote);
  assert.equal(decode(JSON.stringify({...paused,resumeNote:42})),null);
  assert.ok(decode(JSON.stringify({...paused,resumeNote:''})));
});
