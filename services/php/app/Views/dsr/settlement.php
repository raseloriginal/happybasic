<?php $this->extend('dsr.layouts.main'); ?>

<?php
use App\Support\Bn;
$s = $settlement ?? [];
$openTrip = $trip;
$trip = $s['trip'] ?? [];
$counts = $s['counts'] ?? ['pending' => 0, 'orders' => 0, 'cancelled' => 0];
$sum = $s['summary'] ?? [];
$srOcRows = $s['sr_oc_rows'] ?? [];
$dueDetails = $s['due_details'] ?? [];
$notes = $s['notes'] ?? [];

$totalLoad = (float) ($sum['total_load'] ?? 0);
$returnAmt = (float) ($sum['return_amount'] ?? 0);
$salesBase = (float) ($sum['total_sales_base'] ?? 0);
$salesSr = (float) ($sum['total_sales_sr'] ?? 0);
$damaged = (float) ($sum['damaged_amount'] ?? 0);
$expenses = (float) ($sum['daily_expenses'] ?? 0);
$deliveryOc = (float) ($sum['delivery_oc'] ?? 0);
$retailerDue = (float) ($sum['retailer_due'] ?? 0);
$readySale = (float) ($sum['ready_sale'] ?? 0);
$priorDue = (float) ($sum['prior_due_collected'] ?? 0);
$netPay = (float) ($sum['net_pay'] ?? 0);
$locked = $openTrip === null || !$openTrip['editable'];
$money = static fn(float $v): string => Bn::money($v, true);

$initCash = 0;
foreach ($notes as $n) {
    $initCash += ((int) $n['value']) * ((int) $n['qty']);
}
$initDiff = $initCash - $netPay;
$dueDetailsJson = json_encode($dueDetails, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT);
$summaryJson = json_encode($sum, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT);
?>

<?php $this->section('content'); ?>
<?php if ($openTrip === null): ?>
<section class="dsr-page-stack">
    <?php $this->include('dsr.partials.date_nav', ['selectedDate' => $selectedDate ?? null]); ?>
    <article class="card empty-trip-card"><h2 class="section-title">সেটেল করার মতো কোনো ট্রিপ নেই</h2></article>
</section>
<?php else: ?>
<section
    class="dsr-page-stack"
    id="dsrSettlementApp"
    data-summary="<?= e($summaryJson) ?>"
    data-due-details="<?= e($dueDetailsJson) ?>"
    data-locked="<?= $locked ? '1' : '0' ?>"
