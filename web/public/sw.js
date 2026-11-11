const CACHE = 'tolk-shell-v8';
const SHELL = ['/', '/index.html', '/style.css', '/app.js', '/sync.js', '/model.js', '/smart.js', '/pomodoro.js', '/icon.svg', '/brand.png', '/icon-192.png', '/icon-512.png', '/manifest.webmanifest'];
self.addEventListener('install', event => event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(SHELL))));
self.addEventListener('activate', event => event.waitUntil(Promise.all([
  caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('tolk-shell-') && key !== CACHE).map(key => caches.delete(key)))),
  self.clients.claim(),
])));
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin || event.request.method !== 'GET' || url.pathname.startsWith('/api/')) return;
  if (!SHELL.includes(url.pathname)) return;
  event.respondWith(fetch(event.request).then(response => {
    if (response.ok) {const copy = response.clone(); event.waitUntil(caches.open(CACHE).then(cache => cache.put(url.pathname, copy)));}
    return response;
  }).catch(() => caches.match(url.pathname).then(cached => cached || Response.error())));
});
self.addEventListener('push', event => {
  let message={title:'Толк',body:'Откройте ваши задачи',url:'/'};
  try {if(event.data) Object.assign(message,event.data.json());} catch { /* Always present a visible notification. */ }
  event.waitUntil(self.registration.showNotification(message.title,{body:message.body,tag:message.tag||'tolk',icon:'/icon-192.png',badge:'/icon-192.png',data:{url:message.url}}));
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  let url=new URL(event.notification.data?.url||'/',self.location.origin);
  if(url.origin!==self.location.origin)url=new URL('/',self.location.origin);
  event.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(async windows=>{
    const window=windows.find(w=>new URL(w.url).origin===self.location.origin);
    if(window){await window.navigate(url.href);return window.focus();}
    return self.clients.openWindow(url.href);
  }));
});
