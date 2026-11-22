<?php $this->extend('admin.layouts.main'); ?>

<?php $this->section('topbar_actions'); ?>
<button type="button" class="btn btn-primary btn-sm" id="openAddDealerBtn">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M12 5v14M5 12h14"/></svg>
    <span>Add Dealer</span>
</button>
<?php $this->endSection(); ?>

<?php $this->section('content'); ?>
<section class="panel" id="adminDealersApp"
    data-base-url="<?= e(url('/admin/dealers')) ?>"
    data-partners="<?= e(json_encode(array_map(static fn($p) => ['id' => $p['id'], 'name' => $p['name']], $partners), JSON_UNESCAPED_UNICODE)) ?>"
>
    <div class="toolbar">
        <div class="toolbar-filters">
            <div class="search-box">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
                <input type="search" id="adminDealerSearch" placeholder="Search dealer, partner, number, TIN, NID..." autocomplete="off">
            </div>

            <select id="adminDealerPartnerFilter" class="select-input" aria-label="Filter by partner">
                <option value="">All Partners</option>
                <?php foreach ($partners as $p): ?>
                    <option value="<?= (int) $p['id'] ?>" <?= ($selectedPartnerId === (int) $p['id']) ? 'selected' : '' ?>><?= e($p['name']) ?></option>
                <?php endforeach; ?>
            </select>

            <select id="adminDealerStatusFilter" class="select-input" aria-label="Filter by status">
                <option value="">All Status</option>
                <option value="Active">Active</option>
                <option value="Inactive">Inactive</option>
            </select>
        </div>

        <div class="toolbar-meta">
            <span class="muted small"><strong id="adminDealerCount"><?= count($dealers) ?></strong> dealers</span>
        </div>
    </div>

    <div class="table-wrap">
        <table class="data-table">
            <thead>
                <tr>
                    <th>Dealer &amp; Partner</th>
                    <th>Number</th>
                    <th>Trade License</th>
                    <th>NID &amp; TIN</th>
                    <th>Status</th>
                    <th class="text-right">Action</th>
                </tr>
            </thead>
            <tbody id="adminDealersTbody">
                <?php foreach ($dealers as $dlr): ?>
                    <?php $isActive = $dlr['status'] === 'Active'; ?>
                    <tr
                        data-dealer-row
                        data-id="<?= (int) $dlr['id'] ?>"
                        data-partner-id="<?= (int) $dlr['partner_id'] ?>"
                        data-status="<?= e($dlr['status']) ?>"
                        data-search="<?= e(strtolower($dlr['name'] . ' ' . $dlr['partner_name'] . ' ' . $dlr['number'] . ' ' . $dlr['trade_license'] . ' ' . $dlr['nid'] . ' ' . $dlr['tin'] . ' ' . $dlr['address'])) ?>"
                        data-dealer="<?= e(json_encode($dlr, JSON_UNESCAPED_UNICODE)) ?>"
                    >
                        <td>
                            <div class="cell-primary"><?= e($dlr['name']) ?></div>
                            <div class="cell-sub"><?= e($dlr['partner_name']) ?></div>
                        </td>
                        <td class="tabular nowrap"><?= e($dlr['number']) ?></td>
                        <td class="mono nowrap"><?= e($dlr['trade_license']) ?></td>
                        <td>
                            <div class="mono small">NID: <?= e($dlr['nid']) ?></div>
                            <div class="cell-sub mono">TIN: <?= e($dlr['tin']) ?></div>
                        </td>
                        <td>
                            <span class="badge <?= $isActive ? 'badge-success' : 'badge-neutral' ?>" data-row-status><?= e($dlr['status']) ?></span>
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

    <div class="empty-state" id="adminDealersEmpty" <?= $dealers ? 'hidden' : '' ?>>
        <p><?= $dealers ? 'No dealers match your current filter.' : 'No dealers yet. Click “Add Dealer” to create one.' ?></p>
    </div>
</section>

