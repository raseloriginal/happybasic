<?php $this->extend('admin.layouts.main'); ?>

<?php $this->section('topbar_actions'); ?>
<button type="button" class="btn btn-primary btn-sm" id="openAddPartnerBtn">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M12 5v14M5 12h14"/></svg>
    <span>Add Partner</span>
</button>
<?php $this->endSection(); ?>

<?php
$statusBadge = static fn(string $s): string => match ($s) {
    'Active' => 'badge-success',
    'Pending' => 'badge-warning',
    default => 'badge-neutral',
};
?>

<?php $this->section('content'); ?>
<section class="panel" id="adminPartnersApp"
    data-base-url="<?= e(url('/admin/partners')) ?>"
    data-companies-url="<?= e(url('/admin/companies')) ?>"
    data-dealers-url="<?= e(url('/admin/dealers')) ?>"
    data-salesmen-url="<?= e(url('/admin/salesmen')) ?>"
>
    <div class="toolbar">
        <div class="toolbar-filters">
            <div class="search-box">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
                <input type="search" id="partnerSearch" placeholder="Search name, number, TIN, NID, license..." autocomplete="off">
            </div>

            <select id="partnerAreaFilter" class="select-input" aria-label="Filter by area">
                <option value="">All Areas</option>
                <?php foreach ($areas as $area): ?>
                    <option value="<?= (int) $area['id'] ?>"><?= e($area['name']) ?></option>
                <?php endforeach; ?>
            </select>

            <select id="partnerStatusFilter" class="select-input" aria-label="Filter by status">
                <option value="">All Status</option>
                <option value="Active">Active</option>
                <option value="Pending">Pending</option>
                <option value="Inactive">Inactive</option>
            </select>
        </div>

        <div class="toolbar-meta">
            <span class="muted small"><strong id="partnerCount"><?= count($partners) ?></strong> partners</span>
        </div>
    </div>

    <div class="table-wrap">
        <table class="data-table" id="partnersTable">
            <thead>
                <tr>
                    <th>Partner &amp; Area</th>
                    <th>Number</th>
                    <th>TIN</th>
                    <th>Trade License</th>
                    <th>NID</th>
                    <th>Manage</th>
                    <th>Status</th>
                    <th class="text-right">Action</th>
                </tr>
            </thead>
            <tbody id="partnersTbody">
                <?php foreach ($partners as $p): ?>
                    <?php $isActive = $p['status'] === 'Active'; ?>
                    <tr
                        data-partner-row
                        data-id="<?= (int) $p['id'] ?>"
                        data-area-id="<?= (int) $p['area_id'] ?>"
                        data-status="<?= e($p['status']) ?>"
                        data-search="<?= e(strtolower($p['name'] . ' ' . $p['number'] . ' ' . $p['phone'] . ' ' . $p['tin'] . ' ' . $p['trade_license'] . ' ' . $p['nid'] . ' ' . $p['address'] . ' ' . $p['area'])) ?>"
                        data-partner="<?= e(json_encode($p, JSON_UNESCAPED_UNICODE)) ?>"
                    >
                        <td>
                            <div class="cell-primary"><?= e($p['name']) ?></div>
                            <div class="cell-sub"><?= e($p['area']) ?></div>
                        </td>
                        <td class="tabular nowrap"><?= e($p['number']) ?></td>
                        <td class="mono"><?= e($p['tin']) ?></td>
                        <td class="mono"><?= e($p['trade_license']) ?></td>
                        <td class="mono"><?= e($p['nid']) ?></td>
                        <td class="nowrap">
                            <div class="quick-links">
                                <a href="<?= e(url('/admin/companies?partner=' . (int) $p['id'])) ?>" class="quick-link-pill" title="Manage Companies">Companies (<?= (int) $p['counts']['companies'] ?>)</a>
                                <a href="<?= e(url('/admin/dealers?partner=' . (int) $p['id'])) ?>" class="quick-link-pill" title="Manage Dealers">Dealers (<?= (int) $p['counts']['dealers'] ?>)</a>
                                <a href="<?= e(url('/admin/salesmen?partner=' . (int) $p['id'])) ?>" class="quick-link-pill" title="Manage Salesmen (SR)">SR (<?= (int) $p['counts']['salesmen'] ?>)</a>
                            </div>
                        </td>
                        <td>
                            <span class="badge <?= $statusBadge($p['status']) ?>"><?= e($p['status']) ?></span>
                        </td>
                        <td class="text-right nowrap">
                            <div class="action-btns">
                                <button type="button" class="btn btn-ghost btn-xs" data-action="view">Details</button>
                                <button type="button" class="btn btn-ghost btn-xs" data-action="edit">Edit</button>
                                <button type="button" class="btn btn-ghost btn-xs" data-action="toggle"><?= $isActive ? 'Deactivate' : 'Activate' ?></button>
                                <button type="button" class="btn btn-danger-ghost btn-xs" data-action="delete">Delete</button>
                            </div>
                        </td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>

    <div class="empty-state" id="partnersEmpty" <?= $partners ? 'hidden' : '' ?>>
        <p><?= $partners ? 'No partners match your current filter.' : 'No partners yet. Click “Add Partner” to create one.' ?></p>
    </div>
