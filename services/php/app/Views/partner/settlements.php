<?php $this->extend('partner.layouts.main'); ?>

<?php
use App\Support\Bn;
$fmtNum = static fn(float $v): string => Bn::smartNum($v);
$money = static fn(float $v): string => Bn::money($v, true);
$signed = static fn(float $v): string => Bn::signedMoney($v, true);
?>

<?php $this->section('content'); ?>
<form class="toolbar-card" method="GET" action="<?= e(url('/partner/settlements')) ?>" data-spa-get>
    <div class="toolbar-filters">
        <label class="date-field"><span class="muted small">থেকে</span><input type="date" name="from" value="<?= e($from) ?>" class="select-input"></label>
        <label class="date-field"><span class="muted small">পর্যন্ত</span><input type="date" name="to" value="<?= e($to) ?>" class="select-input"></label>
        <button type="submit" class="btn btn-secondary btn-sm">দেখুন</button>
    </div>
    <span class="muted small">চলমান ও কনফার্ম বাকি ট্রিপগুলো সবসময় দেখানো হয়</span>
</form>

<?php if ($settlements === []): ?>
    <div class="card empty-state"><p>এই সময়ে কোনো ডিসপ্যাচড, কনফার্ম বাকি বা সেটেল্ড ট্রিপ নেই।</p></div>
<?php else: ?>
<div class="st-trip-strip" role="tablist" aria-label="ট্রিপ সেটেলমেন্ট">
    <?php foreach ($settlements as $idx => $st): ?>
        <?php
        $t = $st['trip'];
        $c = $st['counts'];
        $cash = $st['cash'];
        $statusClass = 'is-warn';
        $statusLine = '';
        if ($t['status_key'] === 'settled') {
            $statusClass = 'is-ok';
            $pDiff = $cash['partner_diff'] ?? $cash['diff'];
            if ($pDiff !== null && abs((float) $pDiff) >= 0.01) {
                $statusLine = 'সেটেল্ড · ' . $money(abs((float) $pDiff)) . ((float) $pDiff < 0 ? ' কম' : ' বেশি');
            } else {
                $statusLine = 'সেটেল্ড';
            }
        } elseif ($t['status_key'] === 'in_review') {
            $d = (float) ($cash['diff'] ?? 0);
            if ($d < -0.004) {
                $statusClass = 'is-danger';
                $statusLine = 'কনফার্ম বাকি · ' . $money(abs($d)) . ' কম';
            } elseif ($d > 0.004) {
                $statusClass = 'is-warn';
                $statusLine = 'কনফার্ম বাকি · ' . $money(abs($d)) . ' বেশি';
            } else {
                $statusClass = 'is-warn';
                $statusLine = 'কনফার্ম বাকি · মিলেছে';
            }
        } else {
            $statusClass = 'is-warn';
            $statusLine = 'রাস্তায় · ' . Bn::digits((int) $c['stops_done']) . '/' . Bn::digits((int) $c['stops_total']);
        }
        ?>
        <button
            type="button"
            class="st-trip-card <?= $idx === 0 ? 'is-active' : '' ?>"
            role="tab"
            data-settlement-tab="<?= (int) $t['id'] ?>"
            aria-selected="<?= $idx === 0 ? 'true' : 'false' ?>"
        >
            <span class="st-trip-title"><?= e(Bn::digits($t['code'])) ?> · <?= e($t['dsr']) ?></span>
            <span class="st-trip-sub <?= $statusClass ?> tabular"><?= e($statusLine) ?></span>
        </button>
    <?php endforeach; ?>
</div>

