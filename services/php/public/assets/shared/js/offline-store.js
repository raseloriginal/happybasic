/**
 * Offline storage for the field apps (IndexedDB).
 *  - outbox: writes made while offline, sent to the server in order when the network is back;
 *  - kv:     last known page data (stops, van stock, shops…) so the app opens without network.
 *
 * Every queued op has a unique id; the server stores the result per id (IdempotencyMiddleware),
 * so sending an op twice never applies it twice.
 */
(() => {
    'use strict';

    const DB_NAME = 'hb-offline';
    const VERSION = 1;
    let dbPromise = null;

    function open() {
        if (!('indexedDB' in window)) return Promise.reject(new Error('IndexedDB unavailable'));
        if (!dbPromise) {
            dbPromise = new Promise((resolve, reject) => {
                const req = indexedDB.open(DB_NAME, VERSION);
                req.onupgradeneeded = () => {
                    const db = req.result;
                    if (!db.objectStoreNames.contains('outbox')) db.createObjectStore('outbox', { keyPath: 'seq', autoIncrement: true });
                    if (!db.objectStoreNames.contains('kv')) db.createObjectStore('kv', { keyPath: 'k' });
                };
                req.onsuccess = () => resolve(req.result);
                req.onerror = () => reject(req.error);
            });
            dbPromise.catch(() => { dbPromise = null; });
        }
        return dbPromise;
    }

    async function tx(store, mode, fn) {
        const db = await open();
        return new Promise((resolve, reject) => {
            const t = db.transaction(store, mode);
            let out;
            Promise.resolve(fn(t.objectStore(store))).then((v) => { out = v; });
            t.oncomplete = () => resolve(out);
            t.onerror = () => reject(t.error);
            t.onabort = () => reject(t.error);
        });
    }

    const req2p = (r) => new Promise((resolve, reject) => { r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error); });
    const changed = () => window.dispatchEvent(new CustomEvent('hb-outbox-change'));

    function uuid() {
        if (window.crypto?.randomUUID) return window.crypto.randomUUID();
        const b = new Uint8Array(16);
        window.crypto.getRandomValues(b);
        return Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
    }

    const api = {
        uuid,
        available: () => 'indexedDB' in window,

        kvGet: (k) => tx('kv', 'readonly', (s) => req2p(s.get(k))).then((r) => (r ? r.v : null)).catch(() => null),
        kvSet: (k, v) => tx('kv', 'readwrite', (s) => { s.put({ k, v }); }).catch(() => {}),
        kvDel: (k) => tx('kv', 'readwrite', (s) => { s.delete(k); }).catch(() => {}),

        /** @param {{id:string, user:string, method:string, path:string, body:any, label:string}} op */
        async enqueue(op) {
            await tx('outbox', 'readwrite', (s) => { s.add({ ...op, at: Date.now() }); });
            changed();
        },
        /** Ops of one user, oldest first. */
        list: (user) => tx('outbox', 'readonly', (s) => req2p(s.getAll()))
            .then((all) => all.filter((o) => o.user === String(user)).sort((a, b) => a.seq - b.seq))
            .catch(() => []),
        count: (user) => api.list(user).then((l) => l.length),
        async remove(seq) {
            await tx('outbox', 'readwrite', (s) => { s.delete(seq); });
            changed();
        },
        put: (op) => tx('outbox', 'readwrite', (s) => { s.put(op); }),

        /** Ops the server rejected during sync (kept so the user sees what did not go through). */
        failed: (user) => api.kvGet(`failed:${user}`).then((l) => l || []),
        async addFailed(user, item) {
            const l = await api.failed(user);
            l.push(item);
            await api.kvSet(`failed:${user}`, l);
            changed();
        },
        async clearFailed(user) {
            await api.kvDel(`failed:${user}`);
            changed();
        },
    };

    window.HbOffline = api;
})();
