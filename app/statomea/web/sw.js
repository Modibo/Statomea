// Service worker de Statoméa (version web hors connexion). __VERSION__ est remplacé par deploy/publish-web.sh :
// chaque version a son propre cache, l'ancien est supprimé à l'activation de la nouvelle.
//  - page (navigation) : réseau d'abord (4 s), cache sinon — une version publiée est vue dès qu'on est en ligne ;
//  - version.json : réseau seulement (détection des mises à jour) ;
//  - autres fichiers du site : cache d'abord, puis réseau (mis en cache au passage : démos, NOTICES…).
const VERSION = '__VERSION__';
const CACHE = 'statomea-' + VERSION;
const CORE = [
  './',
  'flutter_bootstrap.js?v=' + VERSION,
  'main.dart.js?v=' + VERSION,
  'flutter.js',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'canvaskit/canvaskit.js',
  'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js',
  'canvaskit/chromium/canvaskit.wasm',
  'assets/AssetManifest.bin',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
  'assets/fonts/MaterialIcons-Regular.otf',
  'assets/assets/fonts/NotoSans-Regular.ttf',
  'assets/assets/fonts/NotoSans-Bold.ttf',
  'assets/assets/fonts/NotoSansMath-Regular.ttf',
  'assets/assets/logo/statomea_embleme.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // Un fichier absent (nom changé d'une version de Flutter à l'autre) ne doit pas empêcher l'installation.
    await Promise.all(CORE.map((u) => cache.add(new Request(u, { cache: 'reload' })).catch(() => {})));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const k of await caches.keys()) {
      if (k.startsWith('statomea-') && k !== CACHE) await caches.delete(k);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  if (url.pathname.endsWith('/version.json')) return; // toujours le réseau
  if (req.mode === 'navigate') {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE);
      try {
        const res = await Promise.race([
          fetch(req, { cache: 'no-store' }),
          new Promise((_, reject) => setTimeout(() => reject(new Error('délai')), 4000)),
        ]);
        if (res.ok) cache.put('./', res.clone());
        return res;
      } catch (_) {
        return (await cache.match('./')) || (await cache.match(req)) || Response.error();
      }
    })());
    return;
  }
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const hit = await cache.match(req);
    if (hit) return hit;
    const res = await fetch(req);
    if (res.ok && res.type === 'basic') cache.put(req, res.clone());
    return res;
  })());
});
