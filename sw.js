// Guarda la página en el móvil para que cargue sin conexión una vez abierta.
// Las llamadas a la base de datos (otro dominio, y POST) nunca pasan por aquí.
const CACHE = 'nv2-cache-2';
const FILES = ['./', 'index.html', 'config.js', 'fonts/fraunces-latin-wght-normal.woff2', 'fonts/fraunces-latin-wght-italic.woff2', 'fonts/figtree-latin-wght-normal.woff2'];
self.addEventListener('install', (e) => { e.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES)).then(() => self.skipWaiting())); });
self.addEventListener('activate', (e) => { e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', (e) => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.origin !== self.location.origin) return;
  // Siempre intenta la red (sin caché HTTP) para que no se quede una versión vieja; la copia guardada solo sirve sin conexión.
  e.respondWith(fetch(e.request, { cache: 'no-cache' }).then((r) => { if (r.ok) { const cp = r.clone(); caches.open(CACHE).then((c) => c.put(e.request, cp)); } return r; }).catch(() => caches.match(e.request, { ignoreSearch: true })));
});
