<?php $this->extend('admin.layouts.main'); ?>

<?php $this->section('topbar_actions'); ?>
<button type="button" class="btn btn-primary btn-sm" id="openAddCompanyBtn">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M12 5v14M5 12h14"/></svg>
    <span>Add Company</span>
</button>
<?php $this->endSection(); ?>

<?php
$partnerIds = static fn(array $c): string => ',' . implode(',', array_column($c['links'], 'partner_id')) . ',';
$ownerships = static fn(array $c): string => ',' . implode(',', array_unique(array_column($c['links'], 'ownership'))) . ',';
?>

<?php $this->section('content'); ?>
<section class="panel" id="adminCompaniesApp" data-base-url="<?= e(url('/admin/companies')) ?>">
    <div class="toolbar">
        <div class="toolbar-filters">
            <div class="search-box">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
                <input type="search" id="adminCompanySearch" placeholder="Search company, partner, dealer..." autocomplete="off">
            </div>

            <select id="adminCompanyPartnerFilter" class="select-input" aria-label="Filter by connected partner">
                <option value="">All Partners</option>
                <?php foreach ($partners as $p): ?>
                    <option value="<?= (int) $p['id'] ?>" <?= ($selectedPartnerId === (int) $p['id']) ? 'selected' : '' ?>><?= e($p['name']) ?></option>
                <?php endforeach; ?>
            </select>

            <select id="adminCompanyOwnershipFilter" class="select-input" aria-label="Filter by ownership">
                <option value="">All Ownership</option>
                <option value="Owned">Owned</option>
                <option value="Dealer">Dealer</option>
            </select>

            <select id="adminCompanyStatusFilter" class="select-input" aria-label="Filter by status">
                <option value="">All Status</option>
                <option value="Active">Active</option>
                <option value="Inactive">Inactive</option>
            </select>
        </div>

        <div class="toolbar-meta">
            <span class="muted small"><strong id="adminCompanyCount"><?= count($companies) ?></strong> companies</span>
        </div>
    </div>

    <div class="table-wrap">
        <table class="data-table">
            <thead>
                <tr>
                    <th>Company</th>
                    <th>Connected Partners (via SR)</th>
                    <th>Dealer &amp; Profit Share</th>
                    <th class="text-right">Total SKU</th>
                    <th class="text-right">Stock Value</th>
                    <th>Status</th>
                    <th class="text-right">Action</th>
                </tr>
            </thead>
            <tbody id="adminCompaniesTbody">
                <?php foreach ($companies as $c): ?>
                    <?php
                        $isActive = $c['status'] === 'Active';
                        $dealerLinks = array_values(array_filter($c['links'], static fn($l) => $l['ownership'] === 'Dealer'));
                    ?>
                    <tr
                        data-company-row
                        data-id="<?= (int) $c['id'] ?>"
                        data-partner-ids="<?= e($partnerIds($c)) ?>"
                        data-ownerships="<?= e($ownerships($c)) ?>"
                        data-status="<?= e($c['status']) ?>"
                        data-search="<?= e(strtolower($c['name'] . ' ' . implode(' ', array_column($c['links'], 'partner_name')) . ' ' . implode(' ', array_filter(array_column($c['links'], 'dealer'))))) ?>"
                        data-company="<?= e(json_encode($c, JSON_UNESCAPED_UNICODE)) ?>"
                    >
                        <td>
                            <div class="cell-primary"><?= e($c['name']) ?></div>
                            <div class="cell-sub"><?= count($c['links']) ?> partner(s) · <?= (int) $c['salesmen'] ?> SR</div>
                        </td>
                        <td>
                            <?php if (!$c['links']): ?>
                                <span class="muted small">Not connected yet</span>
                            <?php endif; ?>
                            <?php foreach ($c['links'] as $l): ?>
                                <div class="small"><?= e($l['partner_name']) ?> <span class="badge <?= $l['ownership'] === 'Owned' ? 'badge-success' : 'badge-info' ?>"><?= e($l['ownership']) ?></span></div>
                            <?php endforeach; ?>
                        </td>
                        <td>
                            <?php if (!$dealerLinks): ?>
                                <span class="muted small">Direct ownership</span>
                            <?php endif; ?>
                            <?php foreach ($dealerLinks as $l): ?>
                                <div class="cell-primary"><?= e($l['dealer']) ?></div>
                                <div class="cell-sub tabular">Dealer <?= e((string) $l['dealer_profit_share']) ?>% · Partner <?= e((string) $l['partner_profit_share']) ?>%</div>
                            <?php endforeach; ?>
                        </td>
                        <td class="text-right tabular"><?= number_format((int) $c['total_sku']) ?></td>
                        <td class="text-right tabular nowrap">৳ <?= number_format((float) $c['stock_value']) ?></td>
                        <td>
                            <span class="badge <?= $isActive ? 'badge-success' : 'badge-neutral' ?>" data-row-status><?= e($c['status']) ?></span>
                        </td>
                        <td class="text-right nowrap">
                            <div class="action-btns">
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

    <div class="empty-state" id="adminCompaniesEmpty" <?= $companies ? 'hidden' : '' ?>>
        <p><?= $companies ? 'No companies match your current filter.' : 'No companies yet. Click “Add Company” to create one.' ?></p>
    </div>
</section>

<!-- Add / Edit Company Slide-over Drawer -->
<div class="drawer-overlay" id="adminCompanyDrawer" aria-hidden="true">
    <div class="drawer-panel" role="dialog" aria-modal="true" aria-labelledby="adminCompanyDrawerTitle">
        <div class="drawer-head">
            <div>
                <h2 id="adminCompanyDrawerTitle" class="card-title">Add Company</h2>
                <p id="adminCompanyDrawerSub" class="card-subtitle">Companies are shared by all partners. Partners get connected when an SR is assigned. Set platform fees on the Platform Fees page.</p>
            </div>
            <button type="button" class="icon-btn" data-drawer-close aria-label="Close">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>

        <form id="adminCompanyForm" class="drawer-body" method="POST" action="<?= e(url('/admin/companies')) ?>" novalidate>
            <?= csrf_field() ?>
            <input type="hidden" id="cmp_edit_id" name="id" value="">

            <div class="form-grid">
                <div class="form-group span-2">
                    <label for="cmp_name">Company Name <span class="req">*</span></label>
                    <input id="cmp_name" name="name" type="text" maxlength="150" placeholder="e.g. Bashundhara Food & Beverage" required>
                </div>

                <div class="form-group span-2">
                    <label for="cmp_status">Status <span class="req">*</span></label>
                    <select id="cmp_status" name="status" required>
                        <option value="Active">Active</option>
                        <option value="Inactive">Inactive</option>
                    </select>
                </div>
            </div>

            <div class="drawer-foot">
                <button type="button" class="btn btn-secondary" data-drawer-close>Cancel</button>
                <button type="submit" class="btn btn-primary" id="adminCompanySubmitBtn">Save Company</button>
            </div>
        </form>
    </div>
</div>
<?php $this->endSection(); ?>
