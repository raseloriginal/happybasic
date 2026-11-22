(() => {
    'use strict';
    const H = window.HappyPartner;

    const signed = (n) => `${Number(n) >= 0 ? '+' : '−'}${H.formatMoney(Math.abs(Number(n)))}`;

    // Orders page: item detail modal
    H.registerPage(() => {
        const modal = document.getElementById('orderDetailModal');
        if (!modal) return;
        document.getElementById('partnerContent')?.querySelector('.data-table')?.addEventListener('click', (e) => {
            if (!e.target.closest('[data-view-order]')) return;
            const o = JSON.parse(e.target.closest('tr').dataset.order);
            document.getElementById('orderDetailTitle').textContent = `${H.bnDigits(o.code)} · ${o.retailer}`;
            document.getElementById('orderDetailSub').textContent = `${H.bnDigits(o.date)} · SR ${o.sr} · ${o.company} · ${H.bnStatus(o.status_key)}${o.trip ? ` · ${H.bnDigits(o.trip)}` : ''}`;
            document.getElementById('orderDetailTbody').innerHTML = o.items.map((it) => `
                <tr>
                    <td class="cell-primary">${H.escapeHtml(it.name)}</td>
                    <td class="text-right tabular">${H.bnNum(it.pcs)} পিস<div class="cell-sub">${H.escapeHtml(H.bnDigits(it.qty))}</div></td>
                    <td class="text-right tabular">${H.formatMoney(it.base_rate_pc)}</td>
                    <td class="text-right tabular">${H.formatMoney(it.sr_rate_pc)}</td>
                    <td class="text-right tabular"><strong>${H.formatMoney(it.total)}</strong></td>
                    <td class="text-right tabular ${it.oc > 0 ? 'is-ok' : (it.oc < 0 ? 'is-danger' : '')}">${signed(it.oc)}</td>
                </tr>`).join('');
            H.openModal('orderDetailModal');
        });
    });

    // Company ledger page: add / delete manual entries
    H.registerPage(() => {
        const form = document.getElementById('ledgerEntryForm');
        if (!form) return;
        const type = form.elements.type;
        const syncType = () => { form.querySelector('[data-adjust-only]').hidden = type.value !== 'adjustment'; };
        type.addEventListener('change', syncType);
        syncType();

        form.addEventListener('submit', (e) => {
            e.preventDefault();
            const f = form.elements;
            const btn = form.querySelector('button[type="submit"]');
            H.submitAction(btn, form, 'সংরক্ষণ হচ্ছে…', () => H.api('POST', H.url('/partner/company-ledger'), {
                company_id: Number(f.company_id.value),
                type: f.type.value,
                side: f.side.value,
                amount: f.amount.value,
                date: f.date.value,
                note: f.note.value,
            }));
        });

        document.querySelector('#partnerContent .panel')?.addEventListener('click', async (e) => {
            const btn = e.target.closest('[data-delete-ledger]');
            if (!btn || !window.confirm('খাতার এই এন্ট্রি মুছবেন?')) return;
            await H.submitAction(btn, null, 'মুছে ফেলা হচ্ছে…', () => H.api('DELETE', H.url(`/partner/company-ledger/${btn.dataset.deleteLedger}`)));
        });
    });
})();
