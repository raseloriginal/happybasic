(() => {
    'use strict';
    const H = window.HappyPartner;

    H.registerPage(() => {
        const app = document.getElementById('duesApp');
        if (!app) return;
        const $ = (id) => document.getElementById(id);
        let cur = null;

        function showTab(tab) {
            let n = 0;
            app.querySelectorAll('.due-row').forEach((r) => {
                r.hidden = !r.dataset.tags.split(' ').includes(tab);
                if (!r.hidden) n += 1;
            });
            $('dueEmpty').hidden = n > 0;
            app.querySelectorAll('[data-due-tab]').forEach((b) => b.classList.toggle('is-active', b.dataset.dueTab === tab));
        }
        showTab('open');

        const post = (path, body) => H.api('POST', H.url(`/partner/dues/${path}`), body);
        function open(modal, form) {
            H.formError(form, '');
            $(modal).querySelector('[data-due-name]').textContent = `${cur.retailer} · বাকি ${H.formatBdt(cur.remaining)}`;
            H.openModal(modal);
        }
        const returnInputs = () => [...$('dueReturnItems').querySelectorAll('input')];
        function updateReturnValue() {
            const v = returnInputs().reduce((s, i) => s + (Number(i.value) || 0) * Number(i.dataset.rate), 0);
            $('dueReturnValue').textContent = H.formatBdt(Math.round(v * 100) / 100);
        }
        $('dueReturnItems').addEventListener('input', updateReturnValue);

        app.addEventListener('click', (e) => {
            const tab = e.target.closest('[data-due-tab]');
            if (tab) { showTab(tab.dataset.dueTab); return; }
            const row = e.target.closest('[data-due]');
            const btn = e.target.closest('button');
            if (!row || !btn) return;
            cur = JSON.parse(row.dataset.due);
            const has = (k) => btn.hasAttribute(`data-due-${k}`);

            if (has('approve')) {
                H.submitAction(btn, null, '…', () => post(`${cur.id}/approve`));
            } else if (has('undo')) {
                if (window.confirm(`${cur.retailer}: শেষ কাজটি আনডু করবেন?`)) H.submitAction(btn, null, '…', () => post(`${cur.id}/undo`));
            } else if (has('collect')) {
                $('dueCollectForm').elements.amount.value = cur.remaining;
                open('dueCollectModal', $('dueCollectForm'));
            } else if (has('limit')) {
                $('dueLimitForm').elements.limit.value = cur.limit ?? '';
                open('dueLimitModal', $('dueLimitForm'));
            } else if (has('return')) {
                // all pieces when the whole bill is unpaid, otherwise the partner counts them
                const all = cur.items.reduce((s, i) => s + i.pcs * i.rate, 0) <= cur.remaining + 0.004;
                $('dueReturnItems').innerHTML = cur.items.map((i) => `
                    <label class="due-return-item"><span>${H.escapeHtml(i.name)} <small class="muted">সর্বোচ্চ ${H.bnDigits(i.pcs)} পিস · ${H.formatBdt(i.rate)}/পিস</small></span>
                    <input type="number" min="0" max="${i.pcs}" step="1" value="${all ? i.pcs : 0}" data-pid="${i.product_id}" data-rate="${i.rate}"></label>`).join('');
                updateReturnValue();
                open('dueReturnModal', $('dueReturnForm'));
            }
        });

        const onSubmit = (id, task) => $(id).addEventListener('submit', (e) => {
            e.preventDefault();
            H.submitAction(e.target.querySelector('[type="submit"]'), e.target, 'সংরক্ষণ হচ্ছে…', () => task(e.target.elements));
        });
        onSubmit('dueSettingsForm', (f) => post('settings', { limit: f.limit.value, days: f.days.value }));
        onSubmit('dueLimitForm', (f) => post(`limits/${cur.retailer_id}`, { limit: f.limit.value }));
        onSubmit('dueCollectForm', (f) => post(`${cur.id}/collect`, { amount: f.amount.value }));
        onSubmit('dueReturnForm', () => post(`${cur.id}/return`, { items: Object.fromEntries(returnInputs().map((i) => [i.dataset.pid, i.value])) }));
    });
})();
