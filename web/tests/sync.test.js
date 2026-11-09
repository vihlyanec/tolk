import {test, beforeEach} from 'node:test';
import assert from 'node:assert/strict';

// A small in-memory IndexedDB adapter; assertions exercise the real Client outbox.
const memory = new Map();
globalThis.indexedDB = {open() {
  const request = {};
  setTimeout(() => {
    request.result = {transaction() {
      const tx = {objectStore() {return {
        get(key) {
          const req = {};
          queueMicrotask(() => {req.result = structuredClone(memory.get(key)); req.onsuccess();});
          return req;
        },
        put(value, key) {
          memory.set(key, structuredClone(value));
          queueMicrotask(() => tx.oncomplete());
        },
      };}};
      return tx;
    }};
    request.onsuccess();
  }, 0);
  return request;
}};
const leases = new Map();
Object.defineProperty(globalThis, 'navigator', {value:{locks:{request(name, work) {
  const result = (leases.get(name)||Promise.resolve()).then(work);
  leases.set(name,result.catch(() => {}));
  return result;
}}}, configurable:true});
globalThis.BroadcastChannel = class {postMessage() {}};
const {Client} = await import('../public/sync.js');
const account = {id:'50ec0dd5-9f47-4492-aaf2-4d59d91aee55',name:'Test'};
const entityID = 'f3f68145-3f51-49ca-a731-681494697a61';
const record = (version, title) => ({id:entityID,kind:'task',version,data:{title}});
let requests;
beforeEach(() => {memory.clear(); requests=[]; globalThis.fetch = async () => {throw new Error('offline');};});
async function client() {
  const value = new Client();
  await value.setAccount(account);
  // Explicitly drive the sync lifecycle in each test.
  value.syncing = true;
  value.state.epoch = "test-epoch";
  await value.persist();
  return value;
}
function endpoint(answer) {
  globalThis.fetch = async (_url, options) => {
    const request = JSON.parse(options.body); requests.push(request);
    return {ok:true,json:async () => ({epoch:"test-epoch",...answer(request)})};
  };
}
test('an offline mutation survives a new client instance', async () => {
  const first = await client();
  await first.mutate('task',entityID,{title:'Offline'});
  const restored = await client();
  assert.equal(restored.state.pending.length,1);
  assert.equal(restored.records('task')[0].data.title,'Offline');
  assert.equal(restored.state.records['task:' + entityID],undefined);
});
test('a lost response retains the exact operation ID for retry', async () => {
  const value = await client();
  await value.mutate('task',entityID,{title:'Retry'});
  const original = structuredClone(value.state.pending[0]);
  value.syncing = false;
  await value.sync();
  assert.deepEqual(value.state.pending[0], original);
  endpoint(() => ({results:[{id:original.id,accepted:true,record:record(1,'Retry')}],changes:[],cursor:1,more:false}));
  await value.sync();
  assert.deepEqual(requests[0].operations[0],original);
  assert.equal(value.state.pending.length,0);
  assert.equal((await client()).records('task')[0].data.title,'Retry');
});
test('an editor preserves its original revision after a background update', async () => {
  const value = await client();
  const baseline = record(1,'Original');
  value.state.records['task:' + entityID] = record(2,'Remote edit');
  await value.persist();
  await value.mutate('task',entityID,{title:'My edit'},baseline);
  assert.equal(value.state.pending[0].base,1);
  assert.equal(value.state.pending[0].expected.title,'Original');
});
test('a conflict stops dependent operations and local resolution retains them', async () => {
  const value = await client();
  await value.mutate('task',entityID,{title:'First edit'});
  await value.mutate('task',entityID,{title:'Second edit'});
  const first = value.state.pending[0];
  endpoint(request => ({results:request.operations.map(op => ({id:op.id,accepted:false,fields:['title'],record:record(1,'Remote')})),changes:[],cursor:1,more:false}));
  value.syncing = false;
  await value.sync();
  assert.equal(requests.length,1);
  assert.equal(requests[0].operations.length,1);
  assert.equal(value.state.conflicts.length,1);
  assert.equal(value.state.pending.length,1);
  value.syncing = true;
  await value.resolve(first.id,true);
  assert.equal(value.state.pending.length,1);
  assert.equal(value.state.pending[0].patch.title,'Second edit');
  assert.equal(value.state.pending[0].base,1);
  assert.equal(value.state.conflicts.length,0);
});
test('concurrent tabs append without losing either outbox operation', async () => {
  const first = await client(), second = await client();
  await Promise.all([
    first.mutate('task',entityID,{title:'One'}),
    second.mutate('task','202a361f-63e4-47af-ab1d-66d11452cde9',{title:'Two'}),
  ]);
  assert.equal((await client()).state.pending.length,2);
});
test('large offline descriptions are split into requests below the server limit', async () => {
  const value = await client();
  for (let i=0;i<8;i++) await value.mutate('task',crypto.randomUUID(),{title:'Large task',body:'Я'.repeat(50000)});
  endpoint(request => ({results:request.operations.map(op => ({id:op.id,accepted:true,
    record:{id:op.entityID,kind:'task',version:1,data:op.patch}})),changes:[],cursor:0,more:false}));
  value.syncing = false;
  await value.sync();
  assert.ok(requests.length>1);
  assert.ok(requests.every(request => new TextEncoder().encode(JSON.stringify(request)).length<512000));
  assert.equal(value.state.pending.length,0);
  assert.equal(value.records('task').length,8);
});
test('first connection pulls the epoch before sending offline edits', async () => {
  const value=await client();
  await value.mutate('task',entityID,{title:'Offline first'});
  value.state.epoch=null;await value.persist();
  endpoint(request=>({results:request.operations.map(op=>({id:op.id,accepted:true,record:record(1,'Offline first')})),changes:[],cursor:1,more:false}));
  value.syncing=false;await value.sync();
  assert.equal(requests.length,2);
  assert.deepEqual(requests[0].operations,[]);
  assert.equal(requests[1].operations.length,1);
  assert.equal(value.state.pending.length,0);
});
test('incorrect acknowledgement retains durable edits and cursor', async () => {
  const value=await client();await value.mutate('task',entityID,{title:'Keep me'});
  const original=structuredClone(value.state.pending[0]);
  endpoint(()=>({results:[{id:original.id,accepted:true,record:record(1,'Wrong data')}],changes:[],cursor:100,more:false}));
  value.syncing=false;await value.sync();
  const restored=await client();
  assert.deepEqual(restored.state.pending,[original]);assert.equal(restored.state.cursor,0);
});
test('server restoration freezes writes until explicit comparison', async () => {
  const value=await client();await value.mutate('task',entityID,{title:'Local after restore'});
  endpoint(()=>({epoch:'restored-epoch',results:[],changes:[],cursor:0,more:false}));
  value.syncing=false;await value.sync();
  assert.equal(value.state.serverReset,true);assert.equal(value.state.pending.length,1);
  assert.equal(requests.length,1);
  await value.sync();assert.equal(requests.length,1);
});

