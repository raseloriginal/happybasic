<?php $this->extend('dsr.layouts.main'); ?>

<?php
use App\Support\Bn;
$list = $products ?? [];
$totalDispPcs = 0;
$totalDelivPcs = 0;
$totalAvailPcs = 0;
$totalOc = 0;
foreach ($list as $p) {
    $disp = (int) ($p['dispatched_pcs'] ?? 0);
    $deliv = (int) ($p['delivered_pcs'] ?? 0);
    $totalDispPcs += $disp;
    $totalDelivPcs += $deliv;
    $totalAvailPcs += max(0, $disp - $deliv);
    $totalOc += (float) ($p['delivery_oc'] ?? 0);
}
$productsJson = json_encode($list, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT);
?>

<?php $this->section('content'); ?>
<section class="dsr-page-stack" id="dsrVanStockApp" data-van-stock="<?= e($productsJson) ?>">
    <?php if ($trip === null): ?>
        <article class="card empty-trip-card"><h2 class="section-title">কোনো ডিসপ্যাচ করা ট্রিপ নেই</h2></article>
    <?php endif; ?>
    <!-- Top Summary Strip -->
    <div class="kpi-strip-4">
        <article class="card kpi-mini">
            <span class="kpi-label">মোট লোড</span>
            <strong class="kpi-val tabular" id="vsSumDispatched"><?= Bn::num($totalDispPcs) ?> পিস</strong>
        </article>
        <article class="card kpi-mini">
            <span class="kpi-label">মোট ডেলিভারি</span>
            <strong class="kpi-val tabular is-ok" id="vsSumDelivered"><?= Bn::num($totalDelivPcs) ?> পিস</strong>
        </article>
        <article class="card kpi-mini">
            <span class="kpi-label">ভ্যানে বাকি</span>
            <strong class="kpi-val tabular" id="vsSumAvailable"><?= Bn::num($totalAvailPcs) ?> পিস</strong>
        </article>
        <article class="card kpi-mini">
            <span class="kpi-label">ডেলিভারি O/C</span>
            <strong class="kpi-val tabular <?= $totalOc >= 0 ? 'is-ok' : 'is-warn' ?>" id="vsSumOc">
                <?= Bn::signedMoney((float) round($totalOc), true) ?>
            </strong>
        </article>
    </div>

    <!-- Search Bar -->
    <div class="card filter-bar">
        <label class="search-field" for="vanStockSearch">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
            <input id="vanStockSearch" type="search" placeholder="পণ্য বা কোম্পানি খুঁজুন…" autocomplete="off">
        </label>
        <span class="muted small tabular"><?= Bn::num(count($list)) ?>টি পণ্য<?= $trip ? ' · ' . e(Bn::digits($trip['code'])) : '' ?></span>
    </div>

    <!-- Product List -->
    <article class="card table-card">
        <div class="mobile-stock-list" id="vanStockMobileList">
            <?php foreach ($list as $p): ?>
                <?php
                $qpu = max(1, (int) ($p['qty_per_unit'] ?? 1));
                $unit = (string) ($p['unit_type'] ?? 'Unit');
                $disp = (int) ($p['dispatched_pcs'] ?? 0);
                $deliv = (int) ($p['delivered_pcs'] ?? 0);
                $avail = max(0, $disp - $deliv);
                $oc = (float) ($p['delivery_oc'] ?? 0);
                ?>
                <div class="van-stock-mobile-card" data-search="<?= e(strtolower(($p['name'] ?? '') . ' ' . ($p['company'] ?? ''))) ?>">
                    <div class="vsm-head">
                        <div>
                            <strong><?= e($p['name'] ?? '') ?></strong>
                            <div class="muted small tabular"><?= e($p['company'] ?? '') ?> · ১ <?= e(Bn::unitType($unit)) ?> = <?= Bn::num($qpu) ?> পিস</div>
                        </div>
                        <span class="badge <?= $oc > 0 ? 'badge-success' : ($oc < 0 ? 'badge-warning' : 'badge-neutral') ?> tabular">
                            O/C <?= Bn::signedMoney((float) round($oc), true) ?>
                        </span>
                    </div>
                    <div class="vsm-grid">
                        <div class="vsm-cell">
                            <span class="muted small">লোডকৃত</span>
                            <strong class="tabular"><?= Bn::num($disp) ?> পিস</strong>
                            <span class="vsm-sub tabular"><?= e(Bn::unitPcs($disp, $qpu, $unit)) ?></span>
                        </div>
                        <div class="vsm-cell">
                            <span class="muted small">ডেলিভারি</span>
                            <strong class="tabular is-ok"><?= Bn::num($deliv) ?> পিস</strong>
                            <span class="vsm-sub tabular"><?= e(Bn::unitPcs($deliv, $qpu, $unit)) ?></span>
                        </div>
                        <div class="vsm-cell">
                            <span class="muted small">অবশিষ্ট</span>
                            <strong class="tabular"><?= Bn::num($avail) ?> পিস</strong>
                            <span class="vsm-sub tabular"><?= e(Bn::unitPcs($avail, $qpu, $unit)) ?></span>
                        </div>
                    </div>
                </div>
            <?php endforeach; ?>
        </div>
    </article>
</section>
<?php $this->endSection(); ?>
