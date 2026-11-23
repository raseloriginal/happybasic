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

        el?.classList.add('hb-map-loading');
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

    window.HbMapTiles = { attach };
})();
