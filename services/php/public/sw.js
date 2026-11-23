/* HappyBasic service worker: keeps map tiles and static assets on the device so they load instantly
 * (and without network) after the first time. Only GET requests for tiles and /assets/ are handled. */
const TILES = 'hb-tiles-v2';   // v2: drops Esri 'no data' tiles cached by v1
const ASSETS = 'hb-assets-v1';
const PAGES = 'hb-pages-v1';
// DSR app pages kept for offline use (network first; the copy is used when the network is down or very slow).
const PAGE_PATH = /\/dsr(\/(dashboard|delivery|van-stock|settlement|expense))?\/?$/;
const PAGE_TIMEOUT_MS = 6000;
const TILE_HOSTS = /^(mt\d\.google\.com|server\.arcgisonline\.com)$/;
const TILE_MAX = 4000;                    // entries
const TILE_TTL = 30 * 24 * 3600 * 1000;   // 30 days
const ASSET_MAX = 300;

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil((async () => {
    const keep = [TILES, ASSETS, PAGES];
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

/** Marks a page served from the phone's copy, so the app knows to use its saved data (data-from-cache="1"). */
async function fromCopy(res) {
    const html = (await res.text()).split('data-from-cache="0"').join('data-from-cache="1"');
    return new Response(html, { status: 200, headers: { 'Content-Type': 'text/html; charset=UTF-8' } });
}

async function pageNetworkFirst(req) {
    const cache = await caches.open(PAGES);
    const url = new URL(req.url);
    const net = fetch(req).then(async (res) => {
        const html = (res.headers.get('content-type') || '').includes('text/html');
        // Only real app pages: never a redirect to the login page or an error page.
        if (res.ok && html && !res.redirected) await cache.put(url.href, res.clone());
        return res;
    });
    const copy = (await cache.match(url.href, { ignoreVary: true }))
        || (url.search ? await cache.match(url.origin + url.pathname, { ignoreVary: true }) : undefined);
    if (!copy) return net;
    net.catch(() => {});
    const slow = new Promise((resolve) => setTimeout(() => resolve(null), PAGE_TIMEOUT_MS));
    try {
        const res = await Promise.race([net, slow]);
        if (res) return res;
    } catch { /* offline */ }
    return fromCopy(copy);
}

self.addEventListener('fetch', (e) => {
    const req = e.request;
    if (req.method !== 'GET') return;
    const url = new URL(req.url);
    if (url.origin === location.origin && PAGE_PATH.test(url.pathname)) {
        e.respondWith(pageNetworkFirst(req));
    } else if (TILE_HOSTS.test(url.hostname)) {
        e.respondWith(cacheFirst(req, TILES, TILE_MAX, TILE_TTL));
    } else if (url.origin === location.origin && /\/(assets|uploads)\//.test(url.pathname)) {
        e.respondWith(cacheFirst(req, ASSETS, ASSET_MAX, 0));
    }
});
