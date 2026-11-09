import {canonicalPatch, projectRecord} from './model.js?v=20261109';
// Durable account-scoped cache and outbox. Web Locks serialize tabs, including network ACKs.
const database = new Promise((resolve, reject) => {
  const request = indexedDB.open('tolk-web-v1', 1);
  request.onupgradeneeded = () => request.result.createObjectStore('state');
  request.onsuccess = () => resolve(request.result);
  request.onerror = () => reject(request.error);
});
async function read(key) {
  const db = await database;
  return new Promise((resolve, reject) => {
    const req = db.transaction('state').objectStore('state').get(key);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}
async function write(key, value) {
  const db = await database;
  return new Promise((resolve, reject) => {
    const tx = db.transaction('state', 'readwrite');
    tx.objectStore('state').put(value, key);
    tx.oncomplete = resolve;
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  });
}
export async function api(path, body) {
  const response = await fetch('/api/' + path, {
    method: body === undefined ? 'GET' : 'POST',
    headers: body === undefined ? {} : {'Content-Type': 'application/json'},
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(12000),
  });
  const result = await response.json();
  if (!response.ok) throw Object.assign(new Error(result.error), {status: response.status, serverReset:result.serverReset, epoch:result.epoch});
  return result;
}
const key = record => record.kind + ':' + record.id;
const blank = () => ({records: {}, pending: [], conflicts: [], cursor: 0, epoch: null, lastSync: null});
const lock = work => navigator.locks.request('tolk-web-state', work);
const networkLock = work => navigator.locks.request('tolk-web-network', work);
export class Client extends EventTarget {
  account = null;
  state = blank();
  status = '';
  syncing = false;
  authRequired = false;
  channel = new BroadcastChannel('tolk-web');
  constructor() {
    super();
    this.channel.onmessage = async () => {
      const profile = await read('profile');
      if (profile?.id !== this.account?.id) this.account = profile;
      await this.reload();
    };
  }
  async initialize() {
    if (!navigator.locks) throw new Error('Для сохранения данных обновите Safari до актуальной версии.');
    try {
      const session = await api('session');
      await this.setAccount(session.account);
      return session;
    } catch (error) {
      if (error.status) throw error;
      this.account = await read('profile');
      if (this.account) {
        await this.reload();
        this.status = 'Без связи с сервером';
        return {account: this.account};
      }
      throw new Error('Для первого входа нужен доступ к серверу.');
    }
  }
  async setAccount(account) {
    this.account = account;
    this.authRequired = false;
    await write('profile', account);
    this.state = account ? (await read(account.id) || blank()) : blank();
    this.changed();
  }
  async reload() {
    this.state = this.account ? await read(this.account.id) || blank() : blank();
    this.changed();
  }
  revision = 0;
  projection = null;
  fingerprint = '';
  changed() {
    const fingerprint = JSON.stringify([this.account?.id,Object.entries(this.state.records).map(([id,r])=>[id,r.version]),this.state.pending.map(o=>o.id),this.state.conflicts.map(c=>c.operation.id)]);
    if(fingerprint!==this.fingerprint){this.fingerprint=fingerprint;this.revision++;this.projection=null;}
    this.dispatchEvent(new Event('change'));
  }
  async persist() {
    await write(this.account.id, this.state);
    this.channel.postMessage('changed');
    this.changed();
  }
  records(kind) {
    if(!this.projection){
      const all = structuredClone(this.state.records);
      for(const op of this.state.pending){
        const id=op.kind+':'+op.entityID;
        all[id] ||= {kind:op.kind,id:op.entityID,version:0,data:{}};
        Object.assign(all[id].data,op.patch);
      }
      const zone=Object.values(all).find(r=>r.kind==='settings')?.data.timeZone||'Europe/Moscow';
      this.projection={};
      for(const r of Object.values(all))(this.projection[r.kind] ||= []).push(projectRecord(r,zone));
    }
    return this.projection[kind] || [];
  }
  async mutate(kind, entityID, patch, baseline = null) {
    if (!this.account) throw new Error('Войдите в аккаунт');
    await lock(async () => {
      await this.reload();
      if (this.state.conflicts.some(c => c.operation.kind === kind && c.operation.entityID === entityID))
        throw new Error('Сначала выберите версию в настройках.');
      const current = baseline || this.records(kind).find(r => r.id === entityID);
      patch = canonicalPatch(kind,patch,current,this.records('settings')[0]?.data.timeZone || 'Europe/Moscow');
      const expected = Object.fromEntries(Object.keys(patch).map(field => [field, current?.data[field] ?? null]));
      this.state.pending.push({id: crypto.randomUUID(), kind, entityID, base: current?.version || 0, expected, patch});
      await this.persist();
    });
    void this.sync();
  }
  async sync() {
    if (!this.account || this.syncing || this.state.serverReset) return;
    const syncingAccountID=this.account.id;
    this.syncing = true;
    this.status = 'Синхронизация…';
    this.changed();
    try {
      await networkLock(async () => {
        let more = true;
        while (more) {
          const request = await lock(async () => {
          await this.reload();
          if(this.account?.id!==syncingAccountID || this.state.serverReset) return null;
          const blocked = new Set(this.state.conflicts.map(c => c.operation.kind + ':' + c.operation.entityID));
          // One operation per entity in each request: conflicts stop dependent edits.
          const seen = new Set(blocked);
          let bytes = 1000;
          const operations = [];
          for (const op of this.state.pending) {
            const id = op.kind + ':' + op.entityID;
            if (seen.has(id)) continue;
            const size = new TextEncoder().encode(JSON.stringify(op)).length;
            if (operations.length >= 100 || (operations.length && bytes + size > 500000)) break;
            seen.add(id); bytes += size; operations.push(op);
          }
          const sentOperations=this.state.epoch?operations:[];
          return {accountID:this.account.id,operations:sentOperations,cursor:this.state.cursor,epoch:this.state.epoch};
          });
          if(!request) break;
          // Only the network lease spans fetch. Captures/edits keep using the short state lease.
          const response = await api('sync', {operations:request.operations,cursor:request.cursor,epoch:request.epoch});
          await lock(async()=>{
          await this.reload();
          if(this.account?.id!==request.accountID || this.state.serverReset){more=false;return;}
          const sentOperations=request.operations;
          if (this.state.epoch && this.state.epoch !== response.epoch) throw Object.assign(new Error('Сервер восстановлен. Требуется проверка изменений.'),{serverReset:true});
          if(typeof response.epoch!=='string'||!response.epoch||!Number.isSafeInteger(response.cursor)||response.cursor<this.state.cursor||!Array.isArray(response.results)||!Array.isArray(response.changes))throw new Error('Некорректный ответ сервера. Локальная очередь сохранена.');
          // Legacy cached date/time operations are converted only after the first fresh pull.

          if(response.results.length!==sentOperations.length||new Set(response.results.map(r=>r.id)).size!==response.results.length)throw new Error('Ответ сервера неполный. Локальная очередь сохранена.');
          for(const result of response.results){
            const op=sentOperations.find(o=>o.id===result.id);
            if(!op||op.entityID!==result.record.id||op.kind!==result.record.kind)throw new Error('Сервер не подтвердил запись. Изменения остаются на устройстве.');
            if(result.accepted&&(result.record.version<=op.base||Object.entries(op.patch).some(([field,value])=>!(op.kind==='task'&&field==='modified')&&JSON.stringify(result.record.data[field])!==JSON.stringify(value))))throw new Error('Сервер не подтвердил изменения. Локальная очередь сохранена.');
          }
          this.state.epoch=response.epoch;
          const apply = record => {
            if (!this.state.records[key(record)] || this.state.records[key(record)].version <= record.version)
              this.state.records[key(record)] = record;
          };
          for (const result of response.results) {
            const operation = sentOperations.find(op => op.id === result.id);
            apply(result.record);
            if (!result.accepted) this.state.conflicts.push({operation, fields: result.fields, remote: result.record});
            this.state.pending = this.state.pending.filter(op => op.id !== result.id);
          }
          response.changes.forEach(apply);
          this.state.cursor = response.cursor;
          this.state.lastSync = new Date().toISOString();
          await this.persist();
          const conflictIDs = new Set(this.state.conflicts.map(c => c.operation.kind + ':' + c.operation.entityID));
          more = response.more || this.state.pending.some(op => !conflictIDs.has(op.kind + ':' + op.entityID));
          });
        }
      });
      if(this.account?.id!==syncingAccountID)return;
      this.authRequired = false;
      this.status = this.state.conflicts.length ? 'Нужен выбор версии' : 'Изменения сохранены';
    } catch (error) {
      if(this.account?.id!==syncingAccountID)return;
      if (error.status === 401) this.authRequired = true;
      if(error.serverReset) await lock(async()=>{await this.reload();this.state.serverReset=true;await this.persist();});
      this.status = error.status === 401 ? 'Нужно снова войти' : error.status ? error.message : 'Без связи · изменения на устройстве';
    } finally {
      this.syncing = false;
      this.changed();
    }
  }
  async resolve(operationID, useLocal) {
    await lock(async () => {
      await this.reload();
      const conflict = this.state.conflicts.find(c => c.operation.id === operationID);
      if (!conflict) return;
      const op = conflict.operation;
      // Keep every dependent local edit when choosing local; discard only this entity's
      // local chain when the user explicitly chooses the server version.
      const dependent = this.state.pending.filter(p => p.kind === op.kind && p.entityID === op.entityID);
      this.state.pending = this.state.pending.filter(p => !dependent.includes(p));
      if (useLocal) {
        const current = this.state.records[key(conflict.remote)] || conflict.remote;
        const patch = Object.assign({}, op.patch, ...dependent.map(p => p.patch));
        this.state.pending.push({id: crypto.randomUUID(), kind: op.kind, entityID: op.entityID,
          base: current.version, patch});
      }
      this.state.conflicts = this.state.conflicts.filter(c => c !== conflict);
      await this.persist();
    });
    void this.sync();
  }
  async recoverServer() {
    await lock(async()=>{
      await this.reload();
      const local=this.records('task').concat(this.records('project'),this.records('tag'),this.records('settings'));
      const next=blank();let more=true;
      while(more){const response=await api('sync',{operations:[],cursor:next.cursor});next.epoch=response.epoch;next.cursor=response.cursor;for(const r of response.changes)next.records[key(r)]=r;more=response.more;}
      for(const record of local){
        const remote=next.records[key(record)]||{id:record.id,kind:record.kind,version:0,data:{}};
        const data=record.kind==='task'&&!record.data.schedule?canonicalPatch(record.kind,record.data,record,this.records('settings')[0]?.data.timeZone||'Europe/Moscow'):record.data;
        const patch=Object.fromEntries(Object.entries(data).filter(([field,value])=>!['date','time','modified'].includes(field)&&JSON.stringify(remote.data[field])!==JSON.stringify(value)));
        if(Object.keys(patch).length)next.conflicts.push({operation:{id:crypto.randomUUID(),entityID:record.id,kind:record.kind,base:remote.version,patch},fields:Object.keys(patch),remote});
      }
      this.state=next;await this.persist();
    });
    void this.sync();
  }
  async logout() {
    await lock(async () => {
      await this.reload();
      if (this.state.pending.length || this.state.conflicts.length) throw new Error('Перед выходом синхронизируйте изменения и разрешите конфликты.');
      if ('serviceWorker' in navigator) {
        const registration=await navigator.serviceWorker.getRegistration();
        const subscription=await registration?.pushManager.getSubscription();
        if(subscription){await api('push/unsubscribe',{endpoint:subscription.endpoint});await subscription.unsubscribe();}
      }
      await api('logout', {});
      await write(this.account.id, blank());
      await this.setAccount(null);
      this.channel.postMessage('signed-out');
    });
  }
}
