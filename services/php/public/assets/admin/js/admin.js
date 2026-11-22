(() => {
    'use strict';

    const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

    // Initial Full-Page Boot Loader: wait until everything loads, then reveal cleanly
    const bootLoader = document.getElementById('appBootLoader');
    if (bootLoader) {
        let dismissed = false;
        const dismissBootLoader = () => {
            if (dismissed) return;
            dismissed = true;
            bootLoader.classList.add('is-hidden');
            setTimeout(() => bootLoader.remove(), 260);
        };

        if (document.readyState === 'complete') {
            requestAnimationFrame(dismissBootLoader);
        } else {
            window.addEventListener('load', () => setTimeout(dismissBootLoader, 120), { once: true });
            setTimeout(dismissBootLoader, 1800); // Safety fallback
        }
    }

    // Toast feedback
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

    // Reusable Button Loading State
    function setButtonLoading(btn, loading, loadingText = 'Loading…') {
        if (!btn) return;
        if (loading) {
            if (!btn.dataset.originalHtml) {
                btn.dataset.originalHtml = btn.innerHTML;
            }
            btn.disabled = true;
            btn.classList.add('is-loading');
            btn.innerHTML = `<span class="btn-spinner" aria-hidden="true"></span><span>${escapeHtml(loadingText)}</span>`;
        } else {
            btn.disabled = false;
            btn.classList.remove('is-loading');
            if (btn.dataset.originalHtml !== undefined) {
                btn.innerHTML = btn.dataset.originalHtml;
                delete btn.dataset.originalHtml;
            }
        }
    }

    async function withButtonLoading(btn, loadingText, task, minMs = 240) {
        setButtonLoading(btn, true, loadingText);
        const started = performance.now();
        try {
            const result = await task();
            const elapsed = performance.now() - started;
            if (elapsed < minMs) await sleep(minMs - elapsed);
            return result;
        } finally {
            setButtonLoading(btn, false);
        }
    }

    // Flat SaaS Skeleton Templates
    function bentoSkeleton() {
        return `
            <section class="bento-grid" aria-busy="true" aria-label="Loading dashboard">
                <div class="bento-card bento-hero">
                    <div class="sk-row"><span class="sk sk-line" style="width:110px"></span><span class="sk sk-pill"></span></div>
                    <div class="sk-stack"><span class="sk sk-kpi-lg"></span><span class="sk sk-line" style="width:40%"></span></div>
                    <div class="sk-row" style="height:54px;align-items:flex-end">
                        <span class="sk" style="flex:1;height:40%"></span>
                        <span class="sk" style="flex:1;height:60%"></span>
                        <span class="sk" style="flex:1;height:75%"></span>
                        <span class="sk" style="flex:1;height:95%"></span>
                    </div>
                    <span class="sk sk-line" style="width:70%"></span>
                </div>
                <div class="bento-right-stack">
                    <div class="bento-subgrid bento-cols-2">
                        <div class="bento-card sk-stack"><span class="sk sk-line" style="width:55%"></span><span class="sk sk-kpi"></span><span class="sk sk-line" style="width:38%"></span></div>
                        <div class="bento-card sk-stack"><span class="sk sk-line" style="width:55%"></span><span class="sk sk-kpi"></span><span class="sk sk-line" style="width:45%"></span></div>
                    </div>
                    <div class="bento-subgrid bento-cols-3">
                        <div class="bento-card sk-stack"><span class="sk sk-line" style="width:50%"></span><span class="sk sk-kpi"></span><span class="sk sk-line" style="width:60%"></span></div>
                        <div class="bento-card sk-stack"><span class="sk sk-line" style="width:50%"></span><span class="sk sk-kpi"></span><span class="sk sk-line" style="width:60%"></span></div>
                        <div class="bento-card sk-stack"><span class="sk sk-line" style="width:55%"></span><span class="sk sk-kpi"></span><span class="sk sk-line" style="width:65%"></span></div>
                    </div>
                </div>
                <div class="bento-card bento-span-7 sk-stack">
                    <div class="sk-row"><span class="sk sk-title" style="width:140px"></span><span class="sk sk-pill"></span></div>
                    <div class="health-summary">
                        <span class="sk" style="height:52px"></span><span class="sk" style="height:52px"></span>
                        <span class="sk" style="height:52px"></span><span class="sk" style="height:52px"></span>
                    </div>
                    <span class="sk" style="height:46px"></span>
                    <span class="sk" style="height:46px"></span>
                    <span class="sk" style="height:46px"></span>
                </div>
                <div class="bento-card bento-span-5 sk-stack">
                    <span class="sk sk-title" style="width:140px"></span>
                    <span class="sk sk-bar" style="width:92%;margin-top:8px"></span>
                    <span class="sk sk-bar" style="width:76%;margin-top:14px"></span>
                    <span class="sk sk-bar" style="width:64%;margin-top:14px"></span>
                    <span class="sk sk-bar" style="width:48%;margin-top:14px"></span>
                </div>
            </section>
        `;
    }

    function tableSkeleton(rows = 5, withTabs = false) {
        const tabsHtml = withTabs
            ? `<div class="tabs-bar" style="padding-bottom:10px;gap:14px">
                    <span class="sk sk-line" style="width:110px"></span>
                    <span class="sk sk-line" style="width:160px"></span>
                    <span class="sk sk-line" style="width:95px"></span>
               </div>`
            : '';

        const rowHtml = Array.from({ length: rows }, () => `
            <div class="sk-table-row">
                <div class="sk-stack" style="gap:6px"><span class="sk sk-line" style="width:70%"></span><span class="sk sk-line" style="width:42%"></span></div>
                <span class="sk sk-line" style="width:80%"></span>
                <span class="sk sk-line" style="width:75%"></span>
                <span class="sk sk-line" style="width:85%"></span>
                <span class="sk sk-pill" style="margin-left:auto"></span>
            </div>
        `).join('');

        return `
            <div aria-busy="true" aria-label="Loading data">
                ${tabsHtml}
                <section class="panel">
                    <div class="toolbar">
                        <div class="toolbar-filters">
                            <span class="sk sk-input" style="width:280px"></span>
                            <span class="sk sk-input" style="width:140px"></span>
                        </div>
                        <span class="sk sk-line" style="width:72px"></span>
                    </div>
                    ${rowHtml}
                </section>
            </div>
        `;
    }

    function skeletonForPath(pathname) {
        if (/\/admin\/(partners|companies|dealers|salesmen)(\/|$)/.test(pathname)) return tableSkeleton(5, false);
        if (/\/admin\/settings(\/|$)/.test(pathname)) return tableSkeleton(4, true);
        return bentoSkeleton();
    }

    function pageTitleForPath(pathname) {
        if (/\/admin\/partners(\/|$)/.test(pathname)) return 'Partners';
        if (/\/admin\/companies(\/|$)/.test(pathname)) return 'Companies';
        if (/\/admin\/dealers(\/|$)/.test(pathname)) return 'Dealers';
        if (/\/admin\/salesmen(\/|$)/.test(pathname)) return 'Salesmen (SR)';
        if (/\/admin\/settings(\/|$)/.test(pathname)) return 'Settings';
        return 'Dashboard';
    }

    // Mobile sidebar toggle
    const sidebar = document.getElementById('sidebar');
    const backdrop = document.querySelector('.sidebar-backdrop');
    const toggleSidebar = (open) => {
        if (!sidebar || !backdrop) return;
        sidebar.classList.toggle('is-open', open);
        backdrop.classList.toggle('is-open', open);
    };

    document.querySelectorAll('[data-sidebar-open]').forEach((btn) =>
        btn.addEventListener('click', () => toggleSidebar(true))
    );
    document.querySelectorAll('[data-sidebar-close]').forEach((btn) =>
        btn.addEventListener('click', () => toggleSidebar(false))
    );

    // Slide-over drawers (delegated)
    function openDrawer(id) {
        const el = document.getElementById(id);
        if (!el) return;
        el.classList.add('is-open');
        el.setAttribute('aria-hidden', 'false');
    }

    function closeAllDrawers() {
        document.querySelectorAll('.drawer-overlay.is-open').forEach((el) => {
            el.classList.remove('is-open');
            el.setAttribute('aria-hidden', 'true');
        });
    }

    document.addEventListener('click', (e) => {
        const openBtn = e.target.closest('[data-drawer-open]');
        if (openBtn) {
            openDrawer(openBtn.getAttribute('data-drawer-open'));
            return;
        }
        if (e.target.closest('[data-drawer-close]') || e.target.classList?.contains('drawer-overlay')) {
            closeAllDrawers();
            return;
        }

        const inputToggle = e.target.closest('[data-toggle-input-pw]');
        if (inputToggle) {
            const input = document.getElementById(inputToggle.getAttribute('data-toggle-input-pw'));
            if (input) {
                const hidden = input.type === 'password';
                input.type = hidden ? 'text' : 'password';
                inputToggle.textContent = hidden ? 'Hide' : 'Show';
            }
            return;
        }

        const genBtn = e.target.closest('[data-gen-pw]');
        if (genBtn) {
            const id = genBtn.getAttribute('data-gen-pw');
            const input = document.getElementById(id);
            if (input) {
                const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789@#$';
                let out = '';
                for (let i = 0; i < 10; i++) out += chars[Math.floor(Math.random() * chars.length)];
                input.value = out;
                input.type = 'text';
                const toggleBtn = document.querySelector(`[data-toggle-input-pw="${CSS.escape(id)}"]`);
                if (toggleBtn) toggleBtn.textContent = 'Hide';
            }
        }
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            closeAllDrawers();
            toggleSidebar(false);
        }
    });

    // =====================================================================
    // Backend API client & form helpers
    // =====================================================================
    function csrfToken() {
        return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
    }

    async function api(method, url, body) {
        let res;
        try {
            res = await fetch(url, {
                method,
                credentials: 'same-origin',
                headers: {
                    Accept: 'application/json',
                    'Content-Type': 'application/json',
                    'X-Requested-With': 'XMLHttpRequest',
                    'X-CSRF-TOKEN': csrfToken(),
                },
                body: body === undefined ? undefined : JSON.stringify(body),
            });
        } catch {
            throw Object.assign(new Error('Network error. Check your connection and try again.'), { errors: {} });
        }

        let data = {};
        try { data = await res.json(); } catch { /* non-JSON body */ }

        if (res.status === 401) {
            window.location.href = data.redirect || window.location.href;
            throw Object.assign(new Error(data.message || 'Session ended.'), { errors: {} });
        }
        if (res.status === 419) {
            throw Object.assign(new Error('Your session token expired. Please reload the page.'), { errors: {} });
        }
        if (!res.ok || data.ok === false) {
            const msg = data.message || data.error || `Request failed (HTTP ${res.status}).`;
            throw Object.assign(new Error(msg), { errors: data.errors || {} });
        }
        return data;
    }

    function clearFormErrors(form) {
        form?.querySelectorAll('[aria-invalid="true"]').forEach((el) => el.removeAttribute('aria-invalid'));
        form?.querySelectorAll('.field-error').forEach((el) => el.remove());
    }

    function showFormErrors(form, errors) {
        clearFormErrors(form);
        Object.entries(errors || {}).forEach(([field, messages]) => {
            const input = form?.querySelector(`[name="${CSS.escape(field)}"]`);
            if (!input) return;
            input.setAttribute('aria-invalid', 'true');
            const msg = document.createElement('small');
            msg.className = 'field-error';
            msg.textContent = Array.isArray(messages) ? messages[0] : String(messages);
            (input.closest('.input-with-action') || input).insertAdjacentElement('afterend', msg);
        });
    }

    function formPayload(form) {
        const data = Object.fromEntries(new FormData(form).entries());
        delete data._token;
        delete data.id;
        return data;
    }

    /** Edit mode makes the password optional ("leave blank to keep"). */
    function setPasswordMode(form, inputId, editing) {
        const input = document.getElementById(inputId);
        if (!input) return;
        input.value = '';
        input.type = 'password';
        input.required = !editing;
        input.placeholder = editing ? 'Leave blank to keep current password' : 'Minimum 6 characters';
        const star = form?.querySelector('[data-pw-required]');
        if (star) star.hidden = editing;
        const toggle = document.querySelector(`[data-toggle-input-pw="${CSS.escape(inputId)}"]`);
        if (toggle) toggle.textContent = 'Show';
    }

    function setSelectOptions(select, items, placeholder, selected = '', label = (i) => i.name) {
        if (!select) return;
        select.innerHTML = `<option value="">${escapeHtml(placeholder)}</option>` + items
            .map((i) => `<option value="${escapeHtml(i.id)}">${escapeHtml(label(i))}</option>`)
            .join('');
        select.value = selected === null || selected === undefined ? '' : String(selected);
    }

    /**
     * Generic database-backed table: client-side search/filters, add/edit drawer,
     * status toggle and delete, all persisted through the JSON API.
     */
    function crudTable(cfg) {
        const { tbody, form, baseUrl, key, rowAttr, label } = cfg;
        const rowSel = `tr[${rowAttr}]`;

        const readRow = (tr) => JSON.parse(tr.dataset[cfg.datasetKey] || '{}');
        const findRow = (id) => tbody?.querySelector(`${rowSel}[data-id="${CSS.escape(String(id))}"]`);

        function writeRow(tr, record) {
            tr.setAttribute(rowAttr, '');
            tr.dataset.id = String(record.id);
            tr.dataset[cfg.datasetKey] = JSON.stringify(record);
            cfg.attrs(tr, record);
            tr.innerHTML = cfg.render(record);
        }

        function filter() {
            if (!tbody) return;
            let visible = 0;
            const total = tbody.querySelectorAll(rowSel).length;
            tbody.querySelectorAll(rowSel).forEach((tr) => {
                const ok = cfg.matches(tr);
                tr.hidden = !ok;
                if (ok) visible++;
            });
            if (cfg.countEl) cfg.countEl.textContent = String(visible);
            if (cfg.emptyEl) {
                cfg.emptyEl.hidden = visible > 0;
                const p = cfg.emptyEl.querySelector('p');
                if (p) p.textContent = total === 0 ? cfg.emptyText : `No ${cfg.plural} match your current filter.`;
            }
        }

        function upsert(record) {
            let tr = findRow(record.id);
            if (!tr) {
                tr = document.createElement('tr');
                tbody?.prepend(tr);
            }
            writeRow(tr, record);
            filter();
            cfg.afterChange?.();
        }

        let editingId = null;
        function openAdd() {
            editingId = null;
            form?.reset();
            clearFormErrors(form);
            cfg.onOpen?.(null);
            openDrawer(cfg.drawerId);
        }
        function openEdit(record) {
            editingId = record.id;
            form?.reset();
            clearFormErrors(form);
            cfg.onOpen?.(record);
            openDrawer(cfg.drawerId);
        }

        form?.addEventListener('submit', async (e) => {
            e.preventDefault();
            cfg.beforeSubmit?.();
            if (!form.reportValidity()) return;
            const submitBtn = form.querySelector('button[type="submit"]');
            const payload = cfg.payload ? cfg.payload(form) : formPayload(form);
            const editing = editingId !== null;
            try {
                const res = await withButtonLoading(submitBtn, editing ? 'Updating…' : 'Saving…', () =>
                    api(editing ? 'PUT' : 'POST', editing ? `${baseUrl}/${editingId}` : baseUrl, payload)
                );
                upsert(res[key]);
                clearFormErrors(form);
                closeAllDrawers();
                showToast(res.message || `${label} saved.`);
            } catch (err) {
                showFormErrors(form, err.errors);
                showToast(err.message);
            }
        });

        tbody?.addEventListener('click', async (e) => {
            const tr = e.target.closest(rowSel);
            if (!tr) return;
            const record = readRow(tr);

            if (e.target.closest('[data-action="view"]')) {
                cfg.onView?.(record);
                return;
            }
            if (e.target.closest('[data-action="edit"]')) {
                openEdit(record);
                return;
            }

            const toggleBtn = e.target.closest('[data-action="toggle"]');
            if (toggleBtn) {
                const status = record.status === 'Active' ? 'Inactive' : 'Active';
                try {
                    const res = await withButtonLoading(toggleBtn, 'Saving…', () =>
                        api('PATCH', `${baseUrl}/${record.id}/status`, { status })
                    );
                    upsert(res[key]);
                    showToast(res.message);
                } catch (err) {
                    showToast(err.message);
                }
                return;
            }

            const delBtn = e.target.closest('[data-action="delete"]');
            if (delBtn) {
                if (!window.confirm(`Delete ${label.toLowerCase()} "${record.name}"?`)) return;
                try {
                    const res = await withButtonLoading(delBtn, 'Deleting…', () => api('DELETE', `${baseUrl}/${record.id}`));
                    tr.remove();
                    filter();
                    cfg.afterChange?.();
                    showToast(res.message);
                } catch (err) {
                    showToast(err.message);
                }
            }
        });

        (cfg.filterInputs || []).forEach((el) => {
            el?.addEventListener(el.tagName === 'SELECT' ? 'change' : 'input', filter);
        });

        filter();
        return { filter, openAdd, openEdit, findRow, readRow };
    }

    // Per-page modules register here and are re-initialised after every SPA swap
    const pageModules = [];
    function initPage() {
        pageModules.forEach((init) => {
            try {
                init();
            } catch (err) {
                console.error(err);
            }
        });
    }

    // SPA Router with page-aware Skeleton Loading (wait until full load, then reveal)
    const adminContent = document.getElementById('adminContent');
    const adminPageTitle = document.getElementById('adminPageTitle');
    const adminTopbarActions = document.getElementById('adminTopbarActions');
    const spaProgress = document.getElementById('spaProgress');
    let activeController = null;

    function isSpaLink(anchor) {
        if (!adminContent || !anchor) return false;
        if (anchor.hasAttribute('data-no-spa') || anchor.hasAttribute('download')) return false;
        if (anchor.target && anchor.target !== '_self') return false;

        const rawHref = anchor.getAttribute('href');
        if (!rawHref || rawHref.startsWith('#') || rawHref.startsWith('mailto:') || rawHref.startsWith('tel:') || rawHref.startsWith('javascript:')) {
            return false;
        }

        let target;
        try {
            target = new URL(anchor.href, window.location.origin);
        } catch {
            return false;
        }

        if (target.origin !== window.location.origin) return false;
        if (!/\/admin(\/|$)/.test(target.pathname)) return false;
        if (/\/admin\/login\/?$/.test(target.pathname)) return false;

        return true;
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

    function syncSidebarActiveByPath(pathname) {
        const items = document.querySelectorAll('.sidebar-nav .nav-item');
        items.forEach((item) => {
            const hrefPath = new URL(item.href, window.location.origin).pathname;
            const isDash = /\/admin\/?$/.test(pathname) && /\/admin\/dashboard\/?$/.test(hrefPath);
            item.classList.toggle('is-active', hrefPath === pathname || isDash);
        });
    }

    async function navigateSpa(urlString, { push = true } = {}) {
        const target = new URL(urlString, window.location.origin);

        if (target.pathname === window.location.pathname && target.search === window.location.search) {
            if (push && target.href !== window.location.href) {
                history.pushState({ spa: true }, '', target.href);
            }
            if (target.hash === '#add') {
                document.getElementById('openAddPartnerBtn')?.click();
            } else if (target.hash) {
                const tabBtn = document.querySelector(`[data-tab-target="${CSS.escape(target.hash.slice(1))}"]`);
                tabBtn?.click();
            }
            toggleSidebar(false);
            return;
        }

        if (activeController) activeController.abort();
        activeController = new AbortController();

        closeAllDrawers();
        toggleSidebar(false);
        setProgress('start');
        syncSidebarActiveByPath(target.pathname);

        if (adminPageTitle) adminPageTitle.textContent = pageTitleForPath(target.pathname);
        if (adminTopbarActions) adminTopbarActions.innerHTML = '';
        adminContent.innerHTML = skeletonForPath(target.pathname);
        window.scrollTo({ top: 0, behavior: 'instant' });

        const started = performance.now();
        const minShimmerMs = 200;

        try {
            const res = await fetch(target.href, {
                headers: { 'X-Admin-SPA': '1' },
                credentials: 'same-origin',
                signal: activeController.signal,
            });

            if (!res.ok) {
                window.location.href = target.href;
                return;
            }

            const html = await res.text();
            const doc = new DOMParser().parseFromString(html, 'text/html');
            const nextContent = doc.getElementById('adminContent');

            if (!nextContent) {
                window.location.href = res.url || target.href;
                return;
            }

            const elapsed = performance.now() - started;
            if (elapsed < minShimmerMs) {
                await sleep(minShimmerMs - elapsed);
            }

            if (activeController.signal.aborted) return;

            document.title = doc.title || document.title;

            const nextTitle = doc.getElementById('adminPageTitle');
            if (adminPageTitle && nextTitle) {
                adminPageTitle.textContent = nextTitle.textContent;
            }

            const nextActions = doc.getElementById('adminTopbarActions');
            if (adminTopbarActions && nextActions) {
                adminTopbarActions.innerHTML = nextActions.innerHTML;
            }

            adminContent.innerHTML = nextContent.innerHTML;
            adminContent.classList.remove('spa-enter');
            void adminContent.offsetWidth;
            adminContent.classList.add('spa-enter');

            const nextNavItems = doc.querySelectorAll('.sidebar-nav .nav-item');
            const currNavItems = document.querySelectorAll('.sidebar-nav .nav-item');
            currNavItems.forEach((item, idx) => {
                const active = nextNavItems[idx]?.classList.contains('is-active') ?? false;
                item.classList.toggle('is-active', active);
            });

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

    if (adminContent) {
        history.replaceState({ spa: true }, '', window.location.href);

        document.addEventListener('click', (e) => {
            if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) {
                return;
            }
            const anchor = e.target.closest('a[href]');
            if (!isSpaLink(anchor)) return;

            e.preventDefault();
            navigateSpa(anchor.href, { push: true });
        });

        window.addEventListener('popstate', () => {
            navigateSpa(window.location.href, { push: false });
        });
    }

    // Shared toolkit for page modules (public/assets/admin/js/pages/*.js)
    window.HappyAdmin = {
        showToast,
        escapeHtml,
        setButtonLoading,
        withButtonLoading,
        openDrawer,
        closeAllDrawers,
        api,
        clearFormErrors,
        showFormErrors,
        formPayload,
        setPasswordMode,
        setSelectOptions,
        crudTable,
        registerPage: (init) => pageModules.push(init),
    };
    window.HappyUI = window.HappyAdmin;

    // Page scripts load after this file; run once they have registered.
    document.addEventListener('DOMContentLoaded', initPage);
})();