<!-- Add / Edit Dealer Slide-over Drawer -->
<div class="drawer-overlay" id="adminDealerDrawer" aria-hidden="true">
    <div class="drawer-panel" role="dialog" aria-modal="true" aria-labelledby="adminDealerDrawerTitle">
        <div class="drawer-head">
            <div>
                <h2 id="adminDealerDrawerTitle" class="card-title">Add Dealer</h2>
                <p id="adminDealerDrawerSub" class="card-subtitle">Register dealer business, compliance documents, and partner assignment</p>
            </div>
            <button type="button" class="icon-btn" data-drawer-close aria-label="Close">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>

        <form id="adminDealerForm" class="drawer-body" method="POST" action="<?= e(url('/admin/dealers')) ?>" novalidate>
            <?= csrf_field() ?>
            <input type="hidden" id="dlr_edit_id" name="id" value="">

            <div class="form-grid">
                <div class="form-group span-2">
                    <label for="dlr_partner_id">Assign Partner <span class="req">*</span></label>
                    <select id="dlr_partner_id" name="partner_id" required>
                        <option value="">Select partner</option>
                        <?php foreach ($partners as $p): ?>
                            <option value="<?= (int) $p['id'] ?>"><?= e($p['name']) ?> (<?= e($p['area']) ?>)</option>
                        <?php endforeach; ?>
                    </select>
                </div>

                <div class="form-group">
                    <label for="dlr_name">Dealer Name <span class="req">*</span></label>
                    <input id="dlr_name" name="name" type="text" placeholder="e.g. Karim Traders" required>
                </div>

                <div class="form-group">
                    <label for="dlr_number">Phone Number <span class="req">*</span></label>
                    <input id="dlr_number" name="number" type="tel" placeholder="+880 17XX-XXXXXX" required>
                </div>

                <div class="form-group">
                    <label for="dlr_trade_license">Trade License <span class="req">*</span></label>
                    <input id="dlr_trade_license" name="trade_license" type="text" placeholder="TRAD/DNCC/000000/2026" required>
                </div>

                <div class="form-group">
                    <label for="dlr_nid">NID <span class="req">*</span></label>
                    <input id="dlr_nid" name="nid" type="text" inputmode="numeric" pattern="\d{10}|\d{13}|\d{17}" placeholder="10, 13 or 17 digits" required>
                </div>

                <div class="form-group">
                    <label for="dlr_tin">TIN <span class="req">*</span></label>
                    <input id="dlr_tin" name="tin" type="text" inputmode="numeric" pattern="\d{12}" placeholder="12-digit TIN number" required>
                </div>

                <div class="form-group">
                    <label for="dlr_status">Status <span class="req">*</span></label>
                    <select id="dlr_status" name="status" required>
                        <option value="Active">Active</option>
                        <option value="Inactive">Inactive</option>
                    </select>
                </div>

                <div class="form-group span-2">
                    <div class="label-row">
                        <label for="dlr_password">Account Password <span class="req" data-pw-required>*</span></label>
                        <button type="button" class="text-link small" data-gen-pw="dlr_password">Generate</button>
                    </div>
                    <div class="input-with-action">
                        <input id="dlr_password" name="password" type="password" placeholder="Minimum 6 characters" minlength="6" maxlength="72" required autocomplete="new-password">
                        <button type="button" class="input-action-btn" data-toggle-input-pw="dlr_password">Show</button>
                    </div>
                </div>

                <div class="form-group span-2">
                    <label for="dlr_address">Address <span class="req">*</span></label>
                    <textarea id="dlr_address" name="address" rows="2" placeholder="Shop/office address, road, area" required></textarea>
                </div>
            </div>

            <div class="drawer-foot">
                <button type="button" class="btn btn-secondary" data-drawer-close>Cancel</button>
                <button type="submit" class="btn btn-primary" id="adminDealerSubmitBtn">Save Dealer</button>
            </div>
        </form>
    </div>
</div>

<!-- Dealer Details Slide-over Drawer -->
<div class="drawer-overlay" id="adminDealerDetailDrawer" aria-hidden="true">
    <div class="drawer-panel drawer-sm" role="dialog" aria-modal="true" aria-labelledby="adminDealerDetailTitle">
        <div class="drawer-head">
            <div>
                <h2 id="adminDealerDetailTitle" class="card-title">Dealer Details</h2>
                <p id="adminDealerDetailSub" class="card-subtitle"></p>
            </div>
            <button type="button" class="icon-btn" data-drawer-close aria-label="Close">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>

        <div class="drawer-body">
            <dl class="detail-list" id="adminDealerDetailList"></dl>
        </div>

        <div class="drawer-foot">
            <button type="button" class="btn btn-secondary" data-drawer-close>Close</button>
            <button type="button" class="btn btn-primary" id="adminDealerDetailEditBtn">Edit Dealer</button>
        </div>
    </div>
</div>
<?php $this->endSection(); ?>
