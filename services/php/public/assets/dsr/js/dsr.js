(() => {
    'use strict';

    const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

    // Last known GPS position survives SPA switches; all trip data comes from the server
    const dsrStore = {
        dsrLocation: null,
        gpsFix: false,
        retailers: [],
        retailersSynced: false,
    };

    let activeDeliveryMap = null;
    let activeRsRetMap = null;
    let activeRsNewPinMap = null;
    let activeMapResizeObserver = null;
    let geoWatchId = null;

    function attachDsrTiles(map) {
        let usedFallback = false;
        const googleTiles = window.L.tileLayer('https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}', {
            maxNativeZoom: 20, maxZoom: 22, subdomains: '0123', attribution: '&copy; Google Maps',
        }).addTo(map);
        googleTiles.on('tileerror', () => {
            if (usedFallback) return;
            usedFallback = true;
            try { map.removeLayer(googleTiles); } catch { /* ignore */ }
            window.L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}', {
                maxNativeZoom: 19, maxZoom: 22, attribution: '&copy; Esri',
            }).addTo(map);
        });
    }

    function destroyDeliveryMap() {
        if (geoWatchId !== null && navigator.geolocation) {
            navigator.geolocation.clearWatch(geoWatchId);
            geoWatchId = null;
        }
        if (activeMapResizeObserver) {
            try { activeMapResizeObserver.disconnect(); } catch { /* ignore */ }
            activeMapResizeObserver = null;
        }
        [activeDeliveryMap, activeRsRetMap, activeRsNewPinMap].forEach((m) => {
            if (m) {
                try { m.remove(); } catch { /* ignore */ }
            }
        });
        activeDeliveryMap = null;
        activeRsRetMap = null;
        activeRsNewPinMap = null;
    }

    // Boot Loader
    const bootLoader = document.getElementById('appBootLoader');
    if (bootLoader) {
        let dismissed = false;
        const dismiss = () => {
            if (dismissed) return;
            dismissed = true;
            bootLoader.classList.add('is-hidden');
            setTimeout(() => bootLoader.remove(), 220);
        };
        if (document.readyState === 'complete') {
            requestAnimationFrame(dismiss);
        } else {
            window.addEventListener('load', () => setTimeout(dismiss, 90), { once: true });
            setTimeout(dismiss, 1400);
        }
    }

    const toastStack = document.getElementById('toastStack');
    function showToast(message) {
        if (!toastStack) return;
        const el = document.createElement('div');
        el.className = 'toast';
        el.textContent = message;
        toastStack.appendChild(el);
        setTimeout(() => el.remove(), 30);
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
    const BN_STATUS_MAP = {
        Pending: 'বাকি',
        Delivered: 'ডেলিভার্ড',
        Due: 'বকেয়া',
        Cancelled: 'বাতিল',
    };
    const BN_REASON_MAP = {
        'Shop Closed': 'দোকান বন্ধ',
        'Owner Not Present': 'মালিক উপস্থিত নেই',
        'Price / Rate Dispute': 'দাম নিয়ে মতবিরোধ',
        'Cash Shortage': 'ক্যাশ সংকট',
        'Stock Damage Dispute': 'ক্ষতিগ্রস্ত পণ্য সমস্যা',
        'No Longer Needed': 'আর প্রয়োজন নেই',
        Other: 'অন্যান্য',
    };

    function bnDigits(value) {
        return String(value ?? '').replace(/[0-9]/g, (d) => BN_DIGITS[Number(d)]);
    }

    function bnNum(amount, maxFrac = 2) {
        const val = round2(amount || 0);
        return bnDigits(val.toLocaleString('en-US', { maximumFractionDigits: maxFrac }));
    }

    function bnStatus(status) {
        return BN_STATUS_MAP[status] || status || '';
    }

    function bnReason(raw) {
        const s = String(raw || '').trim();
        if (!s) return '';
        if (BN_REASON_MAP[s]) return BN_REASON_MAP[s];
        const m = s.match(/^(.+?)\s*\((.+)\)$/);
        if (m && BN_REASON_MAP[m[1].trim()]) {
            return `${BN_REASON_MAP[m[1].trim()]} (${m[2]})`;
        }
        return s;
    }

    function round2(n) {
        return Math.round((Number(n) + Number.EPSILON) * 100) / 100;
    }

    function formatBdt(amount) {
        const val = round2(amount || 0);
        return `৳ ${bnNum(val, 2)}`;
    }

    function formatSignedBdt(amount) {
        const val = round2(amount || 0);
        const sign = val > 0 ? '+' : (val < 0 ? '−' : '');
        return `${sign}৳ ${bnNum(Math.abs(val), 2)}`;
    }

    function formatSignedNum(amount) {
        const val = round2(amount || 0);
        const sign = val > 0 ? '+' : (val < 0 ? '−' : '');
        return `${sign}${bnNum(Math.abs(val), 2)}`;
    }

    function formatConvertedQty(qty, qtyPerUnit) {
        const q = Math.max(0, Math.floor(Number(qty) || 0));
        const qpu = Math.max(1, Math.floor(Number(qtyPerUnit) || 1));
        const units = Math.floor(q / qpu);
        const pcs = q % qpu;
        return `${bnDigits(units)} ইউনিট ${bnDigits(pcs)} পিস`;
    }

    function haversineMeters(lat1, lon1, lat2, lon2) {
        const R = 6371000;
        const toRad = (deg) => (deg * Math.PI) / 180;
        const dLat = toRad(lat2 - lat1);
        const dLon = toRad(lon2 - lon1);
        const a = Math.sin(dLat / 2) ** 2
            + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
        return Math.round(R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)));
    }

    function formatDistance(meters) {
        if (meters >= 1000) return `${bnDigits((meters / 1000).toFixed(2))} কি.মি.`;
        return `${bnDigits(meters)} মি.`;
    }

    // Shared Banglish + Bangla Phonetic Search (matches English/Banglish queries to Bangla names)
    const DsrBanglish = (() => {
        const BN_VOWELS_INDEP = {
            'অ': ['o', 'a'], 'আ': ['a', 'a'], 'ই': ['i', 'i'], 'ঈ': ['i', 'i'],
            'উ': ['u', 'u'], 'ঊ': ['u', 'u'], 'ঋ': ['ri', 'ri'],
            'এ': ['e', 'e'], 'ঐ': ['oi', 'oi'], 'ও': ['o', 'o'], 'ঔ': ['ou', 'ou'],
        };
        const BN_KAR = { 'া': 'a', 'ি': 'i', 'ী': 'i', 'ু': 'u', 'ূ': 'u', 'ৃ': 'ri', 'ে': 'e', 'ৈ': 'oi', 'ো': 'o', 'ৌ': 'ou' };
        const BN_CONS = {
            'ক': 'k', 'খ': 'kh', 'গ': 'g', 'ঘ': 'gh', 'ঙ': 'ng',
            'চ': 'ch', 'ছ': 'ch', 'জ': 'j', 'ঝ': 'jh', 'ঞ': 'n',
            'ট': 't', 'ঠ': 'th', 'ড': 'd', 'ঢ': 'dh', 'ণ': 'n',
            'ত': 't', 'থ': 'th', 'দ': 'd', 'ধ': 'dh', 'ন': 'n',
            'প': 'p', 'ফ': 'f', 'ব': 'b', 'ভ': 'v', 'ম': 'm',
            'য': 'j', 'র': 'r', 'ল': 'l',
            'শ': 'sh', 'ষ': 'sh', 'স': 's', 'হ': 'h',
            'ড়': 'r', 'ঢ়': 'r', 'য়': 'y', 'ৎ': 't', 'ং': 'ng', 'ঃ': 'h', 'ঁ': '',
        };
        const BN_DIG = { '০': '0', '১': '1', '২': '2', '৩': '3', '৪': '4', '৫': '5', '৬': '6', '৭': '7', '৮': '8', '৯': '9' };
        const toEn = (s) => String(s || '').replace(/[০-৯]/g, (d) => BN_DIG[d]);
        const foldStrict = (s) => toEn(s).toLowerCase()
            .replace(/ph/g, 'f').replace(/bh/g, 'v').replace(/q/g, 'k').replace(/z/g, 'j')
            .replace(/ee+/g, 'i').replace(/oo+/g, 'u').replace(/aa+/g, 'a')
            .replace(/c(?=[eiy])/g, 's').replace(/c(?!h)/g, 'k').replace(/chh/g, 'ch')
            .replace(/oy/g, 'oi').replace(/ow/g, 'ou')
            .replace(/([bcdfghjklmnpqrstvwxyz])e$/g, '$1').replace(/([a-z])\1+/g, '$1');
        const foldLoose = (s) => s
            .replace(/sh/g, 's').replace(/kh/g, 'k').replace(/gh/g, 'g')
            .replace(/th/g, 't').replace(/dh/g, 'd').replace(/jh/g, 'j').replace(/ch/g, 'c')
            .replace(/[vw]/g, 'b').replace(/([a-z])\1+/g, '$1');
        const foldGlide = (s) => s
            .replace(/([aeiou])y([aeiou])/g, '$1$2').replace(/y/g, 'i')
            .replace(/ae/g, 'ai').replace(/([ai])h([ai])/g, '$1$2').replace(/([a-z])\1+/g, '$1');
        const foldAnchor = (s) => s.replace(/([aeiou])[ie]+/g, '$1').replace(/ou/g, 'o').replace(/oi/g, 'o');

        const WORD_CACHE = new Map();
        const ITEM_CACHE = new WeakMap();

        function buildWord(word) {
            const hit = WORD_CACHE.get(word);
            if (hit) return hit;
            const units = [];
            let i = 0;
            const len = word.length;
            while (i < len) {
                const ch = word[i];
                const code = ch.charCodeAt(0);
                if (code < 0x0980 || code > 0x09FF) {
                    const norm = toEn(ch).toLowerCase();
                    if (/[a-z0-9]/.test(norm)) units.push({ s: i, e: i + 1, a: norm, o: norm, ns: norm });
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
                    if (BN_CONS[ch]) units.push({ s: i, e: i + 1, a: BN_CONS[ch], o: BN_CONS[ch], ns: BN_CONS[ch] });
                    i++;
                    continue;
                }
                if (BN_CONS[ch] !== undefined) {
                    const start = i;
                    let cParts = '';
                    let hasHasantaEnd = false;
                    while (i < len && BN_CONS[word[i]] !== undefined) {
                        const c = word[i];
                        if (c === 'ক' && word[i + 1] === '্' && word[i + 2] === 'ষ') { cParts += 'kh'; i += 3; }
                        else if (c === 'জ' && word[i + 1] === '্' && word[i + 2] === 'ঞ') { cParts += 'g'; i += 3; }
                        else if (i > start && word[i - 1] === '্' && (c === 'য' || c === 'ব' || c === 'ম')) { i++; }
                        else { cParts += BN_CONS[c]; i++; }
                        if (i < len && word[i] === '্') {
                            i++;
                            if (i >= len || BN_CONS[word[i]] === undefined) { hasHasantaEnd = true; break; }
                        } else break;
                    }
                    let kar = '';
                    while (i < len && (BN_KAR[word[i]] !== undefined || word[i] === 'ঁ')) {
                        if (BN_KAR[word[i]] !== undefined) kar += BN_KAR[word[i]];
                        i++;
                    }
                    if (kar !== '' || hasHasantaEnd) units.push({ s: start, e: i, a: cParts + kar, o: cParts + kar, ns: cParts + kar });
                    else if (i >= len) units.push({ s: start, e: i, a: cParts, o: cParts, ns: cParts });
                    else {
                        const drop = units.length > 0;
                        units.push({ s: start, e: i, a: `${cParts}a`, o: `${cParts}o`, ns: drop ? cParts : `${cParts}a` });
                    }
                    continue;
                }
                i++;
            }
            const variants = [];
            const seen = new Set();
            ['a', 'o', 'ns'].forEach((mode) => {
                let str = '';
                for (let u = 0; u < units.length; u++) str += units[u][mode];
                const st = foldStrict(str);
                if (!seen.has(st)) {
                    seen.add(st);
                    const lo = foldLoose(st);
                    const gl = foldGlide(lo);
                    const an = foldAnchor(gl);
                    variants.push({ st, lo, gl, an });
                }
            });
            const res = { units, variants, rawLower: toEn(word).toLowerCase() };
            if (WORD_CACHE.size < 16000) WORD_CACHE.set(word, res);
            return res;
        }

        function getIndexed(item, keyText) {
            const cached = ITEM_CACHE.get(item);
            if (cached && cached.keyText === keyText) return cached.idx;
            const raw = String(keyText || '');
            const words = [];
            const re = /[^\s,.\-_/()]+/g;
            let m;
            while ((m = re.exec(raw)) !== null) words.push(buildWord(m[0]));
            const idx = { lower: toEn(raw).toLowerCase(), words };
            ITEM_CACHE.set(item, { keyText, idx });
            return idx;
        }

        function compileQuery(q) {
            const raw = String(q || '').trim();
            if (!raw) return null;
            const tokens = raw.split(/\s+/).filter(Boolean).map((qt) => {
                const lower = toEn(qt).toLowerCase();
                const st = foldStrict(qt);
                const lo = foldLoose(st);
                const gl = foldGlide(lo);
                const an = foldAnchor(gl);
                return { lower, st, lo, gl, an };
            });
            return tokens.length ? tokens : null;
        }

        function score(idx, qTokens) {
            if (!qTokens) return 0;
            let total = 0;
            for (let t = 0; t < qTokens.length; t++) {
                const q = qTokens[t];
                let best = 0;
                const rIdx = idx.lower.indexOf(q.lower);
                if (rIdx !== -1) best = rIdx === 0 ? 104 : (idx.lower[rIdx - 1] === ' ' ? 94 : 60);
                for (let wi = 0; wi < idx.words.length; wi++) {
                    const w = idx.words[wi];
                    const bonus = wi === 0 ? 10 : 0;
                    if (q.lower.length >= 2 && w.rawLower === q.lower) best = Math.max(best, 118 + bonus);
                    else if (w.rawLower.startsWith(q.lower)) best = Math.max(best, 94 + bonus);
                    for (let vi = 0; vi < w.variants.length; vi++) {
                        const v = w.variants[vi];
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

        function highlight(text, query) {
            const raw = String(text ?? '');
            const qRaw = String(query || '').trim();
            if (!qRaw) return escapeHtml(raw);
            const direct = raw.toLowerCase().indexOf(qRaw.toLowerCase());
            if (direct !== -1) {
                return `${escapeHtml(raw.slice(0, direct))}<mark class="rs-hit">${escapeHtml(raw.slice(direct, direct + qRaw.length))}</mark>${escapeHtml(raw.slice(direct + qRaw.length))}`;
            }
            const first = qRaw.split(/\s+/)[0];
            if (!first) return escapeHtml(raw);
            const qSt = foldStrict(first);
            const qLo = foldLoose(qSt);
            const qGl = foldGlide(qLo);
            const qAn = foldAnchor(qGl);
            const re = /[^\s,.\-_/()]+/g;
            let m;
            while ((m = re.exec(raw)) !== null) {
                const bp = buildWord(m[0]);
                for (const tier of ['st', 'lo', 'gl', 'an']) {
                    const target = tier === 'st' ? qSt : tier === 'lo' ? qLo : tier === 'gl' ? qGl : qAn;
                    if (!target || (tier === 'an' && target.length < 3)) continue;
                    for (const mode of ['a', 'o', 'ns']) {
                        for (let su = 0; su < bp.units.length; su++) {
                            if (su > 0 && target.length < 3) break;
                            let pref = '';
                            for (let ui = su; ui < bp.units.length; ui++) {
                                pref += bp.units[ui][mode];
                                let f = foldStrict(pref);
                                if (tier !== 'st') f = foldLoose(f);
                                if (tier === 'gl' || tier === 'an') f = foldGlide(f);
                                if (tier === 'an') f = foldAnchor(f);
                                if (f.startsWith(target)) {
                                    const s = m.index + bp.units[su].s;
                                    const e = m.index + bp.units[ui].e;
                                    return `${escapeHtml(raw.slice(0, s))}<mark class="rs-hit">${escapeHtml(raw.slice(s, e))}</mark>${escapeHtml(raw.slice(e))}`;
                                }
                            }
                        }
                    }
                }
            }
            return escapeHtml(raw);
        }

        function warmup(items, keyFn) {
            let pos = 0;
            function step() {
                const end = Math.min(items.length, pos + 350);
                for (; pos < end; pos++) getIndexed(items[pos], keyFn(items[pos]));
                if (pos < items.length) setTimeout(step, 0);
            }
            if (items.length) setTimeout(step, 16);
        }

        return { getIndexed, compileQuery, score, highlight, warmup };
    })();

    // Modal Stack synced with Browser/Mobile Back Button
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

    function closeTopmostModal({ fromPopstate = false } = {}) {
        if (modalStack.length > 0) {
            closeModal(modalStack[modalStack.length - 1], { fromPopstate });
            return true;
        }
        const openModals = Array.from(document.querySelectorAll('.modal-overlay.is-open'));
        if (!openModals.length) return false;
        const top = openModals[openModals.length - 1];
        top.classList.remove('is-open');
        top.setAttribute('aria-hidden', 'true');
        return true;
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

    document.addEventListener('click', (e) => {
        const closeSpecific = e.target.closest('[data-close-modal]');
        if (closeSpecific) {
            closeModal(closeSpecific.getAttribute('data-close-modal'));
            return;
        }
        if (e.target.classList?.contains('modal-overlay') && e.target.id) {
            closeModal(e.target.id);
        }
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') closeTopmostModal();
    });


    // =========================================================================
    // API helpers
    // =========================================================================
    function csrfToken() {
        return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
    }

    function appUrl(path) {
        const home = document.querySelector('.mobile-brand')?.getAttribute('href') || '/dsr/dashboard';
        return home.replace(/\/dsr\/dashboard$/, '') + path;
    }

    // ---------------------------------------------------------------- offline
    // Writes that support offline (`offline` arg of dsrApi) are queued in IndexedDB when there is no
    // network, applied to the screen right away, and sent in order once the network is back. Each op
    // carries an X-Op-Id; the server answers a repeated op from its stored result, so nothing is applied twice.
    class NetErr extends Error {}
    const HB_USER = document.body.dataset.hbUser || '0';
    const offlineOk = () => !!window.HbOffline?.available() && HB_USER !== '0';
    /** Body value for a retailer id: shops created offline keep their temporary string id until synced. */
    const rid = (id) => (String(id).startsWith('tmp-') ? String(id) : Number(id));
    const isTmp = (id) => String(id).startsWith('tmp-');
    let pageSyncedHook = null; // set by the current page; called after queued ops reached the server

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
                    'Content-Type': 'application/json',
                    'X-Requested-With': 'XMLHttpRequest',
                    'X-CSRF-TOKEN': csrfToken(),
                    ...(opId ? { 'X-Op-Id': opId } : {}),
                },
                body: body === undefined ? undefined : JSON.stringify(body),
                signal: ctrl?.signal,
            });
        } catch {
            throw new NetErr('নেটওয়ার্ক ত্রুটি। সংযোগ পরীক্ষা করে আবার চেষ্টা করুন।');
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
    async function dsrApi(method, path, body, offline) {
        const canQueue = !!offline && offlineOk();
        const opId = canQueue ? window.HbOffline.uuid() : null;
        // Keep order: while older ops wait in the queue, new ones go behind them.
        if (canQueue && (!navigator.onLine || (await window.HbOffline.count(HB_USER)) > 0)) {
            return queueOp(opId, method, path, body, offline);
        }
        let r;
        try {
            r = await rawSend(method, path, body, opId, canQueue ? 15000 : 0);
        } catch (err) {
            if (canQueue && err instanceof NetErr) return queueOp(opId, method, path, body, offline);
            throw err;
        }
        const { res, data } = r;
        if (res.status === 401) {
            window.location.href = data.redirect || appUrl('/dsr/login');
            throw new Error('সেশন শেষ হয়েছে।');
        }
        if (res.status === 419) throw new Error('আপনার সেশন মেয়াদোত্তীর্ণ হয়েছে। অনুগ্রহ করে পেজ রিলোড করুন।');
        if (!res.ok || data.ok === false) throw new Error(data.message || `অনুরোধ ব্যর্থ হয়েছে (HTTP ${bnDigits(res.status)})।`);
        return data;
    }

    async function queueOp(id, method, path, body, offline) {
        const result = offline.apply() || {}; // may throw (e.g. not enough stock) → nothing is queued
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
            const { res, data } = await rawSend('GET', '/dsr/csrf', undefined, null, 15000);
            if (!res.ok || !data.token) return false;
            document.querySelector('meta[name="csrf-token"]')?.setAttribute('content', data.token);
            return true;
        } catch { return false; }
    }

    /** A shop created offline got its real id: rewrite the ops still waiting that refer to it. */
    async function remapTmp(tmp, real, rest) {
        for (const op of rest) {
            const before = JSON.stringify({ path: op.path, body: op.body });
            if (!before.includes(tmp)) continue;
            const after = JSON.parse(before.split(tmp).join(real));
            await window.HbOffline.put({ ...op, path: after.path, body: after.body });
        }
        (dsrStore.retailers || []).forEach((r) => { if (String(r.id) === tmp) r.id = real; });
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
                    if (op.tmp && data.newRetailer?.id) await remapTmp(op.tmp, String(data.newRetailer.id), ops.slice(1));
                } else {
                    // The server refused it (e.g. trip already submitted, stock changed): keep a record for the user.
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
            // Reload the server's numbers only when nothing is left in the queue — otherwise the
            // screen would lose the local changes of ops still waiting.
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
        if (!(f instanceof HTMLFormElement) || !/\/dsr\/logout$/.test(f.getAttribute('action') || '') || f.dataset.confirmed) return;
        if (!offlineOk()) return;
        e.preventDefault();
        const n = await window.HbOffline.count(HB_USER);
        if (n > 0 && !window.confirm(`${bnDigits(n)}টি অফলাইন কাজ এখনো সিঙ্ক হয়নি। সাইন আউট করলেও সেগুলো এই ফোনে থাকবে এবং আবার লগইন করলে সিঙ্ক হবে। সাইন আউট করবেন?`)) return;
        await Promise.all([window.HbOffline.kvDel(`deliv:${HB_USER}`), window.HbOffline.kvDel(`exp:${HB_USER}`), window.caches?.delete('hb-pages-v1')]);
        f.dataset.confirmed = '1';
        f.submit();
    }, true);

    // Keep every DSR page in the offline cache (once per session, in the background). Only counts as done
    // when the Service Worker controlled the requests and every page came back, so a first visit or a
    // reload in the middle does not leave pages uncached.
    if (offlineOk() && navigator.serviceWorker && navigator.onLine) {
        const warm = async () => {
            try { if (sessionStorage.getItem('hb-dsr-warm')) return; } catch { /* private mode */ }
            if (!navigator.serviceWorker.controller || !navigator.onLine) return;
            let ok = true;
            for (const p of ['/dsr/delivery', '/dsr/expense', '/dsr/van-stock', '/dsr/settlement', '/dsr/dashboard']) {
                try { ok = (await fetch(appUrl(p), { credentials: 'same-origin' })).ok && ok; } catch { ok = false; }
            }
            if (ok) try { sessionStorage.setItem('hb-dsr-warm', '1'); } catch { /* private mode */ }
        };
        navigator.serviceWorker.ready.then(() => setTimeout(warm, 2500)).catch(() => {});
        navigator.serviceWorker.addEventListener('controllerchange', () => setTimeout(warm, 1000));
    }

    async function withBusy(btn, label, task) {
        if (!btn) return task();
        const orig = btn.innerHTML;
        btn.disabled = true;
        btn.textContent = label;
        try {
            return await task();
        } finally {
            btn.disabled = false;
            btn.innerHTML = orig;
        }
    }

    function reloadCurrent() {
        return navigateTo(window.location.href, false);
    }

    // =========================================================================
    // Helper math for a retailer stop draft
    // =========================================================================
    function computeOrderOriginalTotal(stop) {
        let sum = 0;
        (stop.companies || []).forEach((c) => {
            if (c.ready_sale) return;
            (c.items || []).forEach((it) => { sum += Number(it.ordered_qty || 0) * Number(it.sr_rate || 0); });
        });
        return round2(sum);
    }

    function computeOrderMetrics(stop) {
        let gross = 0;
        let deliveryOc = 0;
        (stop.companies || []).forEach((c) => {
            if (c.ready_sale || c.cancelled) return;
            (c.items || []).forEach((it) => {
                const q = Math.max(0, Number(it.qty || 0));
                gross += q * Number(it.sr_rate || 0);
                deliveryOc += q * (Number(it.sr_rate || 0) - Number(it.base_rate || 0));
            });
        });
        const damage = (stop.damages || []).reduce((s, d) => s + Number(d.amount || 0), 0);
        const shouldPay = round2(Math.max(0, gross - damage));
        return {
            orderTotal: computeOrderOriginalTotal(stop),
            shouldPay,
            damage: round2(damage),
            deliveryOc: round2(deliveryOc),
            paid: round2(Number(stop.paid_amount || 0) + Number(stop.old_due_collected || 0)),
            due: round2(stop.due_amount || 0),
        };
    }

    function statusBadgeClass(status) {
        switch (status) {
            case 'Delivered': return 'badge-success';
            case 'Due': return 'badge-warning';
            case 'Cancelled': return 'badge-danger';
            default: return 'badge-info';
        }
    }

    function statusPinClass(status) {
        switch (status) {
            case 'Delivered': return 'is-delivered';
            case 'Due': return 'is-due';
            case 'Cancelled': return 'is-cancelled';
            default: return 'is-pending';
        }
    }

    // =========================================================================
    // Delivery Page (map, stop sheet, damage, payment, cancel, ready sale)
    // =========================================================================
    function initDeliveryPage() {
        const app = document.getElementById('dsrDeliveryApp');
        if (!app) return;

        destroyDeliveryMap();

        if (!dsrStore.dsrLocation) {
            dsrStore.dsrLocation = JSON.parse(app.dataset.dsrLocation || '{"lat":23.8103,"lng":90.4125}');
        }
        let trip = JSON.parse(app.dataset.trip || 'null');
        let editable = !!trip?.editable;
        let selectedDate = app.dataset.selectedDate || trip?.date || new Date().toISOString().slice(0, 10);
        let stops = JSON.parse(app.dataset.orders || '[]');
        let vanStock = JSON.parse(app.dataset.vanStock || '[]');
        const initialRetailers = JSON.parse(app.dataset.retailers || '[]');
        if (!dsrStore.retailersSynced || dsrStore.retailers.length === 0) {
            dsrStore.retailers = initialRetailers;
        }
        let retailers = dsrStore.retailers;
        let damageProducts = JSON.parse(app.dataset.damageProducts || '[]');
        const cancelReasons = JSON.parse(app.dataset.reasons || '[]');
        const dsrLoc = dsrStore.dsrLocation;

        const mapEl = document.getElementById('deliveryMap');
        const quickCardsEl = document.getElementById('deliveryQuickCards');
        const nearbyCountEl = document.getElementById('deliveryNearbyCount');
        const dateSummaryEl = document.getElementById('deliveryDateSummary');
        const recenterBtn = document.getElementById('recenterDeliveryMapBtn');

        const $ = (id) => document.getElementById(id);
        const doUndoBar = $('doUndoBar');
        const doUndoLabel = $('doUndoLabel');
        const doCompaniesContainer = $('doCompaniesContainer');
        const doCancelOrderBtn = $('doCancelOrderBtn');
        const doOpenPayBtn = $('doOpenPayBtn');
        const payAmountInput = $('payAmountInput');

        let activeId = null;
        let draft = null; // working copy of the open stop
        let pendingCancel = null; // { type: 'all' } | { type: 'company', id }
        let leafletLayerGroup = null;
        const hasLeaflet = typeof window.L !== 'undefined';

        const clone = (o) => JSON.parse(JSON.stringify(o));
        const stopById = (id) => stops.find((s) => s.id === String(id)) || null;

        const MONTHS_BN = ['জানু', 'ফেব্রু', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট', 'সেপ্টে', 'অক্টো', 'নভে', 'ডিসে'];
        function formatBnDate(iso) {
            if (!iso) return '';
            const parts = String(iso).split('-').map(Number);
            if (parts.length !== 3) return iso;
            return `${bnDigits(parts[2])} ${MONTHS_BN[(parts[1] - 1)] || ''} ${bnDigits(parts[0])}`;
        }
        function shiftIsoDate(iso, deltaDays) {
            const parts = String(iso).split('-').map(Number);
            const dt = new Date(Date.UTC(parts[0], (parts[1] || 1) - 1, parts[2] || 1));
            dt.setUTCDate(dt.getUTCDate() + deltaDays);
            return dt.toISOString().slice(0, 10);
        }

        const tripStateBanner = $('tripStateBanner');
        const openReadySaleBtn = $('openReadySaleBtn');
        const deliveryDateInput = $('deliveryDateInput');
        const deliveryDateDisplay = $('deliveryDateDisplay');
        const deliveryTripCodeDisplay = $('deliveryTripCodeDisplay');
        let dateReqSeq = 0;

        function syncTripHeaderUi(isLoading = false) {
            if (deliveryDateInput && deliveryDateInput.value !== selectedDate) deliveryDateInput.value = selectedDate;
            if (deliveryDateDisplay) deliveryDateDisplay.textContent = formatBnDate(selectedDate);
            if (deliveryTripCodeDisplay) {
                deliveryTripCodeDisplay.textContent = isLoading
                    ? 'লোড হচ্ছে…'
                    : (trip ? bnDigits(trip.code) : 'ট্রিপ নেই');
            }
            if (openReadySaleBtn) openReadySaleBtn.disabled = !editable;
            if (tripStateBanner) {
                tripStateBanner.classList.remove('is-returned', 'is-muted');
                if (isLoading) {
                    tripStateBanner.hidden = true;
                } else if (!trip) {
                    tripStateBanner.textContent = 'এই তারিখে কোনো ডিসপ্যাচ করা ট্রিপ নেই — অন্য তারিখ বাছুন।';
                    tripStateBanner.classList.add('is-muted');
                    tripStateBanner.hidden = false;
                } else if (!trip.editable) {
                    tripStateBanner.textContent = trip.status_key === 'settled'
                        ? 'এই ট্রিপটি সেটেল হয়ে গেছে — শুধু দেখার জন্য।'
                        : 'সেটেলমেন্টের জন্য জমা দেওয়া হয়েছে — পার্টনার যাচাই করছেন। এখন পরিবর্তন করা যাবে না।';
                    tripStateBanner.hidden = false;
                } else if (trip.settlement_status === 'returned') {
                    tripStateBanner.textContent = `পার্টনার ফেরত পাঠিয়েছেন${trip.review_note ? `: ${trip.review_note}` : ''}। সংশোধন করে পুনরায় জমা দিন।`;
                    tripStateBanner.classList.add('is-returned');
                    tripStateBanner.hidden = false;
                } else {
                    tripStateBanner.hidden = true;
                }
            }
        }

        async function loadDeliveryDate(nextDate) {
            if (!nextDate || !/^\d{4}-\d{2}-\d{2}$/.test(nextDate)) return;
            selectedDate = nextDate;
            const seq = ++dateReqSeq;
            syncTripHeaderUi(true);
            if (quickCardsEl) {
                quickCardsEl.innerHTML = Array.from({ length: 2 }, () => `
                    <div class="quick-retailer-card" style="gap:7px;">
                        <span class="rs-sk" style="width:65%"></span>
                        <span class="rs-sk" style="width:45%;height:9px"></span>
                    </div>
                `).join('');
            }
            try {
                const res = await dsrApi('GET', `/dsr/delivery/state?date=${encodeURIComponent(nextDate)}`);
                if (seq !== dateReqSeq) return;
                trip = res.trip || null;
                editable = !!trip?.editable;
                tripSrIds = (trip?.sr_ids || []).map(Number);
                stops = Array.isArray(res.orders) ? res.orders : [];
                if (Array.isArray(res.vanStock)) vanStock = res.vanStock; else vanStock = [];
                if (Array.isArray(res.damageProducts)) damageProducts = res.damageProducts;
                activeId = null;
                draft = null;
                fittedOnce = false;
                syncTripHeaderUi(false);
                refreshDeliveryViews();
                saveSnapshot();
                try {
                    const url = new URL(window.location.href);
                    url.searchParams.set('date', selectedDate);
                    history.replaceState(history.state, '', url.href);
                } catch { /* ignore */ }
            } catch (err) {
                if (seq !== dateReqSeq) return;
                syncTripHeaderUi(false);
                showToast(err.message);
                refreshDeliveryViews();
            }
        }

        $('deliveryPrevDateBtn')?.addEventListener('click', () => loadDeliveryDate(shiftIsoDate(selectedDate, -1)));
        $('deliveryNextDateBtn')?.addEventListener('click', () => loadDeliveryDate(shiftIsoDate(selectedDate, 1)));
        deliveryDateInput?.addEventListener('change', () => {
            if (deliveryDateInput.value) loadDeliveryDate(deliveryDateInput.value);
        });

        function applyState(data) {
            if (Object.prototype.hasOwnProperty.call(data, 'trip')) {
                trip = data.trip || null;
                editable = !!trip?.editable;
                tripSrIds = (trip?.sr_ids || []).map(Number);
                syncTripHeaderUi(false);
            }
            if (data.orders) stops = data.orders;
            if (data.vanStock) vanStock = data.vanStock;
            if (data.damageProducts) damageProducts = data.damageProducts;
            if (data.retailers) {
                dsrStore.retailers = data.retailers;
                dsrStore.retailersSynced = true;
                retailers = dsrStore.retailers;
            }
            if (data.newRetailer) {
                const nr = data.newRetailer;
                const byId = new Set(retailers.map((r) => String(r.id)));
                if (!byId.has(String(nr.id))) {
                    retailers.unshift(nr);
                    dsrStore.retailers = retailers;
                }
            }
            if (activeId) {
                const fresh = stopById(activeId);
                draft = fresh ? clone(fresh) : null;
            }
            refreshDeliveryViews();
            if (draft) renderStop();
            saveSnapshot();
        }

        // ------------------------------------------------------- offline: local copies of server changes
        // Used only while a write waits in the offline queue. They mirror DsrDelivery on the server closely
        // enough for the screen; once the queue is synced the server's own numbers replace them.
        const snapKey = `deliv:${HB_USER}`;
        function saveSnapshot() {
            if (!offlineOk()) return;
            window.HbOffline.kvSet(snapKey, { date: selectedDate, trip, stops, vanStock, damageProducts, at: Date.now() });
        }

        function stopStatus(s) {
            const keys = s.companies.map((c) => c.status_key);
            if (keys.includes('assigned') || keys.includes('pending')) return 'Pending';
            if (!keys.some((k) => k !== 'cancelled')) return 'Cancelled';
            return Number(s.due_amount || 0) > 0.004 ? 'Due' : 'Delivered';
        }

        /** Van stock and per-line "stock" from the (locally changed) stops — same rules as vanStock()/stops() on the server. */
        function recomputeVan() {
            const delivered = {};
            const readySold = {};
            stops.forEach((s) => s.companies.forEach((c) => {
                if (c.cancelled || c.status_key === 'assigned' || c.status_key === 'pending') return;
                c.items.forEach((it) => {
                    const pid = String(it.product_id);
                    delivered[pid] = (delivered[pid] || 0) + Number(it.qty || 0);
                    if (c.ready_sale) readySold[pid] = (readySold[pid] || 0) + Number(it.qty || 0);
                });
            }));
            vanStock.forEach((p) => {
                const pid = String(p.id);
                p.delivered_pcs = delivered[pid] || 0;
                p.ready_sold_pcs = readySold[pid] || 0;
                p.available_pcs = Number(p.dispatched_pcs || 0) - p.delivered_pcs;
            });
            const avail = Object.fromEntries(vanStock.map((p) => [String(p.id), p.available_pcs]));
            stops.forEach((s) => s.companies.forEach((c) => {
                const resolved = !(c.status_key === 'assigned' || c.status_key === 'pending');
                c.items.forEach((it) => { it.stock = (avail[String(it.product_id)] || 0) + (resolved ? Number(it.qty || 0) : 0); });
            }));
        }

        function commitLocal() {
            recomputeVan();
            stops.forEach((s) => { s.status = stopStatus(s); });
            if (activeId) {
                const fresh = stopById(activeId);
                draft = fresh ? clone(fresh) : null;
            }
            refreshDeliveryViews();
            if (draft) renderStop();
            saveSnapshot();
        }

        function replaceStop(s) {
            const i = stops.findIndex((x) => x.id === s.id);
            if (i === -1) stops.push(s); else stops[i] = s;
        }

        function localSaveStop(local, paid) {
            const m = computeOrderMetrics(local);
            const forBill = Math.min(paid, m.shouldPay);
            local.companies.forEach((c) => {
                if (!c.ready_sale) c.status_key = c.cancelled ? 'cancelled' : 'delivered';
            });
            local.paid_amount = round2(forBill + local.companies.filter((c) => c.ready_sale).reduce((t, c) => t + c.items.reduce((a, it) => a + it.qty * it.sr_rate, 0), 0));
            local.old_due_collected = round2(paid - forBill);
            local.due_amount = round2(m.shouldPay - forBill);
            local.cancel_reason = local.companies.some((c) => c.cancelled) ? (local.cancel_reason || '') : '';
            replaceStop(local);
            commitLocal();
        }

        function localResetStop(id) {
            const s = clone(stopById(id));
            if (!s || !s.companies.some((c) => !c.ready_sale)) throw new Error('এই দোকানে আপনার ট্রিপের কোনো অর্ডার নেই।');
            s.companies.forEach((c) => {
                if (c.ready_sale) return;
                c.status_key = 'assigned';
                c.cancelled = false;
                c.cancel_reason = null;
                c.items.forEach((it) => { it.qty = it.ordered_qty; });
            });
            s.damages = [];
            s.old_due_collected = 0;
            s.cancel_reason = '';
            const readyPaid = s.companies.filter((c) => c.ready_sale).reduce((t, c) => t + c.items.reduce((a, it) => a + it.qty * it.sr_rate, 0), 0);
            s.paid_amount = round2(readyPaid);
            s.due_amount = 0;
            replaceStop(s);
            recomputeVan();
            // not delivered yet: start from the ordered qty, but never more than the van holds
            s.companies.forEach((c) => {
                if (!c.ready_sale) c.items.forEach((it) => { it.qty = Math.min(it.ordered_qty, Math.max(0, it.stock)); });
            });
            commitLocal();
        }

        function localDamages(id, items) {
            const s = clone(stopById(id));
            if (!s) return;
            const byId = Object.fromEntries(damageProducts.map((p) => [String(p.id), p]));
            const merged = new Map();
            items.forEach((it) => merged.set(String(it.product_id), (merged.get(String(it.product_id)) || 0) + Number(it.pcs || 0)));
            s.damages = [];
            merged.forEach((pcs, pid) => {
                const p = byId[pid];
                if (!p || pcs < 1) return;
                const order = s.companies.find((c) => !c.ready_sale && c.status_key === 'assigned' && Number(c.company_id) === Number(p.company_id));
                s.damages.push({ order_id: order ? Number(order.id) : 0, product_id: Number(pid), name: p.name, pcs, amount: round2(pcs * Number(p.rate || 0)) });
            });
            replaceStop(s);
            commitLocal();
        }

        /** Ready sale at the van price (fixed when the trip was loaded), one order per company — like the server. */
        function localReadySale(body, tmpId) {
            const vanById = Object.fromEntries(vanStock.map((p) => [String(p.id), p]));
            const merged = new Map();
            body.items.forEach((it) => merged.set(String(it.product_id), (merged.get(String(it.product_id)) || 0) + Number(it.pcs || 0)));
            merged.forEach((pcs, pid) => {
                const p = vanById[pid];
                if (!p) throw new Error('ভ্যানে লোড করা পণ্য থেকে নির্বাচন করুন।');
                if (pcs > p.available_pcs) throw new Error(`${p.name}: ভ্যানে মাত্র ${bnDigits(p.available_pcs)} পিস বাকি আছে।`);
            });

            let shop;
            let newRetailer = null;
            if (body.mode === 'new') {
                newRetailer = { id: tmpId, name: body.name, phone: body.phone || '', address: body.address || 'স্পট লোকেশন', lat: Number(body.lat), lng: Number(body.lng), sr_id: null, due: 0 };
                shop = newRetailer;
            } else {
                shop = retailers.find((r) => String(r.id) === String(body.retailer_id)) || stopById(body.retailer_id) && { id: body.retailer_id, name: stopById(body.retailer_id).retailer_name };
                if (!shop) throw new Error('একটি দোকান নির্বাচন করুন।');
            }

            const sid = String(shop.id);
            const s = stopById(sid) ? clone(stopById(sid)) : {
                id: sid, retailer_name: shop.name, phone: shop.phone || '', address: shop.address || '', lat: Number(shop.lat || 0), lng: Number(shop.lng || 0),
                sr_names: [], companies: [], damages: [], old_due_collected: 0, existing_due: Number(shop.due || 0),
                paid_amount: 0, due_amount: 0, cancel_reason: '', status: 'Delivered', editable: false,
            };
            const byCompany = new Map();
            merged.forEach((pcs, pid) => {
                const p = vanById[pid];
                if (!byCompany.has(p.company_id)) byCompany.set(p.company_id, []);
                byCompany.get(p.company_id).push({ p, pcs });
            });
            let total = 0;
            const receiptItems = [];
            byCompany.forEach((lines, companyId) => {
                s.companies.push({
                    id: `tmp-${window.HbOffline.uuid()}`, order_code: 'সিঙ্ক বাকি', name: lines[0].p.company, company_id: Number(companyId),
                    sr: 'Ready Sale', ready_sale: true, status_key: 'delivered', cancelled: false, cancel_reason: null,
                    items: lines.map(({ p, pcs }) => {
                        const line = round2(pcs * Number(p.base_rate));
                        total = round2(total + line);
                        receiptItems.push({ name: p.name, pcs, rate: p.base_rate, total: line });
                        return { product_id: String(p.id), name: p.name, unit_type: p.unit_type, qty_per_unit: p.qty_per_unit, ordered_qty: pcs, qty: pcs, base_rate: Number(p.base_rate), sr_rate: Number(p.base_rate), stock: 0 };
                    }),
                });
            });
            s.paid_amount = round2(Number(s.paid_amount || 0) + total);
            replaceStop(s);
            commitLocal();
            return { receipt: { retailer: shop.name, total, codes: ['সিঙ্ক বাকি'], items: receiptItems }, ...(newRetailer ? { newRetailer } : {}) };
        }

        function localDeleteReadySale(orderId) {
            if (isTmp(orderId)) throw new Error('এই রেডি সেলটি এখনো সিঙ্ক হয়নি — সিঙ্ক হওয়ার পর মুছুন।');
            const s = stops.find((x) => x.companies.some((c) => c.id === String(orderId)));
            if (!s) return;
            const c = s.companies.find((x) => x.id === String(orderId));
            s.companies = s.companies.filter((x) => x !== c);
            s.paid_amount = round2(Number(s.paid_amount || 0) - c.items.reduce((a, it) => a + it.qty * it.sr_rate, 0));
            if (!s.companies.length) stops = stops.filter((x) => x !== s);
            commitLocal();
        }

        /** Use the phone's copy when it holds changes the page (from cache, or behind the queue) does not show. */
        async function restoreOfflineState() {
            if (!offlineOk()) return;
            const [snap, pending] = await Promise.all([window.HbOffline.kvGet(snapKey), window.HbOffline.count(HB_USER)]);
            const fromCache = app.dataset.fromCache === '1';
            if (snap && snap.date === selectedDate && (fromCache || pending > 0)) {
                trip = snap.trip || null;
                editable = !!trip?.editable;
                tripSrIds = (trip?.sr_ids || []).map(Number);
                stops = snap.stops || [];
                vanStock = snap.vanStock || [];
                if (Array.isArray(snap.damageProducts)) damageProducts = snap.damageProducts;
                syncTripHeaderUi(false);
                refreshDeliveryViews();
            } else if (!fromCache) {
                saveSnapshot();
            }
            if (fromCache && pending === 0 && navigator.onLine) refreshFromServer();
        }

        async function refreshFromServer() {
            if (modalStack.length) { setTimeout(refreshFromServer, 5000); return; } // don't reset a stop being edited
            try {
                const res = await dsrApi('GET', `/dsr/delivery/state?date=${encodeURIComponent(selectedDate)}`);
                if (!document.body.contains(app)) return;
                applyState(res);
            } catch { /* still offline */ }
        }

        function sortedStops() {
            return stops
                .map((s) => ({ ...s, distance: haversineMeters(dsrLoc.lat, dsrLoc.lng, Number(s.lat), Number(s.lng)), metrics: computeOrderMetrics(s) }))
                .sort((a, b) => (a.status === 'Pending' ? 0 : 1) - (b.status === 'Pending' ? 0 : 1) || a.distance - b.distance);
        }

        function renderQuickCards(items) {
            if (!quickCardsEl) return;
            if (nearbyCountEl) nearbyCountEl.textContent = bnDigits(items.length);
            const pending = items.filter((s) => s.status === 'Pending').length;
            if (dateSummaryEl) {
                dateSummaryEl.textContent = !trip
                    ? `${formatBnDate(selectedDate)}-এ কোনো ট্রিপ নেই`
                    : `${bnDigits(items.length)}টি স্টপের মধ্যে ${bnDigits(pending)}টি বাকি`;
            }
            if (items.length === 0) {
                quickCardsEl.innerHTML = `<div class="muted small" style="padding:10px 6px;">${!trip ? 'এই তারিখে কোনো ডিসপ্যাচ করা ট্রিপ নেই।' : 'এই ট্রিপে কোনো অর্ডার নেই।'}</div>`;
                return;
            }
            quickCardsEl.innerHTML = items.map((s) => `
                <button type="button" class="quick-retailer-card ${statusPinClass(s.status)}" data-open-order="${escapeHtml(s.id)}">
                    <div class="qrc-top">
                        <span class="qrc-name">${escapeHtml(s.retailer_name)}</span>
                        <span class="badge ${statusBadgeClass(s.status)}">${escapeHtml(bnStatus(s.status))}</span>
                    </div>
                    <div class="qrc-addr">${escapeHtml(s.address || s.phone || 'অবস্থান পিনকৃত')} · ${escapeHtml(formatDistance(s.distance))}</div>
                    <div class="qrc-bottom">
                        <span class="muted">${s.status === 'Pending' ? 'পরিশোধযোগ্য' : 'পরিশোধ / বকেয়া'}</span>
                        <strong class="tabular">${s.status === 'Pending' ? formatBdt(s.metrics.shouldPay) : `${formatBdt(s.metrics.paid)} / ${formatBdt(s.due_amount)}`}</strong>
                    </div>
                </button>`).join('');
        }

        let tripSrIds = (trip?.sr_ids || []).map(Number);
        // Retailers created by this trip's SRs that have no order on the trip (no radius limit)
        function allPinPoints(items) {
            const pts = items.filter((s) => Number(s.lat) || Number(s.lng)).map((s) => [Number(s.lat), Number(s.lng)]);
            if (pts.length === 0 || dsrStore.gpsFix) pts.push([dsrLoc.lat, dsrLoc.lng]);
            return pts;
        }
        function fitAllPins() {
            if (!activeDeliveryMap) return;
            activeDeliveryMap.invalidateSize(false);
            const pts = allPinPoints(sortedStops());
            if (pts.length === 1) activeDeliveryMap.setView(pts[0], 17);
            else activeDeliveryMap.fitBounds(window.L.latLngBounds(pts), { paddingTopLeft: [28, 68], paddingBottomRight: [28, 190], maxZoom: 18 });
        }

        let fittedOnce = false;
        function renderMapMarkers(items) {
            if (!hasLeaflet || !activeDeliveryMap || !leafletLayerGroup) return;
            leafletLayerGroup.clearLayers();
            const dsrPhoto = app.dataset.dsrPhoto || '';
            const dsrIcon = dsrPhoto
                ? window.L.divIcon({ className: 'photo-pin-icon', html: `<div class="photo-pin" title="আপনার অবস্থান (DSR)"><img src="${escapeHtml(dsrPhoto)}" alt=""></div>`, iconSize: [46, 56], iconAnchor: [23, 56] })
                : window.L.divIcon({ className: 'retailer-pin-icon', html: '<div class="dsr-pin-dot" title="আপনার অবস্থান (DSR)"></div>', iconSize: [14, 14], iconAnchor: [7, 7] });
            window.L.marker([dsrLoc.lat, dsrLoc.lng], { icon: dsrIcon, zIndexOffset: 300 }).addTo(leafletLayerGroup);
            items.forEach((s) => {
                if (!Number(s.lat) && !Number(s.lng)) return;
                const icon = window.L.divIcon({
                    className: 'retailer-pin-icon',
                    html: `<div class="retailer-pin-wrap ${statusPinClass(s.status)}" title="${escapeHtml(`${s.retailer_name} · ${bnStatus(s.status)}`)}"><span class="retailer-pin-label"><span class="pin-status-dot ${statusPinClass(s.status)}"></span><span>${escapeHtml(s.retailer_name)}</span></span><span class="retailer-pin-dot"></span></div>`,
                    iconSize: [0, 0],
                    iconAnchor: [0, 0],
                });
                window.L.marker([Number(s.lat), Number(s.lng)], { icon, zIndexOffset: 200 }).addTo(leafletLayerGroup).on('click', () => openStop(s.id));
            });
            if (!fittedOnce) {
                fittedOnce = true;
                fitAllPins();
                setTimeout(fitAllPins, 500); // after the container settles into its final size
            }
        }

        function refreshDeliveryViews() {
            const items = sortedStops();
            renderQuickCards(items);
            renderMapMarkers(items);
        }

        // ------------------------------------------------------------ stop sheet
        function renderStop() {
            if (!draft) return;
            const m = computeOrderMetrics(draft);
            const resolved = draft.status !== 'Pending';
            const canEdit = editable && draft.editable;

            if (doUndoBar) {
                doUndoBar.hidden = !(resolved && canEdit);
                if (doUndoLabel) doUndoLabel.textContent = `সংরক্ষিত অবস্থা: ${bnStatus(draft.status)}`;
            }
            $('doRetailerName').textContent = draft.retailer_name;
            const badge = $('doHeadStatusBadge');
            badge.textContent = bnStatus(draft.status);
            badge.className = `badge ${statusBadgeClass(draft.status)}`;
            const reasonText = draft.cancel_reason ? ` · ${bnReason(draft.cancel_reason)}` : '';
            $('doRetailerMeta').textContent = `${draft.address || ''}${draft.phone ? ` · ${bnDigits(draft.phone)}` : ''} · SR: ${draft.sr_names.join(', ') || '—'}${reasonText}`;

            doCompaniesContainer.innerHTML = draft.companies.map((comp, idx) => {
                const locked = !canEdit || comp.ready_sale || comp.cancelled;
                const rows = comp.items.map((it) => {
                    const qty = Math.max(0, Number(it.qty || 0));
                    const lineTotal = round2(qty * Number(it.sr_rate || 0));
                    const itemOc = round2(qty * (Number(it.sr_rate || 0) - Number(it.base_rate || 0)));
                    const ocClass = itemOc > 0.01 ? 'is-ok' : (itemOc < -0.01 ? 'is-warn' : 'muted');
                    const dis = locked ? 'disabled' : '';
                    return `
                        <div class="do-item-row" data-company-id="${escapeHtml(comp.id)}" data-product-id="${escapeHtml(it.product_id)}">
                            <div class="do-item-top">
                                <div class="do-item-name"><span>${escapeHtml(it.name)} (${bnDigits(Number(it.stock || 0))})</span><span class="do-unit-tag">পিস</span></div>
                                <div class="do-item-meta-right tabular">
                                    <span class="muted">অর্ডার: <strong>${bnDigits(Number(it.ordered_qty || 0))}</strong></span>
                                    <span class="muted">·</span>
                                    <span class="${ocClass}">O/C <strong>${escapeHtml(formatSignedNum(itemOc))}</strong></span>
                                </div>
                            </div>
                            <div class="do-item-bottom">
                                <div class="do-stepper-group">
                                    <div class="qty-stepper">
                                        <button type="button" class="step-btn" data-step="-1" ${dis} aria-label="পরিমাণ কমান">−</button>
                                        <input type="number" class="step-val-input tabular" min="0" step="1" value="${qty}" ${dis} aria-label="ডেলিভারি পরিমাণ">
                                        <button type="button" class="step-btn" data-step="1" ${dis} aria-label="পরিমাণ বাড়ান">+</button>
                                    </div>
                                    <span class="do-conv-pill tabular">${escapeHtml(formatConvertedQty(qty, it.qty_per_unit))}</span>
                                </div>
                                <div class="do-line-total tabular">${formatBdt(lineTotal)}</div>
                            </div>
                        </div>`;
                }).join('');

                let compBtn = '';
                if (comp.ready_sale) {
                    compBtn = canEdit ? `<button type="button" class="btn btn-danger-outline btn-xs" data-ready-delete="${escapeHtml(comp.id)}">সরান</button>` : '';
                } else if (canEdit) {
                    compBtn = comp.cancelled
                        ? `<button type="button" class="btn btn-secondary btn-xs" data-company-undo="${escapeHtml(comp.id)}">পূর্বাবস্থা</button>`
                        : `<button type="button" class="btn btn-danger-outline btn-xs" data-company-cancel="${escapeHtml(comp.id)}">বাতিল</button>`;
                }
                const tag = comp.ready_sale ? '<span class="badge badge-success">রেডি সেল</span>' : `<span class="muted small">${escapeHtml(comp.order_code)} · SR ${escapeHtml(comp.sr)}</span>`;
                return `
                    ${idx > 0 ? '<div class="do-company-divider" role="separator"></div>' : ''}
                    <section class="do-company-section ${comp.cancelled ? 'is-cancelled' : ''}">
                        <div class="do-company-head">
                            <span class="do-company-name">${escapeHtml(comp.name)} ${tag}</span>
                            ${compBtn}
                        </div>
                        <div class="do-items-stack">${rows}</div>
                    </section>`;
            }).join('');

            renderDamage(canEdit);

            const dueAlert = $('doExistingDueAlert');
            if (dueAlert) {
                dueAlert.hidden = !(Number(draft.existing_due || 0) > 0);
                $('doExistingDueAmt').textContent = formatBdt(draft.existing_due || 0);
            }
            $('doFooterPaid').textContent = formatBdt(m.paid);
            $('doFooterDue').textContent = formatBdt(m.due);
            const ocEl = $('doFooterOc');
            ocEl.textContent = formatSignedBdt(m.deliveryOc);
            ocEl.className = 'tabular ' + (m.deliveryOc > 0 ? 'is-ok' : (m.deliveryOc < 0 ? 'is-warn' : ''));
            $('doStatusCell').innerHTML = `<span class="badge ${statusBadgeClass(draft.status)}">${escapeHtml(bnStatus(draft.status))}</span>`;
            $('doOrderTotalCell').textContent = formatBdt(m.orderTotal);
            $('doShouldPayCell').textContent = formatBdt(m.shouldPay);

            const hasOrders = draft.companies.some((c) => !c.ready_sale);
            const allCancelled = draft.companies.filter((c) => !c.ready_sale).every((c) => c.cancelled);
            doCancelOrderBtn.disabled = !canEdit || !hasOrders || draft.status === 'Cancelled';
            doOpenPayBtn.disabled = !canEdit || !hasOrders || allCancelled;
            doOpenPayBtn.textContent = resolved ? 'পেমেন্ট আপডেট' : 'পরিশোধ';
        }

        function renderDamage(canEdit) {
            const box = $('doDamageBox');
            if (!box) return;
            const hasDamages = Array.isArray(draft.damages) && draft.damages.length > 0;
            box.hidden = !canEdit && !hasDamages;
            const list = $('doDamageList');
            if (list) {
                list.hidden = !hasDamages;
                list.innerHTML = hasDamages ? draft.damages.map((d, i) => `
                    <div class="do-damage-row">
                        <span>${escapeHtml(d.name)} · <strong class="tabular">${bnDigits(d.pcs)} পিস</strong></span>
                        <span class="tabular is-danger">− ${formatBdt(d.amount)}</span>
                        ${canEdit ? `<button type="button" class="lot-row-remove" data-damage-remove="${i}" aria-label="সরান">×</button>` : ''}
                    </div>`).join('') : '';
            }

            const openBtn = $('doOpenDamageModalBtn');
            if (openBtn) {
                openBtn.hidden = !canEdit;
                openBtn.textContent = '+ ড্যামেজ সংগ্রহ';
            }
        }

        function openStop(id) {
            const stop = stopById(id);
            if (!stop) return;
            activeId = stop.id;
            draft = clone(stop);
            renderStop();
            openModal('deliveryOrderModal');
        }

        quickCardsEl?.addEventListener('click', (e) => {
            const card = e.target.closest('[data-open-order]');
            if (card) openStop(card.getAttribute('data-open-order'));
        });
        $('doHeaderCancelBtn')?.addEventListener('click', () => closeModal('deliveryOrderModal'));

        function findItem(row) {
            const comp = draft.companies.find((c) => c.id === row.getAttribute('data-company-id'));
            return { comp, item: comp?.items.find((i) => i.product_id === row.getAttribute('data-product-id')) };
        }

        doCompaniesContainer?.addEventListener('click', async (e) => {
            if (!draft) return;
            const cancelBtn = e.target.closest('[data-company-cancel]');
            if (cancelBtn) {
                pendingCancel = { type: 'company', id: cancelBtn.getAttribute('data-company-cancel') };
                openCancelDialog('এই কোম্পানির অর্ডার বাতিল করুন', 'একটি কারণ বাছুন। পেমেন্ট কনফার্ম করলে সংরক্ষিত হবে।');
                return;
            }
            const undoBtn = e.target.closest('[data-company-undo]');
            if (undoBtn) {
                const comp = draft.companies.find((c) => c.id === undoBtn.getAttribute('data-company-undo'));
                const fresh = stopById(activeId)?.companies.find((c) => c.id === comp?.id);
                if (comp) {
                    comp.cancelled = false;
                    comp.items = clone(fresh && !fresh.cancelled ? fresh.items : comp.items.map((it) => ({ ...it, qty: it.ordered_qty })));
                }
                renderStop();
                return;
            }
            const rsDel = e.target.closest('[data-ready-delete]');
            if (rsDel) {
                if (!window.confirm('এই রেডি সেলটি সরাবেন? পিসগুলো আবার ভ্যান স্টকে ফিরে যাবে।')) return;
                try {
                    const res = await withBusy(rsDel, '…', () => dsrApi('DELETE', `/dsr/ready-sales/${rsDel.getAttribute('data-ready-delete')}`, undefined, {
                        label: 'রেডি সেল মুছা',
                        apply: () => { localDeleteReadySale(rsDel.getAttribute('data-ready-delete')); return {}; },
                    }));
                    showToast(res.message);
                    applyState(res);
                    if (!stopById(activeId)) closeModal('deliveryOrderModal');
                } catch (err) { showToast(err.message); }
                return;
            }
            const stepBtn = e.target.closest('[data-step]');
            if (stepBtn) {
                const { comp, item } = findItem(stepBtn.closest('.do-item-row'));
                if (!item || comp.cancelled) return;
                const next = Math.max(0, Math.floor((Number(item.qty) || 0) + Number(stepBtn.getAttribute('data-step'))));
                if (next > Number(item.stock || 0)) {
                    showToast(`ভ্যানে ${item.name}-এর মাত্র ${bnDigits(item.stock)} পিস আছে।`);
                    return;
                }
                item.qty = next;
                renderStop();
            }
        });

        doCompaniesContainer?.addEventListener('input', (e) => {
            if (!e.target.classList?.contains('step-val-input') || !draft) return;
            const row = e.target.closest('.do-item-row');
            const { comp, item } = findItem(row);
            if (!item || comp.cancelled) return;
            let val = Math.max(0, Math.floor(Number(e.target.value) || 0));
            if (val > Number(item.stock || 0)) {
                val = Number(item.stock || 0);
                e.target.value = String(val);
                showToast(`ভ্যানে ${item.name}-এর মাত্র ${bnDigits(item.stock)} পিস আছে।`);
            }
            item.qty = val;
            row.querySelector('.do-conv-pill').textContent = formatConvertedQty(val, item.qty_per_unit);
            row.querySelector('.do-line-total').textContent = formatBdt(round2(val * Number(item.sr_rate || 0)));
            const m = computeOrderMetrics(draft);
            $('doShouldPayCell').textContent = formatBdt(m.shouldPay);
            $('doFooterOc').textContent = formatSignedBdt(m.deliveryOc);
        });

        // Dedicated Damage Collection Modal (ALL assigned SRs' products — not limited to van stock)
        const dmgDraftMap = new Map(); // String(product_id) -> { company_id, product_id, name, pcs, rate }
        let dmgViewMode = 'grid';
        let dmgCompanyFilter = 'all';
        let dmgSearchTimer = null;
        let dmgSearchSeq = 0;

        function dmgActiveOrderCompanies() {
            if (!draft) return [];
            return draft.companies.filter((c) => !c.ready_sale && !c.cancelled);
        }

        function dmgAllCompanies() {
            const byId = new Map();
            damageProducts.forEach((p) => {
                const cid = Number(p.company_id);
                if (!byId.has(cid)) byId.set(cid, { company_id: cid, name: p.company || `কোম্পানি #${cid}` });
            });
            return Array.from(byId.values());
        }

        function dmgGrossTotal() {
            let gross = 0;
            dmgActiveOrderCompanies().forEach((c) => {
                (c.items || []).forEach((it) => {
                    gross += Math.max(0, Number(it.qty || 0)) * Number(it.sr_rate || 0);
                });
            });
            return round2(gross);
        }

        function dmgRenderCompanyChips() {
            const rail = $('dmgCompanyChips');
            if (!rail) return;
            const comps = dmgAllCompanies();
            if (comps.length <= 1) {
                rail.hidden = true;
                rail.innerHTML = '';
                dmgCompanyFilter = 'all';
                return;
            }
            rail.hidden = false;
            rail.innerHTML = `<button type="button" class="dmg-chip ${dmgCompanyFilter === 'all' ? 'is-active' : ''}" data-dmg-comp="all">সব (${bnDigits(comps.length)})</button>`
                + comps.map((c) => `<button type="button" class="dmg-chip ${String(dmgCompanyFilter) === String(c.company_id) ? 'is-active' : ''}" data-dmg-comp="${escapeHtml(c.company_id)}">${escapeHtml(c.name)}</button>`).join('');
        }

        function dmgUpdateSummary() {
            let count = 0;
            let totalPcs = 0;
            let totalAmt = 0;
            dmgDraftMap.forEach((d) => {
                if (d.pcs > 0) {
                    count++;
                    totalPcs += d.pcs;
                    totalAmt = round2(totalAmt + round2(d.pcs * d.rate));
                }
            });
            const gross = dmgGrossTotal();
            const net = round2(Math.max(0, gross - totalAmt));
            if ($('dmgHeadTotalBadge')) $('dmgHeadTotalBadge').textContent = `− ${formatBdt(totalAmt)}`;
            if ($('dmgFootGross')) $('dmgFootGross').textContent = formatBdt(gross);
            if ($('dmgFootDeduct')) $('dmgFootDeduct').textContent = `− ${formatBdt(totalAmt)}`;
            if ($('dmgFootNet')) $('dmgFootNet').textContent = formatBdt(net);

            const banner = $('dmgSelectedSummary');
            if (banner) {
                banner.hidden = count === 0;
                if ($('dmgSelectedText')) {
                    $('dmgSelectedText').textContent = `${bnDigits(count)}টি পণ্য (${bnDigits(totalPcs)} পিস) · − ${formatBdt(totalAmt)}`;
                }
            }
        }

        function dmgRenderGrid(queryText = ($('dmgProductSearch')?.value || '').trim()) {
            const grid = $('dmgProductsGrid');
            if (!grid || !draft) return;
            grid.classList.toggle('is-list-view', dmgViewMode === 'list');

            const eligible = damageProducts.filter((p) => (
                dmgCompanyFilter === 'all' || String(p.company_id) === String(dmgCompanyFilter)
            ));

            if (eligible.length === 0) {
                grid.innerHTML = '<div class="muted small" style="grid-column:span 2;padding:24px 8px;text-align:center;">অ্যাসাইনড SR-এর কোনো পণ্য পাওয়া যায়নি।</div>';
                return;
            }

            const qTokens = queryText ? DsrBanglish.compileQuery(queryText) : null;
            const list = qTokens
                ? eligible
                    .map((p) => ({ p, s: DsrBanglish.score(DsrBanglish.getIndexed(p, `${p.name} ${p.company || ''} ${p.code || ''}`), qTokens) }))
                    .filter((x) => x.s > 0)
                    .sort((a, b) => (Math.floor(b.s / 10) - Math.floor(a.s / 10)) || (Number(b.p.id) - Number(a.p.id)))
                    .map((x) => x.p)
                : eligible.slice().sort((a, b) => {
                    const aOn = (dmgDraftMap.get(String(a.id))?.pcs || 0) > 0 ? 0 : 1;
                    const bOn = (dmgDraftMap.get(String(b.id))?.pcs || 0) > 0 ? 0 : 1;
                    return aOn - bOn;
                });

            if (list.length === 0) {
                grid.innerHTML = '<div class="muted small" style="grid-column:span 2;padding:24px 8px;text-align:center;">মিলে যাওয়া কোনো পণ্য পাওয়া যায়নি।</div>';
                return;
            }

            grid.innerHTML = list.map((p) => {
                const pid = String(p.id);
                const qty = Math.max(0, Number(dmgDraftMap.get(pid)?.pcs || 0));
                const subTotal = round2(qty * Number(p.rate || 0));
                const imgSrc = p.image || '';
                const hasImg = Boolean(p.image);

                const actionsHtml = qty > 0
                    ? `
                        <div class="rs-stepper-row">
                            <button type="button" class="rs-step-btn" data-dmg-dec="${escapeHtml(pid)}" aria-label="কমান">−</button>
                            <input type="number" class="rs-qty-box dmg-qty-box tabular" min="0" step="1" value="${qty}" data-dmg-qty="${escapeHtml(pid)}" aria-label="ড্যামেজ পিস">
                            <button type="button" class="rs-step-btn" data-dmg-inc="${escapeHtml(pid)}" aria-label="বাড়ান">+</button>
                        </div>
                        <div class="dmg-card-subtotal tabular">− ${formatBdt(subTotal)}</div>
                    `
                    : `<button type="button" class="dmg-add-btn" data-dmg-add="${escapeHtml(pid)}">+ ড্যামেজ যোগ</button>`;

                return `
                    <article class="rs-prod-card ${qty > 0 ? 'is-dmg-active' : ''}">
                        <div class="rs-prod-thumb" style="background:${escapeHtml(p.tint || '#fff1f2')}">
                            ${hasImg ? `<img src="${escapeHtml(imgSrc)}" alt="${escapeHtml(p.name)}">` : `<div class="rs-prod-monogram">${escapeHtml(p.code || 'D')}</div>`}
                            ${qty > 0 ? `<span class="rs-prod-stock-badge tabular" style="background:#be123c">${bnDigits(qty)} পিস</span>` : ''}
                        </div>
                        <div class="rs-prod-body">
                            <span class="rs-prod-comp" style="color:#be123c">${escapeHtml(p.company || '')}</span>
                            <div class="rs-prod-name">${queryText ? DsrBanglish.highlight(p.name, queryText) : escapeHtml(p.name)}</div>
                            <div class="rs-prod-rate tabular">${formatBdt(p.rate)} <span class="muted small">/পিস</span></div>
                            <div class="rs-prod-actions">${actionsHtml}</div>
                        </div>
                    </article>
                `;
            }).join('');
        }

        function setDmgProductQty(pid, nextQty) {
            const key = String(pid);
            const p = damageProducts.find((x) => String(x.id) === key);
            if (!p) return;
            const pcs = Math.max(0, Math.floor(Number(nextQty) || 0));
            $('dmgError').hidden = true;
            if (pcs <= 0) {
                dmgDraftMap.delete(key);
            } else {
                dmgDraftMap.set(key, {
                    company_id: Number(p.company_id),
                    product_id: Number(p.id),
                    name: p.name,
                    pcs,
                    rate: Number(p.rate || 0),
                });
            }
            dmgUpdateSummary();
            dmgRenderGrid();
        }

        function openDamageModal() {
            if (!draft) return;
            dmgDraftMap.clear();
            (draft.damages || []).forEach((d) => {
                const pid = String(d.product_id);
                const p = damageProducts.find((x) => String(x.id) === pid);
                const rate = p ? Number(p.rate) : (d.pcs > 0 ? round2(Number(d.amount) / Number(d.pcs)) : 0);
                const prev = dmgDraftMap.get(pid);
                dmgDraftMap.set(pid, {
                    company_id: Number(p?.company_id || 0),
                    product_id: Number(d.product_id),
                    name: d.name,
                    pcs: (prev?.pcs || 0) + Number(d.pcs || 0),
                    rate,
                });
            });
            dmgCompanyFilter = 'all';
            if ($('dmgProductSearch')) $('dmgProductSearch').value = '';
            if ($('dmgProdClearBtn')) $('dmgProdClearBtn').hidden = true;
            if ($('dmgProdSpinner')) $('dmgProdSpinner').hidden = true;
            $('dmgError').hidden = true;
            if ($('dmgRetailerSub')) $('dmgRetailerSub').textContent = draft.retailer_name;

            dmgRenderCompanyChips();
            dmgUpdateSummary();
            dmgRenderGrid('');
            openModal('damageCollectionModal');
        }

        $('doOpenDamageModalBtn')?.addEventListener('click', openDamageModal);
        $('doDamageList')?.addEventListener('click', async (e) => {
            const btn = e.target.closest('[data-damage-remove]');
            if (!btn || !draft) return;
            const idx = Number(btn.getAttribute('data-damage-remove'));
            const nextList = draft.damages.filter((_, i) => i !== idx);
            try {
                const sid = draft.id;
                const items = nextList.map((d) => ({ product_id: Number(d.product_id), pcs: Number(d.pcs) }));
                const res = await dsrApi('POST', '/dsr/damages', { retailer_id: rid(sid), items }, {
                    label: `ড্যামেজ · ${draft.retailer_name}`,
                    apply: () => { localDamages(sid, items); return {}; },
                });
                applyState(res);
                showToast(res.message);
            } catch (err) {
                showToast(err.message);
            }
        });

        $('dmgCompanyChips')?.addEventListener('click', (e) => {
            const chip = e.target.closest('[data-dmg-comp]');
            if (!chip) return;
            dmgCompanyFilter = chip.getAttribute('data-dmg-comp') || 'all';
            dmgRenderCompanyChips();
            dmgRenderGrid();
        });

        document.querySelectorAll('[data-dmg-view]').forEach((btn) => {
            btn.addEventListener('click', () => {
                dmgViewMode = btn.getAttribute('data-dmg-view') || 'grid';
                document.querySelectorAll('[data-dmg-view]').forEach((b) => b.classList.toggle('is-active', b === btn));
                dmgRenderGrid();
            });
        });

        $('dmgProductSearch')?.addEventListener('input', () => {
            const val = ($('dmgProductSearch')?.value || '').trim();
            if ($('dmgProdClearBtn')) $('dmgProdClearBtn').hidden = val === '';
            if (dmgSearchTimer) clearTimeout(dmgSearchTimer);
            const seq = ++dmgSearchSeq;
            if (!val) {
                if ($('dmgProdSpinner')) $('dmgProdSpinner').hidden = true;
                dmgRenderGrid('');
                return;
            }
            if ($('dmgProdSpinner')) $('dmgProdSpinner').hidden = false;
            dmgSearchTimer = setTimeout(() => {
                if (seq !== dmgSearchSeq) return;
                if ($('dmgProdSpinner')) $('dmgProdSpinner').hidden = true;
                dmgRenderGrid(($('dmgProductSearch')?.value || '').trim());
            }, 110);
        });
        $('dmgProdClearBtn')?.addEventListener('click', () => {
            if ($('dmgProductSearch')) $('dmgProductSearch').value = '';
            if ($('dmgProdClearBtn')) $('dmgProdClearBtn').hidden = true;
            if ($('dmgProdSpinner')) $('dmgProdSpinner').hidden = true;
            dmgRenderGrid('');
            $('dmgProductSearch')?.focus();
        });

        $('dmgProductsGrid')?.addEventListener('click', (e) => {
            const add = e.target.closest('[data-dmg-add]');
            if (add) { setDmgProductQty(add.getAttribute('data-dmg-add'), 1); return; }
            const inc = e.target.closest('[data-dmg-inc]');
            if (inc) {
                const pid = String(inc.getAttribute('data-dmg-inc'));
                setDmgProductQty(pid, (dmgDraftMap.get(pid)?.pcs || 0) + 1);
                return;
            }
            const dec = e.target.closest('[data-dmg-dec]');
            if (dec) {
                const pid = String(dec.getAttribute('data-dmg-dec'));
                setDmgProductQty(pid, (dmgDraftMap.get(pid)?.pcs || 0) - 1);
            }
        });
        $('dmgProductsGrid')?.addEventListener('change', (e) => {
            const inp = e.target.closest('[data-dmg-qty]');
            if (inp) setDmgProductQty(inp.getAttribute('data-dmg-qty'), inp.value);
        });
        $('dmgClearAllBtn')?.addEventListener('click', () => {
            dmgDraftMap.clear();
            $('dmgError').hidden = true;
            dmgUpdateSummary();
            dmgRenderGrid();
        });
        $('dmgApplyBtn')?.addEventListener('click', async () => {
            if (!draft) return;
            const err = $('dmgError');
            err.hidden = true;
            const items = [];
            dmgDraftMap.forEach((d) => {
                if (d.pcs > 0) items.push({ product_id: Number(d.product_id), pcs: Number(d.pcs) });
            });

            try {
                const res = await withBusy($('dmgApplyBtn'), 'সাবমিট হচ্ছে…', () => dsrApi('POST', '/dsr/damages', {
                    retailer_id: rid(draft.id),
                    items,
                }, {
                    label: `ড্যামেজ · ${draft.retailer_name}`,
                    apply: ((sid) => () => { localDamages(sid, items); return {}; })(draft.id),
                }));
                closeModal('damageCollectionModal');
                applyState(res);
                showToast(res.message);
            } catch (ex) {
                err.textContent = ex.message;
                err.hidden = false;
            }
        });

        // Undo saved delivery -> stop back to pending
        $('doTopUndoBtn')?.addEventListener('click', async (e) => {
            if (!draft || !window.confirm('এই ডেলিভারি বাতিল করবেন? স্টপটি আবার বাকি অবস্থায় যাবে।')) return;
            try {
                const res = await withBusy(e.currentTarget, 'পূর্বাবস্থায় ফিরছে…', () => dsrApi('POST', `/dsr/stops/${draft.id}/reset`, undefined, {
                    label: `ডেলিভারি পূর্বাবস্থা · ${draft.retailer_name}`,
                    apply: ((sid) => () => { localResetStop(sid); return {}; })(draft.id),
                }));
                showToast(res.message);
                applyState(res);
            } catch (err) { showToast(err.message); }
        });

        // Cancel dialog (whole stop or one company)
        function openCancelDialog(title, subtitle) {
            $('crTitle').textContent = title;
            const sub = document.querySelector('#cancelReasonModal .section-subtitle');
            if (sub) sub.textContent = subtitle;
            $('cancelReasonError').hidden = true;
            $('cancelNoteInput').value = '';
            $('cancelReasonList').innerHTML = cancelReasons.map((r, i) => {
                const val = typeof r === 'string' ? r : (r.value || '');
                const lbl = typeof r === 'string' ? bnReason(r) : (r.label || val);
                return `
                <label class="reason-option">
                    <input type="radio" name="cancel_reason" value="${escapeHtml(val)}" ${i === 0 ? 'checked' : ''}>
                    <span>${escapeHtml(lbl)}</span>
                </label>`;
            }).join('');
            openModal('cancelReasonModal');
        }

        doCancelOrderBtn?.addEventListener('click', () => {
            if (!draft) return;
            pendingCancel = { type: 'all' };
            openCancelDialog('সম্পূর্ণ অর্ডার বাতিল করুন', 'এই দোকানের সব কোম্পানির অর্ডার বাতিল করতে একটি কারণ বাছুন।');
        });

        function payload(paid) {
            return {
                orders: draft.companies.filter((c) => !c.ready_sale).map((c) => ({
                    id: Number(c.id),
                    cancelled: !!c.cancelled,
                    items: c.items.map((it) => ({ product_id: Number(it.product_id), pcs: Math.max(0, Math.floor(Number(it.qty || 0))) })),
                })),
                damages: draft.damages.filter((d) => !d.order_id || !draft.companies.find((c) => c.id === String(d.order_id))?.cancelled)
                    .map((d) => ({ order_id: d.order_id ? Number(d.order_id) : 0, product_id: Number(d.product_id), pcs: d.pcs })),
                paid,
                cancel_reason: draft.cancel_reason || '',
            };
        }

        async function saveStop(paid, btn) {
            const res = await withBusy(btn, 'সংরক্ষণ হচ্ছে…', () => dsrApi('POST', `/dsr/stops/${draft.id}`, payload(paid), {
                label: `ডেলিভারি · ${draft.retailer_name}`,
                apply: ((local) => () => { localSaveStop(local, paid); return {}; })(clone(draft)),
            }));
            applyState(res);
            return res;
        }

        $('cancelReasonForm')?.addEventListener('submit', async (e) => {
            e.preventDefault();
            if (!draft || !pendingCancel) return;
            const chosen = e.currentTarget.querySelector('input[name="cancel_reason"]:checked')?.value;
            const note = $('cancelNoteInput').value.trim();
            if (!chosen || (chosen === 'Other' && !note)) {
                $('cancelReasonError').textContent = chosen ? '"অন্যান্য" কারণের জন্য একটি নোট লিখুন।' : 'অনুগ্রহ করে বাতিলের একটি কারণ বাছুন।';
                $('cancelReasonError').hidden = false;
                return;
            }
            draft.cancel_reason = note ? `${chosen} (${note})` : chosen;
            if (pendingCancel.type === 'company') {
                const comp = draft.companies.find((c) => c.id === pendingCancel.id);
                if (comp) {
                    comp.cancelled = true;
                    comp.items.forEach((it) => { it.qty = 0; });
                    draft.damages = draft.damages.filter((d) => String(d.order_id) !== comp.id);
                }
                closeModal('cancelReasonModal');
                renderStop();
                return;
            }
            draft.companies.forEach((c) => {
                if (c.ready_sale) return;
                c.cancelled = true;
                c.items.forEach((it) => { it.qty = 0; });
            });
            draft.damages = [];
            try {
                await saveStop(0, $('confirmCancelOrderBtn'));
                closeModal('cancelReasonModal');
                showToast(`অর্ডার বাতিল করা হয়েছে: ${bnReason(chosen)}`);
            } catch (err) {
                $('cancelReasonError').textContent = err.message;
                $('cancelReasonError').hidden = false;
            }
        });

        // Payment dialog
        function payNumbers() {
            const m = computeOrderMetrics(draft);
            const oldDue = Number(draft.existing_due || 0);
            const cap = round2(m.shouldPay + oldDue);
            let paid = Math.max(0, Number(payAmountInput.value || 0));
            if (paid > cap) { paid = cap; payAmountInput.value = String(cap); }
            paid = round2(paid);
            const forBill = Math.min(paid, m.shouldPay);
            return { m, oldDue, cap, paid, oldCollected: round2(paid - forBill), due: round2(m.shouldPay - forBill) };
        }

        function updatePaymentLiveDisplay() {
            if (!draft) return;
            const n = payNumbers();
            $('payShouldPayVal').textContent = formatBdt(n.m.shouldPay);
            $('payPaidVal').textContent = formatBdt(n.paid);
            $('payDueVal').textContent = formatBdt(n.due);
            $('payOldDueRow').hidden = n.oldCollected <= 0;
            $('payOldDueVal').textContent = formatBdt(n.oldCollected);
            const hint = $('payStatusHint');
            if (n.due > 0) hint.textContent = `বিলের চেয়ে কম পরিশোধ → ${formatBdt(n.due)} দোকানের বকেয়া থাকবে।`;
            else if (n.oldCollected > 0) hint.textContent = `বিল সম্পূর্ণ পরিশোধ + আগের বকেয়া ${formatBdt(n.oldCollected)} আদায় হয়েছে।`;
            else hint.textContent = 'সম্পূর্ণ পরিশোধ → অবস্থা "ডেলিভার্ড" হবে।';
        }

        doOpenPayBtn?.addEventListener('click', () => {
            if (!draft) return;
            const m = computeOrderMetrics(draft);
            const oldDue = Number(draft.existing_due || 0);
            $('payRetailerSubtitle').textContent = draft.retailer_name;
            $('payCapHint').textContent = `সর্বোচ্চ: ${formatBdt(m.shouldPay + oldDue)}${oldDue > 0 ? ` (বিল + আগের বকেয়া ${formatBdt(oldDue)})` : ''}`;
            $('payExistingDueBox').hidden = !(oldDue > 0);
            $('payExistingDueVal').textContent = formatBdt(oldDue);
            payAmountInput.max = String(round2(m.shouldPay + oldDue));
            payAmountInput.value = draft.status !== 'Pending'
                ? String(round2(Number(draft.paid_amount || 0) + Number(draft.old_due_collected || 0)))
                : String(m.shouldPay);
            updatePaymentLiveDisplay();
            openModal('paymentModal');
        });
        payAmountInput?.addEventListener('input', updatePaymentLiveDisplay);
        $('payZeroBtn')?.addEventListener('click', () => { payAmountInput.value = '0'; updatePaymentLiveDisplay(); });
        $('payFullBtn')?.addEventListener('click', () => { payAmountInput.value = String(computeOrderMetrics(draft).shouldPay); updatePaymentLiveDisplay(); });

        $('paymentForm')?.addEventListener('submit', async (e) => {
            e.preventDefault();
            if (!draft) return;
            const n = payNumbers();
            try {
                await saveStop(n.paid, $('confirmPayBtn'));
                closeAllModals({ syncHistory: true });
                showToast(`সংরক্ষিত: পরিশোধ ${formatBdt(n.paid)}${n.due > 0 ? `, বকেয়া ${formatBdt(n.due)}` : ''}${n.oldCollected > 0 ? ` (আগের বকেয়া ${formatBdt(n.oldCollected)})` : ''}`);
            } catch (err) {
                $('payStatusHint').textContent = err.message;
            }
        });

        // ----------------------------------------------------------- ready sale studio (2-step + Banglish search + multi-product cart)
        const rsRetKey = (r) => `${r.name} ${r.address || ''} ${r.phone || ''}`;
        const rsProdKey = (p) => `${p.name} ${p.company || ''} ${p.code || ''}`;
        let rsSyncPromise = null;
        let rsSyncing = false;

        function syncDsrRetailers() {
            if (rsSyncPromise) return rsSyncPromise;
            rsSyncing = true;
            const chip = $('rsRetSyncChip');
            if (chip) chip.hidden = false;
            rsSyncPromise = dsrApi('GET', '/dsr/retailers')
                .then((res) => {
                    if (Array.isArray(res?.retailers)) {
                        const map = new Map(res.retailers.map((r) => [String(r.id), r]));
                        retailers.forEach((ex) => { if (!map.has(String(ex.id))) map.set(String(ex.id), ex); });
                        retailers = Array.from(map.values());
                        dsrStore.retailers = retailers;
                        dsrStore.retailersSynced = true;
                        DsrBanglish.warmup(retailers, rsRetKey);
                        if (offlineOk()) window.HbOffline.kvSet(`shops:${HB_USER}`, res.retailers);
                    }
                })
                .catch(async () => {
                    // offline: use the list saved last time
                    const saved = offlineOk() ? await window.HbOffline.kvGet(`shops:${HB_USER}`) : null;
                    if (Array.isArray(saved) && saved.length) {
                        const map = new Map(saved.map((r) => [String(r.id), r]));
                        retailers.forEach((ex) => { if (!map.has(String(ex.id))) map.set(String(ex.id), ex); });
                        retailers = Array.from(map.values());
                        dsrStore.retailers = retailers;
                        DsrBanglish.warmup(retailers, rsRetKey);
                    }
                    dsrStore.retailersSynced = true;
                })
                .finally(() => {
                    rsSyncing = false;
                    if (chip) chip.hidden = true;
                    refreshDeliveryViews();
                });
            return rsSyncPromise;
        }
        // The full shop list (~600 KB for thousands of shops) is only needed by ready sale: fetched when it is opened.

        const rsCart = new Map(); // product_id -> pcs
        let rsMode = 'existing';
        let rsShopView = 'list'; // 'list' | 'map'
        let rsStep = 1; // 1 = Shop, 2 = Products, 3 = Receipt
        let rsSelectedRetailer = null; // existing retailer object
        let rsNewShopDraft = null; // { name, phone, address, lat, lng }
        let rsNewPin = null; // { lat, lng, isCustom }
        let rsRetLayer = null;
        let rsNewPinMarker = null;
        let rsMapPreviewRet = null;
        let rsViewMode = 'grid';
        let rsSearchTimer = null;
        let rsSearchSeq = 0;
        let rsProdTimer = null;
        let rsProdSeq = 0;
        let rsRetMatches = [];
        let rsRetVisible = 120;

        function rsUnitWord(unitType) {
            const map = { Carton: 'কার্টন', Case: 'কেস', Box: 'বক্স', Pack: 'প্যাক', Dozen: 'ডজন', Sack: 'বস্তা', Bag: 'ব্যাগ', Piece: 'পিস', Unit: 'ইউনিট' };
            return map[unitType] || unitType || 'ইউনিট';
        }

        function rsMonogramUri(code, tint = '#f1f5f9') {
            const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80" viewBox="0 0 120 80"><rect width="120" height="80" fill="${tint}"/><rect x="38" y="16" width="44" height="44" rx="11" fill="#fff" stroke="#e4e7ec" stroke-width="2"/><text x="60" y="44" text-anchor="middle" font-family="system-ui,sans-serif" font-size="14" font-weight="800" fill="#0f172a">${escapeHtml(code || 'P')}</text></svg>`;
            return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;
        }

        function rsVanTotalPcs() {
            return vanStock.reduce((sum, p) => sum + Math.max(0, Number(p.available_pcs || 0)), 0);
        }

        function setRsStep(step) {
            rsStep = step;
            $('rsStepShop').hidden = step !== 1;
            $('rsStepProducts').hidden = step !== 2;
            $('rsStepSuccess').hidden = step !== 3;
            $('rsStepper').hidden = step === 3;

            const hasShop = Boolean((rsMode === 'existing' && rsSelectedRetailer) || (rsMode === 'new' && rsNewShopDraft));
            const p1 = $('rsStepPill1');
            const p2 = $('rsStepPill2');
            if (p1) {
                p1.classList.toggle('is-active', step === 1);
                p1.classList.toggle('is-done', step > 1 && hasShop);
            }
            if (p2) {
                p2.disabled = !hasShop;
                p2.classList.toggle('is-active', step === 2);
                p2.classList.toggle('is-done', step === 3);
            }
            const subEl = $('rsHeadSub');
            if (subEl) {
                if (step === 1) subEl.textContent = 'দোকান নির্বাচন বা নতুন দোকান যোগ করুন';
                else if (step === 2) subEl.textContent = 'ভ্যানের পণ্য বাছুন ও পরিমাণ দিন';
                else subEl.textContent = 'নগদ বিক্রির রসিদ';
            }
            const vanPill = $('rsVanTotalPill');
            if (vanPill) vanPill.textContent = `ভ্যান ${bnDigits(rsVanTotalPcs())} পিস`;
        }

        function updateRsNewPinCoords(lat, lng, isCustom = false) {
            rsNewPin = { lat: round6(lat), lng: round6(lng), isCustom };
            const coords = $('rsNewGpsCoords');
            const title = $('rsNewPinTitle');
            if (coords) {
                coords.textContent = `${bnDigits(rsNewPin.lat.toFixed(5))}, ${bnDigits(rsNewPin.lng.toFixed(5))}${isCustom ? ' · কাস্টম পিন' : ' · GPS'}`;
            }
            if (title) title.textContent = isCustom ? 'কাস্টম লোকেশন পিন সেট হয়েছে' : 'ম্যাপে দোকানের পিন সেট করুন';

            if (hasLeaflet && activeRsNewPinMap) {
                const pos = [rsNewPin.lat, rsNewPin.lng];
                if (!rsNewPinMarker) {
                    const pinIcon = window.L.divIcon({
                        className: 'retailer-pin-icon',
                        html: '<div class="rs-pin-picker-dot"></div>',
                        iconSize: [20, 20],
                        iconAnchor: [10, 10],
                    });
                    rsNewPinMarker = window.L.marker(pos, { icon: pinIcon, draggable: true }).addTo(activeRsNewPinMap);
                    rsNewPinMarker.on('dragend', () => {
                        const p = rsNewPinMarker.getLatLng();
                        updateRsNewPinCoords(p.lat, p.lng, true);
                    });
                } else {
                    rsNewPinMarker.setLatLng(pos);
                }
            }
        }

        function round6(v) {
            return Math.round(Number(v) * 1e6) / 1e6;
        }

        let rsNewPinRefLayer = null;

        function ensureRsNewPinMap() {
            const mapNode = $('rsNewPinMap');
            if (!mapNode) return;
            if (!rsNewPin) rsNewPin = { lat: Number(dsrLoc.lat), lng: Number(dsrLoc.lng), isCustom: false };

            if (hasLeaflet) {
                if (!activeRsNewPinMap) {
                    activeRsNewPinMap = window.L.map(mapNode, {
                        center: [rsNewPin.lat, rsNewPin.lng],
                        zoom: 18,
                        maxZoom: 22,
                        zoomControl: false,
                    });
                    window.L.control.zoom({ position: 'topright' }).addTo(activeRsNewPinMap);
                    attachDsrTiles(activeRsNewPinMap);
                    rsNewPinRefLayer = window.L.layerGroup().addTo(activeRsNewPinMap);
                    activeRsNewPinMap.on('click', (e) => {
                        updateRsNewPinCoords(e.latlng.lat, e.latlng.lng, true);
                    });
                    rsNewPinMarker = null;
                }
                if (rsNewPinRefLayer) {
                    rsNewPinRefLayer.clearLayers();
                    window.L.circle([dsrLoc.lat, dsrLoc.lng], {
                        radius: 100,
                        color: '#1d4ed8',
                        weight: 1.5,
                        dashArray: '4 4',
                        opacity: 0.65,
                        fillColor: '#1d4ed8',
                        fillOpacity: 0.06,
                    }).addTo(rsNewPinRefLayer);
                    retailers.forEach((r) => {
                        const lat = Number(r.lat);
                        const lng = Number(r.lng);
                        if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
                        if (haversineMeters(dsrLoc.lat, dsrLoc.lng, lat, lng) > 100) return;
                        window.L.circleMarker([lat, lng], {
                            radius: 5,
                            color: '#ffffff',
                            weight: 1.5,
                            fillColor: '#64748b',
                            fillOpacity: 0.85,
                        }).bindTooltip(escapeHtml(r.name), { direction: 'top' }).addTo(rsNewPinRefLayer);
                    });
                }
                updateRsNewPinCoords(rsNewPin.lat, rsNewPin.lng, rsNewPin.isCustom);
                setTimeout(() => {
                    activeRsNewPinMap?.invalidateSize(false);
                    activeRsNewPinMap?.setView([rsNewPin.lat, rsNewPin.lng], Math.max(17, activeRsNewPinMap.getZoom() || 18));
                }, 90);
            } else {
                mapNode.innerHTML = `<div class="fallback-map" id="rsNewPinFallback" style="cursor:crosshair;"><div class="fallback-map-note">অফলাইন ম্যাপ — ট্যাপ করে পিন সরান</div><div class="fallback-sr-pin" style="left:50%;top:50%"><div class="rs-pin-picker-dot"></div></div></div>`;
                const span = 0.002;
                $('rsNewPinFallback')?.addEventListener('click', (e) => {
                    const rect = e.currentTarget.getBoundingClientRect();
                    const px = (e.clientX - rect.left) / rect.width;
                    const py = (e.clientY - rect.top) / rect.height;
                    updateRsNewPinCoords(
                        dsrLoc.lat - (py - 0.5) * span * 2,
                        dsrLoc.lng + (px - 0.5) * span * 2,
                        true
                    );
                });
            }
        }

        function setRsMode(mode) {
            rsMode = mode;
            document.querySelectorAll('[data-rs-mode]').forEach((b) => {
                const active = b.getAttribute('data-rs-mode') === mode;
                b.classList.toggle('is-active', active);
                b.setAttribute('aria-selected', active ? 'true' : 'false');
            });
            $('rsExistingGroup').hidden = mode !== 'existing';
            $('rsNewGroup').hidden = mode !== 'new';
            if (mode === 'new') {
                if (!rsNewPin) rsNewPin = { lat: Number(dsrLoc.lat), lng: Number(dsrLoc.lng), isCustom: false };
                $('rsNewShopError').hidden = true;
                ensureRsNewPinMap();
            }
        }
        document.querySelectorAll('[data-rs-mode]').forEach((b) => b.addEventListener('click', () => setRsMode(b.getAttribute('data-rs-mode'))));

        function rsLoadingMarkup(label) {
            const skRows = Array.from({ length: 4 }, (_, i) => `
                <div class="rs-sk-card">
                    <span class="rs-sk" style="width:${[62, 54, 72, 48][i]}%"></span>
                    <span class="rs-sk" style="width:${[42, 48, 38, 45][i]}%;height:9px"></span>
                </div>
            `).join('');
            return `
                <div class="rs-load-box">
                    <div class="rs-load-bar"><span></span></div>
                    <div class="rs-load-label">
                        <span class="rs-spinner" aria-hidden="true"></span>
                        <span>${escapeHtml(label)}</span>
                    </div>
                    ${skRows}
                </div>
            `;
        }

        function showRsMapPreview(r) {
            rsMapPreviewRet = r;
            const card = $('rsMapSelectedCard');
            if (!card) return;
            if (!r) { card.hidden = true; return; }
            const dist = haversineMeters(dsrLoc.lat, dsrLoc.lng, Number(r.lat), Number(r.lng));
            if ($('rsMapSelName')) $('rsMapSelName').textContent = r.name;
            if ($('rsMapSelSub')) $('rsMapSelSub').textContent = `${r.address || r.phone || 'অবস্থান পিনকৃত'} · ${formatDistance(dist)}`;
            card.hidden = false;
        }

        function ensureRsRetMap() {
            const mapNode = $('rsRetailerMap');
            if (!mapNode || !hasLeaflet) return false;
            if (!activeRsRetMap) {
                activeRsRetMap = window.L.map(mapNode, {
                    center: [dsrLoc.lat, dsrLoc.lng],
                    zoom: 16,
                    maxZoom: 22,
                    zoomControl: false,
                });
                window.L.control.zoom({ position: 'topright' }).addTo(activeRsRetMap);
                attachDsrTiles(activeRsRetMap);
                rsRetLayer = window.L.layerGroup().addTo(activeRsRetMap);
            }
            return true;
        }

        const RS_MAP_RADIUS_M = 100;

        function renderRsRetailerMap(rawQ, list) {
            const wrap = $('rsRetailerMapWrap');
            const mapNode = $('rsRetailerMap');
            if (!wrap || wrap.hidden || !mapNode) return;

            const orderedIds = new Set(stops.map((s) => String(s.retailer_id ?? s.id)));
            // Show ALL retailers inside 100m when browsing map; show all keyword matches when searching
            const pins = rawQ
                ? list.slice(0, 220)
                : list.filter((r) => Number(r.distance ?? haversineMeters(dsrLoc.lat, dsrLoc.lng, Number(r.lat), Number(r.lng))) <= RS_MAP_RADIUS_M);

            const labelEl = $('rsRetListLabel');
            if (labelEl) {
                labelEl.textContent = rawQ
                    ? `খোঁজার ফলাফল · ${bnDigits(list.length)}টি দোকান`
                    : `১০০ মি. এর মধ্যে সব দোকান (${bnDigits(pins.length)}টি)`;
            }

            if (!ensureRsRetMap() || !rsRetLayer) {
                mapNode.innerHTML = `<div class="fallback-map"><div class="fallback-map-note">অফলাইন ম্যাপ · ১০০ মি. (${bnDigits(pins.length)}টি দোকান)</div></div>`;
                return;
            }

            rsRetLayer.clearLayers();

            // 100m radius circle around DSR current GPS location
            const radiusCircle = window.L.circle([dsrLoc.lat, dsrLoc.lng], {
                radius: RS_MAP_RADIUS_M,
                color: '#1d4ed8',
                weight: 2,
                opacity: 0.8,
                fillColor: '#1d4ed8',
                fillOpacity: 0.1,
            }).addTo(rsRetLayer);

            // DSR GPS dot
            const rsPhoto = app.dataset.dsrPhoto || '';
            const srIcon = rsPhoto
                ? window.L.divIcon({ className: 'photo-pin-icon', html: `<div class="photo-pin" title="আপনার অবস্থান (১০০ মি.)"><img src="${escapeHtml(rsPhoto)}" alt=""></div>`, iconSize: [46, 56], iconAnchor: [23, 56] })
                : window.L.divIcon({
                    className: 'retailer-pin-icon',
                    html: '<div class="sr-pin-dot" title="আপনার অবস্থান (১০০ মি.)"></div>',
                    iconSize: [14, 14],
                    iconAnchor: [7, 7],
                });
            window.L.marker([dsrLoc.lat, dsrLoc.lng], { icon: srIcon, zIndexOffset: 300 }).addTo(rsRetLayer);

            const coords = [];
            pins.forEach((r) => {
                const lat = Number(r.lat);
                const lng = Number(r.lng);
                if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return;
                const isSel = rsMapPreviewRet && String(rsMapPreviewRet.id) === String(r.id);
                const cls = isSel ? 'is-pending' : (orderedIds.has(String(r.id)) ? 'is-delivered' : 'is-other');
                const icon = window.L.divIcon({
                    className: 'retailer-pin-icon',
                    html: `<div class="retailer-pin-wrap ${cls}"><span class="retailer-pin-label"><span class="pin-status-dot"></span><span>${escapeHtml(r.name)}</span></span><span class="retailer-pin-dot"></span></div>`,
                    iconSize: [0, 0],
                    iconAnchor: [0, 0],
                });
                const marker = window.L.marker([lat, lng], { icon, title: r.name, zIndexOffset: isSel ? 250 : 100 }).addTo(rsRetLayer);
                marker.on('click', () => {
                    showRsMapPreview(r);
                    activeRsRetMap?.panTo([lat, lng], { animate: true });
                });
                if (Math.abs(lat - dsrLoc.lat) < 5 && Math.abs(lng - dsrLoc.lng) < 5) coords.push([lat, lng]);
            });

            activeRsRetMap.invalidateSize(false);
            if (rawQ && coords.length === 1) {
                activeRsRetMap.setView(coords[0], 18, { animate: true });
            } else if (rawQ && coords.length > 1) {
                activeRsRetMap.fitBounds(window.L.latLngBounds(coords), { padding: [36, 36], maxZoom: 18, animate: true });
            } else {
                activeRsRetMap.fitBounds(radiusCircle.getBounds(), { padding: [22, 22], maxZoom: 18 });
            }
        }

        function setRsShopView(view) {
            rsShopView = view;
            $('rsShopViewListBtn')?.classList.toggle('is-active', view === 'list');
            $('rsShopViewMapBtn')?.classList.toggle('is-active', view === 'map');
            if ($('rsRetailerResults')) $('rsRetailerResults').hidden = view !== 'list';
            if ($('rsRetailerMapWrap')) $('rsRetailerMapWrap').hidden = view !== 'map';
            const rawQ = ($('rsRetailerSearch')?.value || '').trim();
            if (view === 'map') {
                setTimeout(() => {
                    activeRsRetMap?.invalidateSize(false);
                    renderRsRetailerMap(rawQ, rsRetMatches);
                }, 60);
            } else if ($('rsRetListLabel')) {
                $('rsRetListLabel').textContent = rawQ
                    ? `খোঁজার ফলাফল · ${bnDigits(rsRetMatches.length)}টি দোকান`
                    : `কাছের দোকান (${bnDigits(Math.min(rsRetMatches.length, 30))}টি আগে)`;
            }
        }

        function paintRsRetailerList(rawQ, list, { append = false } = {}) {
            const box = $('rsRetailerResults');
            const labelEl = $('rsRetListLabel');
            if (labelEl) {
                labelEl.textContent = rawQ
                    ? `খোঁজার ফলাফল · ${bnDigits(list.length)}টি দোকান`
                    : `কাছের দোকান (${bnDigits(Math.min(list.length, 30))}টি আগে)`;
            }

            if (rsShopView === 'map') {
                renderRsRetailerMap(rawQ, list);
            }
            if (!box) return;

            if (list.length === 0) {
                box.innerHTML = `<div class="muted small" style="padding:18px 8px;text-align:center;">${rawQ ? `"${escapeHtml(rawQ)}" নামে কোনো দোকান পাওয়া যায়নি। নতুন দোকান ট্যাবে যোগ করতে পারেন।` : 'কোনো দোকান পাওয়া যায়নি।'}</div>`;
                return;
            }

            const orderedIds = new Set(stops.map((s) => String(s.retailer_id ?? s.id)));
            const cap = rawQ ? rsRetVisible : Math.min(list.length, 35);
            const shown = list.slice(0, cap);
            const remaining = rawQ ? (list.length - shown.length) : 0;

            const html = shown.map((r) => {
                const isSelected = rsSelectedRetailer && String(rsSelectedRetailer.id) === String(r.id);
                const sub = escapeHtml(r.address || r.phone || 'অবস্থান পিনকৃত');
                const inTrip = orderedIds.has(String(r.id));
                const dueTxt = Number(r.due || 0) > 0 ? ` · বকেয়া ${formatBdt(r.due)}` : '';
                return `
                    <button type="button" class="rs-shop-card ${isSelected ? 'is-selected' : ''}" data-rs-pick-shop="${escapeHtml(r.id)}">
                        <div class="rs-shop-card-main">
                            <div class="rs-shop-name">${rawQ ? DsrBanglish.highlight(r.name, rawQ) : escapeHtml(r.name)}</div>
                            <div class="rs-shop-sub tabular">${sub} · ${escapeHtml(formatDistance(r.distance))}${dueTxt}</div>
                        </div>
                        <div class="rs-shop-right">
                            ${inTrip ? '<span class="badge badge-info">ট্রিপে আছে</span>' : ''}
                            <span class="rs-pick-tag">বাছুন →</span>
                        </div>
                    </button>
                `;
            }).join('') + (remaining > 0 ? `<button type="button" class="rs-more-shops-btn" id="rsMoreShopsBtn">আরো ${bnDigits(remaining)}টি দোকান দেখুন</button>` : '');

            const prevScroll = append ? box.scrollTop : 0;
            box.innerHTML = html;
            if (append) box.scrollTop = prevScroll;
        }

        function triggerRsRetailerSearch({ immediate = false } = {}) {
            const input = $('rsRetailerSearch');
            const spinner = $('rsRetSpinner');
            const clearBtn = $('rsRetClearBtn');
            const box = $('rsRetailerResults');
            const rawQ = (input?.value || '').trim();
            if (clearBtn) clearBtn.hidden = rawQ === '';

            if (rsSearchTimer) { clearTimeout(rsSearchTimer); rsSearchTimer = null; }
            const seq = ++rsSearchSeq;

            if (!rawQ) {
                if (spinner) spinner.hidden = true;
                if (rsSyncing && !dsrStore.retailersSynced) {
                    if (box) box.innerHTML = rsLoadingMarkup('দোকান তালিকা লোড হচ্ছে…');
                    rsSyncPromise?.finally(() => { if (seq === rsSearchSeq && !(input?.value || '').trim()) triggerRsRetailerSearch({ immediate: true }); });
                    return;
                }
                const near = retailers
                    .map((r) => ({ ...r, distance: haversineMeters(dsrLoc.lat, dsrLoc.lng, Number(r.lat), Number(r.lng)) }))
                    .sort((a, b) => a.distance - b.distance);
                rsRetMatches = near;
                paintRsRetailerList('', near);
                return;
            }

            rsRetVisible = 120;
            if (spinner) spinner.hidden = false;
            if (box) box.innerHTML = rsLoadingMarkup(rsSyncing ? 'সকল দোকানের তথ্য লোড হচ্ছে…' : 'খোঁজা হচ্ছে…');

            const started = performance.now();
            rsSearchTimer = setTimeout(async () => {
                if (rsSyncPromise && !dsrStore.retailersSynced) await rsSyncPromise;
                const elapsed = performance.now() - started;
                if (!immediate && elapsed < 170) await sleep(170 - elapsed);
                if (seq !== rsSearchSeq) return;

                const curQ = (input?.value || '').trim();
                const qTokens = DsrBanglish.compileQuery(curQ);
                const matches = qTokens
                    ? retailers
                        .map((r) => ({
                            ...r,
                            _s: DsrBanglish.score(DsrBanglish.getIndexed(r, rsRetKey(r)), qTokens),
                            distance: haversineMeters(dsrLoc.lat, dsrLoc.lng, Number(r.lat), Number(r.lng)),
                        }))
                        .filter((r) => r._s > 0)
                        .sort((a, b) => (Math.floor(b._s / 10) - Math.floor(a._s / 10)) || (b._s - a._s) || (Number(b.id) - Number(a.id)))
                    : [];

                if (spinner) spinner.hidden = true;
                rsRetMatches = matches;
                paintRsRetailerList(curQ, matches);
            }, immediate ? 25 : 140);
        }

        function enterRsProductsStep() {
            const avatar = $('rsChosenAvatar');
            const nameEl = $('rsChosenShopName');
            const subEl = $('rsChosenShopSub');
            if (rsMode === 'existing' && rsSelectedRetailer) {
                const dist = haversineMeters(dsrLoc.lat, dsrLoc.lng, Number(rsSelectedRetailer.lat), Number(rsSelectedRetailer.lng));
                if (avatar) avatar.textContent = (rsSelectedRetailer.name || 'দ').slice(0, 1);
                if (nameEl) nameEl.textContent = rsSelectedRetailer.name;
                if (subEl) subEl.textContent = `${rsSelectedRetailer.address || rsSelectedRetailer.phone || 'নির্বাচিত দোকান'} · ${formatDistance(dist)}`;
            } else if (rsMode === 'new' && rsNewShopDraft) {
                if (avatar) avatar.textContent = (rsNewShopDraft.name || '+').slice(0, 1);
                if (nameEl) nameEl.textContent = `${rsNewShopDraft.name} (নতুন দোকান)`;
                if (subEl) subEl.textContent = `${rsNewShopDraft.address || 'বর্তমান জিপিএস অবস্থান'}${rsNewShopDraft.phone ? ` · ${rsNewShopDraft.phone}` : ''}`;
            }
            $('rsError').hidden = true;
            $('rsCartDrawer').hidden = true;
            setRsStep(2);
            renderRsProducts();
            renderRsCartDock();
        }

        function renderRsProducts(queryText = ($('rsProductSearch')?.value || '').trim()) {
            const grid = $('rsProductsGrid');
            if (!grid) return;
            grid.classList.toggle('is-list-view', rsViewMode === 'list');

            const avail = vanStock.filter((p) => Number(p.available_pcs || 0) > 0);
            if (avail.length === 0) {
                grid.innerHTML = '<div class="muted small" style="grid-column:span 2;padding:24px 8px;text-align:center;">ভ্যানে কোনো বিক্রয়যোগ্য পণ্য বাকি নেই।</div>';
                return;
            }

            const qTokens = queryText ? DsrBanglish.compileQuery(queryText) : null;
            const list = qTokens
                ? avail
                    .map((p) => ({ p, s: DsrBanglish.score(DsrBanglish.getIndexed(p, rsProdKey(p)), qTokens) }))
                    .filter((x) => x.s > 0)
                    .sort((a, b) => (Math.floor(b.s / 10) - Math.floor(a.s / 10)) || (Number(b.p.id) - Number(a.p.id)))
                    .map((x) => x.p)
                : avail;

            if (list.length === 0) {
                grid.innerHTML = '<div class="muted small" style="grid-column:span 2;padding:24px 8px;text-align:center;">মিলে যাওয়া কোনো পণ্য ভ্যানে পাওয়া যায়নি।</div>';
                return;
            }

            grid.innerHTML = list.map((p) => {
                const pid = String(p.id);
                const qty = Math.max(0, Number(rsCart.get(pid) || 0));
                const qpu = Math.max(1, Number(p.qty_per_unit || 1));
                const unitName = rsUnitWord(p.unit_type);
                const imgSrc = p.image || rsMonogramUri(p.code, p.tint || '#f8fafc');
                const subTotal = round2(qty * Number(p.base_rate || 0));

                const actionsHtml = qty > 0
                    ? `
                        <div class="rs-stepper-row">
                            <button type="button" class="rs-step-btn" data-rs-dec="${escapeHtml(pid)}" aria-label="কমান">−</button>
                            <input type="number" class="rs-qty-box tabular" min="0" max="${p.available_pcs}" value="${qty}" data-rs-qty-input="${escapeHtml(pid)}" aria-label="পরিমাণ (পিস)">
                            <button type="button" class="rs-step-btn" data-rs-inc="${escapeHtml(pid)}" aria-label="বাড়ান">+</button>
                        </div>
                        <div class="rs-card-subtotal tabular">মোট ${formatBdt(subTotal)}</div>
                    `
                    : `
                        <button type="button" class="rs-add-btn" data-rs-add="${escapeHtml(pid)}">+ যোগ করুন</button>
                        ${qpu > 1 && p.available_pcs >= qpu ? `<button type="button" class="rs-unit-chip-btn" data-rs-add-unit="${escapeHtml(pid)}">+১ ${escapeHtml(unitName)} (${bnDigits(qpu)} পিস)</button>` : ''}
                    `;

                return `
                    <article class="rs-prod-card ${qty > 0 ? 'is-in-cart' : ''}" data-rs-card="${escapeHtml(pid)}">
                        <div class="rs-prod-thumb" style="background:${escapeHtml(p.tint || '#f8fafc')}">
                            <img src="${escapeHtml(imgSrc)}" alt="${escapeHtml(p.name)}">
                            <span class="rs-prod-stock-badge tabular">বাকি ${bnDigits(p.available_pcs)}</span>
                        </div>
                        <div class="rs-prod-body">
                            <span class="rs-prod-comp">${escapeHtml(p.company)}</span>
                            <div class="rs-prod-name">${queryText ? DsrBanglish.highlight(p.name, queryText) : escapeHtml(p.name)}</div>
                            <div class="rs-prod-rate tabular">${formatBdt(p.base_rate)} <span class="muted small">/পিস</span></div>
                            ${qpu > 1 ? `<div class="rs-prod-unit-note tabular">১ ${escapeHtml(unitName)} = ${bnDigits(qpu)} পিস</div>` : ''}
                            <div class="rs-prod-actions">${actionsHtml}</div>
                        </div>
                    </article>
                `;
            }).join('');
        }

        function setRsCartQty(pid, nextQty) {
            const p = vanStock.find((x) => String(x.id) === String(pid));
            if (!p) return;
            const max = Math.max(0, Number(p.available_pcs || 0));
            const clamped = Math.max(0, Math.min(max, Math.floor(Number(nextQty) || 0)));
            if (clamped > max) showToast(`ভ্যানে মাত্র ${bnDigits(max)} পিস আছে।`);
            if (clamped <= 0) rsCart.delete(String(pid));
            else rsCart.set(String(pid), clamped);
            renderRsProducts();
            renderRsCartDock();
        }

        function renderRsCartDock() {
            let count = 0;
            let totalPcs = 0;
            let totalAmt = 0;
            const rows = [];

            rsCart.forEach((pcs, pid) => {
                const p = vanStock.find((x) => String(x.id) === String(pid));
                if (!p || pcs <= 0) return;
                count++;
                totalPcs += pcs;
                const lineTotal = round2(pcs * Number(p.base_rate || 0));
                totalAmt = round2(totalAmt + lineTotal);
                rows.push(`
                    <div class="rs-drawer-row">
                        <span style="min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${escapeHtml(p.name)} · <strong class="tabular">${bnDigits(pcs)} পিস</strong></span>
                        <div style="display:flex;align-items:center;gap:8px;flex-shrink:0;">
                            <strong class="tabular">${formatBdt(lineTotal)}</strong>
                            <button type="button" class="lot-row-remove" data-rs-rm="${escapeHtml(pid)}" aria-label="সরান">&times;</button>
                        </div>
                    </div>
                `);
            });

            if ($('rsCartBadge')) $('rsCartBadge').textContent = `${bnDigits(count)}টি পণ্য · ${bnDigits(totalPcs)} পিস`;
            if ($('rsTotalAmount')) $('rsTotalAmount').textContent = formatBdt(totalAmt);
            if ($('rsDrawerCount')) $('rsDrawerCount').textContent = bnDigits(count);
            if ($('rsCartDrawerList')) $('rsCartDrawerList').innerHTML = rows.join('');
            if ($('rsToggleDrawerBtn')) $('rsToggleDrawerBtn').disabled = count === 0;
            if ($('rsSubmitBtn')) $('rsSubmitBtn').disabled = count === 0;
            if (count === 0 && $('rsCartDrawer')) $('rsCartDrawer').hidden = true;
        }

        function resetAndOpenReadySale(preselectedRetailerId = null) {
            rsCart.clear();
            rsSelectedRetailer = preselectedRetailerId
                ? (retailers.find((r) => String(r.id) === String(preselectedRetailerId)) || null)
                : null;
            rsNewShopDraft = null;
            rsNewPin = { lat: Number(dsrLoc.lat), lng: Number(dsrLoc.lng), isCustom: false };
            rsMapPreviewRet = null;
            if ($('rsMapSelectedCard')) $('rsMapSelectedCard').hidden = true;
            $('rsNewPinMap')?.classList.remove('is-expanded');
            if ($('rsNewPinExpandBtn')) $('rsNewPinExpandBtn').textContent = 'বড় ম্যাপ';
            $('rsError').hidden = true;
            $('rsNewShopError').hidden = true;
            ['rsShopName', 'rsShopPhone', 'rsShopAddress', 'rsRetailerSearch', 'rsProductSearch'].forEach((id) => {
                if ($(id)) $(id).value = '';
            });
            if ($('rsRetClearBtn')) $('rsRetClearBtn').hidden = true;
            if ($('rsProdClearBtn')) $('rsProdClearBtn').hidden = true;
            if ($('rsRetSpinner')) $('rsRetSpinner').hidden = true;
            if ($('rsProdSpinner')) $('rsProdSpinner').hidden = true;

            syncDsrRetailers();
            setRsShopView('list');
            setRsMode('existing');
            openModal('readySaleModal');

            if (rsSelectedRetailer) {
                enterRsProductsStep();
            } else {
                setRsStep(1);
                triggerRsRetailerSearch({ immediate: true });
            }
        }

        function openReadySaleFor(retailerId) {
            resetAndOpenReadySale(retailerId);
        }
        $('openReadySaleBtn')?.addEventListener('click', () => resetAndOpenReadySale(null));

        $('rsHeadBackBtn')?.addEventListener('click', () => {
            if (rsStep === 2) setRsStep(1);
            else closeModal('readySaleModal');
        });
        $('rsStepPill1')?.addEventListener('click', () => {
            if (rsStep !== 3) setRsStep(1);
        });
        $('rsStepPill2')?.addEventListener('click', () => {
            if (!$('rsStepPill2').disabled && rsStep !== 3) enterRsProductsStep();
        });
        $('rsChangeShopBtn')?.addEventListener('click', () => {
            setRsStep(1);
            triggerRsRetailerSearch({ immediate: true });
        });

        $('rsRetailerSearch')?.addEventListener('input', () => triggerRsRetailerSearch());
        $('rsRetailerSearch')?.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') { e.preventDefault(); triggerRsRetailerSearch({ immediate: true }); }
        });
        $('rsRetClearBtn')?.addEventListener('click', () => {
            if ($('rsRetailerSearch')) $('rsRetailerSearch').value = '';
            triggerRsRetailerSearch({ immediate: true });
            $('rsRetailerSearch')?.focus();
        });
        document.querySelectorAll('[data-rs-shop-view]').forEach((btn) => {
            btn.addEventListener('click', () => setRsShopView(btn.getAttribute('data-rs-shop-view') || 'list'));
        });
        $('rsRetMapRecenterBtn')?.addEventListener('click', () => {
            if (activeRsRetMap) activeRsRetMap.setView([dsrLoc.lat, dsrLoc.lng], 17, { animate: true });
        });
        $('rsMapPickBtn')?.addEventListener('click', () => {
            if (!rsMapPreviewRet) return;
            rsSelectedRetailer = rsMapPreviewRet;
            rsMode = 'existing';
            rsNewShopDraft = null;
            enterRsProductsStep();
        });
        $('rsNewGpsResetBtn')?.addEventListener('click', () => {
            updateRsNewPinCoords(dsrLoc.lat, dsrLoc.lng, false);
            activeRsNewPinMap?.setView([dsrLoc.lat, dsrLoc.lng], 17, { animate: true });
            showToast('বর্তমান GPS লোকেশনে পিন আনা হয়েছে।');
        });
        $('rsNewPinExpandBtn')?.addEventListener('click', () => {
            const mapNode = $('rsNewPinMap');
            if (!mapNode) return;
            const exp = mapNode.classList.toggle('is-expanded');
            if ($('rsNewPinExpandBtn')) $('rsNewPinExpandBtn').textContent = exp ? 'ছোট করুন' : 'বড় ম্যাপ';
            setTimeout(() => activeRsNewPinMap?.invalidateSize(false), 180);
        });
        $('rsRetailerResults')?.addEventListener('click', (e) => {
            if (e.target.closest('#rsMoreShopsBtn')) {
                rsRetVisible += 200;
                paintRsRetailerList(($('rsRetailerSearch')?.value || '').trim(), rsRetMatches, { append: true });
                return;
            }
            const card = e.target.closest('[data-rs-pick-shop]');
            if (!card) return;
            const id = card.getAttribute('data-rs-pick-shop');
            rsSelectedRetailer = retailers.find((r) => String(r.id) === String(id)) || null;
            if (!rsSelectedRetailer) return;
            rsMode = 'existing';
            rsNewShopDraft = null;
            enterRsProductsStep();
        });

        $('rsContinueNewShopBtn')?.addEventListener('click', () => {
            const err = $('rsNewShopError');
            err.hidden = true;
            const name = ($('rsShopName')?.value || '').trim();
            const phone = ($('rsShopPhone')?.value || '').trim();
            const address = ($('rsShopAddress')?.value || '').trim();
            if (!name) {
                err.textContent = 'নতুন দোকানের নাম লিখুন।';
                err.hidden = false;
                $('rsShopName')?.focus();
                return;
            }
            const pinLat = rsNewPin?.lat ?? dsrLoc.lat;
            const pinLng = rsNewPin?.lng ?? dsrLoc.lng;
            rsMode = 'new';
            rsSelectedRetailer = null;
            rsNewShopDraft = { name, phone, address: address || 'স্পট লোকেশন', lat: pinLat, lng: pinLng };
            enterRsProductsStep();
        });

        document.querySelectorAll('[data-rs-view]').forEach((btn) => {
            btn.addEventListener('click', () => {
                rsViewMode = btn.getAttribute('data-rs-view') || 'grid';
                document.querySelectorAll('[data-rs-view]').forEach((b) => b.classList.toggle('is-active', b === btn));
                renderRsProducts();
            });
        });

        $('rsProductSearch')?.addEventListener('input', () => {
            const val = ($('rsProductSearch')?.value || '').trim();
            if ($('rsProdClearBtn')) $('rsProdClearBtn').hidden = val === '';
            if (rsProdTimer) clearTimeout(rsProdTimer);
            const seq = ++rsProdSeq;
            if (!val) {
                if ($('rsProdSpinner')) $('rsProdSpinner').hidden = true;
                renderRsProducts('');
                return;
            }
            if ($('rsProdSpinner')) $('rsProdSpinner').hidden = false;
            rsProdTimer = setTimeout(() => {
                if (seq !== rsProdSeq) return;
                if ($('rsProdSpinner')) $('rsProdSpinner').hidden = true;
                renderRsProducts(($('rsProductSearch')?.value || '').trim());
            }, 110);
        });
        $('rsProdClearBtn')?.addEventListener('click', () => {
            if ($('rsProductSearch')) $('rsProductSearch').value = '';
            if ($('rsProdClearBtn')) $('rsProdClearBtn').hidden = true;
            if ($('rsProdSpinner')) $('rsProdSpinner').hidden = true;
            renderRsProducts('');
            $('rsProductSearch')?.focus();
        });

        $('rsProductsGrid')?.addEventListener('click', (e) => {
            const add = e.target.closest('[data-rs-add]');
            if (add) {
                const pid = add.getAttribute('data-rs-add');
                setRsCartQty(pid, (rsCart.get(pid) || 0) + 1);
                return;
            }
            const addUnit = e.target.closest('[data-rs-add-unit]');
            if (addUnit) {
                const pid = addUnit.getAttribute('data-rs-add-unit');
                const p = vanStock.find((x) => String(x.id) === String(pid));
                const qpu = Math.max(1, Number(p?.qty_per_unit || 1));
                setRsCartQty(pid, (rsCart.get(pid) || 0) + qpu);
                return;
            }
            const inc = e.target.closest('[data-rs-inc]');
            if (inc) {
                const pid = inc.getAttribute('data-rs-inc');
                setRsCartQty(pid, (rsCart.get(pid) || 0) + 1);
                return;
            }
            const dec = e.target.closest('[data-rs-dec]');
            if (dec) {
                const pid = dec.getAttribute('data-rs-dec');
                setRsCartQty(pid, (rsCart.get(pid) || 0) - 1);
            }
        });
        $('rsProductsGrid')?.addEventListener('change', (e) => {
            const inp = e.target.closest('[data-rs-qty-input]');
            if (!inp) return;
            setRsCartQty(inp.getAttribute('data-rs-qty-input'), inp.value);
        });

        $('rsToggleDrawerBtn')?.addEventListener('click', () => {
            const drawer = $('rsCartDrawer');
            if (drawer && rsCart.size > 0) drawer.hidden = !drawer.hidden;
        });
        $('rsClearCartBtn')?.addEventListener('click', () => {
            rsCart.clear();
            renderRsProducts();
            renderRsCartDock();
        });
        $('rsCartDrawerList')?.addEventListener('click', (e) => {
            const rm = e.target.closest('[data-rs-rm]');
            if (rm) setRsCartQty(rm.getAttribute('data-rs-rm'), 0);
        });

        $('rsSubmitBtn')?.addEventListener('click', async () => {
            const err = $('rsError');
            err.hidden = true;
            const items = [];
            rsCart.forEach((pcs, pid) => {
                if (pcs > 0) items.push({ product_id: Number(pid), pcs });
            });
            if (items.length === 0) {
                err.textContent = 'অন্তত ১টি পণ্য ও পরিমাণ বাছুন।';
                err.hidden = false;
                return;
            }
            const body = { mode: rsMode, items };
            if (rsMode === 'existing') {
                if (!rsSelectedRetailer) {
                    err.textContent = 'একটি দোকান নির্বাচন করুন।';
                    err.hidden = false;
                    return;
                }
                body.retailer_id = rid(rsSelectedRetailer.id);
            } else {
                if (!rsNewShopDraft?.name) {
                    setRsStep(1);
                    return;
                }
                Object.assign(body, {
                    name: rsNewShopDraft.name,
                    phone: rsNewShopDraft.phone,
                    address: rsNewShopDraft.address,
                    lat: dsrLoc.lat,
                    lng: dsrLoc.lng,
                });
            }

            try {
                const res = await withBusy($('rsSubmitBtn'), 'বিক্রি সম্পন্ন হচ্ছে…', () => {
                    const tmpId = body.mode === 'new' ? `tmp-${window.HbOffline?.uuid?.() || Date.now()}` : null;
                    return dsrApi('POST', '/dsr/ready-sales', body, {
                        label: `রেডি সেল · ${rsMode === 'new' ? body.name : (rsSelectedRetailer?.name || '')}`,
                        tmp: tmpId,
                        apply: () => localReadySale(body, tmpId),
                    });
                });
                applyState(res);
                showToast(res.message);

                const rc = res.receipt || {};
                if ($('rsReceiptMeta')) $('rsReceiptMeta').textContent = (rc.codes || []).map((c) => bnDigits(c)).join(', ');
                if ($('rsReceiptShop')) $('rsReceiptShop').textContent = rc.retailer || '';
                if ($('rsReceiptTotal')) $('rsReceiptTotal').textContent = formatBdt(rc.total || 0);
                if ($('rsReceiptItems')) {
                    $('rsReceiptItems').innerHTML = (rc.items || []).map((it) => `
                        <div class="rs-receipt-line">
                            <span>${escapeHtml(it.name)} × <strong class="tabular">${bnDigits(it.pcs)}</strong></span>
                            <strong class="tabular">${formatBdt(it.total)}</strong>
                        </div>
                    `).join('');
                }
                setRsStep(3);
            } catch (ex) {
                err.textContent = ex.message;
                err.hidden = false;
            }
        });

        $('rsAnotherSaleBtn')?.addEventListener('click', () => resetAndOpenReadySale(null));
        $('rsDoneSaleBtn')?.addEventListener('click', () => closeModal('readySaleModal'));

        // ------------------------------------------------------------------ map
        if (hasLeaflet && mapEl) {
            activeDeliveryMap = window.L.map(mapEl, { center: [dsrLoc.lat, dsrLoc.lng], zoom: 17, maxZoom: 22, zoomControl: false });
            window.L.control.zoom({ position: 'topright' }).addTo(activeDeliveryMap);
            let usedFallbackTiles = false;
            const googleTiles = window.L.tileLayer('https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}', {
                maxNativeZoom: 20, maxZoom: 22, subdomains: '0123', attribution: '&copy; Google Maps',
            }).addTo(activeDeliveryMap);
            googleTiles.on('tileerror', () => {
                if (usedFallbackTiles || !activeDeliveryMap) return;
                usedFallbackTiles = true;
                activeDeliveryMap.removeLayer(googleTiles);
                window.L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}', {
                    maxNativeZoom: 19, maxZoom: 22, attribution: '&copy; Esri',
                }).addTo(activeDeliveryMap);
            });
            leafletLayerGroup = window.L.layerGroup().addTo(activeDeliveryMap);
            const invalidate = () => activeDeliveryMap && activeDeliveryMap.invalidateSize(false);
            requestAnimationFrame(invalidate);
            setTimeout(invalidate, 180);
            setTimeout(invalidate, 450);
            if (typeof ResizeObserver !== 'undefined') {
                activeMapResizeObserver = new ResizeObserver(invalidate);
                activeMapResizeObserver.observe(mapEl);
            }
        }

        recenterBtn?.addEventListener('click', () => {
            fitAllPins();
        });

        // Live GPS for distances, the map dot and new ready-sale retailers
        if (navigator.geolocation && geoWatchId === null) {
            const geoFilter = window.HbGeoFilter.create();
            geoWatchId = navigator.geolocation.watchPosition((raw) => {
                const pos = geoFilter.push(raw);   // smoothed; null while standing still / vague fix
                if (!pos) return;
                dsrLoc.lat = pos.lat;
                dsrLoc.lng = pos.lng;
                dsrStore.gpsFix = true;
                refreshDeliveryViews();
            }, () => {
                if (!dsrStore.gpsFix) showToast('অবস্থান পাওয়া যায়নি। দূরত্ব এবং নতুন দোকান যোগ করতে লোকেশন অ্যাক্সেস চালু করুন।');
            }, { enableHighAccuracy: true, maximumAge: 0, timeout: 20000 });
        }

        refreshDeliveryViews();
        restoreOfflineState();
        pageSyncedHook = () => { if (document.body.contains(app)) refreshFromServer(); };
    }

    // =========================================================================
    // Van Stock Page (server-rendered; search only)
    // =========================================================================
    function initVanStockPage() {
        const app = document.getElementById('dsrVanStockApp');
        if (!app) return;
        const searchInput = document.getElementById('vanStockSearch');
        searchInput?.addEventListener('input', () => {
            const q = searchInput.value.trim().toLowerCase();
            app.querySelectorAll('[data-search]').forEach((el) => {
                el.style.display = (!q || (el.getAttribute('data-search') || '').includes(q)) ? '' : 'none';
            });
        });
    }

    // =========================================================================
    // Settlement Page (cash counter + submit)
    // =========================================================================
    function initSettlementPage() {
        const app = document.getElementById('dsrSettlementApp');
        if (!app) return;

        const summary = JSON.parse(app.dataset.summary || '{}');
        const netPay = Number(summary.net_pay || 0);
        const notesList = document.getElementById('cashNotesList');
        const ccTotalCash = document.getElementById('ccTotalCash');
        const ccDiffBox = document.getElementById('ccDiffBox');
        const ccDiffStatus = document.getElementById('ccDiffStatus');
        const ccDiffAmount = document.getElementById('ccDiffAmount');
        const submitBtn = document.getElementById('submitSettlementBtn');

        function readNotes() {
            const notes = {};
            let total = 0;
            notesList?.querySelectorAll('.note-row').forEach((row) => {
                const denom = Number(row.getAttribute('data-note-value') || 0);
                const qty = Math.max(0, Math.floor(Number(row.querySelector('.note-qty-input')?.value || 0)));
                notes[denom] = qty;
                total += denom * qty;
                const lineEl = row.querySelector('[data-note-line]');
                if (lineEl) lineEl.textContent = formatBdt(denom * qty);
            });
            return { notes, total };
        }

        function recalcCashCounter() {
            const { total } = readNotes();
            const diff = round2(total - netPay);
            if (ccTotalCash) ccTotalCash.textContent = formatBdt(total);
            if (ccDiffBox) {
                ccDiffBox.className = 'cc-diff-box ' + (diff < 0 ? 'is-short' : (diff > 0 ? 'is-excess' : 'is-matched'));
                ccDiffStatus.textContent = diff < 0 ? 'কম' : (diff > 0 ? 'বেশি' : 'মিলেছে');
                ccDiffAmount.textContent = formatSignedBdt(diff);
            }
        }
        recalcCashCounter();
        notesList?.addEventListener('input', recalcCashCounter);

        document.getElementById('resetCashNotesBtn')?.addEventListener('click', () => {
            if (app.dataset.locked === '1') return;
            notesList?.querySelectorAll('.note-qty-input').forEach((inp) => { inp.value = '0'; });
            recalcCashCounter();
        });
        document.getElementById('openDueDetailsBtn')?.addEventListener('click', () => openModal('dueDetailsModal'));

        submitBtn?.addEventListener('click', async () => {
            const { notes, total } = readNotes();
            const diff = round2(total - netPay);
            const msg = diff === 0
                ? `${formatBdt(total)} ক্যাশ দিয়ে সেটেলমেন্ট জমা দেবেন?`
                : `ক্যাশ ${formatBdt(Math.abs(diff))} ${diff < 0 ? 'কম' : 'বেশি'} আছে। তবুও জমা দেবেন?`;
            if (offlineOk() && (!navigator.onLine || (await window.HbOffline.count(HB_USER)) > 0)) {
                showToast('সেটেলমেন্টের আগে নেট চালু করে সব অফলাইন কাজ সিঙ্ক হতে দিন।');
                window.alert('সেটেলমেন্টের আগে নেট চালু করে সব অফলাইন কাজ সিঙ্ক হতে দিন।');
                syncOutbox();
                return;
            }
            if (!window.confirm(msg)) return;
            try {
                const note = document.getElementById('dsrSettlementNote')?.value.trim() || '';
                const res = await withBusy(submitBtn, 'জমা হচ্ছে…', () => dsrApi('POST', '/dsr/settlement', { notes, note }));
                showToast(res.message);
                await reloadCurrent();
            } catch (err) { showToast(err.message); }
        });
    }

    // =========================================================================
    // Expense Page
    // =========================================================================
    function initExpensePage() {
        const app = document.getElementById('dsrExpenseApp');
        if (!app) return;

        let expenses = JSON.parse(app.dataset.expenses || '[]');
        const catLabels = JSON.parse(app.dataset.catLabels || '{}');
        const catLabel = (c) => catLabels[c] || c;
        const locked = app.dataset.locked === '1';
        let activeCat = 'all';
        const listEl = document.getElementById('expenseListContainer');
        const form = document.getElementById('addExpenseForm');
        const errEl = document.getElementById('expFormError');

        function renderExpenses() {
            const total = expenses.reduce((s, e) => s + Number(e.amount || 0), 0);
            document.getElementById('expenseTotalValue').textContent = formatBdt(total);
            document.getElementById('expenseCountBadge').textContent = `${bnDigits(expenses.length)}টি আইটেম`;
            const items = activeCat === 'all' ? expenses : expenses.filter((e) => e.category === activeCat);
            if (!listEl) return;
            if (items.length === 0) {
                listEl.innerHTML = '<div class="muted small" style="padding:18px 0;text-align:center;">এখনো কোনো খরচ নেই।</div>';
                return;
            }
            listEl.innerHTML = items.map((ex) => `
                <div class="expense-row">
                    <div class="expense-row-main">
                        <div class="expense-row-top"><strong>${escapeHtml(ex.title)}</strong><span class="badge badge-neutral">${escapeHtml(catLabel(ex.category))}</span></div>
                        <div class="muted small">${escapeHtml(ex.time)}${ex.note ? ' · ' + escapeHtml(ex.note) : ''}</div>
                    </div>
                    <div class="expense-row-right">
                        <strong class="tabular">${formatBdt(ex.amount)}</strong>
                        ${locked ? '' : `<button type="button" class="btn-trash-sm" data-delete-expense="${ex.id}" aria-label="খরচ মুছুন">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/></svg>
                        </button>`}
                    </div>
                </div>`).join('');
        }

        const openAdd = () => {
            if (locked) return;
            errEl.hidden = true;
            form?.reset();
            openModal('addExpenseModal');
        };
        document.getElementById('openAddExpenseBtn')?.addEventListener('click', openAdd);
        document.getElementById('openAddExpenseInlineBtn')?.addEventListener('click', openAdd);

        document.getElementById('expenseFilterStrip')?.addEventListener('click', (e) => {
            const btn = e.target.closest('[data-exp-cat]');
            if (!btn) return;
            activeCat = btn.getAttribute('data-exp-cat') || 'all';
            e.currentTarget.querySelectorAll('.chip-filter').forEach((b) => b.classList.toggle('is-active', b === btn));
            renderExpenses();
        });

        listEl?.addEventListener('click', async (e) => {
            const btn = e.target.closest('[data-delete-expense]');
            if (!btn || !window.confirm('এই খরচটি মুছে ফেলবেন?')) return;
            try {
                const eid = btn.getAttribute('data-delete-expense');
                const res = await dsrApi('DELETE', `/dsr/expenses/${eid}`, undefined, {
                    label: 'খরচ মুছা',
                    apply: () => {
                        if (isTmp(eid)) throw new Error('এই খরচটি এখনো সিঙ্ক হয়নি — সিঙ্ক হওয়ার পর মুছুন।');
                        return { expenses: expenses.filter((x) => String(x.id) !== String(eid)) };
                    },
                });
                expenses = res.expenses;
                saveExpSnapshot();
                renderExpenses();
                showToast(res.message);
            } catch (err) { showToast(err.message); }
        });

        form?.addEventListener('submit', async (e) => {
            e.preventDefault();
            const body = {
                title: document.getElementById('expTitleInput').value.trim(),
                category: document.getElementById('expCategoryInput').value,
                amount: round2(Number(document.getElementById('expAmountInput').value || 0)),
                note: document.getElementById('expNoteInput').value.trim(),
            };
            if (!body.title || body.amount <= 0) {
                errEl.textContent = 'সঠিক শিরোনাম ও ধনাত্মক পরিমাণ লিখুন।';
                errEl.hidden = false;
                return;
            }
            try {
                const res = await withBusy(document.getElementById('saveExpenseBtn'), 'সংরক্ষণ হচ্ছে…', () => dsrApi('POST', '/dsr/expenses', body, {
                    label: `খরচ · ${body.title}`,
                    apply: () => {
                        const now = new Date();
                        const time = now.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
                        const date = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
                        return { expenses: [{ id: `tmp-${window.HbOffline.uuid()}`, title: body.title, category: body.category, amount: body.amount, note: body.note || null, time, date }, ...expenses] };
                    },
                }));
                expenses = res.expenses;
                saveExpSnapshot();
                closeModal('addExpenseModal');
                renderExpenses();
                showToast(res.message);
            } catch (err) {
                errEl.textContent = err.message;
                errEl.hidden = false;
            }
        });

        renderExpenses();

        function saveExpSnapshot() {
            if (offlineOk()) window.HbOffline.kvSet(`exp:${HB_USER}`, expenses);
        }
        // Opened from the offline cache or with writes still queued: show the phone's copy.
        if (offlineOk()) {
            Promise.all([window.HbOffline.kvGet(`exp:${HB_USER}`), window.HbOffline.count(HB_USER)]).then(([snap, pending]) => {
                if (Array.isArray(snap) && (app.dataset.fromCache === '1' || pending > 0)) {
                    expenses = snap;
                    renderExpenses();
                } else if (app.dataset.fromCache !== '1') {
                    saveExpSnapshot();
                }
            });
        }
        pageSyncedHook = () => { if (document.body.contains(app) && !modalStack.length) reloadCurrent(); };
    }

    function initPage() {
        pageSyncedHook = null;
        initDeliveryPage();
        initVanStockPage();
        initSettlementPage();
        initExpensePage();
    }

    // SPA Navigation
    const contentEl = document.getElementById('dsrContent');
    const appMainEl = document.getElementById('dsrAppMain');
    const pageTitleEl = document.getElementById('dsrPageTitle');
    const topbarActionsEl = document.getElementById('dsrTopbarActions');
    const progressEl = document.getElementById('spaProgress');
    let activeNavController = null;

    function syncActiveNav(pathname) {
        const clean = pathname.replace(/\/+$/, '');
        let activeKey = 'dashboard';
        if (clean.endsWith('/delivery')) activeKey = 'delivery';
        else if (clean.endsWith('/van-stock')) activeKey = 'van_stock';
        else if (clean.endsWith('/settlement')) activeKey = 'settlement';
        else if (clean.endsWith('/expense')) activeKey = 'expense';

        document.querySelectorAll('.bottom-nav-item[data-nav-key]').forEach((a) => {
            a.classList.toggle('is-active', a.getAttribute('data-nav-key') === activeKey);
        });
        if (appMainEl) appMainEl.classList.toggle('is-map-mode', activeKey === 'delivery');
    }

    async function navigateTo(href, pushHistory = true) {
        if (!contentEl) {
            window.location.href = href;
            return;
        }
        if (activeNavController) activeNavController.abort();
        activeNavController = new AbortController();

        destroyDeliveryMap();
        closeAllModals({ syncHistory: false });

        if (progressEl) {
            progressEl.classList.add('is-active');
            progressEl.style.setProperty('--spa-w', '38%');
        }
        contentEl.classList.add('is-switching');

        try {
            const res = await fetch(href, {
                headers: { 'X-Requested-With': 'XMLHttpRequest' },
                signal: activeNavController.signal,
            });
            if (!res.ok) {
                window.location.href = href;
                return;
            }
            const html = await res.text();
            const doc = new DOMParser().parseFromString(html, 'text/html');
            const newContent = doc.getElementById('dsrContent');
            if (!newContent) {
                window.location.href = href;
                return;
            }

            if (progressEl) progressEl.style.setProperty('--spa-w', '82%');
            contentEl.innerHTML = newContent.innerHTML;

            const newTitle = doc.getElementById('dsrPageTitle');
            if (newTitle && pageTitleEl) pageTitleEl.textContent = newTitle.textContent;

            const newActions = doc.getElementById('dsrTopbarActions');
            if (newActions && topbarActionsEl) topbarActionsEl.innerHTML = newActions.innerHTML;

            if (doc.title) document.title = doc.title;

            if (pushHistory) {
                history.pushState({ spa: true, url: res.url || href }, '', res.url || href);
            }
            syncActiveNav(new URL(res.url || href, window.location.origin).pathname);
            initPage();
            window.scrollTo({ top: 0, behavior: 'auto' });
        } catch (err) {
            if (err && err.name === 'AbortError') return;
            window.location.href = href;
        } finally {
            contentEl.classList.remove('is-switching');
            if (progressEl) {
                progressEl.style.setProperty('--spa-w', '100%');
                setTimeout(() => {
                    progressEl.classList.remove('is-active');
                    progressEl.style.setProperty('--spa-w', '0%');
                }, 180);
            }
        }
    }

    document.addEventListener('click', (e) => {
        const link = e.target.closest('a[href]');
        if (!link || link.target === '_blank' || link.hasAttribute('download')) return;
        if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button !== 0) return;

        let url;
        try { url = new URL(link.href, window.location.origin); } catch { return; }
        if (url.origin !== window.location.origin) return;
        if (!/\/dsr(\/|$)/.test(url.pathname)) return;

        e.preventDefault();
        if (url.href === window.location.href) {
            closeAllModals({ syncHistory: false });
            return;
        }
        navigateTo(url.href, true);
    });

    window.addEventListener('popstate', () => {
        if (ignorePopstateCount > 0) {
            ignorePopstateCount -= 1;
            return;
        }
        if (modalStack.length > 0 || document.querySelector('.modal-overlay.is-open')) {
            closeTopmostModal({ fromPopstate: true });
            return;
        }
        navigateTo(window.location.href, false);
    });

    initPage();
})();

