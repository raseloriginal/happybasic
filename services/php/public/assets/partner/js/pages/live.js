(() => {
    'use strict';
    const H = window.HappyPartner;
    const POLL_MS = 8000;
    const COLORS = ['#2563eb', '#7c3aed', '#059669', '#ea580c', '#db2777', '#0891b2'];
    const PLAY = '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>';
    const PAUSE = '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M6 5h4v14H6zM14 5h4v14h-4z"/></svg>';

    const loadScript = (src, ready) => (ready() ? Promise.resolve() : new Promise((ok, no) => {
        const s = document.createElement('script');
        s.src = src;
        s.onload = ok;
        s.onerror = no;
        document.head.appendChild(s);
    }));

    H.registerPage(() => {
        const app = document.getElementById('liveApp');
        if (!app) return;
        const $ = (id) => document.getElementById(id);
        const esc = H.escapeHtml;
        const bn = H.bnDigits;
        const alive = () => document.body.contains(app);

        let team = JSON.parse(app.dataset.team || '[]');
        let date = app.dataset.date;
        const today = app.dataset.today;
        let selected = null;
        let route = null;
        let map = null;
        let layer = null;
        let line = null;
        let seq = 0;
        let busy = false;
        const markers = new Map();
        const isToday = () => date === today;
        const color = (id) => COLORS[Math.abs(id) % COLORS.length];

        // ------------------------------------------------------------ text
        const clock = (t) => {
            const d = new Date(t * 1000 + 6 * 3600e3); // Bangladesh time on any computer
            const h = d.getUTCHours();
            return bn(`${h % 12 || 12}:${String(d.getUTCMinutes()).padStart(2, '0')}`) + (h >= 12 ? ' PM' : ' AM');
        };
        const span = (s) => (s >= 3600 ? `${bn(Math.floor(s / 3600))} ঘ. ${bn(Math.floor((s % 3600) / 60))} মি.` : `${bn(Math.round(s / 60))} মি.`);
        const ago = (t) => {
            const s = Math.max(0, Date.now() / 1000 - t);
            return s < 60 ? 'এইমাত্র' : `${span(s)} আগে`;
        };
        const km = (m) => (m < 1000 ? `${bn(m)} মি.` : `${bn((m / 1000).toFixed(1))} কিমি`);
        const stateOf = (d) => {
            if (!isToday()) return d.t ? ['idle', `শেষ ${clock(d.t)}`] : ['off', 'এই দিনে লোকেশন নেই'];
            if (d.online) return ['on', `লাইভ · ${ago(d.t)}`];
            if (d.t) return ['idle', `শেষ দেখা ${ago(d.t)}`];
            return ['off', 'আজ অ্যাপ খোলেনি'];
        };
        const face = (d) => (d.photo ? `<img src="${esc(d.photo)}" alt="">` : esc((d.name || '?').trim().charAt(0).toUpperCase()));

        // ------------------------------------------------------------ list
        function renderTeam() {
            const on = team.filter((d) => d.online).length;
            $('lvLive').classList.toggle('is-off', !isToday() || on === 0);
            $('lvLive').lastChild.textContent = isToday() ? `${bn(on)} জন লাইভ · মোট ${bn(team.length)}` : 'রুট হিস্টোরি';
            $('lvToday').hidden = isToday();
            $('lvNext').disabled = isToday();
            $('lvTeam').innerHTML = team.length ? team.map((d) => {
                const [cls, text] = stateOf(d);
                const pct = d.shops ? Math.round((d.done / d.shops) * 100) : 0;
                return `<button type="button" class="lv-card ${selected === d.id ? 'is-sel' : ''}" data-dsr="${d.id}" style="--c:${color(d.id)}">
                    <span class="lv-face">${face(d)}<i class="is-${cls}"></i></span>
                    <span class="lv-info"><strong>${esc(d.name)}</strong><small>${esc(text)}${d.accuracy > 100 && d.t ? ` · আনুমানিক (±${d.accuracy >= 1000 ? bn((d.accuracy / 1000).toFixed(1)) + ' কিমি' : bn(d.accuracy) + ' মি.'})` : ''}</small>
                        ${d.shops ? `<span class="lv-prog"><span style="width:${pct}%"></span></span>` : ''}</span>
                    <span class="lv-side">${d.shops ? `<b class="tabular">${bn(d.done)}/${bn(d.shops)}</b><small>দোকান</small>` : ''}${d.battery !== null && isToday() ? `<small class="${d.battery <= 20 ? 'is-neg' : ''}">🔋${bn(d.battery)}%</small>` : ''}</span>
                </button>`;
            }).join('') : '<p class="lv-empty">এখনো কোনো DSR নেই।</p>';
        }

        function renderDetail() {
            const box = $('lvDetail');
            const d = team.find((x) => x.id === selected);
            box.hidden = !d;
            app.classList.toggle('has-detail', !!d);
            if (!d) return;
            if (!route) { box.innerHTML = '<div class="lv-sk"></div><div class="lv-sk"></div><div class="lv-sk"></div>'; return; }
            const items = [
                ...(d.checked_in ? [{ type: 'in', t: d.checked_in }] : []),
                ...route.stops, ...route.events,
            ].sort((a, b) => a.t - b.t);
            const label = {
                in: () => ['হাজিরা দিয়েছেন', ''],
                stop: (i) => [`থেমেছেন ${span(i.sec)}`, ''],
                delivery: (i) => [i.name, `ডেলিভারি · ${H.formatBdt(i.total)}`],
                cancel: (i) => [i.name, 'বাতিল'],
            };
            box.innerHTML = `
                <div class="lv-stats">
                    <div><small>দূরত্ব</small><b class="tabular">${km(route.distance)}</b></div>
                    <div><small>চলেছেন</small><b class="tabular">${span(route.moving)}</b></div>
                    <div><small>থেমেছেন</small><b class="tabular">${bn(route.stops.length)} বার</b></div>
                    <div><small>সময়</small><b class="tabular">${route.start ? `${clock(route.start)} – ${clock(route.end)}` : '—'}</b></div>
                </div>
                <a class="lv-call" href="tel:${esc(d.phone)}">কল করুন · ${esc(bn(d.phone))}</a>
                <ol class="lv-time">${items.length ? items.map((i, n) => {
                    const [a, b] = label[i.type](i);
                    return `<li class="is-${i.type}" ${i.lat ? `data-go="${i.lat},${i.lng}" tabindex="0"` : ''} style="animation-delay:${Math.min(n, 12) * 30}ms"><time class="tabular">${clock(i.t)}</time><span><strong>${esc(a)}</strong>${b ? `<small>${esc(b)}</small>` : ''}</span></li>`;
                }).join('') : '<li class="lv-empty">এই দিনে কোনো ঘটনা নেই।</li>'}</ol>`;
        }

        // ------------------------------------------------------------ map
        const still = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        const pad = () => (window.innerWidth > 900
            ? { paddingTopLeft: [390, 60], paddingBottomRight: [60, 100] }
            : { padding: [40, 40] });

        /** Glide the pin instead of jumping (about one poll long, so movement looks continuous). */
        function glide(m, lat, lng) {
            cancelAnimationFrame(m.hbAnim);
            const a = m.getLatLng();
            if (still || document.hidden || map.distance(a, [lat, lng]) > 3000) { m.setLatLng([lat, lng]); return; }
            const t0 = performance.now();
            const step = (now) => {
                const k = Math.min(1, (now - t0) / 2500);
                const e = k < 0.5 ? 2 * k * k : 1 - ((-2 * k + 2) ** 2) / 2;
                m.setLatLng([a.lat + (lat - a.lat) * e, a.lng + (lng - a.lng) * e]);
                if (k < 1) m.hbAnim = requestAnimationFrame(step);
            };
            m.hbAnim = requestAnimationFrame(step);
        }

        const rings = new Map();
        function syncMarkers() {
            if (!map) return;
            const seen = new Set();
            team.forEach((d) => {
                // rough location (computer / weak GPS): show the area it could be in
                if (d.lat !== null && d.accuracy > 100) {
                    const r = rings.get(d.id) || window.L.circle([d.lat, d.lng], { radius: d.accuracy, weight: 1, interactive: false }).addTo(map);
                    r.setLatLng([d.lat, d.lng]).setRadius(d.accuracy).setStyle({ color: color(d.id), fillColor: color(d.id), fillOpacity: 0.12 });
                    rings.set(d.id, r);
                } else if (rings.has(d.id)) { rings.get(d.id).remove(); rings.delete(d.id); }
                if (d.lat === null) return;
                seen.add(d.id);
                const cls = `lv-pin ${d.online ? 'is-on' : ''} ${selected === d.id ? 'is-sel' : ''} ${selected && selected !== d.id ? 'is-dim' : ''}`;
                let m = markers.get(d.id);
                if (!m) {
                    m = window.L.marker([d.lat, d.lng], {
                        icon: window.L.divIcon({ className: 'lv-pin-wrap', iconSize: [48, 56], iconAnchor: [24, 54], html: `<div class="${cls}" style="--c:${color(d.id)}"><span>${face(d)}</span><em>${esc(d.name)}</em></div>` }),
                        zIndexOffset: 500, alt: d.name,
                    }).addTo(map).on('click', () => select(d.id));
                    markers.set(d.id, m);
                } else {
                    if (!player.on) glide(m, d.lat, d.lng);
                    const el = m.getElement()?.firstElementChild;
                    if (el) el.className = cls;
                }
            });
            markers.forEach((m, id) => { if (!seen.has(id)) { m.remove(); markers.delete(id); } });
            rings.forEach((r, id) => { if (!seen.has(id)) { r.remove(); rings.delete(id); } });
        }

        function fitAll() {
            if (!map) return;
            const pts = selected && route?.points.length ? route.points.map((p) => [p[1], p[2]]) : team.filter((d) => d.lat !== null).map((d) => [d.lat, d.lng]);
            if (pts.length) map.flyToBounds(window.L.latLngBounds(pts), { ...pad(), maxZoom: 16, duration: still ? 0 : 0.8 });
        }

        function drawRoute() {
            layer?.clearLayers();
            line = null;
            if (!map || !route) return;
            const pts = route.points.map((p) => [p[1], p[2]]);
            const c = color(selected);
            if (pts.length) {
                window.L.polyline(pts, { color: '#fff', weight: 9, opacity: 0.9, lineJoin: 'round' }).addTo(layer);
                line = window.L.polyline(pts, { color: c, weight: 5, opacity: 0.95, lineJoin: 'round' }).addTo(layer);
                window.L.circleMarker(pts[0], { radius: 7, color: '#fff', weight: 3, fillColor: '#16a34a', fillOpacity: 1 }).bindTooltip(`শুরু ${clock(route.start)}`).addTo(layer);
            }
            route.stops.forEach((s) => window.L.circleMarker([s.lat, s.lng], { radius: 8, color: '#fff', weight: 3, fillColor: '#f59e0b', fillOpacity: 1 }).bindTooltip(`${clock(s.t)} · ${span(s.sec)} থেমেছেন`).addTo(layer));
            route.events.forEach((s) => s.lat && window.L.circleMarker([s.lat, s.lng], { radius: 6, color: '#fff', weight: 2, fillColor: s.type === 'delivery' ? '#0f172a' : '#dc2626', fillOpacity: 1 }).bindTooltip(`${esc(s.name)} · ${clock(s.t)}`).addTo(layer));
        }

        // ------------------------------------------------------------ playback of the day
        const player = { on: false, pos: 0, speed: 120, raf: 0, last: 0 };
        const SPEEDS = [60, 120, 300, 600];
        function showPlayer() {
            $('lvPlayer').hidden = !(selected && route && route.points.length > 1);
            $('lvPlay').innerHTML = player.on ? PAUSE : PLAY;
            $('lvSpeed').textContent = `${bn(player.speed)}×`;
        }
        function at(t) {
            const p = route.points;
            let lo = 0;
            let hi = p.length - 1;
            while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (p[mid][0] <= t) lo = mid; else hi = mid; }
            const k = Math.min(1, Math.max(0, (t - p[lo][0]) / Math.max(1, p[hi][0] - p[lo][0])));
            return [p[lo][1] + (p[hi][1] - p[lo][1]) * k, p[lo][2] + (p[hi][2] - p[lo][2]) * k, lo];
        }
        function seek(t) {
            player.pos = Math.min(route.end, Math.max(route.start, t));
            const [lat, lng, i] = at(player.pos);
            const m = markers.get(selected);
            if (m) { cancelAnimationFrame(m.hbAnim); m.setLatLng([lat, lng]); }
            line?.setLatLngs([...route.points.slice(0, i + 1).map((p) => [p[1], p[2]]), [lat, lng]]);
            $('lvSeek').value = Math.round(((player.pos - route.start) / Math.max(1, route.end - route.start)) * 1000);
            $('lvClock').textContent = clock(player.pos);
        }
        function stopPlay(reset) {
            player.on = false;
            cancelAnimationFrame(player.raf);
            if (reset && route?.points.length) {
                seek(route.end);
            }
            showPlayer();
        }
        function tick(now) {
            if (!alive() || !player.on) return;
            seek(player.pos + ((now - player.last) / 1000) * player.speed);
            player.last = now;
            if (player.pos >= route.end) { stopPlay(); return; }
            player.raf = requestAnimationFrame(tick);
        }
        $('lvPlay').addEventListener('click', () => {
            if (player.on) { stopPlay(); return; }
            if (player.pos >= route.end) player.pos = route.start;
            player.on = true;
            player.last = performance.now();
            player.raf = requestAnimationFrame(tick);
            showPlayer();
        });
        $('lvSeek').addEventListener('input', (e) => {
            stopPlay();
            seek(route.start + (Number(e.target.value) / 1000) * (route.end - route.start));
        });
        $('lvSpeed').addEventListener('click', () => {
            player.speed = SPEEDS[(SPEEDS.indexOf(player.speed) + 1) % SPEEDS.length];
            showPlayer();
        });

        // ------------------------------------------------------------ data
        async function loadRoute(quiet) {
            const my = ++seq;
            const id = selected;
            try {
                const res = await H.api('GET', H.url(`/partner/live/${id}/route?date=${date}`));
                if (my !== seq || !alive() || id !== selected) return;
                const atEnd = !player.on && (!route || player.pos >= route.end);
                const first = !route;
                route = res.route;
                if (atEnd) {
                    player.pos = route.end || 0;
                    drawRoute();
                    if (route.points.length) { $('lvSeek').value = 1000; $('lvClock').textContent = clock(route.end); }
                }
                renderDetail();
                showPlayer();
                if (first) fitAll();
            } catch (err) {
                if (!quiet && my === seq) { $('lvDetail').innerHTML = `<p class="lv-empty">${esc(err.message)}</p>`; }
            }
        }
        function select(id) {
            stopPlay();
            seq += 1;
            selected = id === selected ? null : id;
            route = null;
            player.pos = 0;
            layer?.clearLayers();
            renderTeam();
            renderDetail();
            showPlayer();
            syncMarkers();
            if (selected) loadRoute(); else { fitAll(); }
        }
        async function setDate(next) {
            if (!next || next > today) return;
            date = next;
            seq += 1;
            stopPlay();
            route = null;
            player.pos = 0;
            layer?.clearLayers();
            markers.forEach((m) => m.remove());
            markers.clear();
            rings.forEach((r) => r.remove());
            rings.clear();
            $('lvDate').value = date;
            $('lvDateText').textContent = new Date(`${date}T00:00:00`).toLocaleDateString('bn-BD', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
            history.replaceState(history.state, '', H.url(`/partner/live${isToday() ? '' : `?date=${date}`}`));
            app.classList.add('is-loading');
            renderDetail();
            showPlayer();
            await refresh(true);
            app.classList.remove('is-loading');
            if (selected) loadRoute(); else fitAll();
        }
        const shift = (n) => {
            const d = new Date(`${date}T00:00:00Z`);
            d.setUTCDate(d.getUTCDate() + n);
            setDate(d.toISOString().slice(0, 10));
        };
        async function refresh(force) {
            if (busy && !force) return;
            busy = true;
            const my = date;
            try {
                const res = await H.api('GET', H.url(`/partner/live/team?date=${my}`));
                if (!alive() || my !== date) return;
                team = res.team;
                if (selected && !team.some((d) => d.id === selected)) { selected = null; route = null; renderDetail(); }
                renderTeam();
                syncMarkers();
                if (!force && selected) loadRoute(true);
            } catch (err) {
                if (force) H.showToast(err.message);
            } finally { busy = false; }
        }

        $('lvTeam').addEventListener('click', (e) => {
            const c = e.target.closest('[data-dsr]');
            if (c) select(Number(c.dataset.dsr));
        });
        $('lvDetail').addEventListener('click', (e) => {
            const li = e.target.closest('[data-go]');
            if (li && map) map.flyTo(li.dataset.go.split(',').map(Number), 17, { duration: still ? 0 : 0.8 });
        });
        $('lvDetail').addEventListener('keydown', (e) => { if (e.key === 'Enter') e.target.closest('[data-go]')?.click(); });
        $('lvFit').addEventListener('click', fitAll);
        $('lvPrev').addEventListener('click', () => shift(-1));
        $('lvNext').addEventListener('click', () => shift(1));
        $('lvToday').addEventListener('click', () => setDate(today));
        $('lvDate').addEventListener('change', (e) => setDate(e.target.value));
        $('lvDate').addEventListener('click', (e) => { try { e.target.showPicker(); } catch { /* old browser */ } });

        renderTeam();
        // Instant updates when the realtime service is reachable; the poll below keeps working without it.
        const rt = typeof EventSource === 'function' ? new EventSource(H.url('/rt/partner'), { withCredentials: true }) : null;
        rt?.addEventListener('location', () => { if (alive() && isToday() && !document.hidden) refresh(); });
        rt?.addEventListener('error', () => { if (rt.readyState === 2) rt.close(); });
        const poll = setInterval(() => {
            if (!alive()) { clearInterval(poll); rt?.close(); cancelAnimationFrame(player.raf); map?.remove(); map = null; return; }
            if (isToday() && !document.hidden) refresh();
        }, POLL_MS);

        (async () => {
            if (!document.querySelector('link[data-leaflet]')) {
                const l = document.createElement('link');
                l.rel = 'stylesheet';
                l.href = app.dataset.leafletCss;
                l.dataset.leaflet = '1';
                document.head.appendChild(l);
                await new Promise((ok) => { l.onload = l.onerror = ok; });
            }
            await loadScript(app.dataset.leafletJs, () => !!window.L);
            await loadScript(app.dataset.tilesJs, () => !!window.HbMapTiles);
            if (!alive()) return;
            map = window.L.map('lvMap', { zoomControl: false, attributionControl: true, zoomSnap: 0.5 }).setView([23.8103, 90.4125], 7);
            window.L.control.zoom({ position: 'topright' }).addTo(map);
            layer = window.L.layerGroup().addTo(map);
            syncMarkers();
            const pts = team.filter((d) => d.lat !== null).map((d) => [d.lat, d.lng]);
            if (pts.length) map.fitBounds(pts, { ...pad(), maxZoom: 16, animate: false });
            window.HbMapTiles.attach(map, $('lvMap'));
            drawRoute();
        })().catch(() => H.showToast('ম্যাপ লোড হয়নি। পেজ রিলোড করুন।'));
    });
})();
