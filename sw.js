/* Offline cache for Carnet du Moulin. Bump VERSION on every release. */
const VERSION='dar-v2.6.4';
const FILES=['./','./index.html','./manifest.webmanifest','./privacy.html','./delete-data.html','./help.js','./icon-192.png','./icon-512.png','./maskable-512.png','./apple-touch-icon.png','./logo.png','./logo-dark.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(VERSION).then(c=>c.addAll(FILES)).then(()=>self.skipWaiting()))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==VERSION).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{
  if(e.request.method!=='GET'||new URL(e.request.url).origin!==location.origin)return;
  e.respondWith(caches.match(e.request,{ignoreSearch:true}).then(r=>r||fetch(e.request).then(res=>{const cp=res.clone();caches.open(VERSION).then(c=>c.put(e.request,cp));return res}).catch(()=>caches.match('./index.html'))));
});
