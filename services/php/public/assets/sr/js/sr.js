(() => {
    'use strict';

    const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

    // Last known GPS position survives SPA switches; retailers always come from the server
    const srStore = {
        srLocation: null,
        retailers: [],
        gpsFix: false,
    };

    let activeLeafletMap = null;
    let activeMapResizeObserver = null;
    let geoWatchId = null;

    function csrfToken() {
        return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
    }

    function appUrl(path) {
        const home = document.querySelector('.mobile-brand')?.getAttribute('href') || '/sr/dashboard';
        return home.replace(/\/sr\/dashboard$/, '') + path;
    }

    // ---------------------------------------------------------------- offline
    // Writes that support offline (`offline` arg of srApi) are queued in IndexedDB when there is no network,
    // applied to the screen right away, and sent in order once the network is back. Each op carries an
    // X-Op-Id; the server answers a repeated op from its stored result, so nothing is applied twice.
    class NetErr extends Error {}
    const HB_USER = document.body.dataset.hbUser || '0';
    const offlineOk = () => !!window.HbOffline?.available() && HB_USER !== '0';
    /** Body value for a retailer id: shops created offline keep their temporary string id until synced. */
    const rid = (id) => (String(id).startsWith('tmp-') ? String(id) : Number(id));
    const isTmp = (id) => String(id).startsWith('tmp-');
    const nowSec = () => Math.floor(Date.now() / 1000);
    const mapKey = `srmap:${HB_USER}`;
    let pageSyncedHook = null; // set by the current page; called after queued ops reached the server

    /** Temporary ids (shop / order made offline) that already got their real id: swap them before sending. */
    async function resolveTmp(path, body) {
        if (body instanceof FormData || !JSON.stringify({ path, body: body ?? null }).includes('tmp-')) return { path, body };
        const map = (await window.HbOffline.kvGet(mapKey)) || {};
        let raw = JSON.stringify({ path, body: body ?? null });
        Object.entries(map).forEach(([t, r]) => { raw = raw.split(t).join(r); });
        const out = JSON.parse(raw);
        return { path: out.path, body: body === undefined ? undefined : out.body };
    }

    async function rawSend(method, path, body, opId, timeoutMs) {
        const ctrl = timeoutMs ? new AbortController() : null;
        const timer = ctrl ? setTimeout(() => ctrl.abort(), timeoutMs) : null;
        let res;
        try {
            res = await fetch(appUrl(path), {
                method,
                credentials: 'same-origin',
                headers: {
                    Accept: 'application/json',
                    ...(body instanceof FormData ? {} : { 'Content-Type': 'application/json' }),
                    'X-Requested-With': 'XMLHttpRequest',
                    'X-CSRF-TOKEN': csrfToken(),
                    ...(opId ? { 'X-Op-Id': opId } : {}),
                },
                body: body === undefined ? undefined : (body instanceof FormData ? body : JSON.stringify(body)),
                signal: ctrl?.signal,
            });
        } catch {
            throw new NetErr('নেটওয়ার্ক সমস্যা। ইন্টারনেট সংযোগ দেখে আবার চেষ্টা করুন।');
        } finally {
            if (timer) clearTimeout(timer);
        }
        let data = {};
        try { data = await res.json(); } catch { /* non-JSON */ }
        return { res, data };
    }

    /**
     * @param {{label:string, apply:function():object, tmp?:string}=} offline  when given, the write is queued
     *        instead of failing if the network is down; `apply` makes the same change on screen right away.
     */
    async function srApi(method, path, body, offline) {
        const canQueue = !!offline && offlineOk();
        const opId = canQueue ? window.HbOffline.uuid() : null;
        // Keep order: while older ops wait in the queue, new ones go behind them.
        if (canQueue && (!navigator.onLine || (await window.HbOffline.count(HB_USER)) > 0)) {
            return queueOp(opId, method, path, body, offline);
        }
        if (canQueue) ({ path, body } = await resolveTmp(path, body));
        let r;
        try {
            r = await rawSend(method, path, body, opId, canQueue ? 15000 : 0);
        } catch (err) {
            if (canQueue && err instanceof NetErr) return queueOp(opId, method, path, body, offline);
            throw err;
        }
        const { res, data } = r;
        if (res.status === 401) {
            window.location.href = data.redirect || appUrl('/sr/login');
            throw new Error('সেশন শেষ হয়েছে।');
        }
        if (res.status === 419) throw new Error('সেশন মেয়াদ শেষ। অনুগ্রহ করে পেজ রিলোড করুন।');
        if (!res.ok || data.ok === false) throw new Error(data.message || `অনুরোধ ব্যর্থ হয়েছে (HTTP ${bnDigits(res.status)})।`);
        return data;
    }

    async function queueOp(id, method, path, body, offline) {
        const result = offline.apply() || {}; // may throw (e.g. day already completed) → nothing is queued
        await window.HbOffline.enqueue({ id, user: HB_USER, method, path, body, label: offline.label, tmp: offline.tmp || null });
        scheduleSync(1500);
        return { ...result, queued: true, message: 'অফলাইনে সংরক্ষিত — নেট পেলে নিজে থেকে সিঙ্ক হবে।' };
    }

    let syncing = false;
    let syncTimer = null;
    function scheduleSync(ms) {
        clearTimeout(syncTimer);
        syncTimer = setTimeout(syncOutbox, ms);
    }

    async function refreshCsrf() {
        try {
            const { res, data } = await rawSend('GET', '/sr/csrf', undefined, null, 15000);
            if (!res.ok || !data.token) return false;
            document.querySelector('meta[name="csrf-token"]')?.setAttribute('content', data.token);
            return true;
        } catch { return false; }
    }

    /** A shop / order made offline got its real id: rewrite the ops still waiting that refer to it, and remember it. */
    async function remapTmp(tmp, real, rest) {
        const map = (await window.HbOffline.kvGet(mapKey)) || {};
        map[tmp] = real;
        await window.HbOffline.kvSet(mapKey, map);
        for (const op of rest) {
            const before = JSON.stringify({ path: op.path, body: op.body ?? null });
            if (!before.includes(tmp)) continue;
            const after = JSON.parse(before.split(tmp).join(real));
            await window.HbOffline.put({ ...op, path: after.path, body: op.body === undefined ? undefined : after.body });
        }
        srStore.retailers.forEach((r) => { if (String(r.id) === tmp) r.id = real; });
    }

    async function syncOutbox() {
        if (syncing || !offlineOk() || !navigator.onLine) return;
        syncing = true;
        renderSyncPill();
        let synced = 0;
        let csrfRetried = false;
        try {
            for (;;) {
                const ops = await window.HbOffline.list(HB_USER);
                if (!ops.length) break;
                const op = ops[0];
                let r;
                try {
                    r = await rawSend(op.method, op.path, op.body, op.id, 30000);
                } catch {
                    scheduleSync(30000); // still no network — try again later
                    break;
                }
                const { res, data } = r;
                if (res.status === 419 && !csrfRetried) {
                    csrfRetried = true;
                    if (await refreshCsrf()) continue;
                }
                if (res.status === 401 || res.status === 419) {
                    showToast('সিঙ্কের জন্য আবার লগইন করুন — অফলাইনের কাজগুলো রাখা আছে।');
                    break;
                }
                if (res.status >= 500 || res.status === 429) {
                    scheduleSync(60000);
                    break;
                }
                if (res.ok && data.ok !== false) {
                    const real = data.retailer?.id ?? data.order?.id;
                    if (op.tmp && real) await remapTmp(op.tmp, String(real), ops.slice(1));
                } else {
                    // The server refused it (e.g. day already assigned to a trip): keep a record for the user.
                    await window.HbOffline.addFailed(HB_USER, { label: op.label, message: data.message || `HTTP ${res.status}`, at: op.at });
                }
                await window.HbOffline.remove(op.seq);
                synced += 1;
            }
        } finally {
            syncing = false;
            renderSyncPill();
        }
        if (synced > 0) {
            showToast(`${bnDigits(synced)}টি অফলাইন কাজ সিঙ্ক হয়েছে।`);
            if ((await window.HbOffline.count(HB_USER)) === 0) pageSyncedHook?.();
        }
    }

    // Sync status pill (offline / waiting / syncing / failed)
    const syncPill = document.createElement('button');
    syncPill.type = 'button';
    syncPill.className = 'hb-sync-pill';
    syncPill.hidden = true;
    document.body.appendChild(syncPill);
    async function renderSyncPill() {
        if (!offlineOk()) return;
        const [ops, failed] = await Promise.all([window.HbOffline.list(HB_USER), window.HbOffline.failed(HB_USER)]);
        const n = ops.length;
        let text = '';
        let tone = '';
        if (failed.length) { text = `⚠ ${bnDigits(failed.length)}টি কাজ সিঙ্ক হয়নি — দেখুন`; tone = 'is-failed'; }
        else if (syncing && n) { text = `সিঙ্ক হচ্ছে… (${bnDigits(n)})`; tone = 'is-syncing'; }
        else if (n) { text = `${navigator.onLine ? '' : 'অফলাইন · '}${bnDigits(n)}টি কাজ সিঙ্ক বাকি`; tone = 'is-waiting'; }
        else if (!navigator.onLine) { text = 'অফলাইন মোড'; tone = 'is-offline'; }
        syncPill.hidden = !text;
        syncPill.textContent = text;
        syncPill.className = `hb-sync-pill ${tone}`;
    }
    syncPill.addEventListener('click', async () => {
        const failed = await window.HbOffline.failed(HB_USER);
        if (failed.length) {
            window.alert(`এই কাজগুলো সার্ভার গ্রহণ করেনি, আবার করতে হবে:\n\n${failed.map((f) => `• ${f.label}: ${f.message}`).join('\n')}`);
            await window.HbOffline.clearFailed(HB_USER);
            return;
        }
        syncOutbox();
    });
    if (offlineOk()) {
        window.addEventListener('hb-outbox-change', renderSyncPill);
        window.addEventListener('online', () => { renderSyncPill(); syncOutbox(); });
        window.addEventListener('offline', renderSyncPill);
        document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') syncOutbox(); });
        renderSyncPill();
        scheduleSync(800);
    }

    // Logout: warn about unsynced work; forget cached pages/data of this user on this phone.
    document.addEventListener('submit', async (e) => {
        const f = e.target;
        if (!(f instanceof HTMLFormElement) || !/\/sr\/logout$/.test(f.getAttribute('action') || '') || f.dataset.confirmed) return;
        if (!offlineOk()) return;
        e.preventDefault();
        const n = await window.HbOffline.count(HB_USER);
        if (n > 0 && !window.confirm(`${bnDigits(n)}টি অফলাইন কাজ এখনো সিঙ্ক হয়নি। সাইন আউট করলেও সেগুলো এই ফোনে থাকবে এবং আবার লগইন করলে সিঙ্ক হবে। সাইন আউট করবেন?`)) return;
        await Promise.all([window.HbOffline.kvDel(`sr:${HB_USER}`), window.HbOffline.kvDel(`srshops:${HB_USER}`), window.HbOffline.kvDel(mapKey), window.caches?.delete('hb-pages-v1')]);
        f.dataset.confirmed = '1';
        f.submit();
    }, true);

    // Keep every SR page in the offline cache (once per session, in the background). Marked done only when the
    // Service Worker controlled the requests and every page came back.
    if (offlineOk() && navigator.serviceWorker && navigator.onLine) {
        const warm = async () => {
            try { if (sessionStorage.getItem('hb-sr-warm')) return; } catch { /* private mode */ }
            if (!navigator.serviceWorker.controller || !navigator.onLine) return;
            let ok = true;
            for (const p of ['/sr/order', '/sr/dashboard', '/sr/history', '/sr/profile']) {
                try { ok = (await fetch(appUrl(p), { credentials: 'same-origin' })).ok && ok; } catch { ok = false; }
            }
            if (ok) try { sessionStorage.setItem('hb-sr-warm', '1'); } catch { /* private mode */ }
        };
        navigator.serviceWorker.ready.then(() => setTimeout(warm, 2500)).catch(() => {});
        navigator.serviceWorker.addEventListener('controllerchange', () => setTimeout(warm, 1000));
    }

    function destroyOrderMap() {
        if (geoWatchId !== null && navigator.geolocation) {
            navigator.geolocation.clearWatch(geoWatchId);
            geoWatchId = null;
        }
        if (activeMapResizeObserver) {
            try {
                activeMapResizeObserver.disconnect();
            } catch {
                // ignore
            }
            activeMapResizeObserver = null;
        }
        if (activeLeafletMap) {
            try {
                activeLeafletMap.remove();
            } catch {
                // ignore cleanup errors if node already detached
            }
            activeLeafletMap = null;
        }
    }

    // Initial Full-Page Boot Loader
    const bootLoader = document.getElementById('appBootLoader');
    if (bootLoader) {
        let dismissed = false;
        const dismiss = () => {
            if (dismissed) return;
            dismissed = true;
            bootLoader.classList.add('is-hidden');
            setTimeout(() => bootLoader.remove(), 250);
        };
        if (document.readyState === 'complete') {
            requestAnimationFrame(dismiss);
        } else {
            window.addEventListener('load', () => setTimeout(dismiss, 110), { once: true });
            setTimeout(dismiss, 1600);
        }
    }

    // Toast
    const toastStack = document.getElementById('toastStack');
    function showToast(message) {
        if (!toastStack) return;
        const el = document.createElement('div');
        el.className = 'toast';
        el.textContent = message;
        toastStack.appendChild(el);
        setTimeout(() => el.remove(), 1000);
    }

    function escapeHtml(str) {
        return String(str ?? '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    const BN_DIGITS = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    const UNIT_BN = {
        Carton: 'কার্টন', Case: 'কেস', Box: 'বক্স', Pack: 'প্যাক',
        Dozen: 'ডজন', Sack: 'বস্তা', Bag: 'ব্যাগ', Piece: 'পিস', Unit: 'ইউনিট',
    };
    const STATUS_BN = {
        pending: 'অপেক্ষমান', assigned: 'নির্ধারিত', dispatched: 'রাস্তায়',
        in_review: 'কনফার্ম বাকি', settled: 'সেটেল্ড', delivered: 'ডেলিভার্ড',
        due: 'বাকি', partial: 'আংশিক', cancelled: 'বাতিল',
    };
    const MONTHS_BN = ['জানু', 'ফেব্রু', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট', 'সেপ্টে', 'অক্টো', 'নভে', 'ডিসে'];

    function bnDigits(v) {
        return String(v ?? '').replace(/\d/g, (d) => BN_DIGITS[Number(d)]);
    }

    function bnNum(n, decimals = 0) {
        return bnDigits(Number(n || 0).toLocaleString('en-US', { minimumFractionDigits: decimals, maximumFractionDigits: decimals }));
    }

    function bnUnit(u) {
        return UNIT_BN[u] || u || 'ইউনিট';
    }

    function bnStatus(key) {
        const k = String(key || '').trim().toLowerCase().replace(/\s+/g, '_');
        return STATUS_BN[k] || String(key || '');
    }

    function formatBdt(amount) {
        return `৳ ${bnDigits(Number(amount || 0).toLocaleString('en-US'))}`;
    }

    function haversineMeters(lat1, lon1, lat2, lon2) {
        const R = 6371000;
        const toRad = (deg) => (deg * Math.PI) / 180;
        const dLat = toRad(lat2 - lat1);
        const dLon = toRad(lon2 - lon1);
        const a = Math.sin(dLat / 2) ** 2
            + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
        return Math.round(R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)) * 10) / 10;
    }

    function formatDistance(meters) {
        if (meters >= 1000) {
            return `${bnDigits((meters / 1000).toFixed(2))} কি.মি.`;
        }
        return `${bnDigits(meters)} মি.`;
    }

    // =========================================================================
    // BANGLISH + BANGLA PHONETIC SEARCH ENGINE (Client-cached & non-blocking)
    // =========================================================================
    const BanglishSearch = (() => {
        const BN_VOWELS_INDEP = {
            'অ': ['o', 'a'], 'আ': ['a', 'a'], 'ই': ['i', 'i'], 'ঈ': ['i', 'i'],
            'উ': ['u', 'u'], 'ঊ': ['u', 'u'], 'ঋ': ['ri', 'ri'],
            'এ': ['e', 'e'], 'ঐ': ['oi', 'oi'], 'ও': ['o', 'o'], 'ঔ': ['ou', 'ou'],
        };
        const BN_KAR = {
            'া': 'a', 'ি': 'i', 'ী': 'i', 'ু': 'u', 'ূ': 'u',
            'ৃ': 'ri', 'ে': 'e', 'ৈ': 'oi', 'ো': 'o', 'ৌ': 'ou',
        };
        const BN_CONS = {
            'ক': 'k', 'খ': 'kh', 'গ': 'g', 'ঘ': 'gh', 'ঙ': 'ng',
            'চ': 'ch', 'ছ': 'ch', 'জ': 'j', 'ঝ': 'jh', 'ঞ': 'n',
            'ট': 't', 'ঠ': 'th', 'ড': 'd', 'ঢ': 'dh', 'ণ': 'n',
            'ত': 't', 'থ': 'th', 'দ': 'd', 'ধ': 'dh', 'ন': 'n',
            'প': 'p', 'ফ': 'f', 'ব': 'b', 'ভ': 'v', 'ম': 'm',
            'য': 'j', 'র': 'r', 'ল': 'l',
            'শ': 'sh', 'ষ': 'sh', 'স': 's', 'হ': 'h',
            'ড়': 'r', 'ঢ়': 'r', 'য়': 'y',
            'ৎ': 't', 'ং': 'ng', 'ঃ': 'h', 'ঁ': '',
        };
        const BN_DIGIT_EN = { '০': '0', '১': '1', '২': '2', '৩': '3', '৪': '4', '৫': '5', '৬': '6', '৭': '7', '৮': '8', '৯': '9' };
        const toEnDigits = (s) => String(s || '').replace(/[০-৯]/g, (d) => BN_DIGIT_EN[d]);

        function foldStrict(s) {
            return toEnDigits(s).toLowerCase()
                .replace(/ph/g, 'f')
                .replace(/bh/g, 'v')
                .replace(/q/g, 'k')
                .replace(/z/g, 'j')
                .replace(/ee+/g, 'i')
                .replace(/oo+/g, 'u')
                .replace(/aa+/g, 'a')
                .replace(/c(?=[eiy])/g, 's')
                .replace(/c(?!h)/g, 'k')
                .replace(/chh/g, 'ch')
                .replace(/oy/g, 'oi')
                .replace(/ow/g, 'ou')
                .replace(/([bcdfghjklmnpqrstvwxyz])e$/g, '$1')
                .replace(/([a-z])\1+/g, '$1');
        }

        function foldLoose(s) {
            return s
                .replace(/sh/g, 's')
                .replace(/kh/g, 'k')
                .replace(/gh/g, 'g')
                .replace(/th/g, 't')
                .replace(/dh/g, 'd')
                .replace(/jh/g, 'j')
                .replace(/ch/g, 'c')
                .replace(/[vw]/g, 'b')
                .replace(/([a-z])\1+/g, '$1');
        }

        function foldGlide(s) {
            return s
                .replace(/([aeiou])y([aeiou])/g, '$1$2')
                .replace(/y/g, 'i')
                .replace(/ae/g, 'ai')
                .replace(/([ai])h([ai])/g, '$1$2')
                .replace(/([a-z])\1+/g, '$1');
        }

        function foldAnchor(s) {
            return s
                .replace(/([aeiou])[ie]+/g, '$1')
                .replace(/ou/g, 'o')
                .replace(/oi/g, 'o');
        }

        const WORD_CACHE = new Map();
        const ITEM_CACHE = new WeakMap();

        function buildWordPhonetics(word) {
            const cached = WORD_CACHE.get(word);
            if (cached) return cached;

            const units = [];
            const len = word.length;
            let i = 0;

            while (i < len) {
                const ch = word[i];
                const code = ch.charCodeAt(0);
                if (code < 0x0980 || code > 0x09FF) {
                    const norm = toEnDigits(ch).toLowerCase();
                    if (/[a-z0-9]/.test(norm)) {
                        units.push({ s: i, e: i + 1, a: norm, o: norm, ns: norm });
                    }
                    i++;
                    continue;
                }
                const ind = BN_VOWELS_INDEP[ch];
                if (ind) {
                    units.push({ s: i, e: i + 1, a: ind[0], o: ind[1], ns: ind[0] });
                    i++;
                    continue;
                }
                if (ch === 'ং' || ch === 'ঃ' || ch === 'ঁ' || ch === 'ৎ') {
                    const val = BN_CONS[ch];
                    if (val) units.push({ s: i, e: i + 1, a: val, o: val, ns: val });
                    i++;
                    continue;
                }
                if (BN_CONS[ch] !== undefined) {
                    const start = i;
                    let cParts = '';
                    let hasHasantaEnd = false;
                    while (i < len && BN_CONS[word[i]] !== undefined) {
                        const c = word[i];
                        if (c === 'ক' && word[i + 1] === '্' && word[i + 2] === 'ষ') {
                            cParts += 'kh';
                            i += 3;
                        } else if (c === 'জ' && word[i + 1] === '্' && word[i + 2] === 'ঞ') {
                            cParts += 'g';
                            i += 3;
                        } else if (i > start && word[i - 1] === '্' && (c === 'য' || c === 'ব' || c === 'ম')) {
                            i++;
                        } else {
                            cParts += BN_CONS[c];
                            i++;
                        }
                        if (i < len && word[i] === '্') {
                            i++;
                            if (i >= len || BN_CONS[word[i]] === undefined) {
                                hasHasantaEnd = true;
                                break;
                            }
                        } else {
                            break;
                        }
                    }
                    let kar = '';
                    while (i < len && (BN_KAR[word[i]] !== undefined || word[i] === 'ঁ')) {
                        if (BN_KAR[word[i]] !== undefined) kar += BN_KAR[word[i]];
                        i++;
                    }
                    if (kar !== '' || hasHasantaEnd) {
                        const tok = cParts + kar;
                        units.push({ s: start, e: i, a: tok, o: tok, ns: tok });
                    } else if (i >= len) {
                        units.push({ s: start, e: i, a: cParts, o: cParts, ns: cParts });
                    } else {
                        const drop = units.length > 0;
                        units.push({ s: start, e: i, a: `${cParts}a`, o: `${cParts}o`, ns: drop ? cParts : `${cParts}a` });
                    }
                    continue;
                }
                i++;
            }

            const variants = [];
            const seenBase = new Set();
            const addMode = (mode) => {
                let str = '';
                for (let u = 0; u < units.length; u++) str += units[u][mode];
                const st = foldStrict(str);
                if (!seenBase.has(st)) {
                    seenBase.add(st);
                    const lo = foldLoose(st);
                    const gl = foldGlide(lo);
                    const an = foldAnchor(gl);
                    variants.push({ st, lo, gl, an });
                }
            };
            addMode('a');
            addMode('o');
            addMode('ns');

            const res = { units, variants, rawLower: toEnDigits(word).toLowerCase() };
            if (WORD_CACHE.size < 16000) WORD_CACHE.set(word, res);
            return res;
        }

        function indexText(text) {
            const raw = String(text || '');
            const words = [];
            const re = /[^\s,.\-_/()]+/g;
            let m;
            while ((m = re.exec(raw)) !== null) {
                words.push(buildWordPhonetics(m[0]));
            }
            return { raw, lower: toEnDigits(raw).toLowerCase(), words };
        }

        function getIndexed(item, keyText) {
            const existing = ITEM_CACHE.get(item);
            if (existing && existing.keyText === keyText) return existing.idx;
            const idx = indexText(keyText);
            ITEM_CACHE.set(item, { keyText, idx });
            return idx;
        }

        function compileQuery(query) {
            const qRaw = String(query || '').trim();
            if (!qRaw) return null;
            const tokens = qRaw.split(/\s+/).filter(Boolean).map((qt) => {
                const lower = toEnDigits(qt).toLowerCase();
                const st = foldStrict(qt);
                const lo = foldLoose(st);
                const gl = foldGlide(lo);
                const an = foldAnchor(gl);
                return { lower, st, lo, gl, an };
            });
            return tokens.length ? tokens : null;
        }

        function scoreCompiled(indexed, qTokens) {
            if (!qTokens) return 0;
            let total = 0;
            for (let t = 0; t < qTokens.length; t++) {
                const q = qTokens[t];
                let best = 0;

                const rIdx = indexed.lower.indexOf(q.lower);
                if (rIdx !== -1) {
                    best = rIdx === 0 ? 104 : (indexed.lower[rIdx - 1] === ' ' ? 94 : 60);
                }

                for (let wi = 0; wi < indexed.words.length; wi++) {
                    const w = indexed.words[wi];
                    const bonus = wi === 0 ? 10 : 0;
                    if (q.lower.length >= 2 && w.rawLower === q.lower) best = Math.max(best, 118 + bonus);
                    else if (w.rawLower.startsWith(q.lower)) best = Math.max(best, 94 + bonus);

                    const vars = w.variants;
                    for (let vi = 0; vi < vars.length; vi++) {
                        const v = vars[vi];
                        if (q.st.length >= 3 && v.st === q.st) best = Math.max(best, 116 + bonus);
                        else if (q.gl.length >= 3 && v.gl === q.gl) best = Math.max(best, 112 + bonus);
                        else if (q.an.length >= 3 && v.an === q.an) best = Math.max(best, 108 + bonus);
                        else if (v.st.startsWith(q.st)) best = Math.max(best, 94 + bonus);
                        else if (v.lo.startsWith(q.lo)) best = Math.max(best, 84 + bonus);
                        else if (v.gl.startsWith(q.gl)) best = Math.max(best, (q.gl.length >= 3 ? 82 : 76) + bonus);
                        else if (q.an.length >= 3 && v.an.startsWith(q.an)) best = Math.max(best, 72 + bonus);
                        else if (q.st.length >= 3 && v.st.includes(q.st)) best = Math.max(best, 50 + bonus);
                        else if (q.gl.length >= 3 && v.gl.includes(q.gl)) best = Math.max(best, 44 + bonus);
                        else if (q.an.length >= 3 && v.an.includes(q.an)) best = Math.max(best, 34 + bonus);
                    }
                }
                if (best === 0) return 0;
                total += best;
            }
            return Math.round(total / qTokens.length);
        }

        function findHighlightRange(text, query) {
            const raw = String(text ?? '');
            const qRaw = String(query || '').trim();
            if (!qRaw) return null;

            const direct = raw.toLowerCase().indexOf(qRaw.toLowerCase());
            if (direct !== -1) return [direct, direct + qRaw.length];

            const firstToken = qRaw.split(/\s+/)[0];
            if (!firstToken) return null;
            const qSt = foldStrict(firstToken);
            const qLo = foldLoose(qSt);
            const qGl = foldGlide(qLo);
            const qAn = foldAnchor(qGl);

            const re = /[^\s,.\-_/()]+/g;
            let m;
            const tiers = ['st', 'lo', 'gl', 'an'];
            while ((m = re.exec(raw)) !== null) {
                const bp = buildWordPhonetics(m[0]);
                for (let ti = 0; ti < tiers.length; ti++) {
                    const tier = tiers[ti];
                    const qTarget = tier === 'st' ? qSt : tier === 'lo' ? qLo : tier === 'gl' ? qGl : qAn;
                    if (!qTarget || (tier === 'an' && qTarget.length < 3)) continue;
                    const modes = ['a', 'o', 'ns'];
                    for (let mi = 0; mi < modes.length; mi++) {
                        const mode = modes[mi];
                        for (let su = 0; su < bp.units.length; su++) {
                            if (su > 0 && qTarget.length < 3) break;
                            let pref = '';
                            for (let ui = su; ui < bp.units.length; ui++) {
                                pref += bp.units[ui][mode];
                                let f = foldStrict(pref);
                                if (tier !== 'st') f = foldLoose(f);
                                if (tier === 'gl' || tier === 'an') f = foldGlide(f);
                                if (tier === 'an') f = foldAnchor(f);
                                if (f.startsWith(qTarget)) {
                                    return [m.index + bp.units[su].s, m.index + bp.units[ui].e];
                                }
                            }
                        }
                    }
                }
            }
            return null;
        }

        function highlight(text, query) {
            const raw = String(text ?? '');
            const rng = findHighlightRange(raw, query);
            if (!rng) return escapeHtml(raw);
            return escapeHtml(raw.slice(0, rng[0]))
                + `<mark class="suggest-hit">${escapeHtml(raw.slice(rng[0], rng[1]))}</mark>`
                + escapeHtml(raw.slice(rng[1]));
        }

        function warmup(items, keyFn) {
            let pos = 0;
            const batchSize = 350;
            function step() {
                const end = Math.min(items.length, pos + batchSize);
                for (; pos < end; pos++) {
                    getIndexed(items[pos], keyFn(items[pos]));
                }
                if (pos < items.length) setTimeout(step, 0);
            }
            if (items.length) setTimeout(step, 16);
        }

        return { getIndexed, compileQuery, scoreCompiled, highlight, warmup };
    })();

    function renderSuggestLoadingMarkup(label = 'খোঁজা হচ্ছে…') {
        const rows = Array.from({ length: 4 }, (_, i) => `
            <div class="suggest-sk-row">
                <div class="suggest-sk-col">
                    <span class="sk sk-line" style="width:${[64, 52, 72, 58][i]}%"></span>
                    <span class="sk sk-line" style="width:${[42, 48, 36, 44][i]}%;height:8px"></span>
                </div>
                <span class="sk sk-pill" style="width:54px"></span>
            </div>
        `).join('');
        return `
            <div class="suggest-load-wrap">
                <div class="suggest-load-bar"><span></span></div>
                <div class="suggest-load-label">
                    <span class="search-spinner" aria-hidden="true"></span>
                    <span>${escapeHtml(label)}</span>
                </div>
                ${rows}
            </div>
        `;
    }

    function setButtonLoading(btn, loading, text = 'লোড হচ্ছে…') {
        if (!btn) return;
        if (loading) {
            if (!btn.dataset.origHtml) btn.dataset.origHtml = btn.innerHTML;
            btn.disabled = true;
            btn.classList.add('is-loading');
            btn.innerHTML = `<span class="btn-spinner" aria-hidden="true"></span><span>${escapeHtml(text)}</span>`;
        } else {
            btn.disabled = false;
            btn.classList.remove('is-loading');
            if (btn.dataset.origHtml !== undefined) {
                btn.innerHTML = btn.dataset.origHtml;
                delete btn.dataset.origHtml;
            }
        }
    }

    async function withButtonLoading(btn, text, task, minMs = 240) {
        setButtonLoading(btn, true, text);
        const start = performance.now();
        try {
            const res = await task();
            const elapsed = performance.now() - start;
            if (elapsed < minMs) await sleep(minMs - elapsed);
            return res;
        } finally {
            setButtonLoading(btn, false);
        }
    }

    // Modal Stack synced with Browser/Mobile History Back Button
    const modalStack = [];
    let ignorePopstateCount = 0;

    function showModalDom(id) {
        const el = document.getElementById(id);
        if (!el) return false;
        el.classList.add('is-open');
        el.setAttribute('aria-hidden', 'false');
        return true;
    }

    function hideModalDom(id) {
        const el = document.getElementById(id);
        if (!el) return;
        el.classList.remove('is-open');
        el.setAttribute('aria-hidden', 'true');
    }

    function openModal(id) {
        if (!showModalDom(id)) return;
        if (!modalStack.includes(id)) {
            modalStack.push(id);
            history.pushState({ spa: true, modalId: id, modalDepth: modalStack.length }, '', window.location.href);
        }
    }

    function closeModal(id, { fromPopstate = false } = {}) {
        hideModalDom(id);
        const idx = modalStack.lastIndexOf(id);
        if (idx !== -1) {
            modalStack.splice(idx, 1);
            if (!fromPopstate) {
                ignorePopstateCount += 1;
                history.back();
            }
        }
    }

    function closeAllModals({ syncHistory = false } = {}) {
        const count = modalStack.length;
        modalStack.length = 0;
        document.querySelectorAll('.modal-overlay.is-open').forEach((el) => {
            el.classList.remove('is-open');
            el.setAttribute('aria-hidden', 'true');
        });
        if (syncHistory && count > 0) {
            ignorePopstateCount += 1;
            history.go(-count);
        }
    }

    function replaceTopModal(fromId, toId) {
        hideModalDom(fromId);
        if (!showModalDom(toId)) return;
        const idx = modalStack.lastIndexOf(fromId);
        if (idx !== -1) {
            modalStack[idx] = toId;
        } else if (!modalStack.includes(toId)) {
            modalStack.push(toId);
            history.pushState({ spa: true, modalId: toId, modalDepth: modalStack.length }, '', window.location.href);
        }
    }

    let sharedAudioCtx = null;
    function getUnlockedAudioCtx() {
        try {
            const Ctx = window.AudioContext || window.webkitAudioContext;
            if (!Ctx) return null;
            if (!sharedAudioCtx) sharedAudioCtx = new Ctx();
            if (sharedAudioCtx.state === 'suspended') {
                sharedAudioCtx.resume().catch(() => {});
            }
            return sharedAudioCtx;
        } catch {
            return null;
        }
    }

    function playOrderSuccessSound(ctx = null) {
        try {
            const audio = ctx || getUnlockedAudioCtx();
            if (!audio) return;
            const now = audio.currentTime + 0.02;
            const notes = [
                { freq: 523.25, start: 0.00, dur: 0.16, gain: 0.14 }, // C5
                { freq: 659.25, start: 0.09, dur: 0.16, gain: 0.14 }, // E5
                { freq: 783.99, start: 0.18, dur: 0.20, gain: 0.15 }, // G5
                { freq: 1046.5, start: 0.28, dur: 0.36, gain: 0.16 }, // C6
            ];
            notes.forEach(({ freq, start, dur, gain }) => {
                const osc = audio.createOscillator();
                const env = audio.createGain();
                osc.type = 'triangle';
                osc.frequency.setValueAtTime(freq, now + start);
                env.gain.setValueAtTime(0.0001, now + start);
                env.gain.linearRampToValueAtTime(gain, now + start + 0.018);
                env.gain.exponentialRampToValueAtTime(0.0001, now + start + dur);
                osc.connect(env);
                env.connect(audio.destination);
                osc.start(now + start);
                osc.stop(now + start + dur + 0.02);
            });
        } catch {
            // Audio blocked or unsupported — fail silently
        }
    }

    function closeTopmostModal({ fromPopstate = false } = {}) {
        if (modalStack.length > 0) {
            const topId = modalStack[modalStack.length - 1];
            closeModal(topId, { fromPopstate });
            return true;
        }
        const openModals = Array.from(document.querySelectorAll('.modal-overlay.is-open'));
        if (!openModals.length) return false;
        const top = openModals[openModals.length - 1];
        top.classList.remove('is-open');
        top.setAttribute('aria-hidden', 'true');
        return true;
    }

    document.addEventListener('click', (e) => {
        const openBtn = e.target.closest('[data-modal-open]');
        if (openBtn) {
            openModal(openBtn.getAttribute('data-modal-open'));
            return;
        }
        const closeSpecific = e.target.closest('[data-close-modal]');
        if (closeSpecific) {
            closeModal(closeSpecific.getAttribute('data-close-modal'));
            return;
        }
        const closeBtn = e.target.closest('[data-modal-close]');
        if (closeBtn) {
            const parentOverlay = closeBtn.closest('.modal-overlay');
            if (parentOverlay?.id) {
                closeModal(parentOverlay.id);
            } else {
                closeTopmostModal();
            }
            return;
        }
        if (e.target.classList?.contains('modal-overlay') && e.target.id && e.target.id !== 'orderSuccessModal') {
            closeModal(e.target.id);
        }
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            closeTopmostModal();
        }
    });

    // =========================================================================
    // 2. ORDER PAGE (FULL-SCREEN MAP + 50m CIRCLES + NEARBY + ADD RETAILER)
    // =========================================================================
    function initOrderPage() {
        const app = document.getElementById('orderApp');
        if (!app) return;

        destroyOrderMap();

        if (!srStore.srLocation) {
            srStore.srLocation = JSON.parse(app.dataset.srLocation || '{"lat":23.8103,"lng":90.4125}');
        }
        const initialRetailers = JSON.parse(app.dataset.retailers || '[]');
        if (!srStore.retailersSynced || srStore.retailers.length === 0) {
            srStore.retailers = initialRetailers;
        }
        const catalogProducts = JSON.parse(app.dataset.products || '[]');
        let day = JSON.parse(app.dataset.day || '{"orders":[]}');
        let activeOrderId = null;
        const retailerCarts = new Map();
        let activeOrderRetailer = null;
        let activeOrderProduct = null;
        let poMode = 'unit';

        const srLoc = srStore.srLocation;
        const mapEl = document.getElementById('retailerMap');
        const searchInput = document.getElementById('retailerSearchInput');
        const searchSpinnerEl = document.getElementById('retailerSearchSpinner');
        const searchClearBtn = document.getElementById('retailerSearchClear');
        const nearbyListEl = document.getElementById('nearbyRetailersList');
        const nearbyCountEl = document.getElementById('nearbyCount');
        const nearbySheetTitle = document.getElementById('nearbySheetTitle');
        const nearbyScopeBadge = document.getElementById('nearbyScopeBadge');
        const nearbySyncPill = document.getElementById('nearbySyncPill');
        const nearbySheet = document.getElementById('nearbySheet');
        const toggleNearbyBtn = document.getElementById('toggleNearbyBtn');
        const recenterBtn = document.getElementById('recenterMapBtn');

        const openAddBtn = document.getElementById('openAddRetailerBtn');
        const addForm = document.getElementById('addRetailerForm');
        const retNameInput = document.getElementById('ret_name');
        const retLocInput = document.getElementById('ret_location');
        const retLatInput = document.getElementById('ret_lat');
        const retLngInput = document.getElementById('ret_lng');
        const retPinHint = document.getElementById('retPinHint');
        const addErrorEl = document.getElementById('addRetailerError');
        const cancelAddBtn = document.getElementById('cancelAddRetailerBtn');
        const closeAddBtn = document.getElementById('closeAddRetailerBtn');

        const pickOnMapBtn = document.getElementById('pickOnMapBtn');
        const pickOnMapInlineBtn = document.getElementById('pickOnMapInlineBtn');
        const pinBanner = document.getElementById('pinPickerBanner');
        const pinCoordsEl = document.getElementById('pinPickerCoords');
        const confirmPinBtn = document.getElementById('confirmPinBtn');
        const cancelPinBtn = document.getElementById('cancelPinBtn');

        const SR_RADIUS_METERS = 50;
        const hasLeaflet = typeof window.L !== 'undefined';
        let leafletLayerGroup = null;
        let pickerMarker = null;
        let isPickingPin = false;
        let pendingPin = null;
        let focusedRetailerId = null;

        const markerIndex = new Map();

        function resetAddRetailerForm() {
            addForm?.reset();
            if (retLatInput) retLatInput.value = '';
            if (retLngInput) retLngInput.value = '';
            if (retPinHint) retPinHint.textContent = 'সঠিক লোকেশন দিতে "ম্যাপে পিন দিন" ব্যবহার করুন।';
            if (addErrorEl) addErrorEl.hidden = true;
            pendingPin = null;
        }

        function highlightMatch(text, query) {
            return BanglishSearch.highlight(text, query);
        }

        const retKey = (r) => `${r.name} ${r.address || ''} ${r.phone || ''}`;
        const prodKey = (p) => `${p.name} ${p.code || ''}`;
        let retailersSyncPromise = null;
        let retailersSyncing = false;

        function mergeRetailerDirectory(freshList) {
            const byId = new Map(freshList.map((r) => [String(r.id), r]));
            srStore.retailers.forEach((existing) => {
                const k = String(existing.id);
                if (!byId.has(k)) byId.set(k, existing);
            });
            srStore.retailers = Array.from(byId.values());
            srStore.retailersSynced = true;
            BanglishSearch.warmup(srStore.retailers, retKey);
        }

        function syncRetailerDirectory() {
            if (retailersSyncPromise) return retailersSyncPromise;
            retailersSyncing = true;
            if (nearbySyncPill) nearbySyncPill.hidden = false;
            if (!srStore.retailersSynced) {
                renderNearbyLoading();
            }
            retailersSyncPromise = srApi('GET', '/sr/retailers')
                .then((res) => {
                    if (Array.isArray(res?.retailers)) {
                        mergeRetailerDirectory(res.retailers);
                        saveShops();
                    }
                })
                .catch(async () => {
                    // offline: the directory saved on the phone
                    const saved = offlineOk() ? await window.HbOffline.kvGet(shopsKey) : null;
                    if (Array.isArray(saved) && saved.length) mergeRetailerDirectory(saved);
                    srStore.retailersSynced = true;
                })
                .finally(() => {
                    retailersSyncing = false;
                    if (nearbySyncPill) nearbySyncPill.hidden = true;
                    if (!(searchInput?.value || '').trim()) {
                        refreshOrderView();
                    }
                });
            return retailersSyncPromise;
        }

        function searchRetailersPhonetic(rawQuery) {
            const qTokens = BanglishSearch.compileQuery(rawQuery);
            if (!qTokens) return [];
            const matches = [];
            for (let i = 0; i < srStore.retailers.length; i++) {
                const r = srStore.retailers[i];
                const idx = BanglishSearch.getIndexed(r, retKey(r));
                const score = BanglishSearch.scoreCompiled(idx, qTokens);
                if (score > 0) {
                    matches.push({
                        ...r,
                        _score: score,
                        distance: haversineMeters(srLoc.lat, srLoc.lng, Number(r.lat), Number(r.lng)),
                    });
                }
            }
            matches.sort((a, b) => (Math.floor(b._score / 10) - Math.floor(a._score / 10))
                || (b._score - a._score)
                || (Number(b.id) - Number(a.id)));
            return matches;
        }

        function filteredSortedRetailers() {
            const rawQ = (searchInput?.value || '').trim();
            if (rawQ) {
                // Global search across ALL retailers — no 50m boundary!
                return searchRetailersPhonetic(rawQ);
            }
            return srStore.retailers
                .map((r) => ({
                    ...r,
                    distance: haversineMeters(srLoc.lat, srLoc.lng, Number(r.lat), Number(r.lng)),
                }))
                .filter((r) => r.distance <= SR_RADIUS_METERS)
                .sort((a, b) => a.distance - b.distance);
        }

        function syncNearbyHeaderMode(rawQ) {
            const isSearch = Boolean(rawQ);
            if (nearbySheetTitle) nearbySheetTitle.textContent = isSearch ? 'খোঁজার ফলাফল' : 'কাছের দোকান';
            if (nearbyScopeBadge) {
                nearbyScopeBadge.textContent = isSearch ? 'সকল এলাকা' : '৫০ মি.';
                nearbyScopeBadge.className = `badge tabular ${isSearch ? 'badge-cobalt' : 'badge-info'}`;
            }
        }

        function renderNearbyLoading() {
            if (!nearbyListEl) return;
            syncNearbyHeaderMode((searchInput?.value || '').trim());
            const sumEl = document.getElementById('nearbyPendingSummary');
            if (sumEl) sumEl.textContent = '· লোড হচ্ছে…';
            nearbyListEl.innerHTML = Array.from({ length: 3 }, () => `
                <div class="nearby-sk-card">
                    <span class="sk sk-line" style="width:70%"></span>
                    <span class="sk sk-line" style="width:48%;height:9px"></span>
                    <span class="sk sk-line" style="width:58%;height:9px"></span>
                </div>
            `).join('');
        }

        const retailerSuggestBox = document.getElementById('retailerSuggestBox');
        let retSuggestTimer = null;
        let retSuggestSeq = 0;
        let retLastQuery = '';
        let retLastMatches = [];
        let retVisibleLimit = 500;

        function paintRetailerSuggestions(rawQ, matches, { appendOnly = false } = {}) {
            if (!retailerSuggestBox) return;
            retailerSuggestBox.hidden = false;
            if (matches.length === 0) {
                retailerSuggestBox.innerHTML = '<div class="suggest-empty">মিলে যাওয়া কোনো দোকান পাওয়া যায়নি।</div>';
                return;
            }
            const shown = matches.slice(0, retVisibleLimit);
            const remaining = matches.length - shown.length;
            const headBar = `
                <div class="suggest-head-bar">
                    <span>সাজেশন (সকল এলাকা)</span>
                    <span class="tabular">${bnNum(matches.length)}টি দোকান পাওয়া গেছে</span>
                </div>
            `;
            const rowsHtml = shown.map((r) => {
                const ordered = orderForRetailer(r.id);
                const subText = escapeHtml(r.address || r.phone || 'অবস্থান পিনকৃত');
                return `
                    <button type="button" class="suggest-row" data-suggest-ret="${escapeHtml(r.id)}">
                        <div class="suggest-row-main">
                            <div class="suggest-title">${highlightMatch(r.name, rawQ)}</div>
                            <div class="suggest-sub tabular">${subText} · ${escapeHtml(formatDistance(r.distance))}</div>
                        </div>
                        <span class="badge ${ordered ? 'badge-success' : 'badge-neutral'}">${ordered ? 'অর্ডার হয়েছে' : 'বাছুন →'}</span>
                    </button>
                `;
            }).join('');
            const moreBtn = remaining > 0
                ? `<button type="button" class="suggest-more-btn" data-suggest-more-ret="1">আরো ${bnNum(remaining)}টি দোকান দেখুন</button>`
                : '';
            const prevScroll = appendOnly ? retailerSuggestBox.scrollTop : 0;
            retailerSuggestBox.innerHTML = headBar + rowsHtml + moreBtn;
            if (appendOnly) retailerSuggestBox.scrollTop = prevScroll;
        }

        function triggerRetailerSearch({ immediate = false } = {}) {
            const rawQ = (searchInput?.value || '').trim();
            if (searchClearBtn) searchClearBtn.hidden = rawQ === '';

            if (retSuggestTimer) {
                clearTimeout(retSuggestTimer);
                retSuggestTimer = null;
            }
            const seq = ++retSuggestSeq;

            if (!rawQ) {
                if (searchSpinnerEl) searchSpinnerEl.hidden = true;
                if (nearbySyncPill && !retailersSyncing) nearbySyncPill.hidden = true;
                if (retailerSuggestBox) {
                    retailerSuggestBox.hidden = true;
                    retailerSuggestBox.innerHTML = '';
                }
                retLastMatches = [];
                if (hasLeaflet && activeLeafletMap && srStore.retailersSynced) {
                    activeLeafletMap.setView([srLoc.lat, srLoc.lng], 18, { animate: true });
                }
                refreshOrderView();
                return;
            }

            if (rawQ !== retLastQuery) {
                retVisibleLimit = 500;
                retLastQuery = rawQ;
            }

            // Show full loading animation BEFORE loading results (input spinner + suggestion skeleton + nearby shimmer)
            if (searchSpinnerEl) searchSpinnerEl.hidden = false;
            if (nearbySyncPill) nearbySyncPill.hidden = false;
            renderNearbyLoading();
            if (retailerSuggestBox) {
                retailerSuggestBox.hidden = false;
                retailerSuggestBox.innerHTML = renderSuggestLoadingMarkup(
                    retailersSyncing ? 'সম্পূর্ণ দোকানের ডেটা লোড হচ্ছে…' : 'সকল এলাকায় খোঁজা হচ্ছে…'
                );
            }

            const startedAt = performance.now();
            const runSearch = async () => {
                if (retailersSyncPromise && !srStore.retailersSynced) {
                    await retailersSyncPromise;
                }
                // Ensure full loading animation renders briefly before swapping in results
                const elapsed = performance.now() - startedAt;
                if (!immediate && elapsed < 190) {
                    await sleep(190 - elapsed);
                }
                if (seq !== retSuggestSeq) return;

                const currentQ = (searchInput?.value || '').trim();
                if (!currentQ) {
                    if (searchSpinnerEl) searchSpinnerEl.hidden = true;
                    if (nearbySyncPill && !retailersSyncing) nearbySyncPill.hidden = true;
                    if (retailerSuggestBox) retailerSuggestBox.hidden = true;
                    refreshOrderView();
                    return;
                }

                retLastMatches = searchRetailersPhonetic(currentQ);
                if (searchSpinnerEl) searchSpinnerEl.hidden = true;
                if (nearbySyncPill && !retailersSyncing) nearbySyncPill.hidden = true;

                renderMapFeatures(retLastMatches, { isSearch: true });
                renderNearbyList(retLastMatches);
                paintRetailerSuggestions(currentQ, retLastMatches);
            };

            retSuggestTimer = setTimeout(runSearch, immediate ? 20 : 150);
        }

        let nearbyRenderedItems = [];
        let nearbyVisibleLimit = 120;

        function srRetailerStatusClass(ordered) {
            if (!ordered) return 'is-pending';
            const st = String(ordered.status_key || '').toLowerCase();
            if (st === 'cancelled') return 'is-cancelled';
            if (st === 'due' || st === 'partial') return 'is-due';
            return 'is-done';
        }

        function buildNearbyCardHtml(r, idx = 0) {
            const focused = focusedRetailerId === r.id;
            const ordered = orderForRetailer(r.id);
            const statusCls = srRetailerStatusClass(ordered);
            const isCancelled = ordered && String(ordered.status_key || '').toLowerCase() === 'cancelled';
            const statusText = ordered
                ? (ordered.status_key === 'pending' ? `আজ অর্ডার নেওয়া হয়েছে · ${formatMoney2(ordered.sr_total)}` : bnStatus(ordered.status_key || ordered.status))
                : (Number(r.due || 0) > 0 ? `যাওয়া বাকি · আগের বাকি ${formatMoney2(r.due)}` : 'যাওয়া বাকি');
            const num = ordered ? (isCancelled ? '✕' : '✓') : bnNum(idx + 1);
            const action = ordered
                ? `<span class="nr-act is-ghost">${ordered.editable === false ? 'দেখুন' : 'এডিট'}</span>`
                : '<span class="nr-act">অর্ডার</span>';
            return `
                <button type="button" class="quick-retailer-card nr-row ${statusCls} ${focused ? 'is-focused' : ''}" data-focus-retailer="${escapeHtml(r.id)}">
                    <span class="nr-num">${num}</span>
                    <span class="nr-main">
                        <span class="qrc-name">${escapeHtml(r.name)}</span>
                        <span class="qrc-addr tabular">${escapeHtml(formatDistance(r.distance))} · ${escapeHtml(statusText)}</span>
                    </span>
                    ${action}
                </button>
            `;
        }

        function renderNearbyList(items) {
            if (!nearbyListEl) return;
            const rawQ = (searchInput?.value || '').trim();
            syncNearbyHeaderMode(rawQ);

            if (!srStore.retailersSynced && retailersSyncing && !rawQ) {
                renderNearbyLoading();
                return;
            }

            const pendingCount = items.filter((r) => !orderForRetailer(r.id)).length;
            if (nearbyCountEl) nearbyCountEl.textContent = bnNum(items.length);
            const sumEl = document.getElementById('nearbyPendingSummary');
            if (sumEl) {
                sumEl.textContent = items.length
                    ? (rawQ ? `· ${bnNum(items.length)}টি পাওয়া গেছে` : `· ${bnNum(pendingCount)}টি বাকি`)
                    : '';
            }

            if (items.length === 0) {
                nearbyRenderedItems = [];
                nearbyListEl.innerHTML = rawQ
                    ? `<div class="muted small" style="padding:10px 6px;">"${escapeHtml(rawQ)}"-এর সাথে মিলে যাওয়া কোনো দোকান পাওয়া যায়নি।</div>`
                    : `<div class="muted small" style="padding:10px 6px;">আপনার ৫০ মিটারের মধ্যে কোনো দোকান পাওয়া যায়নি।</div>`;
                return;
            }

            nearbyRenderedItems = items;
            nearbyVisibleLimit = rawQ ? Math.min(items.length, 200) : items.length;
            const shown = items.slice(0, nearbyVisibleLimit);
            nearbyListEl.innerHTML = shown.map(buildNearbyCardHtml).join('')
                + (items.length > nearbyVisibleLimit ? `<button type="button" class="quick-retailer-card nearby-more-card" data-nearby-more="1"><strong>+ আরো ${bnNum(items.length - nearbyVisibleLimit)}টি</strong><span class="muted small">সব দেখতে ট্যাপ করুন</span></button>` : '');
        }

        function createRetailerDivIcon(name, isDone, isFocused) {
            return window.L.divIcon({
                className: 'retailer-pin-icon',
                html: `<div class="retailer-pin-wrap ${isFocused ? 'is-focused' : ''} ${isDone ? 'is-done' : ''}"><span class="retailer-pin-label"><span class="pin-status-dot ${isDone ? 'is-done' : ''}">${isDone ? '✓' : ''}</span><span>${escapeHtml(name)}</span></span><span class="retailer-pin-stem"></span><span class="retailer-pin-dot ${isDone ? 'is-done' : ''}"></span></div>`,
                iconSize: [0, 0],
                iconAnchor: [0, 0],
            });
        }

        function renderMapFeatures(items, { isSearch = false } = {}) {
            markerIndex.clear();
            const mapItems = isSearch ? items.slice(0, 220) : items;

            if (hasLeaflet && activeLeafletMap && leafletLayerGroup) {
                leafletLayerGroup.clearLayers();

                // 50-meter radius circle around SR's location ONLY
                window.L.circle([srLoc.lat, srLoc.lng], {
                    radius: SR_RADIUS_METERS,
                    color: '#1a4fd8',
                    weight: 2,
                    opacity: 0.85,
                    fillColor: '#1a4fd8',
                    fillOpacity: 0.12,
                }).addTo(leafletLayerGroup);

                // SR current location pin
                const srPhoto = app.dataset.srPhoto || '';
                const srIcon = srPhoto
                    ? window.L.divIcon({
                        className: 'photo-pin-icon',
                        html: `<div class="photo-pin" title="আপনার অবস্থান (৫০ মিটার)"><img src="${escapeHtml(srPhoto)}" alt=""></div>`,
                        iconSize: [46, 56],
                        iconAnchor: [23, 56],
                    })
                    : window.L.divIcon({
                        className: 'retailer-pin-icon',
                        html: `<div class="sr-pin-dot" title="আপনার অবস্থান (৫০ মিটার)"></div>`,
                        iconSize: [15, 15],
                        iconAnchor: [7, 7],
                    });
                window.L.marker([srLoc.lat, srLoc.lng], { icon: srIcon, zIndexOffset: 200 })
                    .bindPopup('<strong>আপনার অবস্থান (SR)</strong><br><span style="font-size:12px;color:#64748b">৫০ মিটার সক্রিয় এলাকা</span>')
                    .addTo(leafletLayerGroup);

                const validCoords = [];
                mapItems.forEach((r) => {
                    const lat = Number(r.lat);
                    const lng = Number(r.lng);
                    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return;
                    const isDone = !!orderForRetailer(r.id);
                    const isFocused = focusedRetailerId === r.id;

                    const marker = window.L.marker([lat, lng], {
                        icon: createRetailerDivIcon(r.name, isDone, isFocused),
                        title: r.name,
                    }).addTo(leafletLayerGroup);

                    marker.on('click', () => {
                        if (isPickingPin) return;
                        openRetailerProducts(r.id);
                    });

                    markerIndex.set(r.id, marker);
                    if (Math.abs(lat - srLoc.lat) < 5 && Math.abs(lng - srLoc.lng) < 5) {
                        validCoords.push([lat, lng]);
                    }
                });

                if (isSearch && validCoords.length === 1) {
                    activeLeafletMap.setView(validCoords[0], 17, { animate: true });
                } else if (isSearch && validCoords.length > 1) {
                    activeLeafletMap.fitBounds(window.L.latLngBounds(validCoords), {
                        padding: [48, 48],
                        maxZoom: 17,
                        animate: true,
                    });
                }
                return;
            }

            // Fallback Interactive Map (when offline / CDN blocked)
            if (!mapEl) return;
            const span = 0.0011;
            const toPctX = (lng) => Math.min(92, Math.max(8, 50 + ((lng - srLoc.lng) / span) * 38));
            const toPctY = (lat) => Math.min(82, Math.max(18, 50 - ((lat - srLoc.lat) / span) * 38));

            const pinsHtml = mapItems.map((r) => {
                const x = toPctX(Number(r.lng));
                const y = toPctY(Number(r.lat));
                const isDone = !!orderForRetailer(r.id);
                const isFocused = focusedRetailerId === r.id;
                return `
                    <div class="fallback-pin ${isFocused ? 'is-focused' : ''}" style="left:${x}%;top:${y}%" data-fallback-ret="${escapeHtml(r.id)}" title="${escapeHtml(r.name)}">
                        <span class="retailer-pin-label"><span class="pin-status-dot ${isDone ? 'is-done' : ''}"></span><span>${escapeHtml(r.name)}</span></span>
                        <span class="retailer-pin-dot ${isDone ? 'is-done' : ''}"></span>
                    </div>
                `;
            }).join('');

            let pickerHtml = '';
            if (isPickingPin && pendingPin) {
                const px = toPctX(pendingPin.lng);
                const py = toPctY(pendingPin.lat);
                pickerHtml = `<div class="fallback-sr-pin" style="left:${px}%;top:${py}%"><div class="picker-pin-dot"></div></div>`;
            }

            mapEl.innerHTML = `
                <div class="fallback-map" id="fallbackMapCanvas">
                    <div class="fallback-map-note">${isSearch ? 'খোঁজার ফলাফল (সকল এলাকা)' : 'আপনার অবস্থান থেকে ৫০ মিটার ব্যাসার্ধ'}</div>
                    <div class="fallback-circle" style="left:50%;top:50%;width:180px;height:180px"></div>
                    <div class="fallback-sr-pin" style="left:50%;top:50%" title="আপনার অবস্থান"><div class="sr-pin-dot"></div></div>
                    ${pinsHtml}
                    ${pickerHtml}
                </div>
            `;

            const canvas = document.getElementById('fallbackMapCanvas');
            canvas?.addEventListener('click', (e) => {
                const pin = e.target.closest('[data-fallback-ret]');
                if (pin && !isPickingPin) {
                    openRetailerProducts(pin.getAttribute('data-fallback-ret'));
                    return;
                }
                if (!isPickingPin) return;
                const rect = canvas.getBoundingClientRect();
                const pctX = ((e.clientX - rect.left) / rect.width) * 100;
                const pctY = ((e.clientY - rect.top) / rect.height) * 100;
                const lng = srLoc.lng + ((pctX - 50) / 38) * span;
                const lat = srLoc.lat - ((pctY - 50) / 38) * span;
                setPickerPin(lat, lng);
            });
        }

        function refreshOrderView() {
            const rawQ = (searchInput?.value || '').trim();
            const items = filteredSortedRetailers();
            renderMapFeatures(items, { isSearch: Boolean(rawQ) });
            renderNearbyList(items);
        }

        function clearPickerOverlay() {
            if (hasLeaflet && activeLeafletMap && pickerMarker) {
                activeLeafletMap.removeLayer(pickerMarker);
                pickerMarker = null;
            }
        }

        function setPickerPin(lat, lng) {
            pendingPin = { lat: Number(lat), lng: Number(lng) };
            if (pinCoordsEl) {
                pinCoordsEl.textContent = `${pendingPin.lat.toFixed(6)}, ${pendingPin.lng.toFixed(6)}`;
            }
            if (confirmPinBtn) confirmPinBtn.disabled = false;

            if (hasLeaflet && activeLeafletMap) {
                clearPickerOverlay();
                const icon = window.L.divIcon({
                    className: 'retailer-pin-icon',
                    html: '<div class="picker-pin-dot"></div>',
                    iconSize: [16, 16],
                    iconAnchor: [8, 8],
                });
                pickerMarker = window.L.marker([pendingPin.lat, pendingPin.lng], {
                    icon,
                    draggable: true,
                    zIndexOffset: 500,
                }).addTo(activeLeafletMap);

                pickerMarker.on('dragend', () => {
                    const pos = pickerMarker.getLatLng();
                    setPickerPin(pos.lat, pos.lng);
                });
            } else {
                renderMapFeatures(filteredSortedRetailers());
            }
        }

        function enterPinPickerMode() {
            isPickingPin = true;
            closeModal('addRetailerModal');
            app.classList.add('is-picking-pin');
            if (pinBanner) pinBanner.hidden = false;

            const existingLat = Number(retLatInput?.value || 0);
            const existingLng = Number(retLngInput?.value || 0);
            if (existingLat && existingLng) {
                setPickerPin(existingLat, existingLng);
            } else {
                pendingPin = null;
                if (pinCoordsEl) pinCoordsEl.textContent = 'ম্যাপের যেকোনো জায়গায় ট্যাপ করুন';
                if (confirmPinBtn) confirmPinBtn.disabled = true;
                clearPickerOverlay();
            }
        }

        function exitPinPickerMode() {
            isPickingPin = false;
            app.classList.remove('is-picking-pin');
            if (pinBanner) pinBanner.hidden = true;
            clearPickerOverlay();
        }

        // Initialize Leaflet map (zoom 18 so the 50m radius around SR location fits cleanly)
        if (hasLeaflet && mapEl) {
            activeLeafletMap = window.L.map(mapEl, {
                center: [srLoc.lat, srLoc.lng],
                zoom: 18,
                maxZoom: 22,
                zoomControl: false,
            });

            window.L.control.zoom({ position: 'topright' }).addTo(activeLeafletMap);

            let usedFallbackTiles = false;
            const primaryTiles = window.L.tileLayer('https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}', {
                maxNativeZoom: 20,
                maxZoom: 22,
                subdomains: '0123',
                attribution: '&copy; Google Maps',
            }).addTo(activeLeafletMap);

            primaryTiles.on('tileerror', () => {
                if (usedFallbackTiles || !activeLeafletMap) return;
                usedFallbackTiles = true;
                activeLeafletMap.removeLayer(primaryTiles);
                window.L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}', {
                    maxNativeZoom: 19,
                    maxZoom: 22,
                    attribution: '&copy; Esri',
                }).addTo(activeLeafletMap);
            });

            leafletLayerGroup = window.L.layerGroup().addTo(activeLeafletMap);

            activeLeafletMap.on('click', (e) => {
                if (!isPickingPin) return;
                setPickerPin(e.latlng.lat, e.latlng.lng);
            });

            // Guarantee Leaflet computes full non-zero dimensions on initial load & SPA swaps
            const syncMapSize = () => activeLeafletMap?.invalidateSize(false);
            requestAnimationFrame(syncMapSize);
            setTimeout(syncMapSize, 180);
            setTimeout(syncMapSize, 450);

            if (typeof ResizeObserver !== 'undefined') {
                activeMapResizeObserver = new ResizeObserver(syncMapSize);
                activeMapResizeObserver.observe(mapEl);
            }
        }

        refreshOrderView();
        syncRetailerDirectory();

        // Interactions
        searchInput?.addEventListener('input', () => {
            triggerRetailerSearch();
        });
        searchInput?.addEventListener('focus', () => {
            if ((searchInput.value || '').trim()) triggerRetailerSearch({ immediate: true });
        });
        searchInput?.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                e.preventDefault();
                if (nearbySheet?.classList.contains('is-collapsed')) {
                    nearbySheet.classList.remove('is-collapsed');
                    toggleNearbyBtn?.setAttribute('aria-expanded', 'true');
                }
                triggerRetailerSearch({ immediate: true });
            }
        });
        searchClearBtn?.addEventListener('click', () => {
            if (searchInput) searchInput.value = '';
            retSuggestSeq++;
            if (retSuggestTimer) clearTimeout(retSuggestTimer);
            if (searchSpinnerEl) searchSpinnerEl.hidden = true;
            if (nearbySyncPill && !retailersSyncing) nearbySyncPill.hidden = true;
            searchClearBtn.hidden = true;
            if (retailerSuggestBox) {
                retailerSuggestBox.hidden = true;
                retailerSuggestBox.innerHTML = '';
            }
            if (hasLeaflet && activeLeafletMap) {
                activeLeafletMap.setView([srLoc.lat, srLoc.lng], 18, { animate: true });
            }
            refreshOrderView();
            searchInput?.focus();
        });
        retailerSuggestBox?.addEventListener('scroll', () => {
            if (retLastMatches.length > retVisibleLimit
                && retailerSuggestBox.scrollTop + retailerSuggestBox.clientHeight >= retailerSuggestBox.scrollHeight - 100) {
                retVisibleLimit += 300;
                paintRetailerSuggestions(retLastQuery, retLastMatches, { appendOnly: true });
            }
        });
        retailerSuggestBox?.addEventListener('click', (e) => {
            const moreBtn = e.target.closest('[data-suggest-more-ret]');
            if (moreBtn) {
                retVisibleLimit += 300;
                paintRetailerSuggestions(retLastQuery, retLastMatches, { appendOnly: true });
                return;
            }
            const row = e.target.closest('[data-suggest-ret]');
            if (!row) return;
            const id = row.getAttribute('data-suggest-ret');
            retailerSuggestBox.hidden = true;
            openRetailerProducts(id);
        });
        document.addEventListener('click', (e) => {
            if (retailerSuggestBox && !retailerSuggestBox.hidden && !e.target.closest('.map-topbar')) {
                retailerSuggestBox.hidden = true;
            }
            if (rpProductSuggestBox && !rpProductSuggestBox.hidden && !e.target.closest('.rp-search-wrap')) {
                rpProductSuggestBox.hidden = true;
            }
        });

        toggleNearbyBtn?.addEventListener('click', () => {
            if (!nearbySheet) return;
            const collapsed = nearbySheet.classList.toggle('is-collapsed');
            toggleNearbyBtn.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
        });

        recenterBtn?.addEventListener('click', () => {
            if (hasLeaflet && activeLeafletMap) {
                activeLeafletMap.setView([srLoc.lat, srLoc.lng], 18, { animate: true });
            }
            showToast('আপনার অবস্থানে (৫০ মিটার) কেন্দ্রিত করা হয়েছে।');
        });

        // =====================================================================
        // RETAILER PRODUCTS GRID MODAL + PRODUCT QTY / PRICE / O/C MODAL
        // =====================================================================
        const rpRetailerName = document.getElementById('rpRetailerName');
        const rpRetailerSub = document.getElementById('rpRetailerSub');
        const rpProductSearch = document.getElementById('rpProductSearch');
        const rpProductSearchSpinner = document.getElementById('rpProductSearchSpinner');
        const rpProductSearchClear = document.getElementById('rpProductSearchClear');
        const srProductsGrid = document.getElementById('srProductsGrid');
        const rpViewGridBtn = document.getElementById('rpViewGridBtn');
        const rpViewListBtn = document.getElementById('rpViewListBtn');

        const floatingCartWrap = document.getElementById('floatingCartWrap');
        const cartFloatBadge = document.getElementById('cartFloatBadge');
        const rpCartTotal = document.getElementById('rpCartTotal');
        const openCartReviewBtn = document.getElementById('openCartReviewBtn');

        const ocRetailerTitle = document.getElementById('ocRetailerTitle');
        const ocTableBody = document.getElementById('ocTableBody');
        const ocSummaryOc = document.getElementById('ocSummaryOc');
        const ocSummarySubtotal = document.getElementById('ocSummarySubtotal');
        const confirmOrderBtn = document.getElementById('confirmOrderBtn');

        const osRetailerSubtitle = document.getElementById('osRetailerSubtitle');
        const osReceiptRetailer = document.getElementById('osReceiptRetailer');
        const osReceiptCode = document.getElementById('osReceiptCode');
        const osReceiptTime = document.getElementById('osReceiptTime');
        const osReceiptSr = document.getElementById('osReceiptSr');
        const osItemsBody = document.getElementById('osItemsBody');
        const osTotalCost = document.getElementById('osTotalCost');
        const osTotalOc = document.getElementById('osTotalOc');
        const undoConfirmedOrderBtn = document.getElementById('undoConfirmedOrderBtn');
        const nextShopBtn = document.getElementById('nextShopBtn');
        let lastConfirmedOrder = null;

        [rpViewGridBtn, rpViewListBtn].forEach((btn) => {
            btn?.addEventListener('click', () => {
                const mode = btn.getAttribute('data-rp-view');
                rpViewGridBtn?.classList.toggle('is-active', mode === 'grid');
                rpViewListBtn?.classList.toggle('is-active', mode === 'list');
                srProductsGrid?.classList.toggle('is-list-view', mode === 'list');
            });
        });

        const poProductName = document.getElementById('poProductName');
        const poProductSub = document.getElementById('poProductSub');
        const poModeUnitBtn = document.getElementById('poModeUnitBtn');
        const poModePcsBtn = document.getElementById('poModePcsBtn');
        const poUnitQtyGroup = document.getElementById('poUnitQtyGroup');
        const poUnitQtyLabel = document.getElementById('poUnitQtyLabel');
        const poUnitQtyInput = document.getElementById('poUnitQtyInput');
        const poUnitMinus = document.getElementById('poUnitMinus');
        const poUnitPlus = document.getElementById('poUnitPlus');
        const poExtraPcsInput = document.getElementById('poExtraPcsInput');
        const poExtraPcsMinus = document.getElementById('poExtraPcsMinus');
        const poExtraPcsPlus = document.getElementById('poExtraPcsPlus');
        const poPcsQtyGroup = document.getElementById('poPcsQtyGroup');
        const poQtyInput = document.getElementById('poQtyInput');
        const poQtyMinus = document.getElementById('poQtyMinus');
        const poQtyPlus = document.getElementById('poQtyPlus');
        const poRateLabel = document.getElementById('poRateLabel');
        const poRateInput = document.getElementById('poRateInput');
        const poBaseRateHint = document.getElementById('poBaseRateHint');
        const poTotalInput = document.getElementById('poTotalInput');
        const poStdTotalHint = document.getElementById('poStdTotalHint');
        const poOcBox = document.getElementById('poOcBox');
        const poOcCaption = document.getElementById('poOcCaption');
        const poOcValue = document.getElementById('poOcValue');
        const poRemoveItemBtn = document.getElementById('poRemoveItemBtn');
        const poSaveItemBtn = document.getElementById('poSaveItemBtn');
        const poForm = document.getElementById('productOrderForm');

        function productSvgUri(code, tint = '#f1f5f9') {
            const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="160" height="100" viewBox="0 0 160 100">`
                + `<rect width="160" height="100" fill="${tint}"/>`
                + `<rect x="54" y="22" width="52" height="52" rx="12" fill="#ffffff" stroke="#e4e7ec" stroke-width="2"/>`
                + `<text x="80" y="55" text-anchor="middle" font-family="system-ui,sans-serif" font-size="18" font-weight="700" fill="#0f172a">${escapeHtml(code)}</text>`
                + `</svg>`;
            return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;
        }

        function prodImg(p) {
            return p?.image || productSvgUri(p?.code || 'PR', p?.tint || '#f1f5f9');
        }

        function orderForRetailer(retailerId) {
            return (day.orders || []).find((o) => String(o.retailer_id) === String(retailerId) && o.status_key !== 'cancelled') || null;
        }

        function itemPcs(it) {
            const p = catalogProducts.find((x) => x.id === it.productId);
            const qpu = Math.max(1, Number(p?.qty_per_unit || 1));
            return it.mode === 'unit' ? (it.unitQty * qpu) + it.extraPcs : it.pcsQty;
        }

        /** Server order -> cart entries (unit mode when at least one full unit). */
        function cartFromOrder(order) {
            const cart = new Map();
            order.items.forEach((it) => {
                const pid = String(it.product_id);
                const qpu = Math.max(1, Number(it.qty_per_unit || 1));
                const unit = it.pcs >= qpu;
                const effQty = unit ? it.pcs / qpu : it.pcs;
                cart.set(pid, {
                    productId: pid,
                    name: it.name,
                    mode: unit ? 'unit' : 'pcs',
                    unitQty: unit ? Math.floor(it.pcs / qpu) : 0,
                    extraPcs: unit ? it.pcs % qpu : 0,
                    pcsQty: unit ? 0 : it.pcs,
                    rate: round2(effQty > 0 ? it.total / effQty : 0),
                    total: round2(it.total),
                    oc: round2(it.oc),
                });
            });
            return cart;
        }

        function round2(n) {
            return Math.round((Number(n) + Number.EPSILON) * 100) / 100;
        }

        function formatMoney2(n) {
            const val = round2(n);
            const hasDecimals = Math.abs(val - Math.round(val)) > 0.001;
            return `৳ ${bnDigits(val.toLocaleString('en-US', {
                minimumFractionDigits: hasDecimals ? 2 : 0,
                maximumFractionDigits: 2,
            }))}`;
        }

        function formatSignedOc(oc) {
            const val = round2(oc);
            if (Math.abs(val) < 0.01) return '৳ ০';
            const sign = val > 0 ? '+' : '−';
            return `${sign}${formatMoney2(Math.abs(val))}`;
        }

        function getActiveCart() {
            if (!activeOrderRetailer) return new Map();
            if (!retailerCarts.has(activeOrderRetailer.id)) {
                retailerCarts.set(activeOrderRetailer.id, new Map());
            }
            return retailerCarts.get(activeOrderRetailer.id);
        }

        function baseRateFor(product, mode) {
            if (mode === 'pcs') {
                return round2(product.pc_price ?? (Number(product.unit_price) / Math.max(1, Number(product.qty_per_unit || 1))));
            }
            return round2(Number(product.unit_price));
        }

        function formatCartQtyPill(item) {
            const pad = (n) => bnDigits(String(n).padStart(2, '0'));
            if (item.mode === 'unit') {
                if (item.unitQty > 0 && item.extraPcs > 0) return `${pad(item.unitQty)} ইউ ${pad(item.extraPcs)} পি`;
                if (item.unitQty > 0) return `${pad(item.unitQty)} ইউ`;
                return `${pad(item.extraPcs)} পি`;
            }
            return `${pad(item.pcsQty)} পি`;
        }

        function renderCartBar() {
            const cart = getActiveCart();
            const entries = Array.from(cart.values());
            const subtotal = entries.reduce((sum, it) => sum + Number(it.total || 0), 0);

            if (rpCartTotal) rpCartTotal.textContent = formatMoney2(subtotal);
            const pcsTotal = entries.reduce((sum, it) => sum + Number(itemPcs(it) || 0), 0);
            if (cartFloatBadge) {
                cartFloatBadge.hidden = false;
                cartFloatBadge.textContent = entries.length ? `${bnNum(pcsTotal)} পিস · ${bnNum(entries.length)}টি পণ্য` : 'কোনো পণ্য নেই';
            }
            const cartCountEl = document.getElementById('rpCartCount');
            if (cartCountEl) {
                cartCountEl.hidden = entries.length === 0;
                cartCountEl.textContent = bnNum(entries.length);
            }
            if (openCartReviewBtn) {
                openCartReviewBtn.disabled = entries.length === 0;
            }
            if (floatingCartWrap) floatingCartWrap.hidden = false;
        }

        function renderOrderCartModal() {
            const cart = getActiveCart();
            const entries = Array.from(cart.values());

            if (ocRetailerTitle) {
                ocRetailerTitle.textContent = activeOrderRetailer ? activeOrderRetailer.name : 'অর্ডার সারাংশ';
            }
            const cancelBtn = document.getElementById('cancelOrderBtn');
            if (cancelBtn) cancelBtn.hidden = !activeOrderId;
            if (confirmOrderBtn) confirmOrderBtn.textContent = activeOrderId ? 'অর্ডার হালনাগাদ' : 'অর্ডার কনফার্ম';

            let subtotal = 0;
            let totalOc = 0;
            entries.forEach((it) => {
                subtotal += Number(it.total || 0);
                totalOc += Number(it.oc || 0);
            });

            if (ocTableBody) {
                ocTableBody.innerHTML = entries.map((it) => {
                    const prod = catalogProducts.find((p) => p.id === it.productId);
                    const img = prodImg(prod);
                    const ocVal = round2(it.oc || 0);
                    let ocTagHtml = '';
                    if (Math.abs(ocVal) >= 0.01) {
                        const cls = ocVal > 0 ? 'is-over' : 'is-comm';
                        const sign = ocVal > 0 ? '+' : '−';
                        ocTagHtml = `<span class="cart-oc-tag ${cls}">${sign}${bnDigits(Math.abs(ocVal))} O/C</span>`;
                    }

                    return `
                        <tr>
                            <td>
                                <div class="cart-prod-cell">
                                    <span class="cart-prod-thumb"><img src="${img}" alt="${escapeHtml(it.name)}"></span>
                                    <div class="cart-prod-meta">
                                        <span class="cart-prod-title">${escapeHtml(it.name)}</span>
                                        ${ocTagHtml}
                                    </div>
                                </div>
                            </td>
                            <td class="text-center">
                                <span class="cart-qty-pill tabular">${escapeHtml(formatCartQtyPill(it))}</span>
                            </td>
                            <td class="text-right tabular nowrap"><strong>${formatMoney2(it.total)}</strong></td>
                            <td class="text-center">
                                <button type="button" class="btn-trash-icon" data-remove-cart-id="${escapeHtml(it.productId)}" aria-label="মুছুন ${escapeHtml(it.name)}">
                                    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6M14 11v6"/><path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/></svg>
                                </button>
                            </td>
                        </tr>
                    `;
                }).join('');
            }

            if (ocSummaryOc) {
                const roundedOc = round2(totalOc);
                const sign = roundedOc > 0 ? '+' : (roundedOc < 0 ? '−' : '');
                ocSummaryOc.textContent = `O/C ${sign}${bnDigits(Math.abs(roundedOc))}`;
                ocSummaryOc.className = 'cart-confirm-oc tabular'
                    + (roundedOc > 0.009 ? ' is-over' : (roundedOc < -0.009 ? ' is-comm' : ''));
            }

            if (ocSummarySubtotal) {
                ocSummarySubtotal.textContent = formatMoney2(subtotal);
            }
        }

        let activeCategory = 'all';
        function renderCategoryRail() {
            const rail = document.getElementById('rpCatRail');
            if (!rail) return;
            const cats = Array.from(new Set(catalogProducts.map((p) => p.category || 'অন্যান্য')));
            rail.hidden = cats.length < 2;
            if (rail.hidden) { activeCategory = 'all'; return; }
            if (activeCategory !== 'all' && !cats.includes(activeCategory)) activeCategory = 'all';
            rail.innerHTML = ['all', ...cats].map((c) => {
                const label = c === 'all' ? 'সব' : c;
                const on = c === activeCategory;
                const icon = c === 'all' ? 'সব' : (Array.from(label)[0] || '•');
                return `<button type="button" class="rp-cat ${on ? 'is-on' : ''}" role="tab" aria-selected="${on ? 'true' : 'false'}" data-rp-cat="${escapeHtml(c)}"><span class="rp-cat-ic">${escapeHtml(icon)}</span><span class="rp-cat-t">${escapeHtml(label)}</span></button>`;
            }).join('');
        }
        document.getElementById('rpCatRail')?.addEventListener('click', (e) => {
            const b = e.target.closest('[data-rp-cat]');
            if (!b) return;
            activeCategory = b.getAttribute('data-rp-cat');
            renderRetailerProductsGrid();
        });

        function renderRetailerProductsGrid() {
            if (!srProductsGrid) return;
            const cart = getActiveCart();
            const rawQ = (rpProductSearch?.value || '').trim();
            const qTokens = rawQ ? BanglishSearch.compileQuery(rawQ) : null;

            const list = qTokens
                ? catalogProducts
                    .map((p) => ({ p, s: BanglishSearch.scoreCompiled(BanglishSearch.getIndexed(p, prodKey(p)), qTokens) }))
                    .filter((x) => x.s > 0)
                    .sort((a, b) => (Math.floor(b.s / 10) - Math.floor(a.s / 10)) || (Number(b.p.id) - Number(a.p.id)))
                    .map((x) => x.p)
                : catalogProducts;
            renderCategoryRail();
            const catList = activeCategory === 'all' ? list : list.filter((p) => (p.category || 'অন্যান্য') === activeCategory);
            if (catList.length === 0) {
                srProductsGrid.innerHTML = `<div class="empty-state" style="grid-column:span 2;padding:24px 12px"><p class="muted small" style="margin:0">কোনো পণ্য পাওয়া যায়নি।</p></div>`;
                return;
            }

            srProductsGrid.innerHTML = catList.map((p) => {
                const inCart = cart.get(p.id);
                const pcRate = baseRateFor(p, 'pcs');
                const unitBn = bnUnit(p.unit_type);
                let badgeText = '';
                if (inCart) {
                    if (inCart.mode === 'unit') {
                        if (inCart.unitQty > 0 && inCart.extraPcs > 0) {
                            badgeText = `${bnNum(inCart.unitQty)} ${unitBn} ${bnNum(inCart.extraPcs)} পিস`;
                        } else if (inCart.unitQty > 0) {
                            badgeText = `${bnNum(inCart.unitQty)} ${unitBn}`;
                        } else {
                            badgeText = `${bnNum(inCart.extraPcs)} পিস`;
                        }
                    } else {
                        badgeText = `${bnNum(inCart.pcsQty)} পিস`;
                    }
                }

                return `
                    <button type="button" class="sr-prod-card ${inCart ? 'is-in-cart' : ''}" data-pick-product="${escapeHtml(p.id)}">
                        <div class="sr-prod-img-wrap">
                            <span class="sr-prod-shadow" aria-hidden="true"></span>
                            <img src="${prodImg(p)}" alt="${escapeHtml(p.name)}">
                            ${inCart ? `<span class="sr-prod-badge">${escapeHtml(badgeText)}</span>` : ''}
                        </div>
                        <div class="sr-prod-info">
                            <div class="sr-prod-name">${escapeHtml(p.name)}</div>
                            <span class="sr-prod-pack tabular">${bnNum(p.qty_per_unit)} পিস / ${escapeHtml(unitBn)} · ${formatMoney2(pcRate)} /পিস</span>
                            <div class="sr-prod-rates">
                                <strong class="tabular">${formatMoney2(p.unit_price)}</strong>
                                <span class="sr-stock ${p.available_pcs > 0 ? '' : 'is-out'} tabular"><i></i>স্টক ${bnNum(Math.max(0, p.available_pcs))}</span>
                            </div>
                        </div>
                    </button>
                `;
            }).join('');
        }

        function openRetailerProducts(retailerId, { replaceFrom = null } = {}) {
            const ret = srStore.retailers.find((r) => r.id === retailerId);
            if (!ret) return;

            if (day.completed) {
                showToast('আজকের অর্ডার সম্পন্ন হয়েছে। পরিবর্তন করতে "আজ" থেকে দিনটি পুনরায় খুলুন।');
                return;
            }
            const existing = orderForRetailer(retailerId);
            if (existing && !existing.editable) {
                showToast(`${ret.name}-এর অর্ডারটি ইতিমধ্যেই ট্রিপে দেওয়া হয়েছে।`);
                return;
            }
            activeOrderId = existing ? existing.id : null;
            if (existing && !retailerCarts.has(retailerId)) retailerCarts.set(retailerId, cartFromOrder(existing));

            focusedRetailerId = retailerId;
            activeOrderRetailer = ret;
            renderNearbyList(filteredSortedRetailers());

            if (hasLeaflet && activeLeafletMap) {
                activeLeafletMap.setView([Number(ret.lat), Number(ret.lng)], 18, { animate: true });
            }

            const dist = haversineMeters(srLoc.lat, srLoc.lng, Number(ret.lat), Number(ret.lng));
            if (rpRetailerName) rpRetailerName.textContent = ret.name;
            if (rpRetailerSub) rpRetailerSub.textContent = `${activeOrderId ? 'অর্ডার এডিট' : 'নতুন অর্ডার'} · ${formatDistance(dist)}`;
            activeCategory = 'all';
            if (rpProductSearch) rpProductSearch.value = '';
            if (rpProductSearchClear) rpProductSearchClear.hidden = true;
            if (rpProductSearchSpinner) rpProductSearchSpinner.hidden = true;
            if (rpProductSuggestBox) rpProductSuggestBox.hidden = true;

            renderRetailerProductsGrid();
            renderCartBar();
            // Swapping in place keeps the modal/history stack in sync (no back() + push race)
            if (replaceFrom) replaceTopModal(replaceFrom, 'retailerProductsModal');
            else openModal('retailerProductsModal');
        }

        // Effective quantity multiplier in current mode (units for 'unit' mode including extra pcs; pcs for 'pcs' mode)
        function getEffectiveQty() {
            if (!activeOrderProduct) return 0;
            const qpu = Math.max(1, Number(activeOrderProduct.qty_per_unit || 1));
            if (poMode === 'unit') {
                const u = Math.max(0, Math.floor(Number(poUnitQtyInput?.value || 0)));
                const p = Math.max(0, Math.floor(Number(poExtraPcsInput?.value || 0)));
                return u + (p / qpu);
            }
            return Math.max(0, Math.floor(Number(poQtyInput?.value || 0)));
        }

        function updateOcDisplay(actualTotal) {
            if (!activeOrderProduct) return;
            const effQty = getEffectiveQty();
            const baseRate = baseRateFor(activeOrderProduct, poMode);
            const stdTotal = round2(effQty * baseRate);
            const oc = round2(actualTotal - stdTotal);

            if (poBaseRateHint) poBaseRateHint.textContent = `বেজ: ${formatMoney2(baseRate)}`;
            if (poStdTotalHint) poStdTotalHint.textContent = `নির্ধারিত: ${formatMoney2(stdTotal)}`;
            if (poOcValue) poOcValue.textContent = formatSignedOc(oc);

            if (poOcBox && poOcCaption) {
                poOcBox.classList.remove('is-over', 'is-comm');
                if (oc > 0.009) {
                    poOcBox.classList.add('is-over');
                    poOcCaption.textContent = 'ওভার (+) নির্ধারিত দরের চেয়ে বেশি';
                } else if (oc < -0.009) {
                    poOcBox.classList.add('is-comm');
                    poOcCaption.textContent = 'কমিশন / ছাড় (−) নির্ধারিত দরের চেয়ে কম';
                } else {
                    poOcCaption.textContent = 'নির্ধারিত দর (কোনো O/C নেই)';
                }
            }
        }

        function syncModeUi() {
            if (!activeOrderProduct) return;
            const unitLabel = bnUnit(activeOrderProduct.unit_type || 'Unit');
            const isUnit = poMode === 'unit';
            if (poModeUnitBtn) {
                poModeUnitBtn.textContent = `ইউনিট (${unitLabel})`;
                poModeUnitBtn.classList.toggle('is-active', isUnit);
            }
            if (poModePcsBtn) {
                poModePcsBtn.textContent = 'পিস';
                poModePcsBtn.classList.toggle('is-active', !isUnit);
            }
            if (poUnitQtyGroup) poUnitQtyGroup.hidden = !isUnit;
            if (poPcsQtyGroup) poPcsQtyGroup.hidden = isUnit;
            if (poUnitQtyLabel) poUnitQtyLabel.textContent = `ইউনিট (${unitLabel})`;
            if (poRateLabel) {
                poRateLabel.textContent = isUnit ? `প্রতি ${unitLabel} দর (৳)` : 'প্রতি পিস দর (৳)';
            }
        }

        function openProductOrderModal(productId) {
            const product = catalogProducts.find((p) => p.id === productId);
            if (!product) return;

            activeOrderProduct = product;
            const existing = getActiveCart().get(product.id);

            poMode = existing ? existing.mode : 'unit';
            const unitQty = existing ? existing.unitQty : 1;
            const extraPcs = existing ? existing.extraPcs : 0;
            const pcsQty = existing ? existing.pcsQty : 1;
            const baseRate = baseRateFor(product, poMode);
            const rate = existing ? existing.rate : baseRate;

            if (poProductName) poProductName.textContent = product.name;
            if (poProductSub) {
                const unitBn = bnUnit(product.unit_type);
                poProductSub.textContent = `প্রতি ${unitBn} ${bnNum(product.qty_per_unit)} পিস · বেজ ${formatMoney2(product.unit_price)}/${unitBn}`;
            }

            syncModeUi();
            if (poUnitQtyInput) poUnitQtyInput.value = String(unitQty);
            if (poExtraPcsInput) poExtraPcsInput.value = String(extraPcs);
            if (poQtyInput) poQtyInput.value = String(pcsQty);

            const effQty = getEffectiveQty();
            const total = existing ? existing.total : round2(effQty * rate);

            if (poRateInput) poRateInput.value = String(round2(rate));
            if (poTotalInput) poTotalInput.value = String(round2(total));
            if (poRemoveItemBtn) poRemoveItemBtn.hidden = !existing;
            if (poSaveItemBtn) poSaveItemBtn.textContent = existing ? 'হালনাগাদ করুন' : 'অর্ডারে যোগ করুন';

            updateOcDisplay(total);
            openModal('productOrderModal');
        }

        const rpProductSuggestBox = document.getElementById('rpProductSuggestBox');
        let prodSuggestTimer = null;
        let prodSuggestSeq = 0;

        function renderProductSuggestions({ immediate = false } = {}) {
            if (!rpProductSuggestBox) return;
            const rawQ = (rpProductSearch?.value || '').trim();
            if (rpProductSearchClear) rpProductSearchClear.hidden = rawQ === '';

            if (prodSuggestTimer) {
                clearTimeout(prodSuggestTimer);
                prodSuggestTimer = null;
            }
            const seq = ++prodSuggestSeq;

            if (!rawQ) {
                if (rpProductSearchSpinner) rpProductSearchSpinner.hidden = true;
                rpProductSuggestBox.hidden = true;
                rpProductSuggestBox.innerHTML = '';
                return;
            }

            if (rpProductSearchSpinner) rpProductSearchSpinner.hidden = false;
            rpProductSuggestBox.hidden = false;
            rpProductSuggestBox.innerHTML = renderSuggestLoadingMarkup('পণ্য খোঁজা হচ্ছে…');

            prodSuggestTimer = setTimeout(() => {
                if (seq !== prodSuggestSeq) return;
                const currentQ = (rpProductSearch?.value || '').trim();
                const qTokens = BanglishSearch.compileQuery(currentQ);
                const matches = qTokens
                    ? catalogProducts
                        .map((p) => ({ p, s: BanglishSearch.scoreCompiled(BanglishSearch.getIndexed(p, prodKey(p)), qTokens) }))
                        .filter((x) => x.s > 0)
                        .sort((a, b) => (Math.floor(b.s / 10) - Math.floor(a.s / 10)) || (Number(b.p.id) - Number(a.p.id)))
                        .map((x) => x.p)
                        .slice(0, 50)
                    : [];

                if (rpProductSearchSpinner) rpProductSearchSpinner.hidden = true;
                rpProductSuggestBox.hidden = false;
                if (matches.length === 0) {
                    rpProductSuggestBox.innerHTML = '<div class="suggest-empty">মিলে যাওয়া কোনো পণ্য পাওয়া যায়নি।</div>';
                    return;
                }
                const headBar = `
                    <div class="suggest-head-bar">
                        <span>সাজেশন</span>
                        <span class="tabular">${bnNum(matches.length)}টি পণ্য পাওয়া গেছে</span>
                    </div>
                `;
                rpProductSuggestBox.innerHTML = headBar + matches.map((p) => {
                    const unitBn = bnUnit(p.unit_type);
                    return `
                        <button type="button" class="suggest-row" data-suggest-prod="${escapeHtml(p.id)}">
                            <div class="suggest-row-main">
                                <div class="suggest-title">${highlightMatch(p.name, currentQ)}</div>
                                <div class="suggest-sub tabular">${formatMoney2(p.unit_price)} /${escapeHtml(unitBn)} · স্টক ${bnNum(Math.max(0, p.available_pcs))} পিস</div>
                            </div>
                            <span class="badge badge-info">যোগ করুন +</span>
                        </button>
                    `;
                }).join('');
            }, immediate ? 35 : 130);
        }

        rpProductSearch?.addEventListener('input', () => {
            renderRetailerProductsGrid();
            renderProductSuggestions();
        });
        rpProductSearch?.addEventListener('focus', () => {
            if ((rpProductSearch.value || '').trim()) renderProductSuggestions({ immediate: true });
        });
        rpProductSearchClear?.addEventListener('click', () => {
            if (rpProductSearch) rpProductSearch.value = '';
            prodSuggestSeq++;
            if (prodSuggestTimer) clearTimeout(prodSuggestTimer);
            if (rpProductSearchSpinner) rpProductSearchSpinner.hidden = true;
            rpProductSearchClear.hidden = true;
            if (rpProductSuggestBox) {
                rpProductSuggestBox.hidden = true;
                rpProductSuggestBox.innerHTML = '';
            }
            renderRetailerProductsGrid();
            rpProductSearch?.focus();
        });
        rpProductSuggestBox?.addEventListener('click', (e) => {
            const row = e.target.closest('[data-suggest-prod]');
            if (!row) return;
            const pid = row.getAttribute('data-suggest-prod');
            rpProductSuggestBox.hidden = true;
            openProductOrderModal(pid);
        });

        srProductsGrid?.addEventListener('click', (e) => {
            const card = e.target.closest('[data-pick-product]');
            if (!card) return;
            openProductOrderModal(card.getAttribute('data-pick-product'));
        });

        [poModeUnitBtn, poModePcsBtn].forEach((btn) => {
            btn?.addEventListener('click', () => {
                if (!activeOrderProduct) return;
                const nextMode = btn.getAttribute('data-order-mode');
                if (nextMode === poMode) return;
                poMode = nextMode;
                syncModeUi();

                if (poMode === 'unit' && Number(poUnitQtyInput?.value || 0) === 0 && Number(poExtraPcsInput?.value || 0) === 0) {
                    if (poUnitQtyInput) poUnitQtyInput.value = '1';
                }
                if (poMode === 'pcs' && Number(poQtyInput?.value || 0) < 1) {
                    if (poQtyInput) poQtyInput.value = '1';
                }

                const effQty = getEffectiveQty();
                const baseRate = baseRateFor(activeOrderProduct, poMode);
                const total = round2(effQty * baseRate);
                if (poRateInput) poRateInput.value = String(baseRate);
                if (poTotalInput) poTotalInput.value = String(total);
                updateOcDisplay(total);
            });
        });

        function handleQtyChanged() {
            if (!activeOrderProduct) return;
            const effQty = getEffectiveQty();
            const rate = Math.max(0, Number(poRateInput?.value || 0));
            const total = round2(effQty * rate);
            if (poTotalInput) poTotalInput.value = String(total);
            updateOcDisplay(total);
        }

        // Unit Mode steppers (Unit + Extra Pcs)
        poUnitMinus?.addEventListener('click', () => {
            const curr = Math.max(0, Math.floor(Number(poUnitQtyInput?.value || 0)));
            if (poUnitQtyInput) poUnitQtyInput.value = String(Math.max(0, curr - 1));
            handleQtyChanged();
        });
        poUnitPlus?.addEventListener('click', () => {
            const curr = Math.max(0, Math.floor(Number(poUnitQtyInput?.value || 0)));
            if (poUnitQtyInput) poUnitQtyInput.value = String(curr + 1);
            handleQtyChanged();
        });
        poExtraPcsMinus?.addEventListener('click', () => {
            const curr = Math.max(0, Math.floor(Number(poExtraPcsInput?.value || 0)));
            if (poExtraPcsInput) poExtraPcsInput.value = String(Math.max(0, curr - 1));
            handleQtyChanged();
        });
        poExtraPcsPlus?.addEventListener('click', () => {
            const curr = Math.max(0, Math.floor(Number(poExtraPcsInput?.value || 0)));
            if (poExtraPcsInput) poExtraPcsInput.value = String(curr + 1);
            handleQtyChanged();
        });
        poUnitQtyInput?.addEventListener('input', handleQtyChanged);
        poExtraPcsInput?.addEventListener('input', handleQtyChanged);

        // Pcs Mode stepper
        poQtyMinus?.addEventListener('click', () => {
            const curr = Math.max(1, Math.floor(Number(poQtyInput?.value || 1)));
            if (poQtyInput) poQtyInput.value = String(Math.max(1, curr - 1));
            handleQtyChanged();
        });
        poQtyPlus?.addEventListener('click', () => {
            const curr = Math.max(0, Math.floor(Number(poQtyInput?.value || 0)));
            if (poQtyInput) poQtyInput.value = String(curr + 1);
            handleQtyChanged();
        });
        poQtyInput?.addEventListener('input', handleQtyChanged);

        // Changing Per Unit/Pcs Amount -> updates Total Amount & O/C
        poRateInput?.addEventListener('input', () => {
            if (!activeOrderProduct) return;
            const effQty = getEffectiveQty();
            const rate = Math.max(0, Number(poRateInput.value || 0));
            const total = round2(effQty * rate);
            if (poTotalInput) poTotalInput.value = String(total);
            updateOcDisplay(total);
        });

        // Changing Total Amount -> updates Per Unit/Pcs Amount & O/C
        poTotalInput?.addEventListener('input', () => {
            if (!activeOrderProduct) return;
            const effQty = getEffectiveQty();
            const total = Math.max(0, Number(poTotalInput.value || 0));
            const rate = effQty > 0 ? round2(total / effQty) : 0;
            if (poRateInput) poRateInput.value = String(rate);
            updateOcDisplay(total);
        });

        poRemoveItemBtn?.addEventListener('click', () => {
            if (!activeOrderProduct) return;
            getActiveCart().delete(activeOrderProduct.id);
            closeModal('productOrderModal');
            renderRetailerProductsGrid();
            renderCartBar();
            showToast(`${activeOrderProduct.name} সরানো হয়েছে।`);
        });

        poForm?.addEventListener('submit', (e) => {
            e.preventDefault();
            if (!activeOrderProduct) return;

            const unitQty = Math.max(0, Math.floor(Number(poUnitQtyInput?.value || 0)));
            const extraPcs = Math.max(0, Math.floor(Number(poExtraPcsInput?.value || 0)));
            const pcsQty = Math.max(0, Math.floor(Number(poQtyInput?.value || 0)));
            const effQty = getEffectiveQty();

            if (effQty <= 0) {
                showToast('অন্তত ১ ইউনিট বা ১ পিস দিন।');
                return;
            }

            const rate = Math.max(0, round2(Number(poRateInput?.value || 0)));
            const total = Math.max(0, round2(Number(poTotalInput?.value || 0)));
            const baseRate = baseRateFor(activeOrderProduct, poMode);
            const oc = round2(total - round2(effQty * baseRate));

            getActiveCart().set(activeOrderProduct.id, {
                productId: activeOrderProduct.id,
                name: activeOrderProduct.name,
                mode: poMode,
                unitQty,
                extraPcs,
                pcsQty,
                rate,
                total,
                oc,
            });

            closeModal('productOrderModal');
            renderRetailerProductsGrid();
            renderCartBar();
            const wantPcs = poMode === 'unit' ? (unitQty * Math.max(1, Number(activeOrderProduct.qty_per_unit || 1))) + extraPcs : pcsQty;
            const stockLeft = Number(activeOrderProduct.available_pcs ?? Infinity);
            showToast(wantPcs > stockLeft
                ? `সতর্কতা: ${activeOrderProduct.name} স্টকে মাত্র ${bnNum(Math.max(0, stockLeft))} পিস আছে।`
                : `${activeOrderProduct.name} সংরক্ষিত হয়েছে (O/C ${formatSignedOc(oc)})।`);
        });

        openCartReviewBtn?.addEventListener('click', () => {
            if (getActiveCart().size === 0) return;
            renderOrderCartModal();
            openModal('orderCartModal');
        });

        ocTableBody?.addEventListener('click', (e) => {
            const btn = e.target.closest('[data-remove-cart-id]');
            if (!btn) return;
            const pid = btn.getAttribute('data-remove-cart-id');
            const cart = getActiveCart();
            cart.delete(pid);
            renderRetailerProductsGrid();
            renderCartBar();
            if (cart.size === 0) {
                closeModal('orderCartModal');
                showToast('কার্ট খালি করা হয়েছে।');
            } else {
                renderOrderCartModal();
            }
        });

        function renderOrderSuccessModal(snapshot) {
            if (!snapshot) return;
            const memoNo = snapshot.orderCode ? bnDigits(snapshot.orderCode) : '—';
            if (osRetailerSubtitle) {
                osRetailerSubtitle.textContent = `${snapshot.retailerName} · মেমো ${memoNo} · ${bnNum(snapshot.items.length)}টি পণ্য`;
            }
            if (osReceiptRetailer) osReceiptRetailer.textContent = snapshot.retailerName;
            if (osReceiptCode) osReceiptCode.textContent = memoNo;
            if (osReceiptTime) osReceiptTime.textContent = `আজ · ${bnDigits(snapshot.orderTime || '')}`;
            if (osReceiptSr) {
                const srName = app.dataset.srName || '';
                const srComp = app.dataset.srCompany || '';
                osReceiptSr.textContent = srName ? `SR: ${srName}${srComp ? ` · ${srComp}` : ''}` : '';
            }
            if (osItemsBody) {
                osItemsBody.innerHTML = snapshot.items.map((it) => {
                    const ocVal = round2(it.oc || 0);
                    const ocTagHtml = Math.abs(ocVal) >= 0.01
                        ? `<span class="li-oc ${ocVal > 0 ? 'is-over' : 'is-comm'}">${ocVal > 0 ? '+' : '−'}${formatMoney2(Math.abs(ocVal))}</span>`
                        : '';
                    return `
                        <div class="li-row">
                            <span class="li-av">${escapeHtml(Array.from(String(it.name || '•'))[0])}</span>
                            <span class="li-main"><b>${escapeHtml(it.name)}</b><span class="tabular">${escapeHtml(formatCartQtyPill(it))} × ${formatMoney2(it.rate)}${ocTagHtml}</span></span>
                            <strong class="tabular">${formatMoney2(it.total)}</strong>
                        </div>
                    `;
                }).join('');
                const over = round2(snapshot.items.reduce((acc, it) => acc + Math.max(0, Number(it.oc || 0)), 0));
                const comm = round2(snapshot.items.reduce((acc, it) => acc + Math.min(0, Number(it.oc || 0)), 0));
                const net = round2(over + comm);
                const setText = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
                setText('osOver', `+${formatMoney2(over)}`);
                setText('osComm', `−${formatMoney2(Math.abs(comm))}`);
                setText('osNet', `${net < 0 ? '−' : (net > 0 ? '+' : '')}${formatMoney2(Math.abs(net))}`);
            }
            if (osTotalCost) {
                osTotalCost.textContent = formatMoney2(snapshot.total);
            }
            if (osTotalOc) {
                const roundedOc = round2(snapshot.totalOc);
                osTotalOc.textContent = formatSignedOc(roundedOc);
                osTotalOc.className = 'os-oc-val tabular'
                    + (roundedOc > 0.009 ? ' is-over' : (roundedOc < -0.009 ? ' is-comm' : ''));
            }
        }

        confirmOrderBtn?.addEventListener('click', async () => {
            if (!activeOrderRetailer) return;
            const cart = getActiveCart();
            if (cart.size === 0) return;

            // Unlock AudioContext synchronously during user gesture
            const audioCtx = getUnlockedAudioCtx();

            const items = Array.from(cart.values()).map((it) => ({ ...it }));
            let total = 0;
            let totalOc = 0;
            items.forEach((it) => {
                total += Number(it.total || 0);
                totalOc += Number(it.oc || 0);
            });

            const snapshot = {
                retailerId: activeOrderRetailer.id,
                retailerName: activeOrderRetailer.name,
                items,
                total: round2(total),
                totalOc: round2(totalOc),
            };

            let res;
            try {
                const editingId = activeOrderId;
                const orderBody = {
                    retailer_id: rid(activeOrderRetailer.id),
                    items: items.map((it) => ({ product_id: Number(it.productId), pcs: itemPcs(it), total: it.total })),
                    at: nowSec(),
                };
                const tmpId = editingId ? null : `tmp-${window.HbOffline?.uuid?.() || Date.now()}`;
                res = await withButtonLoading(confirmOrderBtn, 'সংরক্ষণ হচ্ছে…', () => srApi(
                    editingId ? 'PUT' : 'POST',
                    editingId ? `/sr/orders/${editingId}` : '/sr/orders',
                    orderBody,
                    { label: `অর্ডার · ${activeOrderRetailer.name}`, tmp: tmpId, apply: () => localSaveOrder(orderBody, editingId, tmpId) }
                ));
            } catch (err) {
                showToast(err.message);
                return;
            }

            snapshot.orderId = res.order.id;
            snapshot.orderCode = res.order.code || '';
            snapshot.orderTime = res.order.time || '';
            snapshot.wasNew = !activeOrderId;
            snapshot.total = res.order.sr_total;
            snapshot.totalOc = res.order.oc;
            setDay(res.day);
            retailerCarts.delete(activeOrderRetailer.id);
            activeOrderId = null;
            (res.warnings || []).forEach((w) => showToast(`স্টক সতর্কতা: ${w}`));

            lastConfirmedOrder = snapshot;
            renderRetailerProductsGrid();
            renderCartBar();
            renderOrderSuccessModal(snapshot);
            replaceTopModal('orderCartModal', 'orderSuccessModal');
            playOrderSuccessSound(audioCtx);
        });

        undoConfirmedOrderBtn?.addEventListener('click', async () => {
            if (!lastConfirmedOrder) {
                closeModal('orderSuccessModal');
                return;
            }
            if (lastConfirmedOrder.wasNew) {
                try {
                    const res = await withButtonLoading(undoConfirmedOrderBtn, 'ফিরিয়ে নেওয়া হচ্ছে…', () => srApi('DELETE', `/sr/orders/${lastConfirmedOrder.orderId}`, undefined, {
                        label: 'অর্ডার বাতিল',
                        apply: () => localCancelOrder(lastConfirmedOrder.orderId),
                    }));
                    setDay(res.day);
                } catch (err) {
                    showToast(err.message);
                    return;
                }
                activeOrderId = null;
            } else {
                activeOrderId = lastConfirmedOrder.orderId;
            }
            const restored = new Map();
            lastConfirmedOrder.items.forEach((it) => {
                restored.set(it.productId, { ...it });
            });
            retailerCarts.set(lastConfirmedOrder.retailerId, restored);
            const ret = srStore.retailers.find((r) => r.id === lastConfirmedOrder.retailerId);
            if (ret) activeOrderRetailer = ret;

            lastConfirmedOrder = null;
            renderRetailerProductsGrid();
            renderCartBar();
            renderOrderCartModal();
            replaceTopModal('orderSuccessModal', 'orderCartModal');
            showToast(activeOrderId ? 'অর্ডার সম্পাদনার জন্য খোলা হয়েছে।' : 'অর্ডার বাতিল করে কার্টে ফিরিয়ে আনা হয়েছে।');
        });

        nextShopBtn?.addEventListener('click', () => {
            lastConfirmedOrder = null;
            closeAllModals({ syncHistory: true });
        });

        nearbyListEl?.addEventListener('click', (e) => {
            const moreCard = e.target.closest('[data-nearby-more]');
            if (moreCard) {
                nearbyVisibleLimit += 250;
                const shown = nearbyRenderedItems.slice(0, nearbyVisibleLimit);
                nearbyListEl.innerHTML = shown.map(buildNearbyCardHtml).join('')
                    + (nearbyRenderedItems.length > nearbyVisibleLimit ? `<button type="button" class="quick-retailer-card nearby-more-card" data-nearby-more="1"><strong>+ আরো ${bnNum(nearbyRenderedItems.length - nearbyVisibleLimit)}টি</strong><span class="muted small">সব দেখতে ট্যাপ করুন</span></button>` : '');
                return;
            }
            const row = e.target.closest('[data-focus-retailer]');
            if (!row) return;
            const id = row.getAttribute('data-focus-retailer');
            openRetailerProducts(id);
        });

        openAddBtn?.addEventListener('click', () => {
            if (addErrorEl) addErrorEl.hidden = true;
            openModal('addRetailerModal');
        });

        cancelAddBtn?.addEventListener('click', resetAddRetailerForm);
        closeAddBtn?.addEventListener('click', resetAddRetailerForm);

        pickOnMapBtn?.addEventListener('click', enterPinPickerMode);
        pickOnMapInlineBtn?.addEventListener('click', enterPinPickerMode);

        cancelPinBtn?.addEventListener('click', () => {
            exitPinPickerMode();
            openModal('addRetailerModal');
        });

        confirmPinBtn?.addEventListener('click', () => {
            if (!pendingPin) return;
            const coordsText = `${pendingPin.lat.toFixed(6)}, ${pendingPin.lng.toFixed(6)}`;
            const distFromSr = haversineMeters(srLoc.lat, srLoc.lng, pendingPin.lat, pendingPin.lng);
            if (retLatInput) retLatInput.value = pendingPin.lat.toFixed(6);
            if (retLngInput) retLngInput.value = pendingPin.lng.toFixed(6);
            if (retLocInput) retLocInput.value = coordsText;
            if (retPinHint) {
                retPinHint.textContent = distFromSr <= SR_RADIUS_METERS
                    ? `পিন করা হয়েছে ${bnDigits(coordsText)} (${bnNum(distFromSr)} মি. — আপনার ৫০ মি. এলাকার ভেতরে)`
                    : `পিন করা হয়েছে ${bnDigits(coordsText)} (${bnNum(distFromSr)} মি. — ৫০ মি. এলাকার বাইরে)`;
            }

            exitPinPickerMode();
            openModal('addRetailerModal');
        });

        addForm?.addEventListener('submit', async (e) => {
            e.preventDefault();
            const name = (retNameInput?.value || '').trim();
            const locationText = (retLocInput?.value || '').trim();

            if (!name || !locationText) {
                if (addErrorEl) {
                    addErrorEl.textContent = 'দোকানের নাম ও ঠিকানা লিখুন (অথবা ম্যাপে পিন দিন)।';
                    addErrorEl.hidden = false;
                }
                return;
            }
            if (addErrorEl) addErrorEl.hidden = true;

            const saveBtn = document.getElementById('saveRetailerBtn');
            let lat = Number(retLatInput?.value || 0);
            let lng = Number(retLngInput?.value || 0);

            if (!lat || !lng) {
                // Place near SR's current location (~18m offset) when no manual pin was picked
                const angle = (srStore.retailers.length * 1.3) % (Math.PI * 2);
                lat = Number((srLoc.lat + Math.cos(angle) * 0.00016).toFixed(6));
                lng = Number((srLoc.lng + Math.sin(angle) * 0.00016).toFixed(6));
            }

            const distFromSr = haversineMeters(srLoc.lat, srLoc.lng, lat, lng);
            let newRetailer;
            try {
                const retBody = { name, address: locationText, lat, lng };
                const tmpRet = `tmp-${window.HbOffline?.uuid?.() || Date.now()}`;
                const res = await withButtonLoading(saveBtn, 'সংরক্ষণ হচ্ছে…', () => srApi('POST', '/sr/retailers', retBody, {
                    label: `নতুন দোকান · ${name}`,
                    tmp: tmpRet,
                    apply: () => localAddRetailer(retBody, tmpRet),
                }));
                newRetailer = res.retailer;
            } catch (err) {
                if (addErrorEl) {
                    addErrorEl.textContent = err.message;
                    addErrorEl.hidden = false;
                }
                return;
            }
            srStore.retailers.unshift(newRetailer);
            saveShops();
            focusedRetailerId = newRetailer.id;

            resetAddRetailerForm();
            closeModal('addRetailerModal');
            refreshOrderView();

            if (hasLeaflet && activeLeafletMap) {
                activeLeafletMap.setView([srLoc.lat, srLoc.lng], 18, { animate: true });
            }

            showToast(
                distFromSr <= SR_RADIUS_METERS
                    ? `"${name}" দোকানটি যোগ হয়েছে (${bnNum(distFromSr)} মি. দূরে)।`
                    : `"${name}" দোকানটি সংরক্ষিত হয়েছে (${bnNum(distFromSr)} মি. দূরে — ৫০ মি. এলাকার বাইরে)।`
            );
        });

        // =====================================================================
        // TODAY'S ORDERS: list, edit, cancel, complete / reopen the day
        // =====================================================================
        const todayList = document.getElementById('todayOrdersList');
        const todayBtnLabel = document.getElementById('todayBtnLabel');
        const completeDayBtn = document.getElementById('completeDayBtn');
        const reopenDayBtn = document.getElementById('reopenDayBtn');

        // ------------------------------------------------------- offline: local copies of server changes
        // Used only while a write waits in the offline queue. They mirror Order::save / cancel / completeDay on the
        // server closely enough for the screen; once the queue is synced the server's own data replaces them.
        const snapKey = `sr:${HB_USER}`;
        const shopsKey = `srshops:${HB_USER}`;
        const pad2 = (n) => String(n).padStart(2, '0');
        const localToday = () => { const d = new Date(); return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`; };
        const emptyDay = (date) => ({ date, completed: false, locked: false, orders: [], totals: { orders: 0, value: 0, oc: 0 } });
        const timeLabel = () => { const d = new Date(); const h = d.getHours(); return `${pad2(h % 12 || 12)}:${pad2(d.getMinutes())} ${h >= 12 ? 'PM' : 'AM'}`; };

        function saveSnapshot() {
            if (offlineOk()) window.HbOffline.kvSet(snapKey, { date: day.date, day, products: catalogProducts, at: Date.now() });
        }
        function saveShops() {
            if (offlineOk()) window.HbOffline.kvSet(shopsKey, srStore.retailers);
        }

        /** A new calendar day began while the page was open / cached: today starts empty. */
        function ensureToday() {
            const today = localToday();
            if (day.date !== today) day = emptyDay(today);
        }

        function recomputeDay() {
            day.totals = {
                orders: day.orders.length,
                value: round2(day.orders.reduce((s, o) => s + o.sr_total, 0)),
                oc: round2(day.orders.reduce((s, o) => s + o.oc, 0)),
            };
            day.locked = day.orders.some((o) => !o.editable);
        }

        function localSaveOrder(body, orderId, tmpId) {
            ensureToday();
            if (day.completed) throw new Error('আজকের অর্ডার সম্পন্ন হয়েছে। পরিবর্তন করতে "আজ" থেকে দিনটি পুনরায় খুলুন।');
            const ret = srStore.retailers.find((r) => String(r.id) === String(body.retailer_id));
            if (!ret) throw new Error('একটি দোকান নির্বাচন করুন।');
            if (!body.items.length) throw new Error('অন্তত একটি পণ্য যোগ করুন।');
            const existing = orderId != null
                ? day.orders.find((o) => String(o.id) === String(orderId))
                : orderForRetailer(body.retailer_id);
            if (existing && !existing.editable) throw new Error(`${ret.name}-এর অর্ডারটি ইতিমধ্যেই ট্রিপে দেওয়া হয়েছে।`);

            const frozen = {};
            const own = {};
            (existing?.items || []).forEach((it) => { frozen[String(it.product_id)] = it.base_rate_pc; own[String(it.product_id)] = it.pcs; });
            const warnings = [];
            const items = body.items.map((it) => {
                const p = catalogProducts.find((x) => String(x.id) === String(it.product_id));
                if (!p) throw new Error('একটি পণ্য আর পাওয়া যাচ্ছে না। পেজ রিলোড করে আবার চেষ্টা করুন।');
                const pcs = Math.floor(Number(it.pcs));
                const total = round2(it.total);
                const base = frozen[String(p.id)] ?? Number(p.pc_price);
                const qpu = Math.max(1, Number(p.qty_per_unit || 1));
                const available = Number(p.available_pcs ?? Infinity) + (own[String(p.id)] || 0);
                if (pcs > available) warnings.push(`${p.name}: ordered ${pcs} pcs, only ${Math.max(0, available)} pcs in stock.`);
                return {
                    product_id: Number(p.id), name: p.name, unit_type: p.unit_type, qty_per_unit: qpu, pcs,
                    qty: `${Math.floor(pcs / qpu)} ${p.unit_type} ${pcs % qpu} pcs`, delivered_pcs: 0,
                    base_rate_pc: base, sr_rate_pc: Math.round((total / pcs) * 10000) / 10000, total, oc: round2(total - pcs * base),
                    image: p.image, code: p.code, tint: p.tint,
                };
            });
            const order = {
                ...(existing || {}),
                id: existing ? existing.id : tmpId,
                code: existing ? existing.code : 'সিঙ্ক বাকি',
                date: day.date,
                time: existing ? existing.time : timeLabel(),
                retailer_id: ret.id,
                retailer: ret.name,
                retailer_address: ret.address || null,
                retailer_phone: ret.phone || null,
                trip: null,
                base_total: round2(items.reduce((s, i) => s + i.pcs * i.base_rate_pc, 0)),
                sr_total: round2(items.reduce((s, i) => s + i.total, 0)),
                oc: round2(items.reduce((s, i) => s + i.oc, 0)),
                status: 'Pending',
                status_key: 'pending',
                editable: true,
                items,
            };
            day.orders = existing ? day.orders.map((o) => (o === existing ? order : o)) : [order, ...day.orders];
            recomputeDay();
            saveSnapshot();
            return { order, warnings, day };
        }

        function localCancelOrder(orderId) {
            const o = day.orders.find((x) => String(x.id) === String(orderId));
            if (!o) throw new Error('অর্ডারটি পাওয়া যায়নি।');
            if (!o.editable) throw new Error('এই অর্ডারটি ইতিমধ্যে ট্রিপে দেওয়া হয়েছে, বাতিল করা যাবে না।');
            if (day.completed) throw new Error('সম্পন্ন দিনের অর্ডার বাতিল করা যায় না। আগে দিনটি পুনরায় খুলুন।');
            day.orders = day.orders.filter((x) => x !== o);
            recomputeDay();
            saveSnapshot();
            return { day };
        }

        function localCompleteDay() {
            ensureToday();
            if (!day.orders.length) throw new Error('সম্পন্ন করার মতো কোনো অর্ডার নেই।');
            day.completed = true;
            saveSnapshot();
            return { day };
        }

        function localReopenDay() {
            if (day.orders.some((o) => !o.editable)) throw new Error('এই দিনের অর্ডার ইতিমধ্যে ট্রিপে দেওয়া হয়েছে, তাই দিনটি খোলা যাবে না।');
            day.completed = false;
            saveSnapshot();
            return { day };
        }

        function localAddRetailer(body, tmpId) {
            const dup = srStore.retailers.find((r) => r.name === body.name && Math.abs(Number(r.lat) - body.lat) < 0.0003 && Math.abs(Number(r.lng) - body.lng) < 0.0003);
            if (dup) throw new Error(`"${body.name}" এই লোকেশনে আগেই নিবন্ধিত আছে।`);
            return { retailer: { id: tmpId, name: body.name, phone: '', address: body.address, lat: body.lat, lng: body.lng, sr_id: null, due: 0 } };
        }

        /** Use the phone's copy when it holds changes the page (from cache, or behind the queue) does not show. */
        async function restoreOfflineState() {
            if (!offlineOk()) return;
            const [snap, shops, pending] = await Promise.all([window.HbOffline.kvGet(snapKey), window.HbOffline.kvGet(shopsKey), window.HbOffline.count(HB_USER)]);
            const fromCache = app.dataset.fromCache === '1';
            if (fromCache || pending > 0) {
                if (snap && snap.date === localToday()) {
                    day = snap.day;
                    if (Array.isArray(snap.products) && snap.products.length) catalogProducts.splice(0, catalogProducts.length, ...snap.products);
                } else if (fromCache) {
                    ensureToday();
                }
                if (Array.isArray(shops) && shops.length) mergeRetailerDirectory(shops);
                setDay(day);
            } else {
                saveSnapshot();
            }
            if (fromCache && pending === 0 && navigator.onLine) refreshFromServer();
        }

        /** After the queue reached the server: replace the local guesses (temporary ids, order codes) by the server's data. */
        async function refreshFromServer() {
            if (modalStack.length) { setTimeout(refreshFromServer, 5000); return; } // don't reset a cart being edited
            try {
                const [d, s] = await Promise.all([srApi('GET', '/sr/orders/today'), srApi('GET', '/sr/retailers')]);
                if (!document.body.contains(app)) return;
                if (Array.isArray(s?.retailers)) {
                    srStore.retailers = s.retailers;
                    srStore.retailersSynced = true;
                    BanglishSearch.warmup(srStore.retailers, retKey);
                    saveShops();
                }
                if (d?.day) {
                    day = d.day;
                    saveSnapshot();
                }
                setDay(day);
            } catch { /* still offline */ }
        }

        function setDay(next) {
            day = next || day;
            const t = day.totals || { orders: 0, value: 0 };
            if (todayBtnLabel) todayBtnLabel.textContent = `আজ · ${bnNum(t.orders)}${day.completed ? ' ✓' : ''}`;
            renderTodaySheet();
            refreshOrderView();
        }

        function renderTodaySheet() {
            if (!todayList) return;
            const t = day.totals || { orders: 0, value: 0, oc: 0 };
            const sub = document.getElementById('todayOrdersSub');
            if (sub) sub.textContent = `${bnDigits(day.date)} · ${bnNum(t.orders)}টি অর্ডার · ${formatMoney2(t.value)} · O/C ${formatSignedOc(t.oc)}`;
            const box = document.getElementById('dayStatusBox');
            if (box) {
                box.className = `day-status ${day.completed ? 'is-done' : ''}`;
                box.textContent = day.completed
                    ? (day.locked ? 'সম্পন্ন — অর্ডারগুলো ডেলিভারি ট্রিপে দেওয়া হয়েছে।' : 'সম্পন্ন — ডেলিভারি ট্রিপের অপেক্ষায়। পরিবর্তনের জন্য পুনরায় খুলুন।')
                    : 'খোলা আছে — দিনের কাজ শেষে "আজকের অর্ডার সম্পন্ন করুন" চাপুন যাতে পার্টনার ট্রিপে দিতে পারেন।';
            }
            todayList.innerHTML = (day.orders || []).length ? day.orders.map((o) => `
                <div class="today-order-row">
                    <div class="today-order-main">
                        <strong>${escapeHtml(o.retailer)}</strong>
                        <span class="muted small tabular">${escapeHtml(bnDigits(o.code))} · ${bnNum(o.items.length)}টি পণ্য · ${escapeHtml(bnDigits(o.time))}${o.trip ? ` · ${escapeHtml(bnDigits(o.trip))}` : ''}</span>
                    </div>
                    <div class="today-order-amt">
                        <strong class="tabular">${formatMoney2(o.sr_total)}</strong>
                        <span class="small tabular ${o.oc > 0 ? 'is-over' : (o.oc < 0 ? 'is-comm' : 'muted')}">O/C ${formatSignedOc(o.oc)}</span>
                    </div>
                    ${o.editable && !day.completed ? `
                        <div class="today-order-actions">
                            <button type="button" class="btn btn-secondary btn-xs" data-edit-order="${o.id}">সম্পাদনা</button>
                            <button type="button" class="btn btn-danger-ghost btn-xs" data-cancel-order="${o.id}">বাতিল</button>
                        </div>` : `<span class="badge ${o.editable ? 'badge-neutral' : 'badge-info'}">${escapeHtml(bnStatus(o.status_key || o.status))}</span>`}
                </div>`).join('') : '<div class="empty-state" style="padding:18px 12px"><p class="muted small" style="margin:0">আজ এখনো কোনো অর্ডার নেই।</p></div>';
            if (completeDayBtn) {
                completeDayBtn.hidden = !!day.completed;
                completeDayBtn.disabled = !(day.orders || []).length;
            }
            if (reopenDayBtn) reopenDayBtn.hidden = !day.completed || !!day.locked;
        }

        async function cancelOrder(orderId, btn) {
            if (!window.confirm('এই অর্ডারটি বাতিল করবেন?')) return false;
            try {
                const res = await withButtonLoading(btn, 'বাতিল হচ্ছে…', () => srApi('DELETE', `/sr/orders/${orderId}`, undefined, {
                    label: 'অর্ডার বাতিল',
                    apply: () => localCancelOrder(orderId),
                }));
                showToast(res.message);
                setDay(res.day);
                return true;
            } catch (err) {
                showToast(err.message);
                return false;
            }
        }

        document.getElementById('openTodayOrdersBtn')?.addEventListener('click', () => {
            renderTodaySheet();
            openModal('todayOrdersModal');
        });

        todayList?.addEventListener('click', async (e) => {
            const edit = e.target.closest('[data-edit-order]');
            const cancel = e.target.closest('[data-cancel-order]');
            if (edit) {
                const o = day.orders.find((x) => String(x.id) === edit.dataset.editOrder);
                if (!o) return;
                retailerCarts.set(String(o.retailer_id), cartFromOrder(o));
                openRetailerProducts(String(o.retailer_id), { replaceFrom: 'todayOrdersModal' });
            } else if (cancel) {
                await cancelOrder(cancel.dataset.cancelOrder, cancel);
            }
        });

        document.getElementById('cancelOrderBtn')?.addEventListener('click', async (e) => {
            if (!activeOrderId || !activeOrderRetailer) return;
            if (await cancelOrder(activeOrderId, e.currentTarget)) {
                retailerCarts.delete(activeOrderRetailer.id);
                activeOrderId = null;
                closeAllModals({ syncHistory: true });
                renderCartBar();
            }
        });

        completeDayBtn?.addEventListener('click', async () => {
            if (!window.confirm('আজকের অর্ডার সম্পন্ন করবেন? দিনটি পুনরায় না খোলা পর্যন্ত নতুন অর্ডার যোগ বা পরিবর্তন করা যাবে না।')) return;
            try {
                const res = await withButtonLoading(completeDayBtn, 'সম্পন্ন হচ্ছে…', () => srApi('POST', '/sr/orders/complete', { at: nowSec() }, {
                    label: 'আজকের অর্ডার সম্পন্ন',
                    apply: () => localCompleteDay(),
                }));
                showToast(res.message);
                setDay(res.day);
            } catch (err) { showToast(err.message); }
        });

        reopenDayBtn?.addEventListener('click', async () => {
            try {
                const res = await withButtonLoading(reopenDayBtn, 'খোলা হচ্ছে…', () => srApi('POST', '/sr/orders/reopen', { at: nowSec() }, {
                    label: 'দিন পুনরায় খোলা',
                    apply: () => localReopenDay(),
                }));
                showToast(res.message);
                setDay(res.day);
            } catch (err) { showToast(err.message); }
        });

        setDay(day);
        restoreOfflineState();
        pageSyncedHook = refreshFromServer;

        // =====================================================================
        // LIVE GPS: keep the 50m circle on the SR's real position
        // =====================================================================
        if (navigator.geolocation && geoWatchId === null) {
            const geoFilter = window.HbGeoFilter.create();
            geoWatchId = navigator.geolocation.watchPosition((raw) => {
                const first = !srStore.gpsFix;
                const pos = geoFilter.push(raw);   // smoothed; null while standing still / vague fix
                if (!pos) return;
                srLoc.lat = pos.lat;
                srLoc.lng = pos.lng;
                srStore.gpsFix = true;
                if (first) window.HbMapTiles?.prefetch?.(pos.lat, pos.lng);
                refreshOrderView();
                if (first && hasLeaflet && activeLeafletMap) activeLeafletMap.setView([srLoc.lat, srLoc.lng], 18);
            }, () => {
                if (!srStore.gpsFix) showToast('লোকেশন পাওয়া যায়নি। কাছাকাছি দোকান দেখতে লোকেশন পারমিশন দিন।');
            }, { enableHighAccuracy: true, maximumAge: 0, timeout: 20000 });
        }
    }

    // =========================================================================
    // 3. HISTORY PAGE (< DATE > NAVIGATOR + ORDER DETAIL MODAL)
    // =========================================================================
    function initHistoryPage() {
        const app = document.getElementById('historyApp');
        if (!app) return;

        let orders = JSON.parse(app.dataset.orders || '[]');
        let currentDate = app.dataset.defaultDate;
        const today = app.dataset.today;
        let loadSeq = 0;

        const prevBtn = document.getElementById('historyPrevBtn');
        const nextBtn = document.getElementById('historyNextBtn');
        const dateInput = document.getElementById('historyDateInput');
        const dateDisplay = document.getElementById('historyDateDisplay');
        const countEl = document.getElementById('historyOrderCount');
        const dayTotalEl = document.getElementById('historyDayTotal');
        const dayOcEl = document.getElementById('historyDayOc');
        const listEl = document.getElementById('historyList');
        const emptyEl = document.getElementById('historyEmpty');

        const money = (n) => {
            const v = Math.round((Number(n || 0) + Number.EPSILON) * 100) / 100;
            return `৳ ${bnDigits(v.toLocaleString('en-US', { minimumFractionDigits: Number.isInteger(v) ? 0 : 2, maximumFractionDigits: 2 }))}`;
        };
        const signed = (n) => `${Number(n) >= 0 ? '+' : '−'}${money(Math.abs(Number(n)))}`;

        function formatHumanDate(isoDate) {
            const parts = isoDate.split('-').map(Number);
            if (parts.length !== 3) return bnDigits(isoDate);
            const m = MONTHS_BN[parts[1] - 1] || String(parts[1]);
            return `${bnDigits(parts[2])} ${m} ${bnDigits(parts[0])}`;
        }

        function shiftIsoDate(isoDate, deltaDays) {
            const parts = isoDate.split('-').map(Number);
            return new Date(Date.UTC(parts[0], parts[1] - 1, parts[2] + deltaDays)).toISOString().slice(0, 10);
        }

        function badgeClass(key) {
            if (key === 'delivered') return 'badge-success';
            if (key === 'assigned' || key === 'dispatched') return 'badge-info';
            if (key === 'partial' || key === 'due' || key === 'pending') return 'badge-warning';
            if (key === 'cancelled') return 'badge-danger';
            return 'badge-neutral';
        }

        function buildTimelineHtml(o) {
            const st = String(o.status_key || '').toLowerCase();
            const isCancelled = st === 'cancelled';
            const isDone = st === 'delivered';
            const isPartial = st === 'partial' || st === 'due';
            const hasTrip = !!o.trip || st === 'assigned' || st === 'dispatched' || isDone || isPartial;
            const onRoad = st === 'dispatched' || isDone || isPartial || (isCancelled && hasTrip);

            const s1 = 'is-done';
            const s2 = isDone || isPartial || onRoad ? 'is-done' : (hasTrip ? 'is-active' : '');
            const s3 = isDone || isPartial || (isCancelled && hasTrip) ? 'is-done' : (st === 'dispatched' ? 'is-active' : '');
            const s4 = isDone ? 'is-done' : (isPartial ? 'is-warn' : (isCancelled ? 'is-danger' : ''));
            const s4Dot = isDone ? '✓' : (isPartial ? '!' : (isCancelled ? '✕' : '•'));
            const s4Text = isCancelled ? 'ফেরত' : (isPartial ? (st === 'partial' ? 'আংশিক' : 'বাকি') : 'পৌঁছেছে');

            return `
                <div class="history-timeline">
                    <span class="ht-step ${s1}"><span class="ht-dot">✓</span>অর্ডার</span>
                    <span class="ht-line ${s2 ? 'is-done' : ''}"></span>
                    <span class="ht-step ${s2}"><span class="ht-dot">${hasTrip ? '✓' : '•'}</span>ভ্যান</span>
                    <span class="ht-line ${s3 ? 'is-done' : ''}"></span>
                    <span class="ht-step ${s3}"><span class="ht-dot">${s3 === 'is-done' ? '✓' : '•'}</span>পথে</span>
                    <span class="ht-line ${s4 ? 'is-done' : ''}"></span>
                    <span class="ht-step ${s4}"><span class="ht-dot">${s4Dot}</span>${escapeHtml(s4Text)}</span>
                </div>`;
        }

        function render() {
            if (dateDisplay) dateDisplay.textContent = (currentDate === today ? 'আজ, ' : '') + formatHumanDate(currentDate);
            if (dateInput) dateInput.value = currentDate;
            if (nextBtn) nextBtn.disabled = currentDate >= today;

            const active = orders.filter((o) => o.status_key !== 'cancelled');
            if (countEl) countEl.textContent = bnNum(orders.length);
            if (dayTotalEl) dayTotalEl.textContent = money(active.reduce((s, o) => s + o.sr_total, 0));
            if (dayOcEl) dayOcEl.textContent = signed(active.reduce((s, o) => s + o.oc, 0));
            const subEl = document.getElementById('historySubSummary');
            if (subEl) {
                const shops = new Set(orders.map((o) => o.retailer)).size;
                subEl.textContent = orders.length ? `${bnNum(shops)}টি দোকানে অর্ডার` : 'এই দিনে কোনো অর্ডার নেই';
            }

            if (!listEl || !emptyEl) return;
            emptyEl.hidden = orders.length > 0;
            listEl.innerHTML = orders.map((o, idx) => {
                const st = String(o.status_key || '').toLowerCase();
                const isCancelled = st === 'cancelled';
                const isDone = st === 'delivered';
                const isPartial = st === 'partial' || st === 'due';
                const isTrip = !!o.trip || st === 'assigned' || st === 'dispatched';
                const items = Array.isArray(o.items) ? o.items : [];
                const over = items.reduce((acc, it) => acc + Math.max(0, Number(it.oc || 0)), 0);
                const comm = items.reduce((acc, it) => acc + Math.min(0, Number(it.oc || 0)), 0);

                let stText = 'ডেলিভারি বাকি';
                let stCls = 'is-blue';
                if (isDone) { stText = 'পুরো নিয়েছে'; stCls = 'is-blue'; }
                else if (isCancelled) { stText = 'ফেরত এসেছে'; stCls = 'is-red'; }
                else if (st === 'partial') { stText = o.due > 0 ? `কম নিয়েছে · বাকি ${money(o.due)}` : 'কম নিয়েছে'; stCls = 'is-red'; }
                else if (st === 'due') { stText = `বাকি ${money(o.due)}`; stCls = 'is-red'; }
                else if (isTrip) { stText = 'ডেলিভারির পথে'; }
                const ocText = `ওভার <b class="is-blue">+${money(over)}</b> · কমিশন <b class="${comm < 0 ? 'is-red' : ''}">−${money(Math.abs(comm))}</b>`;
                const extra = isCancelled && o.cancel_reason
                    ? `<span class="hr-alert">দোকানের কারণ: "${escapeHtml(o.cancel_reason)}"</span>`
                    : '';

                return `
                    <button type="button" class="hr-row ${isCancelled ? 'is-cancelled' : ''}" data-order-idx="${idx}">
                        <span class="hr-av">${escapeHtml(Array.from(String(o.retailer || '•'))[0])}</span>
                        <span class="hr-main">
                            <b>${escapeHtml(o.retailer)}</b>
                            <span class="tabular">মেমো #${escapeHtml(bnDigits(o.code))} · ${ocText}</span>
                            ${extra}
                        </span>
                        <span class="hr-right">
                            <b class="tabular">${money(o.sr_total)}</b>
                            <span class="${stCls}">${escapeHtml(stText)}</span>
                        </span>
                    </button>`;
            }).join('');
        }

        async function changeDate(nextDate) {
            if (!nextDate || nextDate > today) return;
            currentDate = nextDate;
            const seq = ++loadSeq;
            if (listEl && emptyEl) {
                emptyEl.hidden = true;
                listEl.innerHTML = Array.from({ length: 3 }, () => `
                    <div class="history-card" style="cursor:default">
                        <div class="history-card-top">
                            <div class="sk-stack" style="flex:1;gap:6px"><span class="sk sk-line" style="width:45%"></span><span class="sk sk-line" style="width:32%"></span></div>
                            <span class="sk sk-line" style="width:74px"></span>
                        </div>
                    </div>`).join('');
            }
            try {
                const res = await srApi('GET', `/sr/history/day?date=${encodeURIComponent(nextDate)}`);
                if (seq !== loadSeq) return; // a newer date was requested meanwhile
                orders = res.orders;
            } catch (err) {
                if (seq !== loadSeq) return;
                orders = [];
                showToast(err.message);
            }
            render();
        }

        prevBtn?.addEventListener('click', () => changeDate(shiftIsoDate(currentDate, -1)));
        nextBtn?.addEventListener('click', () => changeDate(shiftIsoDate(currentDate, 1)));
        dateInput?.addEventListener('change', () => { if (dateInput.value) changeDate(dateInput.value); });

        // Order Detail Modal Tabs & Actions (Screens 6 & 6b)
        const omTabMyBtn = document.getElementById('omTabMyBtn');
        const omTabShopBtn = document.getElementById('omTabShopBtn');
        const omPanelMy = document.getElementById('omPanelMy');
        const omPanelShop = document.getElementById('omPanelShop');
        const omSecondaryBtn = document.getElementById('omSecondaryBtn');
        const omPrintBtn = document.getElementById('omPrintBtn');
        let activeModalOrder = null;
        let activeModalTab = 'my';

        function setOmTab(tab) {
            activeModalTab = tab;
            const isMy = tab === 'my';
            omTabMyBtn?.classList.toggle('is-active', isMy);
            omTabShopBtn?.classList.toggle('is-active', !isMy);
            omTabMyBtn?.setAttribute('aria-selected', isMy ? 'true' : 'false');
            omTabShopBtn?.setAttribute('aria-selected', !isMy ? 'true' : 'false');
            if (omPanelMy) omPanelMy.hidden = !isMy;
            if (omPanelShop) omPanelShop.hidden = isMy;
            if (omSecondaryBtn) {
                omSecondaryBtn.innerHTML = isMy
                    ? '<span>দোকানের কপি</span>'
                    : '<span>দোকানে পাঠান</span>';
            }
        }

        omTabMyBtn?.addEventListener('click', () => setOmTab('my'));
        omTabShopBtn?.addEventListener('click', () => setOmTab('shop'));
        omSecondaryBtn?.addEventListener('click', async () => {
            if (activeModalTab === 'my') {
                setOmTab('shop');
                return;
            }
            if (!activeModalOrder) return;
            const o = activeModalOrder;
            const lines = [
                `${app.dataset.srPartner || 'মেমো'} (${o.company})`,
                `মেমো নং: ${bnDigits(o.code)} | তারিখ: ${formatHumanDate(o.date)}`,
                `দোকান: ${o.retailer}`,
                '----------------',
                ...o.items.map((it) => `${it.name}: ${bnDigits(it.pcs)} পিস — ${money(it.total)}`),
                '----------------',
                `মোট: ${money(o.sr_total)}`,
            ].join('\n');
            if (navigator.share) {
                try { await navigator.share({ title: `মেমো ${o.code}`, text: lines }); return; } catch { /* fallback to clipboard */ }
            }
            if (navigator.clipboard?.writeText) {
                await navigator.clipboard.writeText(lines);
            }
            showToast('দোকানের কপি কপি করা হয়েছে।');
        });
        omPrintBtn?.addEventListener('click', () => {
            setOmTab('shop');
            setTimeout(() => window.print(), 60);
        });

        listEl?.addEventListener('click', (e) => {
            const row = e.target.closest('[data-order-idx]');
            if (!row) return;
            const order = orders[Number(row.getAttribute('data-order-idx'))];
            if (!order) return;
            activeModalOrder = order;
            setOmTab('my');

            document.getElementById('orderDetailRetailer').textContent = order.retailer;
            const statusEl = document.getElementById('orderDetailStatus');
            statusEl.textContent = bnStatus(order.status_key || order.status);
            statusEl.className = `badge ${badgeClass(order.status_key)}`;
            document.getElementById('orderDetailSub').textContent = `মেমো ${bnDigits(order.code)} · ${formatHumanDate(order.date)} · ${bnDigits(order.time)}`;

            const timelineEl = document.getElementById('omDetailTimeline');
            if (timelineEl) timelineEl.innerHTML = buildTimelineHtml(order);

            const itemsCardsEl = document.getElementById('omDetailItemsCards');
            if (itemsCardsEl) {
                itemsCardsEl.innerHTML = order.items.map((it) => {
                    const ocVal = Math.round((Number(it.oc || 0) + Number.EPSILON) * 100) / 100;
                    const ocTag = Math.abs(ocVal) >= 0.01
                        ? `<span class="li-oc ${ocVal > 0 ? 'is-over' : 'is-comm'}">${ocVal > 0 ? '+' : '−'}${money(Math.abs(ocVal))}</span>`
                        : '';
                    const thumb = it.image
                        ? `<img src="${escapeHtml(it.image)}" alt="">`
                        : escapeHtml(Array.from(String(it.name || '•'))[0]);
                    return `
                        <div class="li-row">
                            <span class="li-av">${thumb}</span>
                            <span class="li-main"><b>${escapeHtml(it.name)}</b><span class="tabular">${bnNum(it.pcs)} পিস × ${money(it.sr_rate_pc)}${ocTag}</span></span>
                            <strong class="tabular">${money(it.total)}</strong>
                        </div>`;
                }).join('') + `<div class="li-total"><span>মোট অর্ডার</span><strong class="tabular">${money(order.sr_total)}</strong></div>`;
            }

            const deliveryStr = order.trip
                ? `${order.dsr || '—'} (${bnDigits(order.trip)}${order.trip_date ? ` · ${formatHumanDate(order.trip_date)}` : ''})`
                : 'অপেক্ষমান (ট্রিপ হয়নি)';
            const payStr = order.delivered_total > 0
                ? `${money(order.paid)} জমা${order.due > 0 ? ` · ${money(order.due)} বাকি` : ' · পূর্ণ আদায়'}`
                : 'ডেলিভারির সময়';

            const summaryEl = document.getElementById('omDetailSummaryCard');
            if (summaryEl) {
                const oItems = Array.isArray(order.items) ? order.items : [];
                const oOver = oItems.reduce((acc, it) => acc + Math.max(0, Number(it.oc || 0)), 0);
                const oComm = oItems.reduce((acc, it) => acc + Math.min(0, Number(it.oc || 0)), 0);
                summaryEl.innerHTML = `
                    <span class="mine-k">আমার হিসাব · শুধু আপনি দেখবেন</span>
                    <div class="mine-strip">
                        <div><span>ওভার</span><b class="is-over">+${money(oOver)}</b></div>
                        <div><span>কমিশন</span><b class="is-comm">−${money(Math.abs(oComm))}</b></div>
                        <div><span>নিট</span><b>${signed(order.oc)}</b></div>
                    </div>
                    <div class="mine-facts">
                        <div><span>ডেলিভারি</span><b>${escapeHtml(deliveryStr)}</b></div>
                        <div><span>টাকা নেওয়া</span><b>${escapeHtml(payStr)}</b></div>
                        <div><span>বেজ (ডিলার) মূল্য</span><b class="tabular">${money(order.base_total)}</b></div>
                    </div>
                    ${order.cancel_reason ? `<div class="hr-alert">বাতিল কারণ: ${escapeHtml(order.cancel_reason)}</div>` : ''}`;
            }

            // Tab 2: Formal Distributor Shop Copy Memo (no internal O/C)
            const srName = app.dataset.srName || order.sr || '';
            const partnerName = app.dataset.srPartner || 'পার্টনার ডিস্ট্রিবিউশন';
            const areaName = app.dataset.srArea || '';
            const shopMemoEl = document.getElementById('omShopMemoSheet');
            if (shopMemoEl) {
                const partnerInitial = Array.from(String(partnerName || 'H'))[0];
                shopMemoEl.innerHTML = `
                    <div class="sm-head">
                        <span class="sm-logo">${escapeHtml(partnerInitial)}</span>
                        <span class="sm-brand"><b>${escapeHtml(partnerName)}</b><span>${escapeHtml(areaName)}${areaName ? ' · ' : ''}${escapeHtml(order.company)}</span></span>
                        <span class="sm-tag">ক্যাশ মেমো<br>#${escapeHtml(bnDigits(order.code))}</span>
                    </div>
                    <div class="sm-shop"><span><b>${escapeHtml(order.retailer)}</b>${order.retailer_address ? `<br>${escapeHtml(order.retailer_address)}` : ''}</span><span class="tabular">${escapeHtml(formatHumanDate(order.date))}</span></div>
                    <div class="sm-items">
                        ${order.items.map((it) => `
                            <div class="sm-item"><span><b>${escapeHtml(it.name)}</b><span class="tabular">${bnNum(it.pcs)} পিস × ${money(it.sr_rate_pc)}</span></span><strong class="tabular">${money(it.total)}</strong></div>`).join('')}
                    </div>
                    <div class="sm-total"><span>মোট</span><strong class="tabular">${money(order.sr_total)}</strong></div>
                    <span class="sm-note">${escapeHtml(payStr)}${order.trip ? ` · ট্রিপ ${escapeHtml(bnDigits(order.trip))}` : ''}</span>
                    <div class="sm-sigs"><span>দোকানদার</span><span>SR · ${escapeHtml(srName)}</span></div>
                    <span class="sm-thanks">ধন্যবাদ · Happy Bangladesh</span>
                    <span class="sm-zigzag" aria-hidden="true"></span>`;
            }

            openModal('orderDetailModal');
        });

        render();
    }

    function initProfilePage() {
        const profApp = document.getElementById('profileApp');
        if (profApp) {
            let currentDate = profApp.dataset.defaultDate;
            const today = profApp.dataset.today;
            let seq = 0;

            const prevBtn = document.getElementById('profPrevBtn');
            const nextBtn = document.getElementById('profNextBtn');
            const dateInput = document.getElementById('profDateInput');
            const dateDisplay = document.getElementById('profDateDisplay');
            const memoCountEl = document.getElementById('profMemoCount');
            const orderTotalEl = document.getElementById('profOrderTotal');
            const overOcEl = document.getElementById('profOverOc');
            const commOcEl = document.getElementById('profCommOc');
            const netOcEl = document.getElementById('profNetOc');
            const prodBody = document.getElementById('profProductsBody');

            const formatHumanDate = (iso) => {
                const parts = iso.split('-').map(Number);
                if (parts.length !== 3) return bnDigits(iso);
                return `${bnDigits(parts[2])} ${MONTHS_BN[parts[1] - 1] || parts[1]} ${bnDigits(parts[0])}`;
            };
            const shiftIso = (iso, d) => {
                const parts = iso.split('-').map(Number);
                return new Date(Date.UTC(parts[0], parts[1] - 1, parts[2] + d)).toISOString().slice(0, 10);
            };
            const money = (n) => {
                const v = Math.round((Number(n || 0) + Number.EPSILON) * 100) / 100;
                return `৳ ${bnDigits(v.toLocaleString('en-US', { minimumFractionDigits: Number.isInteger(v) ? 0 : 2, maximumFractionDigits: 2 }))}`;
            };

            async function loadProfDate(nextDate) {
                if (!nextDate || nextDate > today) return;
                currentDate = nextDate;
                if (dateDisplay) dateDisplay.textContent = formatHumanDate(nextDate) + (nextDate === today ? ' (আজ)' : '');
                if (dateInput) dateInput.value = nextDate;
                if (nextBtn) nextBtn.disabled = nextDate >= today;

                const mySeq = ++seq;
                try {
                    const res = await srApi('GET', `/sr/profile/day?date=${encodeURIComponent(nextDate)}`);
                    if (mySeq !== seq) return;
                    const st = res.stats || {};
                    if (memoCountEl) memoCountEl.textContent = `${bnNum(st.orders || 0)}টি`;
                    if (orderTotalEl) orderTotalEl.textContent = money(st.value || 0);
                    if (overOcEl) overOcEl.textContent = `+${money(st.over_oc || 0)}`;
                    if (commOcEl) commOcEl.textContent = `−${money(Math.abs(Number(st.comm_oc || 0)))}`;
                    if (netOcEl) {
                        const net = Number(st.oc || 0);
                        netOcEl.textContent = `${net >= 0 ? '+' : '−'}${money(Math.abs(net))}`;
                        netOcEl.className = `tabular ${net < 0 ? 'is-danger' : 'is-ok'}`;
                    }
                    if (prodBody) {
                        const prods = res.products || [];
                        prodBody.innerHTML = prods.length === 0
                            ? '<tr><td colspan="5" class="text-center muted small" style="padding:18px 10px;">এই তারিখে কোনো পণ্যের হিসাব নেই।</td></tr>'
                            : prods.map((p) => `
                                <tr>
                                    <td>
                                        <div class="prof-prod-cell">
                                            <span class="prof-prod-thumb" style="background:${escapeHtml(p.tint || '#f8fafc')}">
                                                ${p.image ? `<img src="${escapeHtml(p.image)}" alt="${escapeHtml(p.name)}">` : `<span>${escapeHtml(p.code || 'PR')}</span>`}
                                            </span>
                                            <span class="prof-prod-name">${escapeHtml(p.name)}</span>
                                        </div>
                                    </td>
                                    <td class="text-center tabular">${bnNum(p.ordered_pcs)}</td>
                                    <td class="text-center tabular">${p.dispatched_pcs > 0 ? bnNum(p.dispatched_pcs) : '—'}</td>
                                    <td class="text-center tabular is-ok">${p.delivered_pcs > 0 ? bnNum(p.delivered_pcs) : '—'}</td>
                                    <td class="text-center tabular ${p.returned_pcs > 0 ? 'is-danger' : ''}">${p.returned_pcs > 0 ? bnNum(p.returned_pcs) : '—'}</td>
                                </tr>`).join('');
                    }
                } catch (err) {
                    if (mySeq === seq) showToast(err.message);
                }
            }

            prevBtn?.addEventListener('click', () => loadProfDate(shiftIso(currentDate, -1)));
            nextBtn?.addEventListener('click', () => loadProfDate(shiftIso(currentDate, 1)));
            dateInput?.addEventListener('change', () => { if (dateInput.value) loadProfDate(dateInput.value); });
        }

        const photoInput = document.getElementById('srPhotoInput');
        photoInput?.addEventListener('change', async () => {
            const file = photoInput.files[0];
            if (!file) return;
            const fd = new FormData();
            fd.append('photo', file);
            try {
                await srApi('POST', '/sr/profile/photo', fd);
                window.location.reload();
            } catch (err) {
                showToast(err.message);
            }
        });

        const form = document.getElementById('srPasswordForm');
        if (!form) return;
        const errorEl = document.getElementById('srPasswordError');
        form.addEventListener('submit', async (e) => {
            e.preventDefault();
            errorEl.hidden = true;
            const f = form.elements;
            if (f.password.value !== f.password_confirmation.value) {
                errorEl.textContent = 'নতুন পাসওয়ার্ড দুটি মিলছে না।';
                errorEl.hidden = false;
                return;
            }
            try {
                const res = await withButtonLoading(form.querySelector('button[type="submit"]'), 'আপডেট হচ্ছে…', () => srApi('POST', '/sr/profile/password', {
                    current_password: f.current_password.value,
                    password: f.password.value,
                    password_confirmation: f.password_confirmation.value,
                }));
                form.reset();
                showToast(res.message);
            } catch (err) {
                errorEl.textContent = err.message;
                errorEl.hidden = false;
            }
        });
    }

    function initPage() {
        pageSyncedHook = null;
        initOrderPage();
        initProfilePage();
        initHistoryPage();
    }

    // =========================================================================
    // SPA ROUTER + PAGE-AWARE SKELETONS
    // =========================================================================
    const srAppMain = document.getElementById('srAppMain');
    const srContent = document.getElementById('srContent');
    const srPageTitle = document.getElementById('srPageTitle');
    const srTopbarActions = document.getElementById('srTopbarActions');
    const spaProgress = document.getElementById('spaProgress');
    let activeController = null;

    function skeletonForPath(pathname) {
        if (/\/sr\/order(\/|$)/.test(pathname)) {
            return `<div class="order-map-stage" style="display:grid;place-items:center"><div class="app-loader-box"><div class="app-loader-bar"><span></span></div><span class="muted small">দোকান ম্যাপ লোড হচ্ছে…</span></div></div>`;
        }
        if (/\/sr\/history(\/|$)/.test(pathname)) {
            return `<div class="sr-history-page"><div class="card sk-stack"><span class="sk sk-line" style="width:42%"></span></div>${Array.from({ length: 3 }, () => `<div class="history-card"><div class="sk-stack"><span class="sk sk-line" style="width:48%"></span><span class="sk sk-line" style="width:65%"></span></div></div>`).join('')}</div>`;
        }
        if (/\/sr\/profile(\/|$)/.test(pathname)) {
            return `<div class="profile-layout"><div class="card sk-stack"><span class="sk sk-line" style="width:45%"></span><span class="sk sk-line" style="width:30%"></span></div><div class="card sk-stack"><span class="sk sk-line" style="width:55%"></span><span class="sk sk-kpi"></span></div></div>`;
        }
        return `<div class="sr-dash-body" style="margin-top:16px"><div class="card sk-stack"><span class="sk sk-line" style="width:42%"></span><span class="sk sk-kpi"></span><span class="sk sk-line" style="width:100%"></span></div></div>`;
    }

    function isSpaLink(anchor) {
        if (!srContent || !anchor) return false;
        if (anchor.hasAttribute('data-no-spa') || anchor.hasAttribute('download')) return false;
        if (anchor.target && anchor.target !== '_self') return false;
        const rawHref = anchor.getAttribute('href');
        if (!rawHref || rawHref.startsWith('#') || rawHref.startsWith('javascript:')) return false;

        let target;
        try {
            target = new URL(anchor.href, window.location.origin);
        } catch {
            return false;
        }
        return target.origin === window.location.origin && /\/sr(\/|$)/.test(target.pathname);
    }

    function setProgress(state) {
        if (!spaProgress) return;
        spaProgress.classList.remove('is-loading', 'is-done');
        if (state === 'start') {
            void spaProgress.offsetWidth;
            spaProgress.classList.add('is-loading');
        } else if (state === 'done') {
            spaProgress.classList.add('is-done');
        }
    }

    function syncNavByPath(pathname) {
        const isDash = /\/sr\/?$/.test(pathname) || /\/sr\/dashboard\/?$/.test(pathname);
        document.querySelectorAll('.sidebar-nav .nav-item, .bottom-nav .bottom-nav-item').forEach((item) => {
            const hrefPath = new URL(item.href, window.location.origin).pathname;
            const itemIsDash = /\/sr\/dashboard\/?$/.test(hrefPath);
            item.classList.toggle('is-active', hrefPath === pathname || (isDash && itemIsDash));
        });
    }

    async function navigateSpa(urlString, { push = true } = {}) {
        const target = new URL(urlString, window.location.origin);
        if (target.pathname === window.location.pathname && target.search === window.location.search) {
            return;
        }

        if (activeController) activeController.abort();
        activeController = new AbortController();

        destroyOrderMap();
        closeAllModals();
        setProgress('start');
        syncNavByPath(target.pathname);

        const targetIsMap = /\/sr\/order(\/|$)/.test(target.pathname);
        srAppMain?.classList.toggle('is-map-mode', targetIsMap);
        srAppMain?.classList.add('has-custom-header');
        if (srTopbarActions) srTopbarActions.innerHTML = '';
        srContent.innerHTML = skeletonForPath(target.pathname);
        window.scrollTo({ top: 0, behavior: 'instant' });

        const start = performance.now();
        try {
            const res = await fetch(target.href, {
                headers: { 'X-Sr-SPA': '1' },
                credentials: 'same-origin',
                signal: activeController.signal,
            });
            if (!res.ok) {
                window.location.href = target.href;
                return;
            }

            const html = await res.text();
            const doc = new DOMParser().parseFromString(html, 'text/html');
            const nextContent = doc.getElementById('srContent');
            if (!nextContent) {
                window.location.href = res.url || target.href;
                return;
            }

            const elapsed = performance.now() - start;
            if (elapsed < 160) await sleep(160 - elapsed);
            if (activeController.signal.aborted) return;

            document.title = doc.title || document.title;
            const nextMain = doc.getElementById('srAppMain');
            if (srAppMain && nextMain) {
                srAppMain.classList.toggle('is-map-mode', nextMain.classList.contains('is-map-mode'));
                srAppMain.classList.toggle('has-custom-header', nextMain.classList.contains('has-custom-header'));
            }

            const nextTitle = doc.getElementById('srPageTitle');
            if (srPageTitle && nextTitle) srPageTitle.textContent = nextTitle.textContent;

            const nextActions = doc.getElementById('srTopbarActions');
            if (srTopbarActions && nextActions) srTopbarActions.innerHTML = nextActions.innerHTML;

            srContent.innerHTML = nextContent.innerHTML;
            srContent.classList.remove('spa-enter');
            void srContent.offsetWidth;
            srContent.classList.add('spa-enter');

            if (push) {
                const finalUrl = res.url ? new URL(res.url) : target;
                finalUrl.hash = target.hash;
                history.pushState({ spa: true }, '', finalUrl.href);
            }

            initPage();
            setProgress('done');
        } catch (err) {
            if (err.name === 'AbortError') return;
            window.location.href = target.href;
        }
    }

    if (srContent) {
        history.replaceState({ spa: true }, '', window.location.href);
        document.addEventListener('click', (e) => {
            if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
            const anchor = e.target.closest('a[href]');
            if (!isSpaLink(anchor)) return;
            e.preventDefault();
            navigateSpa(anchor.href, { push: true });
        });
        window.addEventListener('popstate', () => {
            if (ignorePopstateCount > 0) {
                ignorePopstateCount -= 1;
                return;
            }
            if (modalStack.length > 0) {
                closeTopmostModal({ fromPopstate: true });
                return;
            }
            navigateSpa(window.location.href, { push: false });
        });
    }

    initPage();
})();
