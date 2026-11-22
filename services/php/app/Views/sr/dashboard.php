<?php $this->extend('sr.layouts.main'); ?>

<?php
use App\Support\Bn;
$todayValue = (float) $today['value'];
$target = (float) $profile['daily_target'];
$pct = $target > 0 ? min(100, (int) round($todayValue / $target * 100)) : 0;
$remaining = max(0, $target - $todayValue);
$monthTarget = (float) $profile['monthly_target'];
$monthPct = $monthTarget > 0 ? min(100, (int) round($month['value'] / $monthTarget * 100)) : 0;
$signed = static fn(float $v): string => Bn::signedMoney($v);
$areaLabel = trim((string) ($profile['area'] ?? '')) ?: 'আজকের রুট';
?>

<?php $this->section('content'); ?>
<div class="sr-dash-page">
    <!-- Cobalt Blue Header Banner -->
    <header class="sr-dash-hero">
        <div class="sr-dash-hero-top">
            <span class="sr-dash-sub">
                <?= e($profile['name']) ?> · SR · <?= e($profile['company']) ?>
            </span>
            <form method="POST" action="<?= e(url('/sr/logout')) ?>" class="logout-form">
                <?= csrf_field() ?>
                <button type="submit" class="hero-logout-btn" title="সাইন আউট" aria-label="সাইন আউট">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/></svg>
                </button>
            </form>
        </div>
        <div class="sr-dash-hero-main">
            <h1 class="sr-dash-title">আজ · <?= e($areaLabel) ?></h1>
            <span class="sr-dash-date tabular"><?= e(Bn::date(date('Y-m-d'))) ?></span>
        </div>
    </header>

    <div class="sr-dash-body">
        <!-- Main Sales KPI Card overlapping hero -->
        <article class="card sr-sales-card">
            <div class="sr-sales-top">
                <span class="sr-sales-label">আজকের বিক্রি</span>
                <?php if ($dayCompleted): ?>
                    <span class="badge badge-success">দিন সম্পন্ন ✓</span>
                <?php elseif ($today['orders'] > 0): ?>
                    <span class="badge badge-info">অর্ডার চলমান</span>
                <?php endif; ?>
            </div>
            <div class="sr-sales-amount tabular"><?= Bn::money($todayValue) ?></div>

            <div class="sr-sales-progress">
                <div class="progress-track" role="progressbar" aria-valuenow="<?= $pct ?>" aria-valuemin="0" aria-valuemax="100" aria-label="দৈনিক লক্ষ্য অগ্রগতি">
                    <div class="progress-fill is-emerald" style="width: <?= $pct ?>%"></div>
                </div>
                <div class="sr-sales-meta">
                    <?php if ($target > 0): ?>
                        <span class="tabular">লক্ষ্য <?= Bn::money($target) ?> · <strong><?= Bn::digits($pct) ?>%</strong> হয়েছে</span>
                        <?php if ($remaining > 0): ?>
                            <span class="muted tabular">আরও <?= Bn::money($remaining) ?> বাকি</span>
                        <?php else: ?>
                            <span class="is-ok"><strong>লক্ষ্য অর্জিত</strong></span>
                        <?php endif; ?>
                    <?php else: ?>
                        <span class="muted">দৈনিক লক্ষ্য নির্ধারিত নেই</span>
                    <?php endif; ?>
                </div>
            </div>
        </article>

        <!-- Primary Cobalt CTA -->
        <a href="<?= e(url('/sr/order')) ?>" class="btn btn-cobalt btn-new-order">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4"><path d="M12 5v14M5 12h14"/></svg>
            <span>নতুন অর্ডার</span>
        </a>

        <!-- Day status banner when relevant -->
        <?php if ($dayCompleted || $today['orders'] > 0): ?>
            <div class="day-status <?= $dayCompleted ? 'is-done' : '' ?>" style="margin-bottom:0">
                <?php if ($dayCompleted): ?>
                    আজকের অর্ডার সম্পন্ন হয়েছে<?= $today['assigned'] > 0 ? ' এবং ডেলিভারি ট্রিপে দেওয়া হয়েছে।' : ' — ডেলিভারি ট্রিপের অপেক্ষায়।' ?>
                <?php else: ?>
                    আজকের অর্ডার খোলা আছে। কাজ শেষে অর্ডার পেজের "আজ" থেকে <strong>দিন সম্পন্ন করুন</strong> চাপুন।
                <?php endif; ?>
            </div>
        <?php endif; ?>

        <!-- Compact 2x2 Summary Grid -->
        <div class="sr-mini-grid">
            <article class="card mini-stat-card">
                <span class="muted small">আজকের অর্ডার</span>
                <strong class="mini-stat-val tabular"><?= Bn::num((int) $today['orders']) ?>টি</strong>
                <span class="muted small tabular"><?= Bn::num((int) $today['retailers']) ?>টি দোকান ভিজিট</span>
            </article>
            <article class="card mini-stat-card">
                <span class="muted small">আজকের O/C</span>
                <strong class="mini-stat-val tabular <?= $today['oc'] < 0 ? 'is-danger' : ($today['oc'] > 0 ? 'is-ok' : '') ?>"><?= $signed((float) $today['oc']) ?></strong>
                <span class="muted small tabular">ব্যালেন্স <?= $signed((float) $profile['oc_balance']) ?></span>
            </article>
            <article class="card mini-stat-card">
                <span class="muted small">এই মাসে বিক্রি</span>
                <strong class="mini-stat-val tabular"><?= Bn::money((float) $month['value'], true) ?></strong>
                <span class="muted small tabular"><?= Bn::num((int) $month['orders']) ?>টি অর্ডার<?= $monthTarget > 0 ? ' · ' . Bn::digits($monthPct) . '%' : '' ?></span>
            </article>
            <a href="<?= e(url('/sr/history')) ?>" class="card mini-stat-card mini-stat-link">
                <span class="muted small">অর্ডার হিস্ট্রি</span>
                <strong class="mini-stat-val" style="color:var(--cobalt)">সব দেখুন →</strong>
                <span class="muted small">তারিখ অনুযায়ী মেমো ও O/C</span>
            </a>
        </div>
    </div>
</div>
<?php $this->endSection(); ?>
