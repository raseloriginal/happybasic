<?php $this->extend('admin.layouts.main'); ?>

<?php $this->section('topbar_actions'); ?>
<button type="submit" class="btn btn-primary btn-sm" id="adminFeeSaveTopBtn" form="adminFeeForm" disabled>
    <span>Save Fees</span>
</button>
<?php $this->endSection(); ?>

<?php $this->section('content'); ?>
<section class="panel" id="adminFeesApp"
    data-base-url="<?= e(url('/admin/platform-fees')) ?>"
    data-links="<?= e(json_encode($links, JSON_UNESCAPED_UNICODE)) ?>"
>
    <div class="toolbar">
        <div class="toolbar-filters">
            <select id="adminFeePartner" class="select-input" aria-label="Select partner">
                <?php if (!$partners): ?>
                    <option value="">No partners yet</option>
                <?php endif; ?>
                <?php foreach ($partners as $p): ?>
                    <option value="<?= (int) $p['id'] ?>" <?= $selectedPartnerId === (int) $p['id'] ? 'selected' : '' ?>>
                        <?= e($p['name']) ?> (<?= e($p['area']) ?>)<?= $p['status'] === 'Active' ? '' : ' (inactive)' ?>
                    </option>
                <?php endforeach; ?>
            </select>

            <select id="adminFeeOwnership" class="select-input" aria-label="Filter by ownership">
                <option value="">All Ownership</option>
                <option value="Owned">Owned</option>
                <option value="Dealer">Dealer</option>
            </select>
        </div>

        <div class="toolbar-meta">
            <span class="muted small"><strong id="adminFeeCount">0</strong> connected companies</span>
        </div>
    </div>

    <form id="adminFeeForm" novalidate>
        <div class="table-wrap">
            <table class="data-table">
                <thead>
                    <tr>
                        <th>Company</th>
                        <th>Ownership</th>
                        <th>Dealer &amp; Profit Share</th>
                        <th class="text-right">SR</th>
                        <th class="text-right">Platform Fee per Lakh Sales (৳)</th>
                        <th class="text-right">History</th>
                    </tr>
                </thead>
                <tbody id="adminFeeTbody"></tbody>
            </table>
        </div>

        <div class="empty-state" id="adminFeeEmpty" hidden>
            <p>No companies connected to this partner yet. Add an SR (Owned or via Dealer) to connect a company.</p>
        </div>

        <div class="fee-foot">
            <span class="muted small" id="adminFeeDirty">A changed fee applies to sales from the moment you save. Past sales keep the fee they were made under.</span>
            <button type="submit" class="btn btn-primary" id="adminFeeSaveBtn" disabled>Save Fees</button>
        </div>
    </form>
</section>

<!-- Fee history drawer -->
<div class="drawer-overlay" id="adminFeeHistoryDrawer" aria-hidden="true">
    <div class="drawer-panel" role="dialog" aria-modal="true" aria-labelledby="adminFeeHistoryTitle">
        <div class="drawer-head">
            <div>
                <h2 id="adminFeeHistoryTitle" class="card-title">Fee History</h2>
                <p id="adminFeeHistorySub" class="card-subtitle">Each fee period with the sales and fee earned inside it.</p>
            </div>
            <button type="button" class="icon-btn" data-drawer-close aria-label="Close">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>
        <div class="drawer-body" id="adminFeeHistoryBody"></div>
    </div>
</div>
<?php $this->endSection(); ?>
