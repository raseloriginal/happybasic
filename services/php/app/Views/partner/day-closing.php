<?php $this->extend('partner.layouts.main'); ?>

<?php
use App\Support\Bn;

$c = $closing;
$p = $c['partner'];
$cnt = $c['counts'];
$cash = $c['cash'];
$pnl = $c['pnl'];
$trips = $c['trips'];
$srRows = $c['sr_oc'];
$variances = $c['variances'];

$money = static fn(float $v): string => Bn::money($v, true);
$signed = static fn(float $v): string => Bn::signedMoney($v, true);
$moneyCompact = static fn(float $v): string => '৳' . Bn::smartNum($v);
$signedCompact = static fn(float $v): string => ($v >= 0 ? '+৳' : '−৳') . Bn::smartNum(abs($v));

$prevDate = date('Y-m-d', strtotime($date . ' -1 day'));
$nextDate = date('Y-m-d', strtotime($date . ' +1 day'));
$today = date('Y-m-d');

$hasTrips = $cnt['trips'] > 0;
$allSettled = $hasTrips && $cnt['in_review'] === 0 && $cnt['dispatched'] === 0;
$noneSubmitted = $hasTrips && $cnt['settled'] === 0 && $cnt['in_review'] === 0;
$diff = (float) $cash['diff'];
$isShort = !$noneSubmitted && $diff < -0.004;
$isExcess = !$noneSubmitted && $diff > 0.004;
$isMatched = !$noneSubmitted && !$isShort && !$isExcess;

$diffLabel = $noneSubmitted ? 'জমা বাকি' : ($isShort ? 'কম' : ($isExcess ? 'বেশি' : 'মিলেছে'));
$diffClass = $noneSubmitted ? 'is-warn' : ($isShort ? 'is-danger' : ($isExcess ? 'is-warn' : 'is-ok'));
$diffBadge = $noneSubmitted ? 'badge-warning' : ($isShort ? 'badge-danger' : ($isExcess ? 'badge-warning' : 'badge-success'));

$expNote = $cash['expense_categories'] !== []
    ? implode(', ', $cash['expense_categories'])
    : 'কোনো খরচ নেই';

$receivedNote = $allSettled
    ? 'আপনি গুনে কনফার্ম করেছেন'
    : ($cnt['settled'] > 0
        ? Bn::num((int) $cnt['settled']) . 'টি সেটেল্ড' . ($cnt['in_review'] > 0 ? ' · ' . Bn::num((int) $cnt['in_review']) . 'টি কনফার্ম বাকি' : '') . ($cnt['dispatched'] > 0 ? ' · ' . Bn::num((int) $cnt['dispatched']) . 'টি রাস্তায়' : '')
        : ($cnt['in_review'] > 0 ? 'DM জমা দিয়েছে (কনফার্ম বাকি)' : 'এখনো জমা হয়নি'));

$partnerSubParts = array_values(array_filter([
    $p['address'] !== '' ? $p['address'] : null,
    $p['area'] !== '' && mb_stripos($p['address'], $p['area']) === false ? $p['area'] : null,
]));
$partnerSubtitle = ($partnerSubParts !== [] ? implode(', ', $partnerSubParts) . ' · ' : '') . config('app.name', 'HappyBasic') . ' Smart Partner';

// Cash breakdown rows shared between screen ledger and print sheet
$cashRows = [
    [
        'label' => 'গুদাম থেকে মাল বের',
        'note' => 'বিক্রির রেটে · ' . Bn::num((int) $cnt['trips']) . 'টি ট্রিপ',
        'amount' => (float) $cash['goods_out'],
        'sign' => 'base',
    ],
    [
        'label' => 'ভালো মাল ফেরত',
        'note' => $cash['return_pcs'] > 0
            ? ($allSettled ? 'গুদাম স্টকে ফিরেছে · ' : 'ফেরত আনুমানিক · ') . Bn::num((int) $cash['return_pcs']) . ' পিস'
            : 'কোনো ফেরত নেই',
        'amount' => -(float) $cash['goods_return'],
        'sign' => 'minus',
    ],
];
if (abs((float) $cash['stock_rate_adj']) >= 0.01) {
    $cashRows[] = [
        'label' => 'রেট / ফেরত সমন্বয়',
        'note' => 'অর্ডার রেট ও ফেরত গণনার পার্থক্য',
        'amount' => (float) $cash['stock_rate_adj'],
        'sign' => (float) $cash['stock_rate_adj'] >= 0 ? 'plus' : 'minus',
    ];
}
$cashRows[] = [
    'label' => 'ড্যামেজ',
    'note' => $cash['damage'] > 0 ? 'ডেলিভারিতে বাদ · কোম্পানি খাতায় ক্লেইম' : 'কোনো ড্যামেজ নেই',
    'amount' => -(float) $cash['damage'],
    'sign' => 'minus',
];
$cashRows[] = [
    'label' => 'নতুন বাকি দেওয়া',
    'note' => $cnt['due_shops'] > 0
        ? Bn::num((int) $cnt['due_shops']) . 'টি দোকান' . ($allSettled ? ' · পার্টনার অনুমোদিত' : '')
        : 'কোনো নতুন বাকি নেই',
    'amount' => -(float) $cash['new_due'],
    'sign' => 'minus',
];
$cashRows[] = [
    'label' => 'SR কমিশন',
    'note' => 'রেটের কমে বিক্রি',
    'amount' => -(float) $cash['sr_commission'],
    'sign' => 'minus',
];
$cashRows[] = [
    'label' => 'SR ওভার',
    'note' => 'রেটের বেশিতে বিক্রি',
    'amount' => (float) $cash['sr_over'],
    'sign' => 'plus',
];
$cashRows[] = [
    'label' => 'আগের বাকি আদায়',
    'note' => $cnt['prior_due_shops'] > 0 ? Bn::num((int) $cnt['prior_due_shops']) . 'টি দোকান থেকে' : 'কোনো আদায় নেই',
    'amount' => (float) $cash['prior_due'],
    'sign' => 'plus',
];
$cashRows[] = [
    'label' => 'DM খরচ',
    'note' => $expNote,
    'amount' => -(float) $cash['expenses'],
    'sign' => 'minus',
];

