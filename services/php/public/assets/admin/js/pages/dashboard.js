(() => {
    'use strict';
    const H = window.HappyAdmin;

    H.registerPage(() => {
        const btn = document.getElementById('refreshHealthBtn');
        if (!btn) return;

        const $ = (id) => document.getElementById(id);
        const esc = H.escapeHtml;

        function renderChecks(checks) {
            return checks.map((c) => `
                <div class="health-row">
                    <div class="health-row-info">
                        <span class="dot ${c.status === 'healthy' ? 'dot-ok' : 'dot-warn'}"></span>
                        <div>
                            <div class="health-name">${esc(c.name)}</div>
                            <div class="muted small">${esc(c.detail)}</div>
                        </div>
                    </div>
                    <div class="health-meter">
                        <div class="meter-track">
                            <div class="meter-fill ${c.load >= 65 ? 'is-warn' : ''}" style="width: ${Number(c.load) || 0}%"></div>
                        </div>
                        <span class="meter-val">${Number(c.load) || 0}%</span>
                    </div>
                </div>`).join('');
        }

        btn.addEventListener('click', async () => {
            const body = $('systemHealthBody');
            const badge = $('healthStatusBadge');
            body?.classList.add('is-loading');
            try {
                const { health } = await H.withButtonLoading(btn, 'Checking…', () => H.api('GET', btn.dataset.healthUrl), 300);
                const ok = health.overall === 'Operational';
                badge.className = `badge ${ok ? 'badge-success' : 'badge-warning'}`;
                badge.innerHTML = `<span class="dot ${ok ? 'dot-ok' : 'dot-warn'}"></span>${esc(health.overall)}`;
                $('healthLatencyVal').textContent = health.latency;
                $('healthDbSizeVal').textContent = health.db_size;
                $('healthMemoryVal').textContent = health.memory_usage;
                $('healthChecksList').innerHTML = renderChecks(health.checks);
                H.showToast(`System health: ${health.overall} (DB ${health.latency}).`);
            } catch (err) {
                badge.className = 'badge badge-warning';
                badge.innerHTML = '<span class="dot dot-warn"></span>Degraded';
                H.showToast(err.message || 'Health check failed.');
            } finally {
                body?.classList.remove('is-loading');
            }
        });
    });
})();
