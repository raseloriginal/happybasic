(() => {
    'use strict';
    const H = window.HappyAdmin;

    H.registerPage(() => {
        const app = document.getElementById('adminCompaniesApp');
        if (!app) return;

        const $ = (id) => document.getElementById(id);
        const esc = H.escapeHtml;
        const money = (n) => Number(n || 0).toLocaleString('en-US', { maximumFractionDigits: 2 });
        const search = $('adminCompanySearch');
        const partnerFilter = $('adminCompanyPartnerFilter');
        const ownershipFilter = $('adminCompanyOwnershipFilter');
        const statusFilter = $('adminCompanyStatusFilter');

        const table = H.crudTable({
            tbody: $('adminCompaniesTbody'),
            form: $('adminCompanyForm'),
            baseUrl: app.dataset.baseUrl,
            key: 'company',
            rowAttr: 'data-company-row',
            datasetKey: 'company',
            label: 'Company',
            plural: 'companies',
            emptyText: 'No companies yet. Click “Add Company” to create one.',
            drawerId: 'adminCompanyDrawer',
            countEl: $('adminCompanyCount'),
            emptyEl: $('adminCompaniesEmpty'),
            filterInputs: [search, partnerFilter, ownershipFilter, statusFilter],
            matches: (tr) => {
                const q = (search?.value || '').trim().toLowerCase();
                return (!q || (tr.dataset.search || '').includes(q))
                    && (!partnerFilter.value || (tr.dataset.partnerIds || '').includes(`,${partnerFilter.value},`))
                    && (!ownershipFilter.value || (tr.dataset.ownerships || '').includes(`,${ownershipFilter.value},`))
                    && (!statusFilter.value || tr.dataset.status === statusFilter.value);
            },
            attrs: (tr, c) => {
                tr.dataset.partnerIds = `,${c.links.map((l) => l.partner_id).join(',')},`;
                tr.dataset.ownerships = `,${[...new Set(c.links.map((l) => l.ownership))].join(',')},`;
                tr.dataset.status = c.status;
                tr.dataset.search = `${c.name} ${c.links.map((l) => `${l.partner_name} ${l.dealer || ''}`).join(' ')}`.toLowerCase();
            },
            render: (c) => {
                const isActive = c.status === 'Active';
                const dealerLinks = c.links.filter((l) => l.ownership === 'Dealer');
                const partners = c.links.length
                    ? c.links.map((l) => `<div class="small">${esc(l.partner_name)} <span class="badge ${l.ownership === 'Owned' ? 'badge-success' : 'badge-info'}">${esc(l.ownership)}</span></div>`).join('')
                    : '<span class="muted small">Not connected yet</span>';
                const dealers = dealerLinks.length
                    ? dealerLinks.map((l) => `<div class="cell-primary">${esc(l.dealer)}</div><div class="cell-sub tabular">Dealer ${esc(l.dealer_profit_share)}% · Partner ${esc(l.partner_profit_share)}%</div>`).join('')
                    : '<span class="muted small">Direct ownership</span>';
                return `
                    <td>
                        <div class="cell-primary">${esc(c.name)}</div>
                        <div class="cell-sub">${c.links.length} partner(s) · ${c.salesmen} SR</div>
                    </td>
                    <td>${partners}</td>
                    <td>${dealers}</td>
                    <td class="text-right tabular">${Number(c.total_sku || 0).toLocaleString('en-US')}</td>
                    <td class="text-right tabular nowrap">৳ ${money(c.stock_value)}</td>
                    <td><span class="badge ${isActive ? 'badge-success' : 'badge-neutral'}" data-row-status>${esc(c.status)}</span></td>
                    <td class="text-right nowrap">
                        <div class="action-btns">
                            <button type="button" class="btn btn-ghost btn-xs" data-action="edit">Edit</button>
                            <button type="button" class="btn btn-ghost btn-xs" data-action="toggle">${isActive ? 'Deactivate' : 'Activate'}</button>
                            <button type="button" class="btn btn-danger-ghost btn-xs" data-action="delete">Delete</button>
                        </div>
                    </td>`;
            },
            onOpen: (c) => {
                $('adminCompanyDrawerTitle').textContent = c ? 'Edit Company' : 'Add Company';
                $('adminCompanySubmitBtn').textContent = c ? 'Update Company' : 'Save Company';
                $('cmp_name').value = c ? c.name : '';
                $('cmp_status').value = c ? c.status : 'Active';
            },
        });

        $('openAddCompanyBtn')?.addEventListener('click', table.openAdd);
    });
})();
