(() => {
    'use strict';

    const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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
    const UNIT_BN = {
        Carton: 'কার্টন', Case: 'কেস', Box: 'বক্স', Pack: 'প্যাক',
        Dozen: 'ডজন', Sack: 'বস্তা', Bag: 'ব্যাগ', Piece: 'পিস', Unit: 'ইউনিট',
    };
    const STATUS_BN = {
        pending: 'অপেক্ষমান', assigned: 'নির্ধারিত', dispatched: 'রাস্তায়',
        in_review: 'কনফার্ম বাকি', settled: 'সেটেল্ড', delivered: 'ডেলিভার্ড',
        due: 'বাকি', partial: 'আংশিক', cancelled: 'বাতিল',
        active: 'সক্রিয়', inactive: 'নিষ্ক্রিয়',
    };

    function bnDigits(val) {
        return String(val ?? '').replace(/\d/g, (d) => BN_DIGITS[Number(d)]);
    }

    function bnNum(n, decimals = 0) {
        const v = Number(n || 0);
        return bnDigits(v.toLocaleString('en-US', {
            minimumFractionDigits: decimals,
            maximumFractionDigits: decimals,
        }));
    }

    function bnUnit(unit) {
        return UNIT_BN[unit] || unit || 'ইউনিট';
    }

    function bnStatus(s) {
        const k = String(s || '').trim().toLowerCase().replace(/\s+/g, '_');
        return STATUS_BN[k] || String(s || '');
    }

    function formatBdt(amount) {
        return `৳ ${bnDigits(Number(amount || 0).toLocaleString('en-US'))}`;
    }

    function productSvgUri(code, tint = '#f1f5f9') {
        const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="160" height="120" viewBox="0 0 160 120">`
            + `<rect width="160" height="120" fill="${tint}"/>`
            + `<rect x="52" y="32" width="56" height="56" rx="12" fill="#ffffff" stroke="#e4e7ec" stroke-width="2"/>`
            + `<text x="80" y="67" text-anchor="middle" font-family="system-ui,sans-serif" font-size="18" font-weight="700" fill="#0f172a">${escapeHtml(code)}</text>`
            + `</svg>`;
        return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;
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

    // Mobile Sidebar
    const sidebar = document.getElementById('sidebar');
    const backdrop = document.querySelector('.sidebar-backdrop');
    const toggleSidebar = (open) => {
        if (!sidebar || !backdrop) return;
        sidebar.classList.toggle('is-open', open);
        backdrop.classList.toggle('is-open', open);
    };

    document.querySelectorAll('[data-sidebar-open]').forEach((b) => b.addEventListener('click', () => toggleSidebar(true)));
    document.querySelectorAll('[data-sidebar-close]').forEach((b) => b.addEventListener('click', () => toggleSidebar(false)));

    // Modal Helpers (delegated)
    function openModal(id) {
        const el = document.getElementById(id);
        if (!el) return;
        el.classList.add('is-open');
        el.setAttribute('aria-hidden', 'false');
    }

    function closeAllModals() {
        document.querySelectorAll('.modal-overlay.is-open').forEach((el) => {
            el.classList.remove('is-open');
            el.setAttribute('aria-hidden', 'true');
        });
    }

    document.addEventListener('click', (e) => {
        const openBtn = e.target.closest('[data-modal-open]');
        if (openBtn) {
            openModal(openBtn.getAttribute('data-modal-open'));
            return;
        }
        if (e.target.closest('[data-modal-close]') || e.target.classList?.contains('modal-overlay')) {
            closeAllModals();
            return;
        }

        if (e.target.closest('[data-print-page]')) {
            window.print();
            return;
        }

        // Delegated inline password reveal on SR/DSR cards & Dealer rows
        const pwToggle = e.target.closest('[data-pw-toggle]');
        if (pwToggle) {
            const maskEl = pwToggle.closest('.pw-reveal')?.querySelector('[data-pw-mask]');
            if (maskEl) {
                const shown = maskEl.dataset.shown === '1';
                maskEl.textContent = shown ? '••••••••' : (maskEl.dataset.pw || '');
                maskEl.dataset.shown = shown ? '0' : '1';
                pwToggle.textContent = shown ? 'দেখুন' : 'লুকান';
            }
            return;
        }

        // Delegated input password Show/Hide button
        const inputToggle = e.target.closest('[data-toggle-input-pw]');
        if (inputToggle) {
            const input = document.getElementById(inputToggle.getAttribute('data-toggle-input-pw'));
            if (input) {
                const hidden = input.type === 'password';
                input.type = hidden ? 'text' : 'password';
                inputToggle.textContent = hidden ? 'লুকান' : 'দেখুন';
            }
            return;
        }

        // Delegated password generator
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
                if (toggleBtn) toggleBtn.textContent = 'লুকান';
            }
        }
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            closeAllModals();
            toggleSidebar(false);
        }
    });


    // =========================================================================
    // BACKEND API + FORM HELPERS (shared with pages/*.js)
    // =========================================================================
    function csrfToken() {
        return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
    }

    async function api(method, url, body) {
        const isForm = body instanceof FormData;
        let res;
        try {
            res = await fetch(url, {
                method,
                credentials: 'same-origin',
                headers: {
                    Accept: 'application/json',
                    ...(isForm || body === undefined ? {} : { 'Content-Type': 'application/json' }),
                    'X-Requested-With': 'XMLHttpRequest',
                    'X-CSRF-TOKEN': csrfToken(),
                },
                body: body === undefined ? undefined : (isForm ? body : JSON.stringify(body)),
            });
        } catch {
            throw Object.assign(new Error('নেটওয়ার্ক সমস্যা। ইন্টারনেট সংযোগ দেখে আবার চেষ্টা করুন।'), { errors: {} });
        }

        let data = {};
        try { data = await res.json(); } catch { /* non-JSON body */ }

        if (res.status === 401) {
            window.location.href = data.redirect || window.location.href;
            throw Object.assign(new Error(data.message || 'সেশন শেষ হয়েছে।'), { errors: {} });
        }
        if (res.status === 419) {
            throw Object.assign(new Error('সেশন মেয়াদ শেষ হয়েছে। অনুগ্রহ করে পেজ রিলোড করুন।'), { errors: {} });
        }
        if (!res.ok || data.ok === false) {
            throw Object.assign(new Error(data.message || data.error || `অনুরোধ ব্যর্থ হয়েছে (HTTP ${bnDigits(res.status)})।`), { errors: data.errors || {} });
        }
        return data;
    }

    /** App URL for a path ("/partner/lots"), honouring a sub-folder install. */
    function url(path) {
        const dash = document.querySelector('.brand-link')?.getAttribute('href') || '/partner/dashboard';
        return dash.replace(/\/partner\/dashboard$/, '') + path;
    }

    function formError(form, message) {
        const el = form?.querySelector('[data-form-error]');
        if (!el) { if (message) showToast(message); return; }
        el.textContent = message || '';
        el.hidden = !message;
    }

    /** Runs an API call from a button: loading state, inline error, toast + page refresh on success. */
    async function submitAction(btn, form, label, task, { reload = true } = {}) {
        formError(form, '');
        try {
            const res = await withButtonLoading(btn, label, task);
            closeAllModals();
            if (res?.message) showToast(res.message);
            if (reload) await reloadPage();
            return res;
        } catch (err) {
            if (form) formError(form, err.message); else showToast(err.message);
            return null;
        }
    }

    function formatMoney(n) {
        const v = Math.round((Number(n || 0) + Number.EPSILON) * 100) / 100;
        const frac = Number.isInteger(v) ? 0 : 2;
        return `৳ ${bnDigits(v.toLocaleString('en-US', { minimumFractionDigits: frac, maximumFractionDigits: 2 }))}`;
    }

    function unitPcs(pcs, qpu, unitType) {
        const q = Math.max(1, Number(qpu || 1));
        const n = Math.abs(Math.trunc(Number(pcs || 0)));
        const sign = Number(pcs) < 0 ? '-' : '';
        return `${sign}${bnDigits(Math.floor(n / q))} ${bnUnit(unitType)} ${bnDigits(n % q)} পিস`;
    }

    function productImg(p) {
        return p.image || productSvgUri(p.code || 'PR', p.tint || '#f1f5f9');
    }

    const pageModules = [];
    function initPage() {
        pageModules.forEach((init) => {
            try { init(); } catch (err) { console.error(err); }
        });
    }

    // =========================================================================
    // SPA ROUTER + PAGE-AWARE SKELETONS
    // =========================================================================
    const partnerContent = document.getElementById('partnerContent');
    const partnerPageTitle = document.getElementById('partnerPageTitle');
    const partnerTopbarActions = document.getElementById('partnerTopbarActions');
    const spaProgress = document.getElementById('spaProgress');
    let activeController = null;

    function skeletonForPath(pathname) {
        if (/\/partner\/trips(\/|$)/.test(pathname)) {
            return `<div class="trips-grid" aria-busy="true">${Array.from({ length: 4 }, () => `<div class="card sk-stack" style="min-height:170px"><span class="sk sk-line" style="width:60%"></span><span class="sk sk-line" style="width:40%"></span><span class="sk sk-line" style="width:85%;margin-top:auto"></span></div>`).join('')}</div>`;
        }
        if (/\/partner\/settlements(\/|$)/.test(pathname)) {
            return `<div aria-busy="true"><div class="st-trip-strip">${Array.from({ length: 3 }, () => `<div class="st-trip-card sk-stack"><span class="sk sk-line" style="width:120px"></span><span class="sk sk-line" style="width:90px"></span></div>`).join('')}</div><div class="st-grid"><div class="card sk-stack"><span class="sk sk-line" style="width:35%"></span><span class="sk" style="height:120px"></span><span class="sk" style="height:56px"></span></div><div class="card sk-stack"><span class="sk sk-line" style="width:45%"></span><span class="sk" style="height:56px"></span><span class="sk" style="height:56px"></span><span class="sk" style="height:88px"></span></div></div></div>`;
        }
        if (/\/partner\/day-closing(\/|$)/.test(pathname)) {
            return `<div aria-busy="true"><div class="dc-kpi-grid">${Array.from({ length: 4 }, () => `<div class="card sk-stack"><span class="sk sk-line" style="width:55%"></span><span class="sk sk-kpi"></span><span class="sk sk-line" style="width:70%"></span></div>`).join('')}</div><div class="dc-grid" style="margin-top:16px"><div class="card sk-stack"><span class="sk sk-line" style="width:40%"></span><span class="sk" style="height:220px"></span></div><div class="card sk-stack"><span class="sk sk-line" style="width:45%"></span><span class="sk" style="height:220px"></span></div></div></div>`;
        }
        if (/\/partner\/products(\/|$)/.test(pathname)) {
            return `<div class="products-grid" aria-busy="true">${Array.from({ length: 6 }, () => `<div class="card sk-stack"><span class="sk" style="height:120px"></span><span class="sk sk-line" style="width:70%"></span><span class="sk sk-line" style="width:45%"></span></div>`).join('')}</div>`;
        }
        if (/\/partner\/lots(\/|$)/.test(pathname)) {
            return `<section class="panel" aria-busy="true"><div class="toolbar"><span class="sk" style="height:36px;width:260px"></span><span class="sk sk-line" style="width:70px"></span></div>${Array.from({ length: 5 }, () => `<div style="padding:14px 18px;border-top:1px solid var(--border);display:grid;grid-template-columns:1fr 1.6fr 1fr 1fr;gap:14px"><span class="sk sk-line"></span><span class="sk sk-line"></span><span class="sk sk-line"></span><span class="sk sk-line"></span></div>`).join('')}</section>`;
        }
        if (/\/partner\/delivery-men(\/|$)/.test(pathname)) {
            return `<div class="staff-grid" aria-busy="true">${Array.from({ length: 6 }, () => `<div class="card sk-stack" style="min-height:175px"><span class="sk sk-line" style="width:62%"></span><span class="sk sk-line" style="width:44%"></span><span class="sk sk-line" style="width:85%;margin-top:auto"></span><span class="sk sk-line" style="width:75%"></span></div>`).join('')}</div>`;
        }
        if (/\/partner\/(orders|company-ledger)(\/|$)/.test(pathname)) {
            return `<section class="panel" aria-busy="true">${Array.from({ length: 6 }, () => `<div style="padding:14px 18px;border-top:1px solid var(--border);display:grid;grid-template-columns:1fr 1.6fr 1fr 1fr;gap:14px"><span class="sk sk-line"></span><span class="sk sk-line"></span><span class="sk sk-line"></span><span class="sk sk-line"></span></div>`).join('')}</section>`;
        }
        return `<div class="summary-grid" aria-busy="true">${Array.from({ length: 3 }, () => `<div class="card sk-stack"><span class="sk sk-line" style="width:50%"></span><span class="sk sk-kpi"></span><span class="sk sk-line" style="width:65%"></span></div>`).join('')}</div>`;
    }

    function isSpaLink(anchor) {
        if (!partnerContent || !anchor) return false;
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
        return target.origin === window.location.origin && /\/partner(\/|$)/.test(target.pathname);
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

    function syncSidebar(pathname) {
        document.querySelectorAll('.sidebar-nav .nav-item').forEach((item) => {
            const hrefPath = new URL(item.href, window.location.origin).pathname;
            const isDash = /\/partner\/?$/.test(pathname) && /\/partner\/dashboard\/?$/.test(hrefPath);
            item.classList.toggle('is-active', hrefPath === pathname || isDash);
        });
    }

    async function navigateSpa(urlString, { push = true, force = false } = {}) {
        const target = new URL(urlString, window.location.origin);
        if (!force && target.pathname === window.location.pathname && target.search === window.location.search) {
            toggleSidebar(false);
            return;
        }

        if (activeController) activeController.abort();
        activeController = new AbortController();

        closeAllModals();
        toggleSidebar(false);
        setProgress('start');
        syncSidebar(target.pathname);
        const scrollY = window.scrollY;
        if (!force) {
            if (partnerTopbarActions) partnerTopbarActions.innerHTML = '';
            partnerContent.innerHTML = skeletonForPath(target.pathname);
            window.scrollTo({ top: 0, behavior: 'instant' });
        }

        const start = performance.now();
        try {
            const res = await fetch(target.href, {
                headers: { 'X-Partner-SPA': '1' },
                credentials: 'same-origin',
                signal: activeController.signal,
            });
            if (!res.ok) {
                window.location.href = target.href;
                return;
            }

            const html = await res.text();
            const doc = new DOMParser().parseFromString(html, 'text/html');
            const nextContent = doc.getElementById('partnerContent');
            if (!nextContent) {
                window.location.href = res.url || target.href;
                return;
            }

            const elapsed = performance.now() - start;
            if (!force && elapsed < 180) await sleep(180 - elapsed);
            if (activeController.signal.aborted) return;

            document.title = doc.title || document.title;
            const nextTitle = doc.getElementById('partnerPageTitle');
            if (partnerPageTitle && nextTitle) partnerPageTitle.textContent = nextTitle.textContent;

            const nextActions = doc.getElementById('partnerTopbarActions');
            if (partnerTopbarActions && nextActions) partnerTopbarActions.innerHTML = nextActions.innerHTML;

            partnerContent.innerHTML = nextContent.innerHTML;
            if (force) {
                window.scrollTo({ top: scrollY, behavior: 'instant' });
            } else {
                partnerContent.classList.remove('spa-enter');
                void partnerContent.offsetWidth;
                partnerContent.classList.add('spa-enter');
            }

            const nextNav = doc.querySelectorAll('.sidebar-nav .nav-item');
            const currNav = document.querySelectorAll('.sidebar-nav .nav-item');
            currNav.forEach((item, idx) => item.classList.toggle('is-active', nextNav[idx]?.classList.contains('is-active') ?? false));

            if (push && !force) {
                const finalUrl = res.url ? new URL(res.url) : target;
                finalUrl.hash = target.hash;
                history.pushState({ spa: true }, '', finalUrl.href);
            }

            initPage();
            setProgress('done');
        } catch (err) {
            if (err.name === 'AbortError') return;
            console.error('SPA navigation failed, reloading:', err);
            window.location.href = target.href;
        }
    }

    if (partnerContent) {
        history.replaceState({ spa: true }, '', window.location.href);
        document.addEventListener('click', (e) => {
            if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
            const anchor = e.target.closest('a[href]');
            if (!isSpaLink(anchor)) return;
            e.preventDefault();
            navigateSpa(anchor.href, { push: true });
        });
        window.addEventListener('popstate', () => navigateSpa(window.location.href, { push: false }));

        // GET filter forms (date range etc.) navigate through the SPA router
        document.addEventListener('submit', (e) => {
            const form = e.target.closest('form[data-spa-get]');
            if (!form) return;
            e.preventDefault();
            const target = new URL(form.action, window.location.origin);
            new FormData(form).forEach((v, k) => { if (String(v) !== '') target.searchParams.set(k, String(v)); });
            navigateSpa(target.href, { push: true });
        });
        document.addEventListener('change', (e) => {
            if (e.target.matches?.('[data-auto-submit]')) e.target.form?.requestSubmit();
        });
    }

    function reloadPage() {
        if (!partnerContent) {
            window.location.reload();
            return Promise.resolve();
        }
        return navigateSpa(window.location.href, { push: false, force: true });
    }

    window.HappyPartner = {
        api, url, showToast, escapeHtml, formatBdt, formatMoney, unitPcs, productImg, productSvgUri,
        bnDigits, bnNum, bnUnit, bnStatus,
        setButtonLoading, withButtonLoading, openModal, closeAllModals, formError, submitAction, reloadPage,
        registerPage: (init) => pageModules.push(init),
    };

    // Page scripts load after this file; run once they have registered.
    document.addEventListener('DOMContentLoaded', initPage);

})();
