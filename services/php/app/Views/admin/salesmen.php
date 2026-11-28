<?php $this->extend('admin.layouts.main'); ?>

<?php $this->section('topbar_actions'); ?>
<button type="button" class="btn btn-primary btn-sm" id="openAddSrBtn">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M12 5v14M5 12h14"/></svg>
    <span>Add SR</span>
</button>
<?php $this->endSection(); ?>

<?php $this->section('content'); ?>
<section class="panel" id="adminSalesmenApp"
    data-base-url="<?= e(url('/admin/salesmen')) ?>"
    data-companies="<?= e(json_encode($companies, JSON_UNESCAPED_UNICODE)) ?>"
    data-dealers="<?= e(json_encode($dealers, JSON_UNESCAPED_UNICODE)) ?>"
>
    <div class="toolbar">
        <div class="toolbar-filters">
            <div class="search-box">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
                <input type="search" id="adminSrSearch" placeholder="Search SR name, number, partner, company, dealer..." autocomplete="off">
            </div>

            <select id="adminSrPartnerFilter" class="select-input" aria-label="Filter by partner">
                <option value="">All Partners</option>
                <?php foreach ($partners as $p): ?>
                    <option value="<?= (int) $p['id'] ?>" <?= ($selectedPartnerId === (int) $p['id']) ? 'selected' : '' ?>><?= e($p['name']) ?></option>
                <?php endforeach; ?>
            </select>

            <select id="adminSrCompanyFilter" class="select-input" aria-label="Filter by company">
                <option value="">All Companies</option>
                <?php foreach ($companies as $cmp): ?>
                    <option value="<?= (int) $cmp['id'] ?>"><?= e($cmp['name']) ?></option>
                <?php endforeach; ?>
            </select>

            <select id="adminSrStatusFilter" class="select-input" aria-label="Filter by status">
                <option value="">All Status</option>
                <option value="Active">Active</option>
                <option value="Inactive">Inactive</option>
            </select>
        </div>

        <div class="toolbar-meta">
            <span class="muted small"><strong id="adminSrCount"><?= count($salesmen) ?></strong> salesmen</span>
        </div>
    </div>

    <div class="table-wrap">
        <table class="data-table">
            <thead>
                <tr>
                    <th>Salesman (SR) &amp; Partner</th>
                    <th>Phone Number</th>
                    <th>Assigned Company</th>
                    <th>Ownership</th>
                    <th>Status</th>
                    <th class="text-right">Action</th>
                </tr>
            </thead>
            <tbody id="adminSrTbody">
                <?php foreach ($salesmen as $sr): ?>
                    <?php $isActive = $sr['status'] === 'Active'; ?>
                    <tr
                        data-sr-row
                        data-id="<?= (int) $sr['id'] ?>"
                        data-partner-id="<?= (int) $sr['partner_id'] ?>"
                        data-company-id="<?= (int) $sr['company_id'] ?>"
                        data-status="<?= e($sr['status']) ?>"
                        data-search="<?= e(strtolower($sr['name'] . ' ' . $sr['partner_name'] . ' ' . $sr['number'] . ' ' . $sr['company'] . ' ' . ($sr['dealer'] ?? ''))) ?>"
                        data-sr="<?= e(json_encode($sr, JSON_UNESCAPED_UNICODE)) ?>"
                    >
                        <td>
                            <div class="cell-primary"><?= e($sr['name']) ?></div>
                            <div class="cell-sub"><?= e($sr['partner_name']) ?></div>
                        </td>
                        <td class="tabular nowrap"><?= e($sr['number']) ?></td>
                        <td><span class="badge badge-neutral"><?= e($sr['company']) ?></span></td>
                        <td>
                            <?php if ($sr['ownership'] === 'Dealer'): ?>
                                <span class="badge badge-info">Dealer</span>
                                <div class="cell-sub"><?= e($sr['dealer']) ?> · <?= e((string) $sr['dealer_profit_share']) ?>% / <?= e((string) $sr['partner_profit_share']) ?>%</div>
                            <?php else: ?>
                                <span class="badge badge-success">Owned</span>
                            <?php endif; ?>
                        </td>
                        <td>
                            <span class="badge <?= $isActive ? 'badge-success' : 'badge-neutral' ?>" data-row-status><?= e($sr['status']) ?></span>
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

    <div class="empty-state" id="adminSrEmpty" <?= $salesmen ? 'hidden' : '' ?>>
        <p><?= $salesmen ? 'No salesmen match your current filter.' : 'No salesmen yet. Click “Add SR” to create one.' ?></p>
    </div>
