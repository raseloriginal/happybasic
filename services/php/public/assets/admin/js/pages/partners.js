(() => {
    'use strict';
    const H = window.HappyAdmin;

    H.registerPage(() => {
        const app = document.getElementById('adminPartnersApp');
        if (!app) return;

        const $ = (id) => document.getElementById(id);
        const esc = H.escapeHtml;
        const form = $('addPartnerForm');
        const search = $('partnerSearch');
        const areaFilter = $('partnerAreaFilter');
        const statusFilter = $('partnerStatusFilter');
        const badge = (s) => (s === 'Active' ? 'badge-success' : s === 'Pending' ? 'badge-warning' : 'badge-neutral');
        const link = (base, id) => `${base}?partner=${encodeURIComponent(id)}`;

        const table = H.crudTable({
            tbody: $('partnersTbody'),
            form,
            baseUrl: app.dataset.baseUrl,
            key: 'partner',
            rowAttr: 'data-partner-row',
            datasetKey: 'partner',
            label: 'Partner',
            plural: 'partners',
            emptyText: 'No partners yet. Click “Add Partner” to create one.',
            drawerId: 'addPartnerDrawer',
            countEl: $('partnerCount'),
            emptyEl: $('partnersEmpty'),
            filterInputs: [search, areaFilter, statusFilter],
            matches: (tr) => {
                const q = (search?.value || '').trim().toLowerCase();
                return (!q || (tr.dataset.search || '').includes(q))
                    && (!areaFilter?.value || tr.dataset.areaId === areaFilter.value)
                    && (!statusFilter?.value || tr.dataset.status === statusFilter.value);
            },
            attrs: (tr, p) => {
                tr.dataset.areaId = String(p.area_id);
                tr.dataset.status = p.status;
                tr.dataset.search = `${p.name} ${p.number} ${p.phone} ${p.tin} ${p.trade_license} ${p.nid} ${p.address} ${p.area}`.toLowerCase();
            },
            render: (p) => `
                <td>
                    <div class="cell-primary">${esc(p.name)}</div>
                    <div class="cell-sub">${esc(p.area)}</div>
                </td>
                <td class="tabular nowrap">${esc(p.number)}</td>
                <td class="mono">${esc(p.tin)}</td>
                <td class="mono">${esc(p.trade_license)}</td>
                <td class="mono">${esc(p.nid)}</td>
                <td class="nowrap">
                    <div class="quick-links">
                        <a href="${esc(link(app.dataset.companiesUrl, p.id))}" class="quick-link-pill" title="Manage Companies">Companies (${p.counts.companies})</a>
                        <a href="${esc(link(app.dataset.dealersUrl, p.id))}" class="quick-link-pill" title="Manage Dealers">Dealers (${p.counts.dealers})</a>
                        <a href="${esc(link(app.dataset.salesmenUrl, p.id))}" class="quick-link-pill" title="Manage Salesmen (SR)">SR (${p.counts.salesmen})</a>
                    </div>
                </td>
                <td><span class="badge ${badge(p.status)}">${esc(p.status)}</span></td>
                <td class="text-right nowrap">
                    <div class="action-btns">
                        <button type="button" class="btn btn-ghost btn-xs" data-action="view">Details</button>
                        <button type="button" class="btn btn-ghost btn-xs" data-action="edit">Edit</button>
                        <button type="button" class="btn btn-ghost btn-xs" data-action="toggle">${p.status === 'Active' ? 'Deactivate' : 'Activate'}</button>
                        <button type="button" class="btn btn-danger-ghost btn-xs" data-action="delete">Delete</button>
                    </div>
                </td>`,
            onOpen: (p) => {
                $('addPartnerTitle').textContent = p ? 'Edit Partner' : 'Add Partner';
                $('addPartnerSub').textContent = p
                    ? 'Update partner details, status, or reset the login password'
                    : 'Enter partner business, compliance, and login credentials';
                $('addPartnerSubmitBtn').textContent = p ? 'Update Partner' : 'Save Partner';
                H.setPasswordMode(form, 'p_password', Boolean(p));
                $('p_status').value = p ? p.status : 'Active';
                if (!p) return;
                $('p_name').value = p.name;
                $('p_number').value = p.number;
                $('p_area').value = String(p.area_id);
                $('p_tin').value = p.tin;
                $('p_trade_license').value = p.trade_license;
                $('p_nid').value = p.nid;
                $('p_address').value = p.address;
            },
            onView: (p) => {
                activeDetail = p;
                $('detailPartnerName').textContent = p.name || 'Partner Details';
                $('detailPartnerArea').textContent = `${p.area} · ${p.status}`;
                $('partnerDetailQuickLinks').innerHTML = `
                    <a href="${esc(link(app.dataset.companiesUrl, p.id))}" class="btn btn-secondary btn-xs">Manage Companies</a>
                    <a href="${esc(link(app.dataset.dealersUrl, p.id))}" class="btn btn-secondary btn-xs">Manage Dealers</a>
                    <a href="${esc(link(app.dataset.salesmenUrl, p.id))}" class="btn btn-secondary btn-xs">Manage SR</a>`;
                $('partnerDetailList').innerHTML = [
                    ['Phone Number', p.number],
                    ['Area', p.area],
                    ['TIN', p.tin],
                    ['Trade License', p.trade_license],
                    ['NID Number', p.nid],
                    ['Address', p.address],
                    ['Status', p.status],
                    ['Created', p.created_at],
                ].map(([k, v]) => `<div class="detail-item"><dt>${esc(k)}</dt><dd>${esc(v)}</dd></div>`).join('');
                H.openDrawer('partnerDetailDrawer');
            },
        });

        let activeDetail = null;
        $('openAddPartnerBtn')?.addEventListener('click', table.openAdd);
        $('partnerDetailEditBtn')?.addEventListener('click', () => {
            if (!activeDetail) return;
            const tr = table.findRow(activeDetail.id);
            H.closeAllDrawers();
            if (tr) table.openEdit(table.readRow(tr));
        });

        if (window.location.hash === '#add') table.openAdd();
    });
})();