// Variance summary text (for both screen callout and print footer box)
$varianceItems = [];
foreach ($variances as $v) {
    $vAmt = $moneyCompact(abs((float) $v['diff']));
    $vDir = (float) $v['diff'] < 0 ? 'কম এসেছে' : 'বেশি এসেছে';
    $vText = "{$vAmt} {$vDir} (ট্রিপ " . Bn::num((int) $v['seq']) . " · {$v['dsr']})";
    if (!empty($v['note'])) {
        $vText .= ' · নোট: ' . $v['note'];
    }
    $varianceItems[] = $vText;
}
if ($cnt['dispatched'] > 0) {
    $varianceItems[] = Bn::num((int) $cnt['dispatched']) . 'টি ট্রিপ এখনো রাস্তায় (' . $moneyCompact((float) $cash['unsubmitted']) . ' জমা বাকি)';
}
if ($cnt['in_review'] > 0) {
    $varianceItems[] = Bn::num((int) $cnt['in_review']) . 'টি ট্রিপ পার্টনার কনফার্ম বাকি';
}
?>

<?php $this->section('topbar_actions'); ?>
<span class="badge badge-neutral tabular"><?= e(Bn::digits($c['code'])) ?></span>
<button type="button" class="btn btn-primary btn-sm" data-print-page <?= !$hasTrips ? 'disabled' : '' ?>>
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 6 2 18 2 18 9"/><path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><rect x="6" y="14" width="12" height="8"/></svg>
    <span>প্রিন্ট / PDF</span>
</button>
<?php $this->endSection(); ?>

<?php $this->section('content'); ?>

<!-- =======================================================================
     SCREEN VIEW (Modern Partner Panel UI — hidden when printing)
     ======================================================================= -->