<?php foreach ($settlements as $idx => $st): ?>
    <?php
    $t = $st['trip'];
    $m = $st['summary'];
    $c = $st['counts'];
    $cash = $st['cash'];
    $dmg = $st['damage_review'];
    $returns = $st['return_items'];
    $isReview = $t['status_key'] === 'in_review';
    $isSettled = $t['status_key'] === 'settled';
    $isDispatched = $t['status_key'] === 'dispatched';

    $expectedDeposit = (float) $m['net_pay'];
    $dsrSubmitted = $cash['counted'];
    $dsrDiff = $cash['diff'];
    $defaultPartnerCash = $isSettled && $cash['partner_received'] !== null
        ? (float) $cash['partner_received']
        : ($dsrSubmitted !== null ? (float) $dsrSubmitted : $expectedDeposit);
    $cashHasDiff = $dsrSubmitted !== null && abs((float) $dsrSubmitted - $expectedDeposit) >= 0.01;

    $defaultDamage = $isSettled && $dmg['partner_amount'] !== null
        ? (float) $dmg['partner_amount']
        : (float) $dmg['dsr_amount'];
    $totalReturnPcs = array_sum(array_map(static fn(array $r): int => (int) $r['counted_return_pcs'], $returns));

    $expCats = $m['expense_categories'] ?? [];
    $expCatsBn = array_map(static function (string $cat): string {
        return match ($cat) {
            'Fuel' => 'তেল',
            'Helper' => 'হেল্পার',
            'Food' => 'খাবার',
            'Toll & Parking' => 'টোল ও পার্কিং',
            'Van Repair' => 'ভ্যান মেরামত',
            'Mobile / Communication' => 'মোবাইল',
            'Other' => 'অন্যান্য',
            default => $cat,
        };
    }, $expCats);
    $expLabel = $expCatsBn !== [] ? 'খরচ (' . implode(', ', $expCatsBn) . ')' : 'খরচ';

    $cashMeta = 'DM ' . $t['dsr'];
    if ($t['submitted_at']) {
        $cashMeta .= ' · ' . Bn::time((string) $t['submitted_at']);
    } elseif ($isDispatched) {
        $cashMeta .= ' · রাস্তায়';
    }

    $dueJson = json_encode([
        'trip' => Bn::digits($t['code']) . ' · ' . $t['dsr'],
        'total' => (float) $m['retailer_due'],
        'shops' => (int) $c['due_shops'],
        'rows' => $st['due_details'],
    ], JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT);
    ?>
    <section
        class="st-panel"
        data-settlement-panel="<?= (int) $t['id'] ?>"
        data-trip-id="<?= (int) $t['id'] ?>"
        data-trip-code="<?= e(Bn::digits($t['code'])) ?>"
        data-expected-cash="<?= e((string) $expectedDeposit) ?>"
        data-dsr-cash="<?= e($dsrSubmitted !== null ? (string) $dsrSubmitted : '') ?>"
        data-dsr-damage="<?= e((string) $dmg['dsr_amount']) ?>"
        <?= $idx > 0 ? 'hidden' : '' ?>
    >
        <?php if ($t['settlement_status'] === 'returned' && $t['review_note']): ?>
            <div class="notice">DM-কে ফেরত পাঠানো হয়েছে: <?= e($t['review_note']) ?></div>
        <?php endif; ?>

        <div class="st-grid">
            <!-- Left Card: Cash -->
            <article class="card st-cash-card">
                <div class="st-card-head">
                    <h2 class="section-title">ক্যাশ</h2>
                    <span class="muted small tabular"><?= e($cashMeta) ?></span>
                </div>

                <div class="st-ledger">
                    <div class="st-ledger-row">
                        <div class="st-ledger-label">
                            <span>সিস্টেমে ক্যাশ বিক্রি</span>
                            <?php if ($m['ready_sale'] > 0 || $m['prior_due_collected'] > 0): ?>
                                <small class="muted tabular">
                                    অর্ডার <?= $money(max(0.0, (float) $m['paid'] - (float) $m['ready_sale'])) ?>
                                    <?php if ($m['ready_sale'] > 0): ?> · রেডি সেল <?= $money((float) $m['ready_sale']) ?><?php endif; ?>
                                    <?php if ($m['prior_due_collected'] > 0): ?> · আগের বাকি আদায় <?= $money((float) $m['prior_due_collected']) ?><?php endif; ?>
                                </small>
                            <?php endif; ?>
                        </div>
                        <span class="st-ledger-val tabular"><?= $money((float) $m['system_cash']) ?></span>
                    </div>

                    <div class="st-ledger-row">
                        <div class="st-ledger-label">
                            <span><?= e($expLabel) ?></span>
                        </div>
                        <span class="st-ledger-val tabular <?= $m['daily_expenses'] > 0 ? 'is-danger' : 'muted' ?>">
                            <?= $m['daily_expenses'] > 0 ? '− ' . $money((float) $m['daily_expenses']) : $money(0) ?>
                        </span>
                    </div>

                    <div class="st-divider"></div>

                    <div class="st-ledger-row st-row-strong">
                        <span>জমা দেওয়ার কথা</span>
                        <strong class="tabular"><?= $money($expectedDeposit) ?></strong>
                    </div>

                    <div class="st-ledger-row st-row-strong">
                        <span>DM জমা দিয়েছে</span>
                        <?php if ($dsrSubmitted !== null): ?>
                            <strong class="tabular"><?= $money((float) $dsrSubmitted) ?></strong>
                        <?php else: ?>
                            <span class="muted">এখনো জমা দেয়নি</span>
                        <?php endif; ?>
                    </div>
                </div>

                <?php if ($dsrSubmitted !== null): ?>
                    <?php
                    $vClass = $dsrDiff < -0.004 ? 'is-short' : ($dsrDiff > 0.004 ? 'is-excess' : 'is-matched');
                    $vTitle = $dsrDiff < -0.004
                        ? $money(abs((float) $dsrDiff)) . ' কম'
                        : ($dsrDiff > 0.004 ? $money(abs((float) $dsrDiff)) . ' বেশি' : 'টাকা মিলেছে');
                    ?>
                    <div class="st-callout <?= $vClass ?>">
                        <strong class="tabular"><?= e($vTitle) ?></strong>
                        <?php if ($cash['dsr_note']): ?>
                            <p class="st-callout-note">DM-এর নোট: &ldquo;<?= e($cash['dsr_note']) ?>&rdquo;</p>
                        <?php endif; ?>
                    </div>
                <?php endif; ?>

                <?php if ($isReview): ?>
                    <div class="st-verify-block">
                        <div class="st-verify-head">
                            <span class="st-verify-label">আপনি গুনে কত পেলেন?</span>
                            <button type="button" class="text-link st-custom-toggle" data-cash-custom-toggle>অন্য পরিমাণ</button>
                        </div>

                        <div class="st-cash-seg" role="radiogroup" aria-label="প্রাপ্ত ক্যাশ যাচাই">
                            <?php if ($cashHasDiff): ?>
                                <button
                                    type="button"
                                    class="st-seg-opt is-active tabular"
                                    data-cash-choice="dsr"
                                    data-cash-value="<?= e((string) $dsrSubmitted) ?>"
                                >DM-এর মতো <?= $money((float) $dsrSubmitted) ?></button>
                                <button
                                    type="button"
                                    class="st-seg-opt tabular"
                                    data-cash-choice="expected"
                                    data-cash-value="<?= e((string) $expectedDeposit) ?>"
                                >পুরো <?= $money($expectedDeposit) ?> পেয়েছি</button>
                            <?php else: ?>
                                <button
                                    type="button"
                                    class="st-seg-opt is-active tabular"
                                    data-cash-choice="expected"
                                    data-cash-value="<?= e((string) $expectedDeposit) ?>"
                                >পুরো <?= $money($expectedDeposit) ?> পেয়েছি</button>
                                <button
                                    type="button"
                                    class="st-seg-opt"
                                    data-cash-choice="custom"
                                >ভিন্ন পরিমাণ</button>
                            <?php endif; ?>
                        </div>

                        <div class="st-custom-cash" data-cash-custom-wrap hidden>
                            <label class="muted small" for="stCashInput<?= (int) $t['id'] ?>">সঠিক প্রাপ্ত টাকা (৳)</label>
                            <div class="st-custom-cash-row">
                                <input
                                    id="stCashInput<?= (int) $t['id'] ?>"
                                    type="number"
                                    min="0"
                                    step="0.01"
                                    class="select-input tabular"
                                    data-cash-input
                                    value="<?= e((string) $defaultPartnerCash) ?>"
                                >
                                <span class="badge badge-neutral tabular" data-cash-live-diff>
                                    <?= $dsrDiff < -0.004 ? $money(abs((float) $dsrDiff)) . ' কম' : ($dsrDiff > 0.004 ? $money(abs((float) $dsrDiff)) . ' বেশি' : 'মিলেছে') ?>
                                </span>
                            </div>
                        </div>
                    </div>
                <?php elseif ($isSettled): ?>
                    <?php
                    $finalCash = $cash['partner_received'] ?? $dsrSubmitted ?? $expectedDeposit;
                    $finalDiff = round((float) $finalCash - $expectedDeposit, 2);
                    ?>
                    <div class="st-settled-cash">
                        <span class="muted small">কনফার্মকৃত ক্যাশ</span>
                        <div class="st-settled-cash-val">
                            <strong class="tabular"><?= $money((float) $finalCash) ?></strong>
                            <span class="badge <?= $finalDiff < -0.004 ? 'badge-danger' : ($finalDiff > 0.004 ? 'badge-warning' : 'badge-success') ?> tabular">
                                <?= $finalDiff < -0.004 ? $money(abs($finalDiff)) . ' কম' : ($finalDiff > 0.004 ? $money(abs($finalDiff)) . ' বেশি' : 'মিলেছে') ?>
                            </span>
                        </div>
                    </div>
                <?php endif; ?>

                <?php if ($m['retailer_due'] > 0): ?>
                    <button type="button" class="st-due-row is-clickable" data-open-dues="<?= e($dueJson) ?>">
                        <span>আজ বাকি দেওয়া (হাতে নেই)</span>
                        <strong class="tabular"><?= $money((float) $m['retailer_due']) ?> · <?= Bn::num((int) $c['due_shops']) ?> দোকান</strong>
                    </button>
                <?php else: ?>
                    <div class="st-due-row">
                        <span>আজ বাকি দেওয়া (হাতে নেই)</span>
                        <strong class="tabular">৳ ০ · ০ দোকান</strong>
                    </div>
                <?php endif; ?>
            </article>

            <!-- Right Card: Returned Goods + Damage Note -->
            <article class="card st-return-card">
                <div class="st-card-head">
                    <h2 class="section-title">ফেরত মাল</h2>
                    <span class="muted small"><?= $isSettled ? 'যাচাইকৃত ও স্টকে ফেরত' : 'DM-এর হিসাব' ?></span>
                </div>

                <?php if ($returns === []): ?>
                    <div class="st-return-empty muted small">
                        ভ্যানের সব পণ্য ডেলিভারি হয়েছে — কোনো ফেরত মাল নেই।
                    </div>
                <?php else: ?>
                    <div class="st-return-table">
                        <div class="st-return-head">
                            <span>পণ্য</span>
                            <span class="text-right">DM বলেছে</span>
                            <span class="text-right">আপনি গুনলেন</span>
                        </div>

                        <?php foreach ($returns as $r): ?>
                            <?php
                            $expPcs = (int) $r['expected_return_pcs'];
                            $cntPcs = (int) $r['counted_return_pcs'];
                            $retDiff = $cntPcs - $expPcs;
                            ?>
                            <div
                                class="st-return-row"
                                data-return-row
                                data-product-id="<?= (int) $r['product_id'] ?>"
                                data-expected-pcs="<?= $expPcs ?>"
                                data-max-pcs="<?= (int) $r['dispatched_pcs'] ?>"
                            >
                                <div class="st-prod-cell">
                                    <div class="st-prod-thumb" style="background: <?= e($r['tint']) ?>">
                                        <?php if ($r['image']): ?>
                                            <img src="<?= e($r['image']) ?>" alt="">
                                        <?php else: ?>
                                            <span class="st-prod-code"><?= e($r['code']) ?></span>
                                        <?php endif; ?>
                                        <span class="st-prod-unit"><?= e(Bn::unitType((string) $r['unit_type'])) ?></span>
                                    </div>
                                    <div class="st-prod-meta">
                                        <strong class="st-prod-name"><?= e($r['name']) ?></strong>
                                        <span class="st-prod-reason"><?= e(Bn::digits($r['reason'])) ?></span>
                                    </div>
                                </div>

                                <div class="st-reported-cell tabular">
                                    <strong><?= Bn::num($expPcs) ?> পিস</strong>
                                    <?php if ($r['qty_per_unit'] > 1): ?>
                                        <small class="muted"><?= e(Bn::unitPcs($expPcs, (int) $r['qty_per_unit'], (string) $r['unit_type'])) ?></small>
                                    <?php endif; ?>
                                </div>

                                <div class="st-count-cell">
                                    <div class="st-stepper <?= !$isReview ? 'is-disabled' : '' ?>">
                                        <button type="button" class="st-step-btn" data-ret-step="-1" <?= !$isReview ? 'disabled' : '' ?> aria-label="সংখ্যা কমান">−</button>
                                        <input
                                            type="number"
                                            class="st-step-input tabular"
                                            min="0"
                                            max="<?= (int) $r['dispatched_pcs'] ?>"
                                            step="1"
                                            value="<?= $cntPcs ?>"
                                            data-ret-input
                                            <?= !$isReview ? 'readonly tabindex="-1"' : '' ?>
                                            aria-label="<?= e($r['name']) ?> ফেরত পিস"
                                        >
                                        <button type="button" class="st-step-btn" data-ret-step="1" <?= !$isReview ? 'disabled' : '' ?> aria-label="সংখ্যা বাড়ান">+</button>
                                    </div>
                                    <span
                                        class="st-ret-diff tabular <?= $retDiff < 0 ? 'is-danger' : ($retDiff > 0 ? 'is-warn' : '') ?>"
                                        data-ret-diff
                                        <?= $retDiff === 0 ? 'hidden' : '' ?>
                                    >
                                        DM থেকে <?= $retDiff > 0 ? '+' . Bn::num($retDiff) : Bn::num($retDiff) ?>
                                    </span>
                                </div>
                            </div>
                        <?php endforeach; ?>
                    </div>
                <?php endif; ?>

                <p class="st-return-caption muted small tabular">
                    <?php if ($isSettled): ?>
                        গুনে <?= Bn::num($totalReturnPcs) ?> পিস ওয়্যারহাউজ স্টকে ফেরত নেওয়া হয়েছে
                    <?php else: ?>
                        ফেরত মাল গুনে স্টকে যাবে
                    <?php endif; ?>
                </p>

                <!-- Damage Note Sub-Card -->
                <div class="st-damage-box">
                    <div class="st-damage-head">
                        <strong>ড্যামেজ · নোট</strong>
                        <strong class="tabular <?= $defaultDamage > 0 ? 'is-danger' : 'muted' ?>" data-damage-display><?= $money($defaultDamage) ?></strong>
                    </div>

                    <div class="st-damage-control">
                        <span class="muted">মোট মূল্য</span>
                        <div class="st-stepper st-stepper-money <?= !$isReview ? 'is-disabled' : '' ?>">
                            <button type="button" class="st-step-btn" data-dmg-step="-10" <?= !$isReview ? 'disabled' : '' ?> aria-label="ড্যামেজ মূল্য কমান">−</button>
                            <span class="st-money-prefix">৳</span>
                            <input
                                type="number"
                                class="st-step-input tabular"
                                min="0"
                                step="1"
                                value="<?= e((string) $defaultDamage) ?>"
                                data-damage-input
                                <?= !$isReview ? 'readonly tabindex="-1"' : '' ?>
                                aria-label="যাচাইকৃত মোট ড্যামেজ মূল্য"
                            >
                            <button type="button" class="st-step-btn" data-dmg-step="10" <?= !$isReview ? 'disabled' : '' ?> aria-label="ড্যামেজ মূল্য বাড়ান">+</button>
                        </div>
                    </div>

                    <?php if ($dmg['items'] !== []): ?>
                        <div class="st-damage-notes">
                            <span class="muted small">DM-এর হিসাব:</span>
                            <ul class="st-damage-list">
                                <?php foreach ($dmg['items'] as $di): ?>
                                    <li>
                                        <span><?= e($di['retailer']) ?> · <?= e($di['product']) ?> (<?= Bn::num((int) $di['qty_pcs']) ?> পিস)</span>
                                        <span class="tabular muted"><?= $money((float) $di['amount']) ?></span>
                                    </li>
                                <?php endforeach; ?>
                            </ul>
                        </div>
                    <?php else: ?>
                        <p class="st-damage-empty muted small">DM কোনো ড্যামেজ পণ্যের রিপোর্ট দেয়নি।</p>
                    <?php endif; ?>

                    <?php if ($isReview): ?>
                        <input
                            type="text"
                            class="select-input st-damage-note-input"
                            maxlength="255"
                            placeholder="ড্যামেজ নোট (ঐচ্ছিক)…"
                            data-damage-note
                            value="<?= e((string) ($dmg['partner_note'] ?? '')) ?>"
                        >
                    <?php elseif ($dmg['partner_note']): ?>
                        <p class="st-damage-partner-note small">পার্টনারের নোট: &ldquo;<?= e($dmg['partner_note']) ?>&rdquo;</p>
                    <?php endif; ?>

                    <p class="st-damage-foot muted small">
                        এখন শুধু মোট টাকা নোট হিসেবে থাকবে · কনফার্ম করলে কোম্পানি খাতায় সমন্বয় হবে
                    </p>
                </div>
            </article>
        </div>

        <!-- Action / Status Footer Bar -->
        <?php if ($isReview): ?>
            <div class="card st-action-bar">
                <div class="st-action-summary muted small tabular" data-action-summary>
                    কনফার্ম হচ্ছে <strong><?= $money($defaultPartnerCash) ?></strong> ক্যাশ · <strong><?= Bn::num($totalReturnPcs) ?> পিস</strong> স্টকে ফেরত · <strong><?= $money($defaultDamage) ?></strong> ড্যামেজ
                </div>
                <div class="st-action-controls">
                    <input type="text" class="select-input" placeholder="DM-কে ফেরত পাঠানোর কারণ লিখুন…" data-sendback-note maxlength="255">
                    <button type="button" class="btn btn-secondary btn-sm" data-sendback="<?= (int) $t['id'] ?>">ফেরত পাঠান</button>
                    <button type="button" class="btn btn-primary btn-sm" data-approve="<?= (int) $t['id'] ?>" data-code="<?= e(Bn::digits($t['code'])) ?>">কনফার্ম ও সেটেল করুন</button>
                </div>
            </div>
        <?php elseif ($isDispatched): ?>
            <div class="card st-status-bar">
                <span class="badge badge-warning">রাস্তায়</span>
                <span class="muted small tabular">
                    <?= Bn::num((int) $c['stops_total']) ?>টির মধ্যে <?= Bn::num((int) $c['stops_done']) ?>টি দোকান সম্পন্ন (<?= Bn::num((int) $c['pending']) ?>টি অর্ডার বাকি)। DM হিসাব জমা দিলে এখানে কনফার্ম করতে পারবেন।
                </span>
            </div>
        <?php elseif ($isSettled): ?>
            <div class="card st-status-bar">
                <span class="badge badge-success">সেটেল্ড</span>
                <span class="muted small tabular">
                    অনুমোদিত <?= $t['approved_at'] ? e(Bn::dateTime((string) $t['approved_at'])) : e(Bn::date($t['date'])) ?>
                    · ক্যাশ প্রাপ্তি <?= $money((float) ($cash['partner_received'] ?? $dsrSubmitted ?? $expectedDeposit)) ?>
                    · স্টকে ফেরত <?= Bn::num($totalReturnPcs) ?> পিস
                    · ড্যামেজ <?= $money($defaultDamage) ?>
                </span>
            </div>
        <?php endif; ?>

        <!-- Compact Collapsible SR O/C Breakdown -->
        <?php if ($st['sr_oc_rows'] !== []): ?>
            <details class="card st-oc-details">
                <summary class="st-oc-summary">
                    <span>SR ওভার/কমিশন (O/C) হিসাব (<?= Bn::num(count($st['sr_oc_rows'])) ?> জন SR)</span>
                    <span class="muted small tabular">মোট ডেলিভারি O/C: <strong class="<?= $m['delivery_oc'] >= 0 ? 'is-ok' : 'is-warn' ?>"><?= $signed((float) $m['delivery_oc']) ?></strong></span>
                </summary>
                <div class="table-wrap st-oc-table">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>SR</th>
                                <th class="text-right">অর্ডার O/C</th>
                                <th class="text-right">ডেলিভারি O/C</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($st['sr_oc_rows'] as $sr): ?>
                                <tr>
                                    <td><div class="cell-primary"><?= e($sr['sr_name']) ?></div><div class="cell-sub"><?= e($sr['area']) ?> · <?= Bn::num((int) $sr['orders']) ?>টি অর্ডার</div></td>
                                    <td class="text-right tabular"><?= $signed((float) $sr['order_oc']) ?></td>
                                    <td class="text-right tabular"><strong><?= $signed((float) $sr['delivery_oc']) ?></strong></td>
                                </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            </details>
        <?php endif; ?>
    </section>
