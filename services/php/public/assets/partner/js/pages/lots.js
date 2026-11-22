(() => {
    'use strict';
    const H = window.HappyPartner;

    H.registerPage(() => {
        const app = document.getElementById('lotsApp');
        if (!app) return;

        const products = JSON.parse(app.dataset.products || '[]');
        const tbody = document.getElementById('lotsTbody');
        const search = document.getElementById('lotSearch');
        const companyFilter = document.getElementById('lotCompanyFilter');
        const countEl = document.getElementById('lotCount');
        const emptyEl = document.getElementById('lotsEmpty');
        const form = document.getElementById('addLotForm');
        const rows = document.getElementById('lotRowsContainer');
        const totalEl = document.getElementById('lotEstimatedTotal');
        const companySel = document.getElementById('lot_company');

        function filterLots() {
            const q = (search?.value || '').trim().toLowerCase();
            const cmp = companyFilter?.value || '';
            let visible = 0;
            tbody?.querySelectorAll('[data-lot-row]').forEach((tr) => {
                const ok = (!q || (tr.dataset.search || '').includes(q)) && (!cmp || tr.dataset.company === cmp);
                tr.hidden = !ok;
                if (ok) visible++;
            });
            if (countEl) countEl.textContent = H.bnNum(visible);
            if (emptyEl && tbody?.children.length) emptyEl.hidden = visible > 0;
        }
        search?.addEventListener('input', filterLots);
        companyFilter?.addEventListener('change', filterLots);

        const productById = (id) => products.find((p) => String(p.id) === String(id));

        function productOptions() {
            const cid = companySel.value;
            const list = products.filter((p) => String(p.company_id) === cid);
            if (!cid) return '<option value="">আগে কোম্পানি নির্বাচন করুন</option>';
            if (!list.length) return '<option value="">এই কোম্পানির কোনো পণ্য নেই</option>';
            return '<option value="">পণ্য নির্বাচন করুন</option>' + list.map((p) =>
                `<option value="${p.id}">${H.escapeHtml(p.name)} (${H.bnNum(p.qty_per_unit)} পিস/${H.escapeHtml(H.bnUnit(p.unit_type))})</option>`).join('');
        }

        function recalc() {
            let total = 0;
            rows.querySelectorAll('.lot-item-row').forEach((row) => {
                const p = productById(row.querySelector('[data-lot-product]').value);
                const pcs = Math.max(0, Math.floor(Number(row.querySelector('[data-lot-qty]').value || 0)));
                const price = Number(row.querySelector('[data-lot-price]').value || 0);
                const hint = row.querySelector('[data-lot-conv]');
                hint.textContent = p && pcs > 0 ? H.unitPcs(pcs, p.qty_per_unit, p.unit_type) : '';
                if (pcs > 0 && price > 0) total += pcs * price;
            });
            totalEl.textContent = H.formatMoney(total);
            const all = rows.querySelectorAll('[data-remove-lot-row]');
            all.forEach((b) => { b.disabled = all.length <= 1; });
        }

        function addRow() {
            const row = document.createElement('div');
            row.className = 'lot-item-row';
            row.innerHTML = `
                <select data-lot-product required>${productOptions()}</select>
                <div class="qty-with-hint">
                    <span class="qty-hint tabular" data-lot-conv></span>
                    <input type="number" min="1" step="1" placeholder="পিস" data-lot-qty required>
                </div>
                <input type="number" min="0.01" step="0.01" placeholder="দর / পিস" data-lot-price required>
                <input type="date" data-lot-expire required>
                <button type="button" class="lot-row-remove" data-remove-lot-row title="সারি সরান" aria-label="সারি সরান">×</button>`;
            rows.appendChild(row);
            recalc();
        }

        rows?.addEventListener('change', (e) => {
            const sel = e.target.closest('[data-lot-product]');
            if (sel) {
                const p = productById(sel.value);
                const price = sel.closest('.lot-item-row').querySelector('[data-lot-price]');
                if (p && p.company_price_pc > 0 && !price.value) price.value = p.company_price_pc;
            }
            recalc();
        });
        rows?.addEventListener('input', recalc);
        rows?.addEventListener('click', (e) => {
            const btn = e.target.closest('[data-remove-lot-row]');
            if (!btn || rows.children.length <= 1) return;
            btn.closest('.lot-item-row').remove();
            recalc();
        });
        companySel?.addEventListener('change', () => {
            rows.querySelectorAll('[data-lot-product]').forEach((sel) => { sel.innerHTML = productOptions(); });
            recalc();
        });
        document.getElementById('addLotRowBtn')?.addEventListener('click', addRow);

        document.querySelector('[data-lot-add]')?.addEventListener('click', () => {
            form.reset();
            H.formError(form, '');
            rows.innerHTML = '';
            addRow();
            H.openModal('addLotModal');
        });

        tbody?.addEventListener('click', async (e) => {
            const tr = e.target.closest('[data-lot-row]');
            if (!tr) return;
            const lot = JSON.parse(tr.dataset.lot);
            if (e.target.closest('[data-delete-lot]')) {
                if (!window.confirm(`${H.bnDigits(lot.code)} লটটি মুছবেন? এর স্টক ও কোম্পানি খাতার এন্ট্রিও মুছে যাবে।`)) return;
                await H.submitAction(e.target.closest('button'), null, 'মুছে ফেলা হচ্ছে…', () => H.api('DELETE', H.url(`/partner/lots/${lot.id}`)));
                return;
            }
            if (!e.target.closest('[data-view-lot]')) return;
            document.getElementById('lotDetailTitle').textContent = H.bnDigits(lot.code);
            document.getElementById('lotDetailSub').textContent = `${lot.company} · ${H.bnDigits(lot.date)} · মোট ${H.formatMoney(lot.total_value)}${lot.notes ? ` · ${lot.notes}` : ''}`;
            document.getElementById('lotDetailTbody').innerHTML = lot.rows.map((r) => `
                <tr>
                    <td class="cell-primary">${H.escapeHtml(r.product)}</td>
                    <td class="text-right tabular">${H.bnNum(r.pcs)} পিস<div class="cell-sub">${H.escapeHtml(H.bnDigits(r.qty))}</div></td>
                    <td class="text-right tabular">${H.bnNum(r.remaining_pcs)} পিস</td>
                    <td class="text-right tabular">${H.formatMoney(r.company_price)}</td>
                    <td class="text-right tabular"><strong>${H.formatMoney(r.subtotal)}</strong></td>
                    <td class="tabular nowrap">${H.escapeHtml(H.bnDigits(r.expire_date))}</td>
                </tr>`).join('');
            H.openModal('lotDetailModal');
        });

        form?.addEventListener('submit', (e) => {
            e.preventDefault();
            const items = Array.from(rows.querySelectorAll('.lot-item-row')).map((row) => ({
                product_id: Number(row.querySelector('[data-lot-product]').value || 0),
                pcs: Math.floor(Number(row.querySelector('[data-lot-qty]').value || 0)),
                price_pc: Number(row.querySelector('[data-lot-price]').value || 0),
                expire_date: row.querySelector('[data-lot-expire]').value,
            }));
            if (!companySel.value || items.some((it) => !it.product_id || it.pcs < 1 || it.price_pc <= 0 || !it.expire_date)) {
                H.formError(form, 'কোম্পানি নির্বাচন করুন এবং প্রতিটি সারির সব তথ্য (পণ্য, পিস, দর, মেয়াদ) পূরণ করুন।');
                return;
            }
            const btn = form.querySelector('button[type="submit"]');
            H.submitAction(btn, form, 'সংরক্ষণ হচ্ছে…', () => H.api('POST', H.url('/partner/lots'), {
                company_id: Number(companySel.value),
                lot_date: form.elements.lot_date.value,
                notes: form.elements.notes.value,
                items,
            }));
        });
    });
})();
