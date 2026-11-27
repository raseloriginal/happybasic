<?php $this->extend('sr.layouts.main'); ?>

<?php
use App\Support\Bn;
$todayValue = (float) $today['value'];
$target = (float) $profile['daily_target'];
$pct = $target > 0 ? min(100, (int) round($todayValue / $target * 100)) : 0;
$remaining = max(0, $target - $todayValue);
$monthTarget = (float) $profile['monthly_target'];
$monthPct = $monthTarget > 0 ? min(100, (int) round($month['value'] / $monthTarget * 100)) : 0;
$signed = static fn(float $v): string => Bn::signedMoney($v, true);
$over = (float) $today['over_oc'];
$comm = abs((float) $today['comm_oc']);
$ring = 2 * M_PI * 36;
?>

<?php $this->section('content'); ?>
<div class="hp-page sr-home">
    <div class="hp-sky" aria-hidden="true" style="--sky-h: 290px"></div>

    <header class="hp-top">
        <span class="hp-avatar">
            <?php if (!empty($currentSr['photo_path'])): ?><img src="<?= e(url($currentSr['photo_path'])) ?>" alt=""><?php else: ?><?= e(mb_substr((string) $profile['name'], 0, 1)) ?><?php endif; ?>
        </span>
        <div class="hp-top-t">
            <span>SR · <?= e($profile['company']) ?> · <?= e($profile['partner']) ?></span>
            <b><?= e($profile['name']) ?></b>
        </div>
        <form method="POST" action="<?= e(url('/sr/logout')) ?>" class="logout-form">
            <?= csrf_field() ?>
            <button type="submit" class="hp-icon-btn" title="সাইন আউট" aria-label="সাইন আউট">
                <svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/></svg>
            </button>
        </form>
    </header>

    <section class="hp-sale">
        <div class="hp-sale-l">
            <span>আজকের অর্ডার<?= $dayCompleted ? ' · দিন সম্পন্ন ✓' : '' ?></span>
            <strong><?= Bn::money($todayValue, true) ?></strong>
            <span><?php if ($target > 0): ?><?= $remaining > 0 ? 'লক্ষ্য ' . Bn::money($target, true) . ' · আরও ' . Bn::money($remaining, true) . ' বাকি' : 'লক্ষ্য অর্জিত ✓' ?><?php else: ?>দৈনিক লক্ষ্য নির্ধারিত নেই<?php endif; ?></span>
        </div>
        <?php if ($target > 0): ?>
            <div class="hp-ring" role="img" aria-label="দৈনিক লক্ষ্যের <?= Bn::digits($pct) ?>% হয়েছে">
                <svg width="84" height="84" viewBox="0 0 84 84" aria-hidden="true">
                    <circle cx="42" cy="42" r="36" fill="none" stroke="rgba(255,255,255,.2)" stroke-width="8"/>
                    <circle cx="42" cy="42" r="36" fill="none" stroke="#fff" stroke-width="8" stroke-linecap="round"
                        stroke-dasharray="<?= round($ring, 2) ?>" stroke-dashoffset="<?= round($ring * (1 - $pct / 100), 2) ?>" transform="rotate(-90 42 42)"/>
                </svg>
                <span><b><?= Bn::digits($pct) ?>%</b><small>লক্ষ্য</small></span>
            </div>
        <?php endif; ?>
    </section>

    <section class="hp-stats">
        <div><b><?= Bn::num((int) $today['orders']) ?></b><span>মেমো</span></div>
        <div><b class="is-ink2"><?= Bn::num((int) $today['retailers']) ?></b><span>দোকান</span></div>
        <div><b class="is-blue">+<?= Bn::money($over, true) ?></b><span>ওভার</span></div>
        <div><b class="is-red">−<?= Bn::money($comm, true) ?></b><span>কমিশন</span></div>
    </section>

    <a href="<?= e(url('/sr/order')) ?>" class="hp-cta">
        <svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>
        নতুন অর্ডার
    </a>

    <?php if ($dayCompleted || $today['orders'] > 0): ?>
        <div class="hp-note<?= $dayCompleted ? ' is-done' : '' ?>">
            <?php if ($dayCompleted): ?>
                আজকের অর্ডার সম্পন্ন হয়েছে<?= $today['assigned'] > 0 ? ' এবং ডেলিভারি ট্রিপে দেওয়া হয়েছে।' : ' — ডেলিভারি ট্রিপের অপেক্ষায়।' ?>
            <?php else: ?>
                আজকের অর্ডার খোলা আছে। কাজ শেষে অর্ডার পেজের "আজ" থেকে <strong>দিন সম্পন্ন করুন</strong> চাপুন।
            <?php endif; ?>
        </div>
    <?php endif; ?>

    <div class="hp-two">
        <article class="hp-card">
            <span>এই মাসে অর্ডার</span>
            <b><?= Bn::money((float) $month['value'], true) ?></b>
            <span><?= Bn::num((int) $month['orders']) ?>টি মেমো<?= $monthTarget > 0 ? ' · লক্ষ্যের ' . Bn::digits($monthPct) . '%' : '' ?></span>
        </article>
        <a href="<?= e(url('/sr/history')) ?>" class="hp-card is-link">
            <span>O/C ব্যালেন্স</span>
            <b class="<?= $profile['oc_balance'] < 0 ? 'is-red' : 'is-blue' ?>"><?= $signed((float) $profile['oc_balance']) ?></b>
            <span>হিস্ট্রি দেখুন ›</span>
        </a>
    </div>
</div>
<?php $this->endSection(); ?>