test('slow sync never blocks capture and ACK preserves edits made during fetch',async()=>{
 const value=await client();await value.mutate('task',entityID,{title:'Before request'});
 let release,started;
 const began=new Promise(resolve=>started=resolve);
 let count=0;
 globalThis.fetch=async(_url,options)=>{
  const request=JSON.parse(options.body);requests.push(request);
  if(++count===1){started();await new Promise(resolve=>release=resolve);}
  return {ok:true,json:async()=>({epoch:'test-epoch',results:request.operations.map(op=>({id:op.id,accepted:true,record:{id:op.entityID,kind:op.kind,version:count,data:op.patch}})),changes:[],cursor:count,more:false})};
 };
 value.syncing=false;const syncing=value.sync();await began;
 try{
  await Promise.race([value.mutate('task',entityID,{title:'Typed while waiting'}),new Promise((_,reject)=>setTimeout(()=>reject(Error('Capture waited on network')),200))]);
  assert.equal(value.records('task')[0].data.title,'Typed while waiting');
 }finally{release();}
 await syncing;
 assert.equal(value.state.pending.length,0);assert.equal(value.records('task')[0].data.title,'Typed while waiting');
 assert.equal(requests.length,2);
});
test('projection is reused on status updates and invalidated on content changes',async()=>{
 const value=await client();await value.mutate('task',entityID,{title:'Cached'});
 const records=value.records('task');value.changed();assert.equal(value.records('task'),records);
 await value.mutate('task',entityID,{title:'Fresh'});assert.notEqual(value.records('task'),records);
 assert.equal(value.records('task')[0].data.title,'Fresh');
});

test('a delayed response cannot install data into a different account',async()=>{
 const value=await client();let release,started;
 const began=new Promise(resolve=>started=resolve);
 globalThis.fetch=async()=>{started();await new Promise(resolve=>release=resolve);return {ok:true,json:async()=>({epoch:'test-epoch',results:[],changes:[record(1,'Private original')],cursor:1,more:false})};};
 value.syncing=false;const syncing=value.sync();await began;
 await value.setAccount({id:'202a361f-63e4-47af-ab1d-66d11452cde9',name:'Different account'});release();await syncing;
 assert.equal(value.records('task').length,0);assert.equal(value.state.cursor,0);
});
