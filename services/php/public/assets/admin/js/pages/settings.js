(() => {
    'use strict';
    const H = window.HappyAdmin;

    H.registerPage(() => {
        const app = document.getElementById('adminSettingsApp');
        if (!app) return;

        const $ = (id) => document.getElementById(id);
        const esc = H.escapeHtml;
        const base = app.dataset.baseUrl;
        const badge = (s) => `badge ${s === 'Active' ? 'badge-success' : 'badge-neutral'}`;

        // ---- Tabs ----------------------------------------------------------
        const tabBtns = app.querySelectorAll('[data-tab-target]');
        const tabPanels = app.querySelectorAll('[data-tab-panel]');
        function activateTab(name) {
            if (![...tabBtns].some((b) => b.dataset.tabTarget === name)) return;
            tabBtns.forEach((b) => {
                const on = b.dataset.tabTarget === name;
                b.classList.toggle('is-active', on);
                b.setAttribute('aria-selected', on ? 'true' : 'false');
            });
            tabPanels.forEach((p) => {
                const on = p.dataset.tabPanel === name;
                p.hidden = !on;
                p.classList.toggle('is-active', on);
            });
        }
        tabBtns.forEach((b) => b.addEventListener('click', () => {
            activateTab(b.dataset.tabTarget);
            history.replaceState({ spa: true }, '', `#${b.dataset.tabTarget}`);
        }));
        if (window.location.hash) activateTab(window.location.hash.slice(1));

        // ---- Sessions ------------------------------------------------------
        const sessionsTbody = $('sessionsTbody');
        const updateSessionCount = () => {
            $('sessionCountBadge').textContent = String(sessionsTbody.querySelectorAll('[data-session-row]').length);
        };
        sessionsTbody?.addEventListener('click', async (e) => {
            const btn = e.target.closest('[data-revoke-session]');
            if (!btn) return;
            try {
                const res = await H.withButtonLoading(btn, 'Revoking…', () => H.api('DELETE', `${base}/sessions/${btn.dataset.revokeSession}`));
                btn.closest('tr')?.remove();
                updateSessionCount();
                H.showToast(res.message);
            } catch (err) {
                H.showToast(err.message);
            }
        });
        $('revokeAllSessionsBtn')?.addEventListener('click', async (e) => {
            if (!window.confirm('Sign out every other user and device?')) return;
            try {
                const res = await H.withButtonLoading(e.currentTarget, 'Revoking…', () => H.api('POST', `${base}/sessions/revoke-others`, {}));
                sessionsTbody.querySelectorAll('[data-session-row][data-current="0"]').forEach((r) => r.remove());
                updateSessionCount();
                H.showToast(res.message);
            } catch (err) {
                H.showToast(err.message);
            }
        });

        // ---- Simple status lists: categories & areas -------------------------
        function simpleList({ tbody, form, nameInput, statusInput, url, key, rowAttr, datasetKey, countBadge, render, label }) {
            const updateCount = () => { countBadge.textContent = String(tbody.querySelectorAll(`[${rowAttr}]`).length); };
            const write = (tr, item) => {
                tr.setAttribute(rowAttr, '');
                tr.dataset.id = String(item.id);
                tr.dataset[datasetKey] = JSON.stringify(item);
                tr.innerHTML = render(item);
            };

            form?.addEventListener('submit', async (e) => {
                e.preventDefault();
                const name = nameInput.value.trim();
                if (!name) {
                    form.reportValidity();
                    return;
                }
                try {
                    const res = await H.withButtonLoading(form.querySelector('button[type="submit"]'), 'Adding…', () =>
                        H.api('POST', url, { name, status: statusInput.value })
                    );
                    const tr = document.createElement('tr');
                    write(tr, res[key]);
                    tbody.prepend(tr);
                    form.reset();
                    updateCount();
                    H.showToast(res.message);
                } catch (err) {
                    H.showToast(err.message);
                }
            });

            tbody?.addEventListener('click', async (e) => {
                const tr = e.target.closest(`[${rowAttr}]`);
                if (!tr) return;
                const item = JSON.parse(tr.dataset[datasetKey]);
                const toggle = e.target.closest('[data-toggle-category], [data-toggle-area]');
                const del = e.target.closest('[data-delete-category], [data-delete-area]');
                try {
                    if (toggle) {
                        const status = item.status === 'Active' ? 'Inactive' : 'Active';
                        const res = await H.withButtonLoading(toggle, 'Saving…', () => H.api('PATCH', `${url}/${item.id}/status`, { status }));
                        write(tr, res[key]);
                        H.showToast(res.message);
                    } else if (del) {
                        if (!window.confirm(`Delete ${label} "${item.name}"?`)) return;
                        const res = await H.withButtonLoading(del, 'Deleting…', () => H.api('DELETE', `${url}/${item.id}`));
                        tr.remove();
                        updateCount();
                        H.showToast(res.message);
                    }
                } catch (err) {
                    H.showToast(err.message);
                }
            });
        }

        simpleList({
            tbody: $('categoriesTbody'),
            form: $('addCategoryForm'),
            nameInput: $('newCategoryName'),
            statusInput: $('newCategoryStatus'),
            url: `${base}/categories`,
            key: 'category',
            rowAttr: 'data-category-row',
            datasetKey: 'category',
            countBadge: $('categoryCountBadge'),
            label: 'category',
            render: (c) => `
                <td class="cell-primary">${esc(c.name)}</td>
                <td class="mono">${esc(c.slug)}</td>
                <td class="tabular">${Number(c.products).toLocaleString('en-US')}</td>
                <td><span class="${badge(c.status)}" data-cat-status>${esc(c.status)}</span></td>
                <td class="text-right nowrap">
                    <button type="button" class="btn btn-ghost btn-xs" data-toggle-category>Toggle</button>
                    <button type="button" class="btn btn-danger-ghost btn-xs" data-delete-category>Delete</button>
                </td>`,
        });

        simpleList({
            tbody: $('areasTbody'),
            form: $('addAreaForm'),
            nameInput: $('newAreaName'),
            statusInput: $('newAreaStatus'),
            url: `${base}/areas`,
            key: 'area',
            rowAttr: 'data-area-row',
            datasetKey: 'area',
            countBadge: $('areaCountBadge'),
            label: 'area',
            render: (a) => `
                <td class="cell-primary">${esc(a.name)}</td>
                <td class="tabular">${Number(a.partners).toLocaleString('en-US')}</td>
                <td><span class="${badge(a.status)}">${esc(a.status)}</span></td>
                <td class="text-right nowrap">
                    <button type="button" class="btn btn-ghost btn-xs" data-toggle-area>Toggle</button>
                    <button type="button" class="btn btn-danger-ghost btn-xs" data-delete-area>Delete</button>
                </td>`,
        });

        // ---- Activity log filter ---------------------------------------------
        const logSearch = $('logSearch');
        const logModule = $('logModuleFilter');
        const filterLogs = () => {
            const q = (logSearch.value || '').trim().toLowerCase();
            const mod = logModule.value;
            let visible = 0;
            $('logsTbody').querySelectorAll('tr').forEach((tr) => {
                const ok = (!q || (tr.dataset.search || '').includes(q)) && (!mod || tr.dataset.module === mod);
                tr.hidden = !ok;
                if (ok) visible++;
            });
            $('logCount').textContent = String(visible);
        };
        logSearch?.addEventListener('input', filterLogs);
        logModule?.addEventListener('change', filterLogs);
    });
})();
