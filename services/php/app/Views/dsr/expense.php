<?php $this->extend('dsr.layouts.main'); ?>

<?php
use App\Support\Bn;
$list = $expenses ?? [];
$totalExp = array_sum(array_column($list, 'amount'));
$expensesJson = json_encode($list, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT);
$catMap = [];
foreach ($categories as $cat) {
    $catMap[$cat] = Bn::expenseCategory($cat);
}
$catMapJson = json_encode($catMap, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT);
?>

<?php $locked = $trip === null || !$trip['editable']; ?>
<?php $this->section('topbar_actions'); ?>
<button type="button" class="btn btn-primary btn-sm" id="openAddExpenseBtn" <?= $locked ? 'disabled' : '' ?>>
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M12 5v14M5 12h14"/></svg>
    <span>খরচ যোগ</span>
</button>
<?php $this->endSection(); ?>

<?php $this->section('content'); ?>
<section class="dsr-page-stack" id="dsrExpenseApp" data-expenses="<?= e($expensesJson) ?>" data-cat-labels="<?= e($catMapJson) ?>" data-locked="<?= $locked ? '1' : '0' ?>">
    <?php if ($trip === null): ?>
        <article class="card empty-trip-card"><h2 class="section-title">কোনো ডিসপ্যাচ করা ট্রিপ নেই</h2></article>
    <?php elseif (!$trip['editable']): ?>
        <div class="trip-state-banner is-inline">সেটেলমেন্ট জমা দেওয়া হয়েছে — পার্টনার যাচাই শেষ না হওয়া পর্যন্ত খরচ লক থাকবে।</div>
    <?php endif; ?>

    <!-- Top Summary Card -->
    <article class="card exp-summary-card">
        <div>
            <span class="kpi-label">মোট দৈনিক খরচ</span>
            <div class="kpi-value-lg tabular" id="expenseTotalValue"><?= Bn::money((float) $totalExp, true) ?></div>
            <span class="muted small tabular"><?= $trip ? e(Bn::digits($trip['code'])) . ' · ' . e(Bn::date($trip['date'])) : '—' ?></span>
        </div>
        <div class="exp-summary-right">
            <span class="badge badge-neutral tabular" id="expenseCountBadge"><?= Bn::num(count($list)) ?>টি আইটেম</span>
            <button type="button" class="btn btn-primary btn-sm" id="openAddExpenseInlineBtn" <?= $locked ? 'disabled' : '' ?>>+ খরচ যোগ</button>
        </div>
    </article>

    <!-- Category Filter -->
    <div class="exp-filter-strip" id="expenseFilterStrip">
        <button type="button" class="chip-filter is-active" data-exp-cat="all">সব</button>
        <?php foreach ($categories as $cat): ?>
            <button type="button" class="chip-filter" data-exp-cat="<?= e($cat) ?>"><?= e(Bn::expenseCategory($cat)) ?></button>
        <?php endforeach; ?>
    </div>

    <!-- Expense List -->
    <article class="card">
        <div class="card-head">
            <div>
                <h2 class="section-title">দৈনিক খরচের তালিকা</h2>
            </div>
        </div>
        <div class="expense-list" id="expenseListContainer">
            <?php foreach ($list as $ex): ?>
                <div class="expense-row" data-exp-id="<?= e($ex['id']) ?>">
                    <div class="expense-row-main">
                        <div class="expense-row-top">
                            <strong><?= e($ex['title']) ?></strong>
                            <span class="badge badge-neutral"><?= e(Bn::expenseCategory((string) $ex['category'])) ?></span>
                        </div>
                        <div class="muted small tabular"><?= e(Bn::digits($ex['time'])) ?><?= !empty($ex['note']) ? ' · ' . e($ex['note']) : '' ?></div>
                    </div>
                    <div class="expense-row-right">
                        <strong class="tabular"><?= Bn::money((float) $ex['amount'], true) ?></strong>
                        <button type="button" class="btn-trash-sm" data-delete-expense="<?= e($ex['id']) ?>" aria-label="খরচ মুছুন">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/></svg>
                        </button>
                    </div>
                </div>
            <?php endforeach; ?>
        </div>
    </article>
</section>

<!-- Add Expense Modal -->
<div class="modal-overlay modal-top modal-center" id="addExpenseModal" aria-hidden="true">
    <div class="modal-panel dialog-card" role="dialog" aria-modal="true" aria-labelledby="addExpTitle">
        <div class="modal-head">
            <div>
                <h3 id="addExpTitle" class="section-title">দৈনিক খরচ যোগ করুন</h3>
            </div>
            <button type="button" class="icon-btn" data-close-modal="addExpenseModal" aria-label="বন্ধ করুন">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>
        <form id="addExpenseForm" class="dialog-form">
            <div class="modal-body">
                <div class="form-group">
                    <label for="expTitleInput">খরচের বিবরণ</label>
                    <input id="expTitleInput" type="text" placeholder="যেমন: সিএনজি / তেল খরচ" required>
                </div>
                <div class="po-price-grid">
                    <div class="form-group">
                        <label for="expCategoryInput">ক্যাটাগরি</label>
                        <select id="expCategoryInput" required>
                            <?php foreach ($categories as $cat): ?>
                                <option value="<?= e($cat) ?>"><?= e(Bn::expenseCategory($cat)) ?></option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    <div class="form-group">
                        <label for="expAmountInput">টাকার পরিমাণ (৳)</label>
                        <input id="expAmountInput" type="number" min="1" step="0.01" inputmode="numeric" placeholder="০" required>
                    </div>
                </div>
                <div class="form-group">
                    <label for="expNoteInput">নোট (ঐচ্ছিক)</label>
                    <input id="expNoteInput" type="text" placeholder="স্লিপ নম্বর বা মন্তব্য">
                </div>
                <div class="alert alert-error" id="expFormError" hidden></div>
            </div>
            <div class="modal-foot">
                <button type="button" class="btn btn-secondary" data-close-modal="addExpenseModal">বাতিল</button>
                <button type="submit" class="btn btn-primary" id="saveExpenseBtn">খরচ সংরক্ষণ করুন</button>
            </div>
        </form>
    </div>
</div>
<?php $this->endSection(); ?>