>
    <?php $this->include('dsr.partials.date_nav', ['selectedDate' => $selectedDate ?? null]); ?>
    <?php if ($locked): ?>
        <div class="trip-state-banner is-inline">জমা দেওয়া হয়েছে<?= !empty($trip['submitted_at']) ? ' (' . e(Bn::dateTime((string) $trip['submitted_at'])) . ')' : '' ?> — পার্টনারের যাচাইয়ের অপেক্ষায়।</div>
    <?php elseif (($trip['settlement_status'] ?? null) === 'returned'): ?>
        <div class="trip-state-banner is-inline is-returned">পার্টনার ফেরত পাঠিয়েছেন<?= $trip['review_note'] ? ': ' . e($trip['review_note']) : '' ?>। যাচাই করে পুনরায় জমা দিন।</div>
    <?php elseif ($counts['pending'] > 0): ?>
        <div class="trip-state-banner is-inline">এখনো <?= Bn::num((int) $counts['pending']) ?>টি অর্ডার বাকি আছে। জমা দেওয়ার আগে সব দোকান ডেলিভারি বা বাতিল করুন।</div>
    <?php endif; ?>

    <!-- Top Summary (4 KPIs) -->
    <div class="kpi-strip-4">
        <article class="card kpi-mini">
            <span class="kpi-label">মোট লোড (ডিসপ্যাচ)</span>
            <strong class="kpi-val tabular" id="setTopLoad"><?= $money($totalLoad) ?></strong>
        </article>
        <article class="card kpi-mini">
            <span class="kpi-label">ফেরত মাল</span>
            <strong class="kpi-val tabular is-warn" id="setTopReturn"><?= $money($returnAmt) ?></strong>
        </article>
        <article class="card kpi-mini">
            <span class="kpi-label">মোট বিক্রি</span>
            <strong class="kpi-val tabular" id="setTopSales"><?= $money($salesSr) ?></strong>
        </article>
        <article class="card kpi-mini kpi-mini-accent">
            <span class="kpi-label">জমা দেওয়ার কথা</span>
            <strong class="kpi-val tabular" id="setTopNetPay"><?= $money($netPay) ?></strong>
        </article>
    </div>

    <div class="settlement-bento">
        <div class="bento-main">
            <!-- Account Breakdown -->
            <article class="card">
                <div class="card-head">
                    <div>
                        <h2 class="section-title">হিসাবের বিবরণ</h2>
                        <p class="section-subtitle tabular"><?= e(Bn::digits($trip['code'])) ?> · <?= e($trip['dsr']) ?> · <?= Bn::num((int) $counts['orders']) ?>টি অর্ডার (<?= Bn::num((int) $counts['cancelled']) ?>টি বাতিল)</p>
                    </div>
                    <span class="badge badge-info tabular"><?= e(Bn::date($trip['date'])) ?></span>
                </div>

                <div class="account-ledger">
                    <div class="ledger-row">
                        <div class="ledger-label">
                            <strong>মোট লোড মূল্য</strong>
                        </div>
                        <strong class="ledger-val tabular"><?= $money($totalLoad) ?></strong>
                    </div>

                    <div class="ledger-row">
                        <div class="ledger-label">
                            <strong>মোট বিক্রি (বিক্রয়মূল্য)</strong>
                            <div class="sales-rate-split">
                                <span class="rate-pill">বেজ দর: <strong class="tabular"><?= $money($salesBase) ?></strong></span>
                                <span class="rate-pill rate-pill-accent">SR দর: <strong class="tabular"><?= $money($salesSr) ?></strong></span>
                            </div>
                        </div>
                        <strong class="ledger-val tabular"><?= $money($salesSr) ?></strong>
                    </div>

                    <?php if ($readySale > 0): ?>
                    <div class="ledger-row">
                        <div class="ledger-label">
                            <strong>রেডি সেল (+)</strong>
                        </div>
                        <strong class="ledger-val tabular is-ok">+ <?= $money($readySale) ?></strong>
                    </div>
                    <?php endif; ?>
                    <?php if ($priorDue > 0): ?>
                    <div class="ledger-row">
                        <div class="ledger-label">
                            <strong>আগের বাকি আদায় (+)</strong>
                        </div>
                        <strong class="ledger-val tabular is-ok">+ <?= $money($priorDue) ?></strong>
                    </div>
                    <?php endif; ?>
                    <div class="ledger-row">
                        <div class="ledger-label">
                            <strong>ফেরত মালের মূল্য</strong>
                        </div>
                        <strong class="ledger-val tabular is-warn"><?= $money($returnAmt) ?></strong>
                    </div>

                    <div class="ledger-row">
                        <div class="ledger-label">
                            <strong>ড্যামেজ পণ্য (−)</strong>
                        </div>
                        <strong class="ledger-val tabular is-danger">− <?= $money($damaged) ?></strong>
                    </div>

                    <div class="ledger-row">
                        <div class="ledger-label">
                            <strong>দৈনিক খরচ (−)</strong>
                            <span class="muted small"><a href="<?= e(url('/dsr/expense')) ?>" class="inline-link">খরচ দেখুন</a></span>
                        </div>
                        <strong class="ledger-val tabular is-danger" id="setExpenseVal">− <?= $money($expenses) ?></strong>
                    </div>

                    <div class="ledger-row">
                        <div class="ledger-label">
                            <strong>ডেলিভারি O/C (ওভার / কমিশন)</strong>
                        </div>
                        <strong class="ledger-val tabular <?= $deliveryOc >= 0 ? 'is-ok' : 'is-warn' ?>">
                            <?= Bn::signedMoney($deliveryOc, true) ?>
                        </strong>
                    </div>

                    <div class="ledger-row">
                        <div class="ledger-label">
                            <strong>দোকান বাকি (−)</strong>
                            <div class="muted small">
                                <button type="button" class="link-btn" id="openDueDetailsBtn">বিস্তারিত দেখুন (<?= Bn::num(count($dueDetails)) ?>)</button>
                            </div>
                        </div>
                        <strong class="ledger-val tabular is-warn">− <?= $money($retailerDue) ?></strong>
                    </div>

                    <div class="ledger-row ledger-row-net">
                        <div class="ledger-label">
                            <strong>ক্যাশ জমা (Net Pay)</strong>
                        </div>
                        <strong class="ledger-val-lg tabular" id="setNetPayLedger"><?= $money($netPay) ?></strong>
                    </div>
                </div>
            </article>

            <!-- SR-wise O/C View -->
            <article class="card table-card">
                <div class="card-head">
                    <div>
                        <h3 class="section-title">SR অনুযায়ী ডেলিভারি O/C</h3>
                    </div>
                </div>
                <div class="table-wrap">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>SR</th>
                                <th class="text-right">অর্ডার</th>
                                <th class="text-right">অর্ডার O/C</th>
                                <th class="text-right">ডেলিভারি O/C</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($srOcRows as $row): ?>
                                <tr>
                                    <td>
                                        <div class="cell-primary"><?= e($row['sr_name']) ?></div>
                                        <div class="cell-sub"><?= e($row['area']) ?></div>
                                    </td>
                                    <td class="text-right tabular"><?= Bn::num((int) $row['orders']) ?></td>
                                    <td class="text-right tabular"><?= Bn::signedMoney((float) $row['order_oc'], true) ?></td>
                                    <td class="text-right tabular">
                                        <strong class="<?= (float) $row['delivery_oc'] >= 0 ? 'is-ok' : 'is-warn' ?>">
                                            <?= Bn::signedMoney((float) $row['delivery_oc'], true) ?>
                                        </strong>
                                    </td>
                                </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            </article>
        </div>

        <!-- Cash Counter -->
        <aside class="bento-side">
            <article class="card cash-counter-card">
                <div class="card-head">
                    <div>
                        <h3 class="section-title">নগদ টাকা গণনা</h3>
                    </div>
                    <button type="button" class="btn btn-ghost btn-xs" id="resetCashNotesBtn">রিসেট</button>
                </div>

                <div class="notes-list" id="cashNotesList">
                    <?php foreach ($notes as $n): ?>
                        <?php $val = (int) $n['value']; $qty = (int) $n['qty']; ?>
                        <div class="note-row" data-note-value="<?= $val ?>">
                            <div class="note-denom">
                                <span class="note-chip tabular">৳ <?= Bn::digits($val) ?></span>
                                <span class="note-times">×</span>
                            </div>
                            <input
                                type="number"
                                class="note-qty-input tabular"
                                min="0"
                                step="1"
                                inputmode="numeric"
                                value="<?= $qty ?>"
                                <?= $locked ? 'readonly' : '' ?>
                                aria-label="<?= Bn::digits($val) ?> টাকার নোটের সংখ্যা"
                            >
                            <div class="note-line-total tabular" data-note-line><?= $money((float) ($val * $qty)) ?></div>
                        </div>
                    <?php endforeach; ?>
                </div>

                <div class="cash-counter-summary">
                    <div class="cc-sum-row">
                        <span class="muted">গণনাকৃত মোট ক্যাশ</span>
                        <strong class="tabular" id="ccTotalCash"><?= $money((float) $initCash) ?></strong>
                    </div>
                    <div class="cc-sum-row">
                        <span class="muted">জমা দেওয়ার কথা (Net Pay)</span>
                        <strong class="tabular" id="ccNetPay"><?= $money($netPay) ?></strong>
                    </div>
                    <div class="cc-diff-box <?= $initDiff < 0 ? 'is-short' : ($initDiff > 0 ? 'is-excess' : 'is-matched') ?>" id="ccDiffBox">
                        <div>
                            <span class="cc-diff-label" id="ccDiffStatus">
                                <?= $initDiff < 0 ? 'কম' : ($initDiff > 0 ? 'বেশি' : 'মিলেছে') ?>
                            </span>
                        </div>
                        <strong class="cc-diff-val tabular" id="ccDiffAmount">
                            <?= Bn::signedMoney((float) $initDiff, true) ?>
                        </strong>
                    </div>

                    <div class="form-group" style="margin-top:4px;margin-bottom:4px;">
                        <label for="dsrSettlementNote">পার্টনারের জন্য নোট (ঐচ্ছিক)</label>
                        <input
                            type="text"
                            id="dsrSettlementNote"
                            maxlength="255"
                            placeholder="যেমন: খুচরা কম ছিল, কাল দেব"
                            value="<?= e((string) ($s['cash']['dsr_note'] ?? '')) ?>"
                            <?= $locked ? 'readonly' : '' ?>
                        >
                    </div>

                    <button type="button" class="btn btn-primary btn-block" id="submitSettlementBtn" <?= $locked || $counts['pending'] > 0 ? 'disabled' : '' ?>><?= $locked ? 'যাচাইয়ের অপেক্ষায়' : 'সেটেলমেন্ট জমা দিন' ?></button>
                </div>
            </article>
        </aside>
    </div>
