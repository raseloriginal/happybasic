/**
 * GPS smoothing for the SR/DSR maps (Google-Maps-like): a 1-D Kalman filter weighted by the
 * reported accuracy. Standing still, the dot stays put (noise is averaged away and small
 * wobbles are ignored); walking or driving, it follows in real time.
 *
 *   const f = HbGeoFilter.create();
 *   const p = f.push(position);   // → { lat, lng, accuracy } when the dot should move, otherwise null
 */
(() => {
    'use strict';

    const R = 6371000;
    const dist = (a, b, c, d) => {
        const rad = Math.PI / 180;
        const dLat = (c - a) * rad;
        const dLng = (d - b) * rad;
        const h = Math.sin(dLat / 2) ** 2 + Math.cos(a * rad) * Math.cos(c * rad) * Math.sin(dLng / 2) ** 2;
        return 2 * R * Math.asin(Math.sqrt(h));
    };

    function create({ maxAccuracy = 100, idleSpeed = 0.6, minStep = 5 } = {}) {
        let lat = null;
        let lng = null;
        let variance = 0;     // m²
        let lastT = 0;
        let emitted = null;   // last position handed to the map
        let away = 0;         // consecutive fixes clearly away from the filtered position

        return {
            push(pos) {
                const c = pos.coords;
                const t = pos.timestamp || Date.now();
                const acc = Math.max(c.accuracy || 25, 5);

                if (lat === null) {
                    lat = c.latitude; lng = c.longitude; variance = acc * acc; lastT = t;
                    emitted = { lat, lng, accuracy: acc };
                    return emitted;
                }
                if (acc > maxAccuracy) return null;       // too vague to trust

                const dt = Math.max((t - lastT) / 1000, 0);
                lastT = t;
                // Assume standing still unless the device reports speed or two fixes in a row are clearly
                // away from where we think we are — then trust the new fixes (real movement).
                const far = dist(lat, lng, c.latitude, c.longitude) > 2 * acc + 12;
                away = far ? away + 1 : 0;
                if (away >= 2) { variance = Math.max(variance, 4 * acc * acc); away = 0; }
                const q = Math.max(idleSpeed, c.speed || 0);
                variance += dt * q * q;
                const k = variance / (variance + acc * acc);
                lat += k * (c.latitude - lat);
                lng += k * (c.longitude - lng);
                variance *= 1 - k;

                // Dead-band: ignore wobble smaller than the filter's own uncertainty.
                const band = Math.max(minStep, Math.sqrt(variance) * 0.6);
                if (dist(emitted.lat, emitted.lng, lat, lng) < band) return null;
                emitted = { lat, lng, accuracy: Math.sqrt(variance) };
                return emitted;
            },
        };
    }

    window.HbGeoFilter = { create };
})();
