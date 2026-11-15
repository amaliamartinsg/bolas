// Guarda la página en el móvil para que funcione sin conexión una vez abierta.
const CACHE = 'nv1-cache-1';
const FILES = ['./', 'index.html', 'data.js', 'fonts/fraunces-latin-wght-normal.woff2', 'fonts/fraunces-latin-wght-italic.woff2', 'fonts/figtree-latin-wght-normal.woff2'];
self.addEventListener('install', (e) => { e.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES)).then(() => self.skipWaiting())); });
self.addEventListener('activate', (e) => { e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  e.respondWith(fetch(e.request).then((r) => { const cp = r.clone(); caches.open(CACHE).then((c) => c.put(e.request, cp)); return r; }).catch(() => caches.match(e.request)));
});
