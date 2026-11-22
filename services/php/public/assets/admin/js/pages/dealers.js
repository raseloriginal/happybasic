(() => {
    'use strict';
    const H = window.HappyAdmin;

    H.registerPage(() => {
        const app = document.getElementById('adminDealersApp');
        if (!app) return;

        const $ = (id) => document.getElementById(id);
        const esc = H.escapeHtml;
        const form = $('adminDealerForm');
        const search = $('adminDealerSearch');
        const partnerFilter = $('adminDealerPartnerFilter');
        const statusFilter = $('adminDealerStatusFilter');
        let activeDetail = null;

        const table = H.crudTable({
            tbody: $('adminDealersTbody'),
            form,
            baseUrl: app.dataset.baseUrl,
            key: 'dealer',
            rowAttr: 'data-dealer-row',
            datasetKey: 'dealer',
            label: 'Dealer',
            plural: 'dealers',
            emptyText: 'No dealers yet. Click “Add Dealer” to create one.',
            drawerId: 'adminDealerDrawer',
            countEl: $('adminDealerCount'),
            emptyEl: $('adminDealersEmpty'),
            filterInputs: [search, partnerFilter, statusFilter],
            matches: (tr) => {
                const q = (search?.value || '').trim().toLowerCase();
                return (!q || (tr.dataset.search || '').includes(q))
                    && (!partnerFilter.value || tr.dataset.partnerId === partnerFilter.value)
                    && (!statusFilter.value || tr.dataset.status === statusFilter.value);
            },
            attrs: (tr, d) => {
                tr.dataset.partnerId = String(d.partner_id);
                tr.dataset.status = d.status;
                tr.dataset.search = `${d.name} ${d.partner_name} ${d.number} ${d.trade_license} ${d.nid} ${d.tin} ${d.address}`.toLowerCase();
            },
            render: (d) => {
                const isActive = d.status === 'Active';
                return `
                    <td>
                        <div class="cell-primary">${esc(d.name)}</div>
                        <div class="cell-sub">${esc(d.partner_name)}</div>
                    </td>
                    <td class="tabular nowrap">${esc(d.number)}</td>
                    <td class="mono nowrap">${esc(d.trade_license)}</td>
                    <td>
                        <div class="mono small">NID: ${esc(d.nid)}</div>
                        <div class="cell-sub mono">TIN: ${esc(d.tin)}</div>
                    </td>
                    <td><span class="badge ${isActive ? 'badge-success' : 'badge-neutral'}" data-row-status>${esc(d.status)}</span></td>
                    <td class="text-right nowrap">
                        <div class="action-btns">
                            <button type="button" class="btn btn-ghost btn-xs" data-action="view">Details</button>
                            <button type="button" class="btn btn-ghost btn-xs" data-action="edit">Edit</button>
                            <button type="button" class="btn btn-ghost btn-xs" data-action="toggle">${isActive ? 'Deactivate' : 'Activate'}</button>
                            <button type="button" class="btn btn-danger-ghost btn-xs" data-action="delete">Delete</button>
                        </div>
                    </td>`;
            },
            onOpen: (d) => {
                $('adminDealerDrawerTitle').textContent = d ? 'Edit Dealer' : 'Add Dealer';
                $('adminDealerDrawerSub').textContent = d ? 'Modify dealer details, reassign partner, or reset password' : 'Register dealer business, compliance documents, and partner assignment';
                $('adminDealerSubmitBtn').textContent = d ? 'Update Dealer' : 'Save Dealer';
                H.setPasswordMode(form, 'dlr_password', Boolean(d));
                $('dlr_partner_id').value = d ? String(d.partner_id) : (partnerFilter.value || '');
                $('dlr_status').value = d ? d.status : 'Active';
                if (!d) return;
                $('dlr_name').value = d.name;
                $('dlr_number').value = d.number;
                $('dlr_trade_license').value = d.trade_license;
                $('dlr_nid').value = d.nid;
                $('dlr_tin').value = d.tin;
                $('dlr_address').value = d.address;
            },
            onView: (d) => {
                activeDetail = d;
                $('adminDealerDetailTitle').textContent = d.name || 'Dealer Details';
                $('adminDealerDetailSub').textContent = `${d.partner_name} · ${d.status}`;
                $('adminDealerDetailList').innerHTML = [
                    ['Assigned Partner', d.partner_name],
                    ['Phone Number', d.number],
                    ['Trade License', d.trade_license],
                    ['NID', d.nid],
                    ['TIN', d.tin],
                    ['Address', d.address],
                    ['Companies Assigned', String(d.companies)],
                    ['Status', d.status],
                ].map(([k, v]) => `<div class="detail-item"><dt>${esc(k)}</dt><dd>${esc(v)}</dd></div>`).join('');
                H.openDrawer('adminDealerDetailDrawer');
            },
        });

        $('openAddDealerBtn')?.addEventListener('click', table.openAdd);
        $('adminDealerDetailEditBtn')?.addEventListener('click', () => {
            if (!activeDetail) return;
            const tr = table.findRow(activeDetail.id);
            H.closeAllDrawers();
            if (tr) table.openEdit(table.readRow(tr));
        });
    });
})();