</section>

<!-- Add / Edit Partner Slide-over Drawer -->
<div class="drawer-overlay" id="addPartnerDrawer" aria-hidden="true">
    <div class="drawer-panel" role="dialog" aria-modal="true" aria-labelledby="addPartnerTitle">
        <div class="drawer-head">
            <div>
                <h2 id="addPartnerTitle" class="card-title">Add Partner</h2>
                <p id="addPartnerSub" class="card-subtitle">Enter partner business, compliance, and login credentials</p>
            </div>
            <button type="button" class="icon-btn" data-drawer-close aria-label="Close">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>

        <form id="addPartnerForm" class="drawer-body" method="POST" action="<?= e(url('/admin/partners')) ?>" novalidate>
            <?= csrf_field() ?>
            <input type="hidden" id="p_edit_id" name="id" value="">

            <div class="form-grid">
                <div class="form-group span-2">
                    <label for="p_name">Partner Name <span class="req">*</span></label>
                    <input id="p_name" name="name" type="text" maxlength="150" placeholder="e.g. Rahman Trading Co." required>
                </div>

                <div class="form-group">
                    <label for="p_number">Phone Number <span class="req">*</span></label>
                    <input id="p_number" name="number" type="tel" placeholder="+880 17XX-XXXXXX" required>
                </div>

                <div class="form-group">
                    <label for="p_area">Area <span class="req">*</span></label>
                    <select id="p_area" name="area_id" required>
                        <option value="">Select area</option>
                        <?php foreach ($areas as $area): ?>
                            <option value="<?= (int) $area['id'] ?>" <?= $area['status'] !== 'Active' ? 'data-inactive="1"' : '' ?>><?= e($area['name']) ?><?= $area['status'] !== 'Active' ? ' (inactive)' : '' ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>

                <div class="form-group">
                    <label for="p_tin">TIN <span class="req">*</span></label>
                    <input id="p_tin" name="tin" type="text" inputmode="numeric" pattern="\d{12}" placeholder="12-digit TIN number" required>
                </div>

                <div class="form-group">
                    <label for="p_trade_license">Trade License <span class="req">*</span></label>
                    <input id="p_trade_license" name="trade_license" type="text" maxlength="100" placeholder="TRAD/DNCC/000000/2026" required>
                </div>

                <div class="form-group">
                    <label for="p_nid">NID Number <span class="req">*</span></label>
                    <input id="p_nid" name="nid" type="text" inputmode="numeric" pattern="\d{10}|\d{13}|\d{17}" placeholder="10, 13 or 17 digits" required>
                </div>

                <div class="form-group">
                    <label for="p_status">Status <span class="req">*</span></label>
                    <select id="p_status" name="status" required>
                        <option value="Active">Active</option>
                        <option value="Pending">Pending</option>
                        <option value="Inactive">Inactive</option>
                    </select>
                </div>

                <div class="form-group span-2">
                    <label for="p_address">Address <span class="req">*</span></label>
                    <textarea id="p_address" name="address" rows="2" maxlength="255" placeholder="Street, road, sector, city" required></textarea>
                </div>

                <div class="form-group span-2">
                    <div class="label-row">
                        <label for="p_password">Account Password <span class="req" data-pw-required>*</span></label>
                        <button type="button" class="text-link small" data-gen-pw="p_password">Generate</button>
                    </div>
                    <div class="input-with-action">
                        <input id="p_password" name="password" type="password" placeholder="Minimum 6 characters" minlength="6" maxlength="72" required autocomplete="new-password">
                        <button type="button" class="input-action-btn" data-toggle-input-pw="p_password">Show</button>
                    </div>
                </div>
            </div>

            <div class="drawer-foot">
                <button type="button" class="btn btn-secondary" data-drawer-close>Cancel</button>
                <button type="submit" class="btn btn-primary" id="addPartnerSubmitBtn">Save Partner</button>
            </div>
        </form>
    </div>
</div>

<!-- Partner Detail Slide-over Drawer -->
<div class="drawer-overlay" id="partnerDetailDrawer" aria-hidden="true">
    <div class="drawer-panel drawer-sm" role="dialog" aria-modal="true" aria-labelledby="detailPartnerName">
        <div class="drawer-head">
            <div>
                <h2 id="detailPartnerName" class="card-title">Partner Details</h2>
                <p id="detailPartnerArea" class="card-subtitle"></p>
            </div>
            <button type="button" class="icon-btn" data-drawer-close aria-label="Close">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>

        <div class="drawer-body">
            <div class="drawer-quick-links" id="partnerDetailQuickLinks"></div>
            <dl class="detail-list" id="partnerDetailList"></dl>
        </div>

        <div class="drawer-foot">
            <button type="button" class="btn btn-secondary" data-drawer-close>Close</button>
            <button type="button" class="btn btn-primary" id="partnerDetailEditBtn">Edit Partner</button>
        </div>
    </div>
</div>
<?php $this->endSection(); ?>