<div class="dc-screen">
    <form class="toolbar-card dc-toolbar" method="GET" action="<?= e(url('/partner/day-closing')) ?>" data-spa-get>
        <div class="toolbar-filters">
            <a href="<?= e(url('/partner/day-closing?date=' . $prevDate)) ?>" class="icon-btn" title="আগের দিন" aria-label="আগের দিন">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m15 18-6-6 6-6"/></svg>
            </a>
            <label class="date-field">
                <span class="muted small">তারিখ</span>
                <input type="date" name="date" value="<?= e($date) ?>" class="select-input" data-auto-submit>
            </label>
            <a href="<?= e(url('/partner/day-closing?date=' . $nextDate)) ?>" class="icon-btn" title="পরের দিন" aria-label="পরের দিন">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m9 18 6-6-6-6"/></svg>
            </a>
            <?php if ($date !== $today): ?>
                <a href="<?= e(url('/partner/day-closing')) ?>" class="btn btn-secondary btn-sm">আজ</a>
            <?php endif; ?>
        </div>

        <div class="dc-toolbar-right">
            <span class="muted small"><?= e(Bn::fullDate($date)) ?></span>
            <?php if ($hasTrips): ?>
                <span class="badge <?= $allSettled ? 'badge-success' : 'badge-warning' ?>">
                    <?= $allSettled ? 'সব ট্রিপ সেটেল্ড' : Bn::num((int) $cnt['settled']) . '/' . Bn::num((int) $cnt['trips']) . ' সেটেল্ড' ?>
                </span>
            <?php endif; ?>
        </div>
    </form>

    <?php if ($c['recent_dates'] !== []): ?>
        <div class="dc-date-pills">
            <span class="muted small">সাম্প্রতিক দিন:</span>
            <?php foreach ($c['recent_dates'] as $rd): ?>
                <a href="<?= e(url('/partner/day-closing?date=' . $rd)) ?>" class="dc-date-pill <?= $rd === $date ? 'is-active' : '' ?>">
                    <?= e(Bn::date((string) $rd)) ?>
                </a>
            <?php endforeach; ?>
        </div>
    <?php endif; ?>

    <?php if (!$hasTrips): ?>
        <div class="card empty-state dc-empty">
            <p><strong><?= e(Bn::fullDate($date)) ?></strong> তারিখে কোনো ডিসপ্যাচড বা সেটেল্ড ট্রিপ নেই।</p>
            <?php if ($cnt['pending_trips'] > 0): ?>
                <p class="muted small">এই তারিখে <?= Bn::num((int) $cnt['pending_trips']) ?>টি ট্রিপ এখনো ডিসপ্যাচ করা হয়নি। <a href="<?= e(url('/partner/trips')) ?>" class="text-link">ট্রিপ পেজে যান →</a></p>
            <?php else: ?>
            <?php endif; ?>
        </div>
    <?php else: ?>

        <?php if (!$allSettled || $cnt['pending_trips'] > 0): ?>
            <div class="notice dc-status-notice">
                <div>
                    <?php if ($cnt['in_review'] > 0): ?>
                        <strong><?= Bn::num((int) $cnt['in_review']) ?>টি ট্রিপ</strong> কনফার্মের অপেক্ষায় আছে।
                    <?php endif; ?>
                    <?php if ($cnt['dispatched'] > 0): ?>
                        <strong><?= Bn::num((int) $cnt['dispatched']) ?>টি ট্রিপ</strong> এখনো রাস্তায় আছে।
                    <?php endif; ?>
                    <?php if ($cnt['pending_trips'] > 0): ?>
                        <strong><?= Bn::num((int) $cnt['pending_trips']) ?>টি ট্রিপ</strong> ডিসপ্যাচ বাকি।
                    <?php endif; ?>
                    চূড়ান্ত ডে ক্লোজিং প্রিন্টের আগে সব ট্রিপ সেটেল করে নিন।
                </div>
                <a href="<?= e(url('/partner/settlements?from=' . $date . '&to=' . $date)) ?>" class="text-link">সেটেলমেন্ট দেখুন →</a>
            </div>
        <?php endif; ?>

        <!-- 4 Hero KPI Cards -->
        <section class="dc-kpi-grid">
            <article class="card kpi-card">
                <span class="kpi-label">গুদাম থেকে মাল বের</span>
                <div class="kpi-value tabular"><?= $money((float) $cash['goods_out']) ?></div>
                <span class="muted small tabular">
                    <?= Bn::num((int) $cnt['trips']) ?>টি ট্রিপ · ফেরত <?= $money((float) $cash['goods_return']) ?>
                </span>
            </article>

            <article class="card kpi-card">
                <span class="kpi-label">হাতে আসার কথা (নিট ক্যাশ)</span>
                <div class="kpi-value tabular"><?= $money((float) $cash['expected']) ?></div>
                <span class="muted small tabular">
                    সিস্টেম হিসাব · খরচ <?= $money((float) $cash['expenses']) ?> বাদে
                </span>
            </article>

            <article class="card kpi-card">
                <span class="kpi-label">আসলে হাতে এলো</span>
                <div class="kpi-value <?= $isShort ? 'is-danger' : 'is-ok' ?> tabular"><?= $money((float) $cash['received']) ?></div>
                <span class="muted small tabular"><?= e($receivedNote) ?></span>
            </article>

            <article class="card kpi-card">
                <div class="dc-kpi-top">
                    <span class="kpi-label">ক্যাশ পার্থক্য</span>
                    <span class="badge <?= $diffBadge ?>"><?= e($diffLabel) ?></span>
                </div>
                <div class="kpi-value <?= $diffClass ?> tabular">
                    <?= $isMatched ? $money(0) : $money(abs($diff)) ?>
                </div>
                <span class="muted small tabular">
                    আজকের নিট লাভ: <strong class="<?= $pnl['net_profit'] >= 0 ? 'is-ok' : 'is-danger' ?>"><?= $money((float) $pnl['net_profit']) ?></strong>
                </span>
            </article>
        </section>

        <!-- Main 2-Column Workspace -->
        <div class="dc-grid">
            <!-- Left Column: Cash Account + DM/Trip Table -->
            <div class="dc-col-main">
                <!-- Cash Breakdown Card -->
                <article class="card">
                    <div class="card-head">
                        <div>
                            <h2 class="section-title">টাকার হিসাব (ক্যাশ ফ্লো)</h2>
                        </div>
                        <span class="badge badge-neutral tabular"><?= Bn::num((int) $cnt['trips']) ?>টি ট্রিপ</span>
                    </div>

                    <div class="dc-ledger">
                        <?php foreach ($cashRows as $i => $row): ?>
                            <?php
                            $amt = (float) $row['amount'];
                            $valClass = 'muted';
                            $formatted = $money(0);
                            if ($row['sign'] === 'base') {
                                $valClass = '';
                                $formatted = $money(abs($amt));
                            } elseif (abs($amt) >= 0.01) {
                                $valClass = $amt > 0 ? 'is-ok' : 'is-danger';
                                $formatted = ($amt > 0 ? '+ ' : '− ') . $money(abs($amt));
                            }
                            ?>
                            <div class="dc-ledger-row">
                                <span class="dc-ledger-sl tabular"><?= Bn::num($i + 1) ?></span>
                                <div class="dc-ledger-info">
                                    <strong><?= e($row['label']) ?></strong>
                                    <span class="muted small"><?= e($row['note']) ?></span>
                                </div>
                                <span class="dc-ledger-amt tabular <?= $valClass ?>"><?= $formatted ?></span>
                            </div>
                        <?php endforeach; ?>
                    </div>

                    <div class="dc-ledger-totals">
                        <div class="dc-total-row">
                            <div>
                                <strong>হাতে আসার কথা</strong>
                                <span class="muted small">সিস্টেমের হিসাব</span>
                            </div>
                            <strong class="tabular dc-total-val"><?= $money((float) $cash['expected']) ?></strong>
                        </div>
                        <div class="dc-total-row is-received">
                            <div>
                                <strong>আসলে হাতে এলো</strong>
                                <span class="muted small"><?= e($receivedNote) ?></span>
                            </div>
                            <strong class="tabular dc-total-val <?= $isShort ? 'is-danger' : 'is-ok' ?>"><?= $money((float) $cash['received']) ?></strong>
                        </div>
                    </div>

                    <div class="st-callout <?= $isShort ? 'is-short' : ($isExcess || $noneSubmitted ? 'is-excess' : 'is-matched') ?>" style="margin-top: 12px;">
                        <strong class="tabular">
                            <?php if ($noneSubmitted): ?>
                                এখনো কোনো ট্রিপের ক্যাশ জমা হয়নি (<?= $money((float) $cash['expected']) ?> বাকি)
                            <?php elseif ($isMatched && $allSettled): ?>
                                দিনের ক্যাশ হিসাব সম্পূর্ণ মিলেছে
                            <?php elseif ($isShort): ?>
                                গরমিল: <?= $money(abs($diff)) ?> কম এসেছে
                            <?php elseif ($isExcess): ?>
                                গরমিল: <?= $money(abs($diff)) ?> বেশি এসেছে
                            <?php else: ?>
                                জমা হওয়া হিসাব মিলেছে
                            <?php endif; ?>
                        </strong>
                        <?php if ($varianceItems !== []): ?>
                            <p class="st-callout-note"><?= e(implode(' · ', $varianceItems)) ?></p>
                        <?php endif; ?>
                    </div>

                    <?php if ($cash['notes'] !== []): ?>
                        <details class="dc-notes-details">
                            <summary class="dc-notes-summary">
                                <span>নোট গণনার সারাংশ (DM জমা)</span>
                                <span class="muted small tabular"><?= Bn::num(array_sum(array_column($cash['notes'], 'qty'))) ?>টি নোট</span>
                            </summary>
                            <div class="dc-notes-grid">
                                <?php foreach ($cash['notes'] as $n): ?>
                                    <div class="dc-note-chip tabular">
                                        <span>৳<?= Bn::num((int) $n['value']) ?> × <?= Bn::num((int) $n['qty']) ?></span>
                                        <strong><?= $money((float) $n['total']) ?></strong>
                                    </div>
                                <?php endforeach; ?>
                            </div>
                        </details>
                    <?php endif; ?>
                </article>

                <!-- DM / Trip Breakdown Card -->
                <article class="card dc-table-card">
                    <div class="card-head dc-card-pad">
                        <div>
                            <h2 class="section-title">DM ও ট্রিপ অনুযায়ী হিসাব</h2>
                        </div>
                        <a href="<?= e(url('/partner/settlements?from=' . $date . '&to=' . $date)) ?>" class="text-link">সেটেলমেন্ট →</a>
                    </div>
                    <div class="table-wrap">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>DM · ট্রিপ</th>
                                    <th class="text-right">মাল বের</th>
                                    <th class="text-right">ফেরত</th>
                                    <th class="text-right">বাকি</th>
                                    <th class="text-right">খরচ</th>
                                    <th class="text-right">জমার কথা</th>
                                    <th class="text-right">জমা দিল</th>
                                    <th class="text-right">পার্থক্য</th>
                                </tr>
                            </thead>
                            <tbody>
                                <?php foreach ($trips as $t): ?>
                                    <?php
                                    $tBadge = match ($t['status_key']) {
                                        'settled' => 'badge-success',
                                        'in_review' => 'badge-warning',
                                        default => 'badge-info',
                                    };
                                    $tDiff = $t['cash_diff'];
                                    ?>
                                    <tr>
                                        <td>
                                            <div class="cell-primary"><?= e($t['dsr']) ?></div>
                                            <div class="cell-sub tabular">
                                                <?= e(Bn::digits($t['code'])) ?> · <span class="badge <?= $tBadge ?> dc-mini-badge"><?= e(Bn::status($t['status_key'])) ?></span>
                                            </div>
                                        </td>
                                        <td class="text-right tabular"><?= $money((float) $t['load_base']) ?></td>
                                        <td class="text-right tabular muted"><?= $money((float) $t['return_base']) ?></td>
                                        <td class="text-right tabular"><?= $t['new_due'] > 0 ? $money((float) $t['new_due']) : '—' ?></td>
                                        <td class="text-right tabular"><?= $t['expense'] > 0 ? $money((float) $t['expense']) : '—' ?></td>
                                        <td class="text-right tabular"><?= $money((float) $t['expected_cash']) ?></td>
                                        <td class="text-right tabular">
                                            <?php if ($t['received_cash'] !== null): ?>
                                                <strong><?= $money((float) $t['received_cash']) ?></strong>
                                            <?php else: ?>
                                                <span class="muted">বাকি</span>
                                            <?php endif; ?>
                                        </td>
                                        <td class="text-right tabular">
                                            <?php if ($tDiff === null): ?>
                                                <span class="muted">—</span>
                                            <?php elseif (abs((float) $tDiff) < 0.01): ?>
                                                <span class="is-ok" title="মিলেছে">✓</span>
                                            <?php else: ?>
                                                <strong class="<?= (float) $tDiff < 0 ? 'is-danger' : 'is-warn' ?>"><?= $signed((float) $tDiff) ?></strong>
                                            <?php endif; ?>
                                        </td>
                                    </tr>
                                <?php endforeach; ?>
                            </tbody>
                            <tfoot>
                                <tr>
                                    <th>মোট (<?= Bn::num((int) $cnt['trips']) ?>টি ট্রিপ)</th>
                                    <th class="text-right tabular"><?= $money((float) $cash['goods_out']) ?></th>
                                    <th class="text-right tabular"><?= $money((float) $cash['goods_return']) ?></th>
                                    <th class="text-right tabular"><?= $money((float) $cash['new_due']) ?></th>
                                    <th class="text-right tabular"><?= $money((float) $cash['expenses']) ?></th>
                                    <th class="text-right tabular"><?= $money((float) $cash['expected']) ?></th>
                                    <th class="text-right tabular"><?= $money((float) $cash['received']) ?></th>
                                    <th class="text-right tabular <?= $diffClass ?>">
                                        <?= $isMatched ? '✓' : $signed($diff) ?>
                                    </th>
                                </tr>
                            </tfoot>
                        </table>
                    </div>
                </article>
            </div>

            <!-- Right Column: Profit & Loss + SR O/C + Operational Strip -->
            <div class="dc-col-side">
                <!-- Today's Profit & Loss -->
                <article class="card">
                    <div class="card-head">
                        <div>
                            <h2 class="section-title">আজকের লাভ-ক্ষতি</h2>
                        </div>
                        <span class="badge <?= $pnl['net_profit'] >= 0 ? 'badge-success' : 'badge-danger' ?> tabular">
                            মার্জিন <?= Bn::digits($pnl['margin_pct']) ?>%
                        </span>
                    </div>

                    <div class="dc-profit-hero <?= $pnl['net_profit'] < 0 ? 'is-loss' : '' ?>">
                        <span class="small muted">আজকের নিট লাভ</span>
                        <strong class="tabular <?= $pnl['net_profit'] >= 0 ? 'is-ok' : 'is-danger' ?>"><?= $money((float) $pnl['net_profit']) ?></strong>
                    </div>

                    <div class="dc-pnl-list">
                        <div class="dc-pnl-row">
                            <span>ডেলিভারি হওয়া মালের বিক্রি (রেটে)</span>
                            <strong class="tabular"><?= $money((float) $pnl['delivered_base']) ?></strong>
                        </div>
                        <div class="dc-pnl-row">
                            <span class="muted">কেনা দাম (FIFO)</span>
                            <span class="tabular muted"><?= $money((float) $pnl['fifo_cost']) ?></span>
                        </div>
                        <div class="dc-pnl-row is-sub">
                            <span>কেনা দাম বাদে মার্জিন (গড় <?= Bn::digits($pnl['margin_pct']) ?>%)</span>
                            <strong class="tabular is-ok"><?= $money((float) $pnl['gross_margin']) ?></strong>
                        </div>
                        <div class="dc-pnl-row">
                            <span>DM খরচ</span>
                            <span class="tabular <?= $pnl['expenses'] > 0 ? 'is-danger' : 'muted' ?>">
                                <?= $pnl['expenses'] > 0 ? '− ' . $money((float) $pnl['expenses']) : $money(0) ?>
                            </span>
                        </div>
                        <div class="dc-pnl-row">
                            <span>ড্যামেজ (মোট)</span>
                            <span class="tabular <?= $pnl['damage'] > 0 ? 'is-danger' : 'muted' ?>">
                                <?= $pnl['damage'] > 0 ? '− ' . $money((float) $pnl['damage']) : $money(0) ?>
                            </span>
                        </div>
                        <?php if ($pnl['damage_claim'] > 0): ?>
                            <div class="dc-pnl-row">
                                <span>কোম্পানি ড্যামেজ ক্লেইম</span>
                                <span class="tabular is-ok">+ <?= $money((float) $pnl['damage_claim']) ?></span>
                            </div>
                        <?php endif; ?>
                        <div class="dc-pnl-row">
                            <span>
                                Happy ফি<?= $pnl['avg_fee_rate'] > 0 ? ' (প্রতি লাখ ' . $moneyCompact((float) $pnl['avg_fee_rate']) . ')' : '' ?>
                            </span>
                            <span class="tabular <?= $pnl['platform_fee'] > 0 ? 'is-danger' : 'muted' ?>">
                                <?= $pnl['platform_fee'] > 0 ? '− ' . $money((float) $pnl['platform_fee']) : $money(0) ?>
                            </span>
                        </div>
                    </div>

                    <?php if (abs((float) $pnl['sr_net_oc']) >= 0.01): ?>
                        <p class="muted small dc-pnl-foot tabular">
                            SR নিট <?= $pnl['sr_net_oc'] >= 0 ? 'ওভার (SR-এর পাওনা)' : 'কমিশন (SR থেকে কর্তন)' ?>: <strong><?= $signed((float) $pnl['sr_net_oc']) ?></strong> · আলাদাভাবে SR O/C খাতায় সমন্বিত।
                        </p>
                    <?php endif; ?>
                </article>

                <!-- SR Over / Commission -->
                <article class="card dc-table-card">
                    <div class="card-head dc-card-pad">
                        <div>
                            <h2 class="section-title">SR ওভার / কমিশন</h2>
                        </div>
                        <span class="badge <?= $cash['sr_net_oc'] >= 0 ? 'badge-success' : 'badge-warning' ?> tabular">
                            <?= $signed((float) $cash['sr_net_oc']) ?>
                        </span>
                    </div>

                    <?php if ($srRows === []): ?>
                        <div class="dc-card-pad muted small">এই তারিখে কোনো SR অর্ডার ডেলিভারি হয়নি।</div>
                    <?php else: ?>
                        <div class="table-wrap">
                            <table class="data-table">
                                <thead>
                                    <tr>
                                        <th>SR</th>
                                        <th class="text-right">বিক্রি</th>
                                        <th class="text-right">নিট O/C</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <?php foreach ($srRows as $sr): ?>
                                        <tr>
                                            <td>
                                                <div class="cell-primary"><?= e($sr['sr_name']) ?></div>
                                                <div class="cell-sub"><?= e($sr['company']) ?> · <?= Bn::num((int) $sr['orders']) ?>টি অর্ডার</div>
                                            </td>
                                            <td class="text-right tabular"><?= $money((float) $sr['sales_sr']) ?></td>
                                            <td class="text-right tabular">
                                                <strong class="<?= $sr['net_oc'] > 0.004 ? 'is-ok' : ($sr['net_oc'] < -0.004 ? 'is-danger' : 'muted') ?>">
                                                    <?= abs((float) $sr['net_oc']) < 0.01 ? $money(0) : $signed((float) $sr['net_oc']) ?>
                                                </strong>
                                            </td>
                                        </tr>
                                    <?php endforeach; ?>
                                </tbody>
                            </table>
                        </div>
                    <?php endif; ?>
                </article>

                <!-- Operational Quick Stats -->
                <article class="card">
                    <h2 class="section-title" style="margin-bottom: 12px;">দিনের কার্যক্রম</h2>
                    <div class="dc-mini-stats">
                        <div class="dc-mini-stat">
                            <span class="muted small">মোট অর্ডার</span>
                            <strong class="tabular"><?= Bn::num((int) $cnt['orders']) ?></strong>
                        </div>
                        <div class="dc-mini-stat">
                            <span class="muted small">ডেলিভার্ড</span>
                            <strong class="tabular is-ok"><?= Bn::num((int) $cnt['delivered']) ?></strong>
                        </div>
                        <div class="dc-mini-stat">
                            <span class="muted small">বাতিল</span>
                            <strong class="tabular <?= $cnt['cancelled'] > 0 ? 'is-danger' : 'muted' ?>"><?= Bn::num((int) $cnt['cancelled']) ?></strong>
                        </div>
                        <div class="dc-mini-stat">
                            <span class="muted small">রেডি সেল</span>
                            <strong class="tabular"><?= $money((float) $cash['ready_sale']) ?></strong>
                        </div>
                        <div class="dc-mini-stat">
                            <span class="muted small">নতুন বাকি</span>
                            <strong class="tabular"><?= Bn::num((int) $cnt['due_shops']) ?> দোকান</strong>
                        </div>
                        <div class="dc-mini-stat">
                            <span class="muted small">আগের বাকি আদায়</span>
                            <strong class="tabular is-ok"><?= Bn::num((int) $cnt['prior_due_shops']) ?> দোকান</strong>
                        </div>
                    </div>
                </article>
            </div>
        </div>
    <?php endif; ?>