<?php endforeach; ?>

<!-- Retailer Dues Breakdown Modal -->
<div class="modal-overlay" id="stDuesModal" aria-hidden="true">
    <div class="modal-panel modal-lg" role="dialog" aria-modal="true" aria-labelledby="stDuesTitle">
        <div class="modal-head">
            <div>
                <h3 class="section-title" id="stDuesTitle">আজ বাকি দেওয়া</h3>
                <p class="section-subtitle" id="stDuesSubtitle">সেটেলমেন্ট কনফার্ম হলে দোকানের বাকি খাতায় যোগ হবে</p>
            </div>
            <button type="button" class="icon-btn" data-modal-close aria-label="বন্ধ করুন">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>
        <div class="modal-body" style="padding: 0;">
            <div class="table-wrap">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>দোকান</th>
                            <th>অর্ডার</th>
                            <th class="text-right">বিল</th>
                            <th class="text-right">জমা</th>
                            <th class="text-right">বাকি</th>
                        </tr>
                    </thead>
                    <tbody id="stDuesBody"></tbody>
                </table>
            </div>
        </div>
        <div class="modal-foot">
            <button type="button" class="btn btn-secondary btn-sm" data-modal-close>বন্ধ করুন</button>
        </div>
    </div>
</div>
<?php endif; ?>
<?php $this->endSection(); ?>
