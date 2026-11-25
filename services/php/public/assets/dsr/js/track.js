/**
 * Location sharing (DSR → partner live map). Starts by itself as soon as any DSR page is open.
 * Points are kept on the phone (IndexedDB) and sent in batches, so a route made offline arrives later.
 * Phones stop GPS for a web page that is closed or behind a locked screen; that cannot be changed here.
 */
(() => {
    'use strict';
    const user = document.body.dataset.hbUser || '0';
    const store = window.HbOffline;
    if (user === '0' || !navigator.geolocation || !store?.available()) return;

    const base = (document.currentScript?.src || '').split('/assets/')[0];
    const key = `trk:${user}`;
    const SEND_MS = 12000;
    const STATUS_MS = 60000;
    const HEARTBEAT_S = 60;   // a point even when standing still, so the partner sees "online"
    const MAX_KEEP = 6000;

    let token = document.querySelector('meta[name="csrf-token"]')?.content || '';
    let watch = null;
    let filter = null;
    let here = null;          // last smoothed position
    let lastT = 0;
    let buf = [];
    let battery = null;
    let sending = false;

    const badge = document.createElement('div');
    badge.className = 'hb-track-badge';
    badge.hidden = true;
    badge.setAttribute('role', 'status');
    badge.innerHTML = '<i></i><span></span>';
    document.body.appendChild(badge);
    function show(text, bad) {
        badge.hidden = !text;
        badge.classList.toggle('is-bad', !!bad);
        badge.lastChild.textContent = text || '';
    }

    navigator.getBattery?.().then((b) => {
        const set = () => { battery = Math.round(b.level * 100); };
        set();
        b.addEventListener('levelchange', set);
    }).catch(() => {});

    function add(pos) {
        const t = Math.floor(Date.now() / 1000);
        if (t <= lastT) return;
        lastT = t;
        buf.push({ t, lat: +pos.lat.toFixed(7), lng: +pos.lng.toFixed(7), acc: Math.round(pos.accuracy || 0), bat: battery });
    }

    function start() {
        if (watch !== null) return;
        filter = window.HbGeoFilter.create();
        watch = navigator.geolocation.watchPosition(onFix, onErr, GEO);
    }
    const GEO = { enableHighAccuracy: true, maximumAge: 5000, timeout: 30000 };
    function onFix(raw) {
        if (watch === null) return;
        const c = raw.coords;
        const p = filter.push(raw);
        if (p) here = p;
        const quiet = Date.now() / 1000 - lastT >= HEARTBEAT_S;
        if (c.accuracy > 100) {
            // Computers have no GPS: Wi-Fi / IP location is rough (hundreds of metres or more). Still send it,
            // about once a minute, with its accuracy, so the partner sees roughly where the DSR is.
            if (quiet) add({ lat: c.latitude, lng: c.longitude, accuracy: c.accuracy });
        } else if (p) add(p);
        else if (here && quiet) add(here);
        show(''); // location is recorded silently; only a permission problem is shown
    }
    function onErr(err) {
        if (err.code === 1) show('লোকেশন বন্ধ — অনুমতি দিন', true);
    }
    /** Phones stay silent while nothing moves: ask once a minute so the partner still sees "live". */
    function heartbeat() {
        if (watch === null || document.hidden || Date.now() / 1000 - lastT < HEARTBEAT_S) return;
        navigator.geolocation.clearWatch(watch); // a fresh watch always reports the current position once
        watch = navigator.geolocation.watchPosition(onFix, onErr, GEO);
    }
    function stop() {
        if (watch !== null) navigator.geolocation.clearWatch(watch);
        watch = null;
        here = null;
        show('');
    }
    const apply = (on) => (on ? start() : stop());

    async function call(method, path, body) {
        const res = await fetch(base + path, {
            method,
            credentials: 'same-origin',
            headers: { Accept: 'application/json', 'Content-Type': 'application/json', 'X-Requested-With': 'XMLHttpRequest', 'X-CSRF-TOKEN': token },
            body: body ? JSON.stringify(body) : undefined,
        });
        return { status: res.status, data: await res.json().catch(() => ({})) };
    }

    async function status() {
        if (!navigator.onLine) return;
        try {
            const { status: s, data } = await call('GET', '/dsr/track');
            if (s !== 200) { if (s === 401) stop(); return; }
            token = data.token || token;
            apply(data.tracking);
        } catch { /* offline: keep going as we were */ }
    }

    async function flush() {
        if (sending) return;
        sending = true;
        try {
            let all = (await store.kvGet(key)) || [];
            if (buf.length) {
                all = all.concat(buf.splice(0)).slice(-MAX_KEEP);
                await store.kvSet(key, all);
            }
            while (all.length && navigator.onLine) {
                const { status: s, data } = await call('POST', '/dsr/track', { points: all.slice(0, 300) });
                if (s === 419) { await status(); break; }
                if (s !== 200) break;
                all = all.slice(300);
                await store.kvSet(key, all);
                apply(data.tracking);
            }
        } catch { /* no network: points stay on the phone */ } finally { sending = false; }
    }

    setInterval(flush, SEND_MS);
    setInterval(status, STATUS_MS);
    setInterval(heartbeat, SEND_MS);
    window.addEventListener('online', () => status().then(flush));
    document.addEventListener('visibilitychange', () => (document.visibilityState === 'visible' ? status().then(flush) : flush()));
    start();
    status();
})();