</div>

<!-- =======================================================================
     PRINT-ONLY A4 DAY CLOSING SHEET (Matches formal Day Closing voucher)
     ======================================================================= -->
<section class="dc-print" aria-label="ডে ক্লোজিং প্রিন্ট শিট">
    <header class="dcp-header">
        <div class="dcp-brand">
            <h1><?= e($p['name']) ?></h1>
            <p><?= e($partnerSubtitle) ?></p>
        </div>
        <div class="dcp-meta">
            <div class="dcp-doc-title">DAY CLOSING</div>
            <div class="dcp-doc-sub">দিনের হিসাব</div>
            <div class="dcp-doc-line">নং: <?= e(Bn::digits($c['code'])) ?></div>
            <div class="dcp-doc-line">তারিখ: <?= e(Bn::fullDate($date)) ?></div>
        </div>
    </header>

    <div class="dcp-kpis">
        <div class="dcp-kpi">
            <span>গুদাম থেকে বের</span>
            <strong class="tabular"><?= $moneyCompact((float) $cash['goods_out']) ?></strong>
        </div>
        <div class="dcp-kpi">
            <span>হাতে আসার কথা</span>
            <strong class="tabular"><?= $moneyCompact((float) $cash['expected']) ?></strong>
        </div>
        <div class="dcp-kpi">
            <span>হাতে এলো</span>
            <strong class="tabular"><?= $moneyCompact((float) $cash['received']) ?></strong>
        </div>
        <div class="dcp-kpi">
            <span><?= e($diffLabel) ?></span>
            <strong class="tabular"><?= $isMatched ? '✓ ৳০' : $moneyCompact(abs($diff)) ?></strong>
        </div>
    </div>

    <!-- 1. Cash Account -->
    <div class="dcp-section">
        <h2>১. টাকার হিসাব</h2>
        <table class="dcp-table">
            <thead>
                <tr>
                    <th style="width: 34px;">ক্র.</th>
                    <th style="width: 32%;">বিবরণ</th>
                    <th>নোট</th>
                    <th class="text-right" style="width: 115px;">টাকা (৳)</th>
                </tr>
            </thead>
            <tbody>
                <?php $sl = 0; foreach ($cashRows as $row): $sl++; ?>
                    <?php
                    $amt = (float) $row['amount'];
                    if ($row['sign'] === 'base') {
                        $txt = $moneyCompact(abs($amt));
                    } elseif (abs($amt) < 0.01) {
                        $txt = '৳০';
                    } else {
                        $txt = ($amt > 0 ? '+' : '−') . $moneyCompact(abs($amt));
                    }
                    ?>
                    <tr>
                        <td class="tabular"><?= Bn::num($sl) ?></td>
                        <td><?= e($row['label']) ?></td>
                        <td class="dcp-note"><?= e($row['note']) ?></td>
                        <td class="text-right tabular"><?= $txt ?></td>
                    </tr>
                <?php endforeach; ?>
                <tr class="dcp-row-total">
                    <td class="tabular"><?= Bn::num(++$sl) ?></td>
                    <td><strong>হাতে আসার কথা</strong></td>
                    <td class="dcp-note">সিস্টেমের হিসাব</td>
                    <td class="text-right tabular"><strong><?= $moneyCompact((float) $cash['expected']) ?></strong></td>
                </tr>
                <tr class="dcp-row-total">
                    <td class="tabular"><?= Bn::num(++$sl) ?></td>
                    <td><strong>আসলে হাতে এলো</strong></td>
                    <td class="dcp-note"><?= e($receivedNote) ?></td>
                    <td class="text-right tabular"><strong><?= $moneyCompact((float) $cash['received']) ?></strong></td>
                </tr>
            </tbody>
        </table>
    </div>

    <!-- 2. DM / Trip Summary -->
    <div class="dcp-section">
        <h2>২. DM / ট্রিপ অনুযায়ী</h2>
        <table class="dcp-table">
            <thead>
                <tr>
                    <th>DM · ট্রিপ</th>
                    <th class="text-right">মাল বের</th>
                    <th class="text-right">ফেরত</th>
                    <th class="text-right">বাকি</th>
                    <th class="text-right">খরচ</th>
                    <th class="text-right">জমার কথা</th>
                    <th class="text-right">জমা দিল</th>
                    <th class="text-right">পার্থক্য</th>
                </tr>
            </thead>
            <tbody>
                <?php if ($trips === []): ?>
                    <tr><td colspan="8" class="dcp-note">এই তারিখে কোনো ট্রিপ নেই।</td></tr>
                <?php else: ?>
                    <?php foreach ($trips as $t): ?>
                        <?php $tDiff = $t['cash_diff']; ?>
                        <tr>
                            <td><?= e($t['dsr']) ?> · ট্রিপ <?= Bn::num((int) $t['seq']) ?></td>
                            <td class="text-right tabular"><?= $moneyCompact((float) $t['load_base']) ?></td>
                            <td class="text-right tabular"><?= $moneyCompact((float) $t['return_base']) ?></td>
                            <td class="text-right tabular"><?= $moneyCompact((float) $t['new_due']) ?></td>
                            <td class="text-right tabular"><?= $moneyCompact((float) $t['expense']) ?></td>
                            <td class="text-right tabular"><?= $moneyCompact((float) $t['expected_cash']) ?></td>
                            <td class="text-right tabular"><strong><?= $t['received_cash'] !== null ? $moneyCompact((float) $t['received_cash']) : '—' ?></strong></td>
                            <td class="text-right tabular">
                                <?php if ($tDiff === null): ?>
                                    বাকি
                                <?php elseif (abs((float) $tDiff) < 0.01): ?>
                                    ✓
                                <?php else: ?>
                                    <?= $signedCompact((float) $tDiff) ?>
                                <?php endif; ?>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                <?php endif; ?>
            </tbody>
        </table>
    </div>

    <!-- 3. SR Over/Commission + 4. Today's Profit & Loss -->
    <div class="dcp-two-col">
        <div class="dcp-section">
            <h2>৩. SR ওভার / কমিশন</h2>
            <table class="dcp-table">
                <thead>
                    <tr>
                        <th>SR</th>
                        <th class="text-right">বিক্রি</th>
                        <th class="text-right">নিট</th>
                    </tr>
                </thead>
                <tbody>
                    <?php if ($srRows === []): ?>
                        <tr><td colspan="3" class="dcp-note">কোনো SR বিক্রি নেই।</td></tr>
                    <?php else: ?>
                        <?php foreach ($srRows as $sr): ?>
                            <tr>
                                <td><?= e($sr['sr_name']) ?></td>
                                <td class="text-right tabular"><?= $moneyCompact((float) $sr['sales_sr']) ?></td>
                                <td class="text-right tabular">
                                    <?= abs((float) $sr['net_oc']) < 0.01 ? '৳০' : $signedCompact((float) $sr['net_oc']) ?>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </tbody>
            </table>
        </div>

        <div class="dcp-section">
            <h2>৪. আজকের লাভ-ক্ষতি</h2>
            <table class="dcp-table">
                <tbody>
                    <tr>
                        <td>ডেলিভারি হওয়া মালের বিক্রি (রেটে)</td>
                        <td class="text-right tabular"><?= $moneyCompact((float) $pnl['delivered_base']) ?></td>
                    </tr>
                    <tr>
                        <td>কেনা দাম বাদে মার্জিন (গড় <?= Bn::digits($pnl['margin_pct']) ?>%)</td>
                        <td class="text-right tabular"><?= $moneyCompact((float) $pnl['gross_margin']) ?></td>
                    </tr>
                    <tr>
                        <td>DM খরচ</td>
                        <td class="text-right tabular"><?= $pnl['expenses'] > 0 ? '−' . $moneyCompact((float) $pnl['expenses']) : '৳০' ?></td>
                    </tr>
                    <tr>
                        <td>ড্যামেজ<?= $pnl['damage_claim'] > 0 ? ' (ক্লেইম বাদে নিট)' : '' ?></td>
                        <td class="text-right tabular"><?= $pnl['damage_net'] > 0 ? '−' . $moneyCompact((float) $pnl['damage_net']) : '৳০' ?></td>
                    </tr>
                    <tr>
                        <td>Happy ফি<?= $pnl['avg_fee_rate'] > 0 ? ' (প্রতি লাখ ' . $moneyCompact((float) $pnl['avg_fee_rate']) . ')' : '' ?></td>
                        <td class="text-right tabular"><?= $pnl['platform_fee'] > 0 ? '−' . $moneyCompact((float) $pnl['platform_fee']) : '৳০' ?></td>
                    </tr>
                    <tr class="dcp-row-total">
                        <td><strong>আজকের নিট লাভ</strong></td>
                        <td class="text-right tabular"><strong><?= $moneyCompact((float) $pnl['net_profit']) ?></strong></td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>

    <!-- Bottom Variance / Match Box -->
    <div class="dcp-variance-box">
        <?php if ($varianceItems !== []): ?>
            <strong>গরমিল:</strong> <?= e(implode(' · ', $varianceItems)) ?>
        <?php else: ?>
            <strong>হিসাব ঠিক আছে:</strong> সব ট্রিপের ক্যাশ ও মাল সঠিকভাবে মিলেছে।
        <?php endif; ?>
    </div>

    <!-- Signatures -->
    <footer class="dcp-signatures">
        <div><span>হিসাবরক্ষক / ম্যানেজার</span></div>
        <div><span>পার্টনার স্বাক্ষর</span></div>
        <div><span>Happy অডিট</span></div>
    </footer>
</section>

<?php $this->endSection(); ?>
