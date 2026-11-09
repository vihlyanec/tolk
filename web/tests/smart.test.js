import {test} from 'node:test';import assert from 'node:assert/strict';import {parseQuick} from '../public/smart.js';
test('Mac named-date form produces the same absolute moment on the web',()=>{
 const p=parseQuick('📞 Созвон 12 дек в 10',{now:Date.parse('2026-11-06T12:00:00Z')});
 assert.equal(p.title,'📞 Созвон');assert.deepEqual(p.schedule,{kind:'timed',instant:Date.parse('2026-12-12T07:00:00Z')/1000});
});
test('unrecognized metadata and impossible dates remain in the title',()=>{
 const p=parseQuick('Работа https://example.com/12дек 31 фев /Неизвестный #неизвестная',{now:Date.parse('2026-11-06T12:00:00Z')});
 assert.equal(p.title,'Работа https://example.com/12дек 31 фев /Неизвестный #неизвестная');assert.equal(p.schedule.kind,'none');assert.ok(p.warnings.length);
});

test('mobile capture recognizes all metadata without consuming unknown tokens',()=>{
 const options={metadata:true,now:Date.parse('2026-11-09T09:00:00Z'),projects:[{id:'p',data:{title:'Работа'}}],tags:[{id:'t',data:{title:'важное'}}]};
 const p=parseQuick('Позвонить завтра в 10 /Работа #важное !1 на 45 мин',options);
 assert.equal(p.title,'Позвонить');assert.deepEqual(p.schedule,{kind:'timed',instant:Date.parse('2026-11-10T07:00:00Z')/1000});
 assert.equal(p.projectID,'p');assert.deepEqual(p.tagIDs,['t']);assert.equal(p.priority,1);assert.equal(p.duration,45);
 assert.deepEqual(new Set(p.recognized),new Set(['projectID','tagIDs','priority','duration','date','time']));
 assert.equal(parseQuick('Проверить /Неизвестный #новая',options).title,'Проверить /Неизвестный #новая');
});
test('relative mobile input keeps the right day across midnight',()=>{
 const options={now:Date.parse('2026-11-09T20:50:00Z')};
 for(const text of ['Проверить через полчаса','Проверить через 30 минут']){
  const p=parseQuick(text,options);assert.equal(p.title,'Проверить');assert.deepEqual(p.schedule,{kind:'timed',instant:Date.parse('2026-11-09T21:20:00Z')/1000});
 }
 assert.deepEqual(parseQuick('Проверить через 2 дня',options).schedule,{kind:'day',day:'2026-11-11'});
});

test('legacy callers never receive UI metadata in the wire patch',()=>{
 assert.equal(Object.hasOwn(parseQuick('Созвон завтра'),'recognized'),false);
});
