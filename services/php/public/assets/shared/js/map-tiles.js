/**
 * Map tiles tuned for slow networks (SR / DSR maps).
 *  - loads fewer tiles around the view (keepBuffer 1) and only once movement settles;
 *  - shows a "loading" skeleton until the first tile arrives;
 *  - if no tile arrives within a few seconds (or tiles error), switches to the backup provider.
 */
(() => {
    'use strict';

    const PRIMARY = ['https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}', { maxNativeZoom: 20, subdomains: '0123', attribution: '&copy; Google Maps' }];
    const BACKUP = ['https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}', { maxNativeZoom: 17, attribution: '&copy; Esri' }];
    const COMMON = { crossOrigin: true, maxZoom: 22, keepBuffer: 1, updateWhenIdle: true, updateWhenZooming: false };
    const SLOW_MS = 10000;

    function layer([url, opts]) {
        return window.L.tileLayer(url, { ...COMMON, ...opts });
    }

    /** @param {L.Map} map  @param {HTMLElement=} el map container, gets the loading skeleton */
    function attach(map, el) {
        let current = layer(PRIMARY).addTo(map);
        let switched = false;
        let timer = null;
        const done = () => {
            clearTimeout(timer);
            el?.classList.remove('hb-map-loading');
        };
        const useBackup = () => {
            if (switched) return;
            switched = true;
            try { map.removeLayer(current); } catch { /* map already gone */ }
            current = layer(BACKUP).addTo(map);
            current.once('tileload', done);
        };

        if (navigator.onLine) el?.classList.add('hb-map-loading'); // offline: no skeleton, pins and the live position show at once
        current.once('tileload', done);
        current.on('tileerror', useBackup);
        timer = setTimeout(() => { if (el?.classList.contains('hb-map-loading')) useBackup(); }, SLOW_MS);
        // Safety: never leave the skeleton up forever.
        setTimeout(done, 20000);
    }

    // Service worker (public/sw.js): keeps tiles on the device so a place seen once never downloads again.
    if ('serviceWorker' in navigator) {
        const src = document.currentScript?.src || '';
        const base = src.split('/assets/')[0];
        if (base) navigator.serviceWorker.register(`${base}/sw.js`).catch(() => { /* needs https or localhost */ });
    }

    // ---- keep the map around the user on the device, so the map (and the moving pin on it) works without network.
    // About 160 tiles (~1 km square at street zoom), the same tiles the user would see by panning around there.
    const PF_AREAS = [[18, 4], [17, 3], [16, 2], [15, 1]]; // [zoom, tiles each side of the centre]
    const tileX = (lng, z) => Math.floor(((lng + 180) / 360) * 2 ** z);
    const tileY = (lat, z) => {
        const r = (lat * Math.PI) / 180;
        return Math.floor(((1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2) * 2 ** z);
    };
    const metres = (aLat, aLng, bLat, bLng) => {
        const k = 111320;
        return Math.hypot((aLat - bLat) * k, (aLng - bLng) * k * Math.cos((aLat * Math.PI) / 180));
    };

    function prefetch(lat, lng) {
        if (!navigator.onLine || navigator.connection?.saveData || !navigator.serviceWorker?.controller) return;
        let last = null;
        try { last = JSON.parse(localStorage.getItem('hb-tile-pf') || 'null'); } catch { /* private mode */ }
        if (last && Date.now() - last.at < 7 * 864e5 && metres(last.lat, last.lng, lat, lng) < 400) return;
        try { localStorage.setItem('hb-tile-pf', JSON.stringify({ lat, lng, at: Date.now() })); } catch { /* private mode */ }

        const urls = [];
        PF_AREAS.forEach(([z, n]) => {
            const cx = tileX(lng, z);
            const cy = tileY(lat, z);
            for (let dx = -n; dx <= n; dx++) {
                for (let dy = -n; dy <= n; dy++) {
                    const x = cx + dx;
                    const y = cy + dy;
                    urls.push(`https://mt${Math.abs(x + y) % 4}.google.com/vt/lyrs=m&x=${x}&y=${y}&z=${z}`); // same url Leaflet asks for
                }
            }
        });
        let next = 0;
        const worker = () => {
            if (next >= urls.length || !navigator.onLine) return;
            const img = new Image();
            img.crossOrigin = 'anonymous';
            img.onload = img.onerror = () => setTimeout(worker, 40);
            img.src = urls[next++];
        };
        setTimeout(() => { for (let i = 0; i < 5; i++) worker(); }, 4000); // after the map itself has loaded
    }

    window.HbMapTiles = { attach, prefetch };
})();