</section>

<!-- Add / Edit SR Slide-over Drawer -->
<div class="drawer-overlay" id="adminSrDrawer" aria-hidden="true">
    <div class="drawer-panel" role="dialog" aria-modal="true" aria-labelledby="adminSrDrawerTitle">
        <div class="drawer-head">
            <div>
                <h2 id="adminSrDrawerTitle" class="card-title">Add Salesman (SR)</h2>
                <p id="adminSrDrawerSub" class="card-subtitle">Choose ownership, then partner or dealer, then company. This connects the partner to the company.</p>
            </div>
            <button type="button" class="icon-btn" data-drawer-close aria-label="Close">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>

        <form id="adminSrForm" class="drawer-body" method="POST" action="<?= e(url('/admin/salesmen')) ?>" novalidate>
            <?= csrf_field() ?>
            <input type="hidden" id="sr_edit_id" name="id" value="">

            <div class="form-grid">
                <div class="form-group span-2">
                    <label for="sr_ownership">Ownership <span class="req">*</span></label>
                    <select id="sr_ownership" name="ownership" required>
                        <option value="Owned">Owned (partner directly)</option>
                        <option value="Dealer">Dealer (partner via dealer)</option>
                    </select>
                </div>

                <div class="form-group span-2" id="srPartnerGroup">
                    <label for="sr_partner_id">Partner <span class="req">*</span></label>
                    <select id="sr_partner_id" name="partner_id" required>
                        <option value="">Select partner</option>
                        <?php foreach ($partners as $p): ?>
                            <option value="<?= (int) $p['id'] ?>"><?= e($p['name']) ?> (<?= e($p['area']) ?>)</option>
                        <?php endforeach; ?>
                    </select>
                </div>

                <div class="form-group" id="srDealerGroup" hidden>
                    <label for="sr_dealer_id">Dealer <span class="req">*</span></label>
                    <select id="sr_dealer_id" name="dealer_id">
                        <option value="">Select dealer</option>
                    </select>
                    <small class="muted" id="srDealerPartnerHint"></small>
                </div>

                <div class="form-group" id="srDealerShareGroup" hidden>
                    <label for="sr_dealer_profit_share">Dealer Profit Share (%) <span class="req">*</span></label>
                    <input id="sr_dealer_profit_share" name="dealer_profit_share" type="number" min="0" max="100" step="0.01" placeholder="e.g. 35">
                    <small class="muted" id="srPartnerShareHint"></small>
                </div>

                <div class="form-group span-2">
                    <label for="sr_company">Company <span class="req">*</span></label>
                    <select id="sr_company" name="company_id" required>
                        <option value="">Select company</option>
                    </select>
                </div>

                <div class="form-group">
                    <label for="sr_name">Salesman Name <span class="req">*</span></label>
                    <input id="sr_name" name="name" type="text" maxlength="120" placeholder="e.g. Hasan Mahmud" required>
                </div>

                <div class="form-group">
                    <label for="sr_number">Phone Number <span class="req">*</span></label>
                    <input id="sr_number" name="number" type="tel" placeholder="+880 17XX-XXXXXX" required>
                </div>

                <div class="form-group span-2">
                    <label for="sr_daily_target">Daily Target (৳)</label>
                    <input id="sr_daily_target" name="daily_target" type="number" min="0" step="0.01" inputmode="decimal" placeholder="e.g. 50000">
                    <small class="muted">Daily order value target. Leave empty for no target.</small>
                </div>

                <div class="form-group span-2">
                    <div class="label-row">
                        <label for="sr_password">Account Password <span class="req" data-pw-required>*</span></label>
                        <button type="button" class="text-link small" data-gen-pw="sr_password">Generate</button>
                    </div>
                    <div class="input-with-action">
                        <input id="sr_password" name="password" type="password" placeholder="Minimum 6 characters" minlength="6" maxlength="72" required autocomplete="new-password">
                        <button type="button" class="input-action-btn" data-toggle-input-pw="sr_password">Show</button>
                    </div>
                </div>

                <div class="form-group span-2">
                    <label for="sr_status">Status <span class="req">*</span></label>
                    <select id="sr_status" name="status" required>
                        <option value="Active">Active</option>
                        <option value="Inactive">Inactive</option>
                    </select>
                </div>
            </div>

            <div class="drawer-foot">
                <button type="button" class="btn btn-secondary" data-drawer-close>Cancel</button>
                <button type="submit" class="btn btn-primary" id="adminSrSubmitBtn">Save SR</button>
            </div>
        </form>
    </div>
</div>
<?php $this->endSection(); ?>
