/* HappyBasic service worker: keeps map tiles and static assets on the device so they load instantly
 * (and without network) after the first time. Only GET requests for tiles and /assets/ are handled. */
const TILES = 'hb-tiles-v2';   // v2: drops Esri 'no data' tiles cached by v1
const ASSETS = 'hb-assets-v1';
const TILE_HOSTS = /^(mt\d\.google\.com|server\.arcgisonline\.com)$/;
const TILE_MAX = 4000;                    // entries
const TILE_TTL = 30 * 24 * 3600 * 1000;   // 30 days
const ASSET_MAX = 300;

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil((async () => {
    const keep = [TILES, ASSETS];
    for (const k of await caches.keys()) if (!keep.includes(k)) await caches.delete(k);
    await self.clients.claim();
})()));

async function trim(name, max) {
    const cache = await caches.open(name);
    const keys = await cache.keys();
    for (let i = 0; i < keys.length - max; i++) await cache.delete(keys[i]);   // oldest first
}

async function cacheFirst(req, name, max, ttl) {
    const cache = await caches.open(name);
    const hit = await cache.match(req);
    if (hit) {
        const age = Date.now() - new Date(hit.headers.get('date') || 0).getTime();
        if (!ttl || !(age > ttl)) return hit;
    }
    try {
        const res = await fetch(req);
        if (res && res.ok) {
            cache.put(req, res.clone());
            if (Math.random() < 0.02) trim(name, max);
        }
        return res;
    } catch (err) {
        if (hit) return hit;   // offline: stale tile is better than none
        throw err;
    }
}

self.addEventListener('fetch', (e) => {
    const req = e.request;
    if (req.method !== 'GET') return;
    const url = new URL(req.url);
    if (TILE_HOSTS.test(url.hostname)) {
        e.respondWith(cacheFirst(req, TILES, TILE_MAX, TILE_TTL));
    } else if (url.origin === location.origin && /\/(assets|uploads)\//.test(url.pathname)) {
        e.respondWith(cacheFirst(req, ASSETS, ASSET_MAX, 0));
    }
});