</section>

<!-- Retailer Due Details Modal -->
<div class="modal-overlay modal-top" id="dueDetailsModal" aria-hidden="true">
    <div class="modal-panel" role="dialog" aria-modal="true" aria-labelledby="dueDetailsTitle">
        <div class="modal-head">
            <div>
                <h3 id="dueDetailsTitle" class="section-title">দোকান বাকির তালিকা</h3>
            </div>
            <button type="button" class="icon-btn" data-close-modal="dueDetailsModal" aria-label="বন্ধ করুন">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>
        <div class="modal-body">
            <div class="table-wrap">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>দোকান</th>
                            <th class="text-right">অর্ডার</th>
                            <th class="text-right">জমা</th>
                            <th class="text-right">বাকি</th>
                        </tr>
                    </thead>
                    <tbody id="dueDetailsBody">
                        <?php foreach ($dueDetails as $dd): ?>
                            <tr>
                                <td>
                                    <div class="cell-primary"><?= e($dd['retailer']) ?></div>
                                    <div class="cell-sub tabular"><?= e($dd['area']) ?> · <?= e(Bn::digits($dd['phone'])) ?></div>
                                </td>
                                <td class="text-right tabular"><?= $money((float) $dd['order_total']) ?></td>
                                <td class="text-right tabular"><?= $money((float) $dd['paid']) ?></td>
                                <td class="text-right tabular"><strong class="is-warn"><?= $money((float) $dd['due']) ?></strong></td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>
        <div class="modal-foot">
            <button type="button" class="btn btn-secondary" data-close-modal="dueDetailsModal">বন্ধ</button>
        </div>
    </div>
</div>
<?php endif; ?>
<?php $this->endSection(); ?>
