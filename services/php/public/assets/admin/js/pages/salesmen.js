(() => {
    'use strict';
    const H = window.HappyAdmin;

    H.registerPage(() => {
        const app = document.getElementById('adminSalesmenApp');
        if (!app) return;

        const $ = (id) => document.getElementById(id);
        const esc = H.escapeHtml;
        const companies = JSON.parse(app.dataset.companies || '[]');
        const dealers = JSON.parse(app.dataset.dealers || '[]');
        const form = $('adminSrForm');
        const search = $('adminSrSearch');
        const partnerFilter = $('adminSrPartnerFilter');
        const companyFilter = $('adminSrCompanyFilter');
        const statusFilter = $('adminSrStatusFilter');
        const ownershipSelect = $('sr_ownership');
        const partnerSelect = $('sr_partner_id');
        const dealerSelect = $('sr_dealer_id');
        const shareInput = $('sr_dealer_profit_share');
        const companySelect = $('sr_company');
        const activeOr = (list, keepId) => list.filter((i) => i.status === 'Active' || String(i.id) === String(keepId));
        const labelOf = (i, extra = '') => `${i.name}${extra}${i.status === 'Active' ? '' : ' (inactive)'}`;

        function syncOwnership() {
            const isDealer = ownershipSelect.value === 'Dealer';
            $('srPartnerGroup').hidden = isDealer;
            $('srDealerGroup').hidden = !isDealer;
            $('srDealerShareGroup').hidden = !isDealer;
            partnerSelect.required = !isDealer;
            dealerSelect.required = isDealer;
            shareInput.required = isDealer;
            syncHints();
        }

        function syncHints() {
            const d = dealers.find((x) => String(x.id) === dealerSelect.value);
            $('srDealerPartnerHint').textContent = d ? `Partner: ${d.partner_name}` : '';
            const v = parseFloat(shareInput.value);
            $('srPartnerShareHint').textContent = Number.isNaN(v) ? '' : `Partner share: ${Math.round((100 - v) * 100) / 100}%`;
        }

        ownershipSelect.addEventListener('change', syncOwnership);
        dealerSelect.addEventListener('change', syncHints);
        shareInput.addEventListener('input', syncHints);

        const table = H.crudTable({
            tbody: $('adminSrTbody'),
            form,
            baseUrl: app.dataset.baseUrl,
            key: 'sr',
            rowAttr: 'data-sr-row',
            datasetKey: 'sr',
            label: 'SR',
            plural: 'salesmen',
            emptyText: 'No salesmen yet. Click “Add SR” to create one.',
            drawerId: 'adminSrDrawer',
            countEl: $('adminSrCount'),
            emptyEl: $('adminSrEmpty'),
            filterInputs: [search, partnerFilter, companyFilter, statusFilter],
            matches: (tr) => {
                const q = (search?.value || '').trim().toLowerCase();
                return (!q || (tr.dataset.search || '').includes(q))
                    && (!partnerFilter.value || tr.dataset.partnerId === partnerFilter.value)
                    && (!companyFilter.value || tr.dataset.companyId === companyFilter.value)
                    && (!statusFilter.value || tr.dataset.status === statusFilter.value);
            },
            attrs: (tr, s) => {
                tr.dataset.partnerId = String(s.partner_id);
                tr.dataset.companyId = String(s.company_id);
                tr.dataset.status = s.status;
                tr.dataset.search = `${s.name} ${s.partner_name} ${s.number} ${s.company} ${s.dealer || ''}`.toLowerCase();
            },
            render: (s) => {
                const isActive = s.status === 'Active';
                const ownership = s.ownership === 'Dealer'
                    ? `<span class="badge badge-info">Dealer</span><div class="cell-sub">${esc(s.dealer)} · ${esc(s.dealer_profit_share)}% / ${esc(s.partner_profit_share)}%</div>`
                    : '<span class="badge badge-success">Owned</span>';
                return `
                    <td>
                        <div class="cell-primary">${esc(s.name)}</div>
                        <div class="cell-sub">${esc(s.partner_name)}</div>
                    </td>
                    <td class="tabular nowrap">${esc(s.number)}</td>
                    <td><span class="badge badge-neutral">${esc(s.company)}</span></td>
                    <td>${ownership}</td>
                    <td><span class="badge ${isActive ? 'badge-success' : 'badge-neutral'}" data-row-status>${esc(s.status)}</span></td>
                    <td class="text-right nowrap">
                        <div class="action-btns">
                            <button type="button" class="btn btn-ghost btn-xs" data-action="edit">Edit</button>
                            <button type="button" class="btn btn-ghost btn-xs" data-action="toggle">${isActive ? 'Deactivate' : 'Activate'}</button>
                            <button type="button" class="btn btn-danger-ghost btn-xs" data-action="delete">Delete</button>
                        </div>
                    </td>`;
            },
            beforeSubmit: syncOwnership,
            payload: (f) => {
                const data = H.formPayload(f);
                if (data.ownership === 'Dealer') delete data.partner_id;
                else { delete data.dealer_id; delete data.dealer_profit_share; }
                return data;
            },
            onOpen: (s) => {
                $('adminSrDrawerTitle').textContent = s ? 'Edit Salesman (SR)' : 'Add Salesman (SR)';
                $('adminSrSubmitBtn').textContent = s ? 'Update SR' : 'Save SR';
                H.setPasswordMode(form, 'sr_password', Boolean(s));
                ownershipSelect.value = s ? s.ownership : 'Owned';
                partnerSelect.value = s && s.ownership === 'Owned' ? String(s.partner_id) : (partnerFilter.value || '');
                H.setSelectOptions(dealerSelect, activeOr(dealers, s?.dealer_id), 'Select dealer', s?.dealer_id ?? '',
                    (d) => labelOf(d, ` (${d.partner_name})`));
                shareInput.value = s?.dealer_profit_share ?? '';
                H.setSelectOptions(companySelect, activeOr(companies, s?.company_id), 'Select company', s?.company_id ?? (companyFilter.value || ''),
                    (c) => labelOf(c));
                $('sr_name').value = s ? s.name : '';
                $('sr_number').value = s ? s.number : '';
                $('sr_status').value = s ? s.status : 'Active';
                $('sr_daily_target').value = s?.daily_target || '';
                syncOwnership();
            },
        });

        $('openAddSrBtn')?.addEventListener('click', table.openAdd);
    });
})();
