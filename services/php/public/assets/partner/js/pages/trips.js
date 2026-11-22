(() => {
    'use strict';
    const H = window.HappyPartner;

    const STATUS_BADGE = { pending: 'badge-warning', dispatched: 'badge-info', in_review: 'badge-info', settled: 'badge-success' };

    H.registerPage(() => {
        const app = document.getElementById('tripsApp');
        if (!app) return;

        let trips = JSON.parse(app.dataset.trips || '[]');
        const products = JSON.parse(app.dataset.products || '[]');
        let active = null;

        const grid = document.getElementById('tripsGrid');
        const gridSection = document.getElementById('tripsGridSection');
        const detailSection = document.getElementById('tripDetailSection');
        const list = document.getElementById('tripProductList');
        const dispatchBtn = document.getElementById('dispatchTripBtn');
        const extraBox = document.getElementById('tripAddExtra');
        const extraSelect = document.getElementById('extraProductSelect');
        const extraPcs = document.getElementById('extraProductPcs');

        const srList = document.getElementById('srPickerList');
        const dsrList = document.getElementById('dsrPickerList');
        const orderDate = document.getElementById('tripOrderDate');
        const deliveryDate = document.getElementById('tripDeliveryDate');
        const newTripForm = document.getElementById('newTripForm');
        const newTripError = document.getElementById('newTripError');

        // ------------------------------------------------------------------ grid
        function renderGrid() {
            grid.querySelectorAll('[data-trip-box]').forEach((n) => n.remove());
            trips.forEach((t) => {
                const checked = t.items.filter((i) => i.checked).length;
                const box = document.createElement('button');
                box.type = 'button';
                box.className = 'trip-box';
                box.dataset.tripBox = t.id;
                box.innerHTML = `
                    <div class="trip-box-head">
                        <div>
                            <h3 class="trip-dsr-name">${H.escapeHtml(t.dsr)}</h3>
                            <span class="muted small tabular">${H.escapeHtml(H.bnDigits(t.code))} · অর্ডার ${H.escapeHtml(H.bnDigits(t.order_date || '—'))}</span>
                        </div>
                        <span class="badge ${STATUS_BADGE[t.status_key] || 'badge-neutral'}">${H.escapeHtml(H.bnStatus(t.status_key))}</span>
                    </div>
                    <div class="trip-sr-pills">${t.srs.map((s) => `<span class="sr-pill">SR: ${H.escapeHtml(s.name)}</span>`).join('')}</div>
                    <div class="trip-box-foot">
                        <span class="muted tabular">${H.bnNum(t.retailers)} দোকান · ${H.bnNum(t.items.length)} পণ্য (${H.bnNum(checked)}/${H.bnNum(t.items.length)} যাচাই)</span>
                        <strong class="tabular">${H.formatMoney(t.order_value)}</strong>
                    </div>`;
                box.addEventListener('click', () => openDetail(t.id));
                grid.appendChild(box);
            });
        }

        function replaceTrip(t) {
            const idx = trips.findIndex((x) => x.id === t.id);
            if (t.date !== app.dataset.date) {
                if (idx >= 0) trips.splice(idx, 1);
            } else if (idx >= 0) {
                trips[idx] = t;
            } else {
                trips.unshift(t);
            }
            if (active && active.id === t.id) active = t;
        }

        // ---------------------------------------------------------------- detail
        function diffLabel(it) {
            const d = it.loaded_pcs - it.ordered_pcs;
            if (it.extra) return `<span class="qty-diff is-extra">+${H.bnNum(it.loaded_pcs)} অতিরিক্ত</span>`;
            if (d === 0) return '<span class="qty-diff">= অর্ডার সমান</span>';
            return `<span class="qty-diff ${d > 0 ? 'is-more' : 'is-less'}">${d > 0 ? '+' : '−'}${H.bnNum(Math.abs(d))} পিস ${d > 0 ? 'বেশি' : 'কম'}</span>`;
        }

        function rowHtml(it, locked) {
            const short = it.loaded_pcs > it.stock_pcs && !locked;
            return `
                <div class="checklist-row trip-item-row ${it.checked ? 'is-checked' : ''}" data-product="${it.product_id}">
                    <input type="checkbox" class="checklist-check" data-check ${it.checked ? 'checked' : ''} ${locked ? 'disabled' : ''} aria-label="যাচাইকৃত">
                    <div class="checklist-info">
                        <img class="checklist-img" src="${H.productImg(it)}" alt="">
                        <div>
                            <div class="checklist-name">${H.escapeHtml(it.name)}</div>
                            <div class="muted small tabular">${H.bnNum(it.qty_per_unit)} পিস / ${H.escapeHtml(H.bnUnit(it.unit_type))} · স্টক ${H.bnNum(it.stock_pcs)} পিস</div>
                        </div>
                    </div>
                    <div class="text-right tabular">
                        <strong>${H.bnNum(it.ordered_pcs)} পিস</strong>
                        <div class="muted small">${H.escapeHtml(H.unitPcs(it.ordered_pcs, it.qty_per_unit, it.unit_type))}</div>
                    </div>
                    <div class="qty-with-hint">
                        <span class="qty-hint tabular" data-conv>${H.escapeHtml(H.unitPcs(it.loaded_pcs, it.qty_per_unit, it.unit_type))}</span>
                        <input type="number" class="select-input load-input" min="0" step="1" value="${it.loaded_pcs}" data-load ${locked ? 'disabled' : ''}>
                    </div>
                    <div class="text-right" data-diff>${diffLabel(it)}${short ? '<div class="qty-diff is-less">স্টকের বেশি</div>' : ''}</div>
                    <div class="text-right">${it.extra && !locked ? '<button type="button" class="lot-row-remove" data-remove-extra title="অতিরিক্ত পণ্য সরান">×</button>' : ''}</div>
                </div>`;
        }

        function renderDetail() {
            const t = active;
            const locked = t.status_key !== 'pending';
            document.getElementById('tripDetailTitle').textContent = `${t.dsr} — ${H.bnDigits(t.code)}`;
            document.getElementById('tripDetailSubtitle').textContent =
                `ডেলিভারি ${H.bnDigits(t.date)} · অর্ডার ${H.bnDigits(t.order_date || '—')} · ${H.bnNum(t.orders)}টি অর্ডার · ${H.bnNum(t.retailers)}টি দোকান · ${H.formatMoney(t.order_value)}`;
            document.getElementById('tripDetailSrs').innerHTML = t.srs.map((s) => `
                <span class="sr-pill">SR: ${H.escapeHtml(s.name)}${locked ? '' : ` <button type="button" class="pill-x" data-remove-sr="${s.id}" title="ট্রিপ থেকে SR সরান">×</button>`}</span>`).join('');

            list.innerHTML = t.items.length ? t.items.map((it) => rowHtml(it, locked)).join('') : '<div class="empty-state"><p>এই ট্রিপে কোনো পণ্য নেই।</p></div>';

            const checked = t.items.filter((i) => i.checked).length;
            document.getElementById('tripCheckCounter').textContent = `${H.bnNum(checked)} / ${H.bnNum(t.items.length)} যাচাইকৃত`;
            const badge = document.getElementById('tripDetailStatusBadge');
            badge.textContent = H.bnStatus(t.status_key);
            badge.className = `badge ${STATUS_BADGE[t.status_key] || 'badge-neutral'}`;
            dispatchBtn.textContent = locked ? H.bnStatus(t.status_key) : 'ডিসপ্যাচ করুন';
            dispatchBtn.disabled = locked || t.items.length === 0 || checked < t.items.length;

            extraBox.hidden = locked;
            const onTrip = new Set(t.items.map((i) => i.product_id));
            extraSelect.innerHTML = '<option value="">অতিরিক্ত পণ্য যোগ করুন…</option>' + products
                .filter((p) => !onTrip.has(p.id))
                .map((p) => `<option value="${p.id}">${H.escapeHtml(p.name)} · ${H.escapeHtml(p.company)} (স্টক ${H.bnNum(p.stock_pcs)} পিস)</option>`).join('');
        }

        function openDetail(id) {
            active = trips.find((t) => t.id === id) || null;
            if (!active) return;
            renderDetail();
            gridSection.hidden = true;
            detailSection.hidden = false;
            window.scrollTo({ top: 0, behavior: 'instant' });
        }

        document.getElementById('backToTripsBtn')?.addEventListener('click', () => {
            active = null;
            detailSection.hidden = true;
            gridSection.hidden = false;
            renderGrid();
        });

        async function patchItem(productId, body) {
            try {
                const res = await H.api('PATCH', H.url(`/partner/trips/${active.id}/items/${productId}`), body);
                replaceTrip(res.trip);
                return true;
            } catch (err) {
                H.showToast(err.message);
                return false;
            }
        }

        list.addEventListener('input', (e) => {
            const input = e.target.closest('[data-load]');
            if (!input) return;
            const row = input.closest('[data-product]');
            const it = active.items.find((i) => String(i.product_id) === row.dataset.product);
            const pcs = Math.max(0, Math.floor(Number(input.value || 0)));
            row.querySelector('[data-conv]').textContent = H.unitPcs(pcs, it.qty_per_unit, it.unit_type);
            row.querySelector('[data-diff]').innerHTML = diffLabel({ ...it, loaded_pcs: pcs }) + (pcs > it.stock_pcs ? '<div class="qty-diff is-less">স্টকের বেশি</div>' : '');
        });

        list.addEventListener('change', async (e) => {
            const row = e.target.closest('[data-product]');
            if (!row) return;
            const pid = row.dataset.product;
            if (e.target.matches('[data-load]')) {
                const pcs = Math.max(0, Math.floor(Number(e.target.value || 0)));
                if (await patchItem(pid, { loaded_pcs: pcs, checked: false })) renderDetail();
            } else if (e.target.matches('[data-check]')) {
                if (await patchItem(pid, { checked: e.target.checked })) renderDetail();
                else e.target.checked = !e.target.checked;
            }
        });

        list.addEventListener('click', async (e) => {
            if (!e.target.closest('[data-remove-extra]')) return;
            const pid = e.target.closest('[data-product]').dataset.product;
            try {
                const res = await H.api('DELETE', H.url(`/partner/trips/${active.id}/items/${pid}`));
                replaceTrip(res.trip);
                renderDetail();
            } catch (err) { H.showToast(err.message); }
        });

        document.getElementById('tripDetailSrs')?.addEventListener('click', async (e) => {
            const btn = e.target.closest('[data-remove-sr]');
            if (!btn || !window.confirm('এই SR ও তাঁর অর্ডারগুলো ট্রিপ থেকে সরাতে চান? অর্ডারগুলো আবার আন-অ্যাসাইন্ড হয়ে যাবে।')) return;
            try {
                const res = await H.api('DELETE', H.url(`/partner/trips/${active.id}/srs/${btn.dataset.removeSr}`));
                H.showToast(res.message);
                if (res.trip) {
                    replaceTrip(res.trip);
                    renderDetail();
                } else {
                    trips = trips.filter((t) => t.id !== active.id);
                    document.getElementById('backToTripsBtn').click();
                }
            } catch (err) { H.showToast(err.message); }
        });

        document.getElementById('addExtraBtn')?.addEventListener('click', async (e) => {
            const pid = Number(extraSelect.value || 0);
            const pcs = Math.floor(Number(extraPcs.value || 0));
            if (!pid || pcs < 1) { H.showToast('একটি পণ্য নির্বাচন করে পিস সংখ্যা লিখুন।'); return; }
            try {
                const res = await H.withButtonLoading(e.currentTarget, 'যোগ হচ্ছে…', () => H.api('POST', H.url(`/partner/trips/${active.id}/items`), { product_id: pid, pcs }));
                extraPcs.value = '';
                replaceTrip(res.trip);
                renderDetail();
            } catch (err) { H.showToast(err.message); }
        });

        dispatchBtn?.addEventListener('click', async () => {
            if (!active || !window.confirm(`${H.bnDigits(active.code)} ট্রিপটি ডিসপ্যাচ করবেন? লোড করা স্টক FIFO নিয়মে বাদ যাবে এবং ট্রিপ লক হবে।`)) return;
            try {
                const res = await H.withButtonLoading(dispatchBtn, 'ডিসপ্যাচ হচ্ছে…', () => H.api('POST', H.url(`/partner/trips/${active.id}/dispatch`)));
                replaceTrip(res.trip);
                renderDetail();
                H.showToast(res.message);
            } catch (err) { H.showToast(err.message); }
        });

        // ------------------------------------------------------------ new trip
        async function loadPlanner() {
            newTripError.hidden = true;
            srList.innerHTML = dsrList.innerHTML = '<div class="muted small" style="padding:12px">লোড হচ্ছে…</div>';
            document.getElementById('selectedSrCount').textContent = '০';
            try {
                const res = await H.api('GET', H.url(`/partner/trips/planner?order_date=${orderDate.value}&delivery_date=${deliveryDate.value}`));
                srList.innerHTML = res.srs.length ? res.srs.map((sr) => `
                    <label class="picker-item ${sr.completed ? '' : 'is-faded'}" title="${sr.completed ? '' : 'SR এখনো এই দিনের অর্ডার সম্পন্ন করেননি'}">
                        <input type="checkbox" value="${sr.id}" ${sr.completed ? '' : 'disabled'}>
                        <div class="picker-item-body">
                            <div class="picker-item-title">
                                <span>${H.escapeHtml(sr.name)}</span>
                                <span class="tabular muted small">${H.formatMoney(sr.value)}</span>
                            </div>
                            <div class="picker-item-sub tabular">${H.escapeHtml(sr.area)} · ${H.bnNum(sr.orders)} অর্ডার · ${H.bnNum(sr.retailers)} দোকান · ${H.bnNum(sr.products)} পণ্য${sr.completed ? '' : ' · <strong>সম্পন্ন হয়নি</strong>'}</div>
                        </div>
                    </label>`).join('') : '<div class="muted small" style="padding:12px">এই তারিখে কোনো আন-অ্যাসাইন্ড SR অর্ডার নেই।</div>';

                dsrList.innerHTML = res.dsrs.length ? res.dsrs.map((d) => {
                    const unsettled = d.open_trip && d.open_trip !== d.trip;
                    const locked = (d.trip && d.trip_status !== 'pending') || unsettled;
                    return `
                    <label class="picker-item ${locked ? 'is-faded' : ''}">
                        <input type="radio" name="dsr_id" value="${d.id}" ${locked ? 'disabled' : ''}>
                        <div class="picker-item-body">
                            <div class="picker-item-title">
                                <span>${H.escapeHtml(d.name)}</span>
                                ${unsettled ? `<span class="badge badge-warning">বাকি ট্রিপ ${H.escapeHtml(H.bnDigits(d.open_trip))}</span>` : (d.trip ? `<span class="badge ${locked ? 'badge-info' : 'badge-neutral'}">${locked ? 'ডিসপ্যাচড' : 'ট্রিপ আছে'}</span>` : '')}
                            </div>
                            <div class="picker-item-sub tabular">${H.escapeHtml(H.bnDigits(d.phone))}${d.trip ? ` · ${H.escapeHtml(H.bnDigits(d.trip))}` : ''}</div>
                        </div>
                    </label>`;
                }).join('') : '<div class="muted small" style="padding:12px">কোনো সক্রিয় ডেলিভারিম্যান নেই। আগে DSR যোগ করুন।</div>';
            } catch (err) {
                newTripError.textContent = err.message;
                newTripError.hidden = false;
            }
        }

        srList?.addEventListener('change', (e) => {
            e.target.closest('.picker-item')?.classList.toggle('is-selected', e.target.checked);
            document.getElementById('selectedSrCount').textContent = H.bnNum(srList.querySelectorAll('input:checked').length);
        });
        dsrList?.addEventListener('change', (e) => {
            dsrList.querySelectorAll('.picker-item').forEach((i) => i.classList.remove('is-selected'));
            e.target.closest('.picker-item')?.classList.add('is-selected');
        });
        orderDate?.addEventListener('change', () => {
            if (deliveryDate.value < orderDate.value) deliveryDate.value = orderDate.value;
            loadPlanner();
        });
        deliveryDate?.addEventListener('change', loadPlanner);

        document.querySelectorAll('[data-new-trip]').forEach((b) => b.addEventListener('click', () => {
            H.openModal('newTripModal');
            loadPlanner();
        }));

        newTripForm?.addEventListener('submit', async (e) => {
            e.preventDefault();
            const srIds = Array.from(srList.querySelectorAll('input:checked')).map((i) => Number(i.value));
            const dsrId = Number(dsrList.querySelector('input:checked')?.value || 0);
            if (!srIds.length || !dsrId) {
                newTripError.textContent = 'বাম দিক থেকে অন্তত একজন SR এবং ডান দিক থেকে একজন DSR নির্বাচন করুন।';
                newTripError.hidden = false;
                return;
            }
            newTripError.hidden = true;
            try {
                const res = await H.withButtonLoading(document.getElementById('createTripSubmitBtn'), 'অ্যাসাইন হচ্ছে…', () => H.api('POST', H.url('/partner/trips'), {
                    sr_ids: srIds, dsr_id: dsrId, order_date: orderDate.value, delivery_date: deliveryDate.value,
                }));
                H.closeAllModals();
                H.showToast(res.message);
                if (res.trip.date !== app.dataset.date) {
                    window.location.href = H.url(`/partner/trips?date=${res.trip.date}`);
                    return;
                }
                replaceTrip(res.trip);
                renderGrid();
                openDetail(res.trip.id);
            } catch (err) {
                newTripError.textContent = err.message;
                newTripError.hidden = false;
            }
        });

        renderGrid();
    });
})();
