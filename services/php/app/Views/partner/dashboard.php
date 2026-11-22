<?php $this->extend('partner.layouts.main'); ?>

<?php
use App\Support\Bn;
$s = $stats;
$range = $from === $to ? Bn::date($from) : Bn::date($from) . ' → ' . Bn::date($to);
?>

<?php $this->section('topbar_actions'); ?>
<a href="<?= e(url('/partner/trips')) ?>" class="btn btn-primary btn-sm">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M12 5v14M5 12h14"/></svg>
    <span>ট্রিপ পরিচালনা</span>
</a>
<?php $this->endSection(); ?>

<?php $this->section('content'); ?>
<form class="toolbar-card" method="GET" action="<?= e(url('/partner/dashboard')) ?>" data-spa-get>
    <div class="toolbar-filters">
        <label class="date-field"><span class="muted small">থেকে</span><input type="date" name="from" value="<?= e($from) ?>" class="select-input"></label>
        <label class="date-field"><span class="muted small">পর্যন্ত</span><input type="date" name="to" value="<?= e($to) ?>" class="select-input"></label>
        <button type="submit" class="btn btn-secondary btn-sm">দেখুন</button>
        <a href="<?= e(url('/partner/dashboard')) ?>" class="text-link small">আজ</a>
    </div>
    <span class="muted small"><?= e($range) ?></span>
</form>

<section class="summary-grid">
    <article class="card kpi-card">
        <span class="kpi-label">মোট অর্ডার মূল্য</span>
        <div class="kpi-value tabular"><?= Bn::money((float) $s['order_value']) ?></div>
        <span class="muted small tabular"><?= Bn::num((int) $s['orders']) ?>টি অর্ডার · <?= Bn::num((int) $s['retailers']) ?>টি দোকান · O/C <?= Bn::signedMoney((float) $s['oc']) ?></span>
    </article>
    <article class="card kpi-card">
        <span class="kpi-label">মোট ডেলিভারি</span>
        <div class="kpi-value is-ok tabular"><?= Bn::money((float) $s['delivered']) ?></div>
        <span class="muted small tabular">অর্ডারের <?= Bn::digits($s['delivered_pct']) ?>% ডেলিভারি হয়েছে</span>
    </article>
    <article class="card kpi-card">
        <span class="kpi-label">মোট বাকি (Due)</span>
        <div class="kpi-value is-warn tabular"><?= Bn::money((float) $s['due']) ?></div>
        <span class="muted small">দোকান থেকে আদায় বাকি</span>
    </article>
    <article class="card kpi-card">
        <span class="kpi-label">ট্রিপে না দেওয়া অর্ডার</span>
        <div class="kpi-value tabular"><?= Bn::money((float) $s['unassigned_value']) ?></div>
        <span class="muted small tabular"><?= Bn::num((int) $s['unassigned']) ?>টি অর্ডার ট্রিপের অপেক্ষায়</span>
    </article>
    <article class="card kpi-card">
        <span class="kpi-label">লট ক্রয়</span>
        <div class="kpi-value tabular"><?= Bn::money((float) $s['purchases']) ?></div>
        <span class="muted small">এই সময়ের মধ্যে প্রাপ্ত লট</span>
    </article>
    <article class="card kpi-card">
        <span class="kpi-label">বর্তমান স্টক মূল্য</span>
        <div class="kpi-value tabular"><?= Bn::money((float) $s['stock_value']) ?></div>
        <span class="muted small">কোম্পানি ক্রয়মূল্যে অবশিষ্ট স্টক</span>
    </article>
</section>

<section class="section-block">
    <div class="section-head">
        <div>
            <h2 class="section-title">ট্রিপসমূহ</h2>
            <p class="section-subtitle">DSR অনুযায়ী দোকান ডেলিভারির অগ্রগতি (নির্ধারিত তারিখের মধ্যে)</p>
        </div>
        <a href="<?= e(url('/partner/trips')) ?>" class="text-link">সব ট্রিপ দেখুন →</a>
    </div>

    <?php if ($s['trips'] === []): ?>
        <div class="empty-state"><p>এই সময়ে কোনো ট্রিপ নেই।</p></div>
    <?php endif; ?>

    <div class="area-trip-grid">
        <?php foreach ($s['trips'] as $trip): ?>
            <?php
                $total = max(1, (int) $trip['retailers']);
                $done = (int) $trip['done_retailers'];
                $pct = (int) round($done / $total * 100);
                $badge = match ($trip['status_key']) {
                    'settled' => 'badge-success',
                    'dispatched', 'in_review' => 'badge-info',
                    default => 'badge-warning',
                };
            ?>
            <article class="card area-card">
                <div class="area-card-head">
                    <div>
                        <h3 class="area-name"><?= e($trip['dsr']) ?></h3>
                        <span class="muted small tabular"><?= e(Bn::digits($trip['code'])) ?> · <?= e(Bn::date($trip['date'])) ?> · <?= Bn::money((float) $trip['order_value']) ?></span>
                    </div>
                    <span class="badge <?= $badge ?>"><?= e(Bn::status($trip['status_key'])) ?></span>
                </div>
                <div class="area-stats">
                    <div class="area-stat">
                        <span class="muted small">মোট দোকান</span>
                        <strong class="tabular"><?= Bn::num((int) $trip['retailers']) ?></strong>
                    </div>
                    <div class="area-stat">
                        <span class="muted small">সম্পন্ন</span>
                        <strong class="tabular"><?= Bn::num($done) ?></strong>
                    </div>
                    <div class="area-stat text-right">
                        <span class="muted small">অগ্রগতি</span>
                        <strong class="tabular"><?= Bn::digits($pct) ?>%</strong>
                    </div>
                </div>
                <div class="progress-track" role="progressbar" aria-valuenow="<?= $pct ?>" aria-valuemin="0" aria-valuemax="100">
                    <div class="progress-fill <?= $pct === 100 ? 'is-complete' : '' ?>" style="width: <?= $pct ?>%"></div>
                </div>
            </article>
        <?php endforeach; ?>
    </div>
</section>
<?php $this->endSection(); ?>
