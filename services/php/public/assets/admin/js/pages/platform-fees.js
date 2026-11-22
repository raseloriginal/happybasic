(() => {
    'use strict';
    const H = window.HappyAdmin;

    H.registerPage(() => {
        const app = document.getElementById('adminFeesApp');
        if (!app) return;

        const $ = (id) => document.getElementById(id);
        const esc = H.escapeHtml;
        const form = $('adminFeeForm');
        const tbody = $('adminFeeTbody');
        const partnerSelect = $('adminFeePartner');
        const ownershipFilter = $('adminFeeOwnership');
        const saveBtns = [$('adminFeeSaveBtn'), $('adminFeeSaveTopBtn')];
        let links = JSON.parse(app.dataset.links || '[]');

        const money = (n) => Number(n || 0).toLocaleString('en-US', { maximumFractionDigits: 2 });
        const fmtDate = (v) => (v ? new Date(v.replace(' ', 'T')).toLocaleString('en-GB', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '');
        const inputs = () => [...tbody.querySelectorAll('input[data-company-id]')];
        const dirtyInputs = () => inputs().filter((i) => i.value.trim() !== i.dataset.original);

        function syncDirty() {
            const n = dirtyInputs().length;
            saveBtns.forEach((b) => { if (b) b.disabled = n === 0; });
            $('adminFeeDirty').textContent = n
                ? `${n} unsaved change(s). New fees apply from the moment you save; past sales keep their old fee.`
                : 'A changed fee applies to sales from the moment you save. Past sales keep the fee they were made under.';
        }

        function render() {
            const pid = Number(partnerSelect.value);
            const rows = links.filter((l) => l.partner_id === pid);
            const shown = rows.filter((l) => !ownershipFilter.value || l.ownership === ownershipFilter.value);
            tbody.innerHTML = shown.map((l) => {
                const fee = String(l.platform_fee_per_lakh);
                const inactive = l.company_status === 'Active' ? '' : ' <span class="badge badge-neutral">Inactive</span>';
                const dealer = l.ownership === 'Dealer'
                    ? `<div class="cell-primary">${esc(l.dealer)}</div><div class="cell-sub tabular">Dealer ${esc(l.dealer_profit_share)}% · Partner ${esc(l.partner_profit_share)}%</div>`
                    : '<span class="muted small">Direct ownership</span>';
                return `<tr>
                    <td><div class="cell-primary">${esc(l.company)}${inactive}</div></td>
                    <td><span class="badge ${l.ownership === 'Owned' ? 'badge-success' : 'badge-info'}">${esc(l.ownership)}</span></td>
                    <td>${dealer}</td>
                    <td class="text-right tabular">${l.srs}</td>
                    <td class="text-right">
                        <input class="fee-input tabular" type="number" min="0" max="99999999" step="0.01" required
                            data-company-id="${l.company_id}" data-original="${esc(fee)}" value="${esc(fee)}"
                            aria-label="Platform fee for ${esc(l.company)}">
                        <div class="cell-sub">${l.fee_since ? `since ${esc(fmtDate(l.fee_since))}` : 'not set yet'}</div>
                    </td>
                    <td class="text-right">
                        <button type="button" class="btn btn-ghost btn-xs" data-history="${l.company_id}" ${l.fee_changes ? '' : 'disabled'}>
                            History${l.fee_changes ? ` (${l.fee_changes})` : ''}
                        </button>
                    </td>
                </tr>`;
            }).join('');
            $('adminFeeCount').textContent = String(rows.length);
            $('adminFeeEmpty').hidden = shown.length > 0;
            if (!rows.length) $('adminFeeEmpty').querySelector('p').textContent = 'No companies connected to this partner yet. Add an SR (Owned or via Dealer) to connect a company.';
            else if (!shown.length) $('adminFeeEmpty').querySelector('p').textContent = 'No companies match this ownership filter.';
            syncDirty();
        }

        function changePartner() {
            if (dirtyInputs().length && !window.confirm('Discard unsaved fee changes?')) {
                partnerSelect.value = partnerSelect.dataset.current;
                return;
            }
            partnerSelect.dataset.current = partnerSelect.value;
            const url = new URL(window.location.href);
            url.searchParams.set('partner', partnerSelect.value);
            window.history.replaceState(window.history.state, '', url);
            render();
        }

        partnerSelect.dataset.current = partnerSelect.value;
        partnerSelect.addEventListener('change', changePartner);
        ownershipFilter.addEventListener('change', () => {
            if (dirtyInputs().length && !window.confirm('Discard unsaved fee changes?')) return;
            render();
        });
        tbody.addEventListener('input', (e) => {
            if (e.target.matches('input[data-company-id]')) e.target.removeAttribute('aria-invalid');
            syncDirty();
        });

        async function openHistory(companyId) {
            const body = $('adminFeeHistoryBody');
            body.innerHTML = '<p class="muted small">Loading...</p>';
            H.openDrawer('adminFeeHistoryDrawer');
            try {
                const { history: h } = await H.api('GET', `${app.dataset.baseUrl}/${partnerSelect.value}/history/${companyId}`);
                const partner = partnerSelect.selectedOptions[0]?.textContent.trim() || '';
                $('adminFeeHistoryTitle').textContent = `Fee History · ${h.company}`;
                $('adminFeeHistorySub').textContent = `${partner}. Fee earned uses the rate frozen on each order, so a later change never alters it.`;
                const rows = h.periods.map((p, i) => `<tr>
                    <td class="nowrap">${esc(fmtDate(p.from))}<div class="cell-sub">${p.to ? `to ${esc(fmtDate(p.to))}` : 'to now'}</div></td>
                    <td class="text-right tabular nowrap">৳ ${money(p.fee_per_lakh)}${i === 0 ? ' <span class="badge badge-success">Current</span>' : ''}<div class="cell-sub">${esc(p.changed_by || '')}</div></td>
                    <td class="text-right tabular nowrap">৳ ${money(p.sales)}<div class="cell-sub">${p.orders} order(s)</div></td>
                    <td class="text-right tabular nowrap">৳ ${money(p.fee)}</td>
                </tr>`).join('');
                body.innerHTML = `<div class="table-wrap"><table class="data-table">
                    <thead><tr><th>Period</th><th class="text-right">Fee / Lakh</th><th class="text-right">Sales</th><th class="text-right">Fee Earned</th></tr></thead>
                    <tbody>${rows}</tbody>
                    <tfoot><tr><th>Total</th><th></th>
                        <th class="text-right tabular nowrap">৳ ${money(h.totals.sales)}<div class="cell-sub">${h.totals.orders} order(s)</div></th>
                        <th class="text-right tabular nowrap">৳ ${money(h.totals.fee)}</th></tr></tfoot>
                </table></div>`;
            } catch (err) {
                body.innerHTML = `<p class="muted small">${esc(err.message)}</p>`;
            }
        }

        tbody.addEventListener('click', (e) => {
            const btn = e.target.closest('[data-history]');
            if (btn) openHistory(btn.dataset.history);
        });

        form.addEventListener('submit', async (e) => {
            e.preventDefault();
            const dirty = dirtyInputs();
            if (!dirty.length) return;

            const bad = dirty.filter((i) => i.value.trim() === '' || !i.checkValidity());
            inputs().forEach((i) => i.removeAttribute('aria-invalid'));
            if (bad.length) {
                bad.forEach((i) => i.setAttribute('aria-invalid', 'true'));
                bad[0].focus();
                H.showToast('Enter a valid fee (0 or more) for every changed company.');
                return;
            }

            const fees = Object.fromEntries(dirty.map((i) => [i.dataset.companyId, i.value.trim()]));
            try {
                const res = await H.withButtonLoading($('adminFeeSaveBtn'), 'Saving...',
                    () => H.api('PUT', `${app.dataset.baseUrl}/${partnerSelect.value}`, { fees }));
                links = res.links;
                render();
                H.showToast(res.message);
            } catch (err) {
                Object.keys(err.errors || {}).forEach((k) => {
                    tbody.querySelector(`input[data-company-id="${k.replace('fees.', '')}"]`)?.setAttribute('aria-invalid', 'true');
                });
                H.showToast(err.message);
            }
        });

        render();
    });
})();
