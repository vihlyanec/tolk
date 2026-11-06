import {test} from 'node:test';import assert from 'node:assert/strict';import {parseQuick} from '../public/smart.js';
test('Mac named-date form produces the same absolute moment on the web',()=>{
 const p=parseQuick('📞 Созвон 12 дек в 10',{now:Date.parse('2026-11-06T12:00:00Z')});
 assert.equal(p.title,'📞 Созвон');assert.deepEqual(p.schedule,{kind:'timed',instant:Date.parse('2026-12-12T07:00:00Z')/1000});
});
test('unrecognized metadata and impossible dates remain in the title',()=>{
 const p=parseQuick('Работа https://example.com/12дек 31 фев /Неизвестный #неизвестная',{now:Date.parse('2026-11-06T12:00:00Z')});
 assert.equal(p.title,'Работа https://example.com/12дек 31 фев /Неизвестный #неизвестная');assert.equal(p.schedule.kind,'none');assert.ok(p.warnings.length);
});
