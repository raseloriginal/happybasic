<?php
$this->extend('retailer.layouts.main');
use App\Support\Bn;

$money = static fn(float $v): string => '৳' . Bn::digits(number_format($v));
$c = $day['counts'];
$truck = '<path d="M3 6h11v10H3zM14 10h4l3 3v3h-7"/><circle cx="7" cy="18" r="2"/><circle cx="17" cy="18" r="2"/>';
$initial = static fn(string $s): string => mb_substr(trim(preg_replace('/^(SR|DM)\s+/u', '', $s)), 0, 1);
$deliveries = count($day['cards']);
$live = null;
foreach ($day['cards'] as $card) {
    if ($card['stage'] === 'onway') {
        $live = $card;
        break;
    }
}
$companiesOf = static fn(array $card): string => implode(' + ', array_values(array_unique(array_column($card['rows'], 'company'))));
?>
<?php $this->section('content'); ?>
<div class="sky" aria-hidden="true" style="--sky-h: 330px"></div>
<main class="page">
    <header class="top">
        <span class="av-sq"><?= e(mb_substr((string) $currentRetailer['name'], 0, 1)) ?></span>
        <div class="top-t"><span>আসসালামু আলাইকুম</span><b><?= e($currentRetailer['name']) ?></b></div>
        <a href="<?= e(url('/retailer/notifications')) ?>" class="icon-btn" aria-label="নোটিফিকেশন<?= $unread > 0 ? ' · ' . Bn::digits($unread) . 'টি নতুন' : '' ?>">
            <svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z"/><path d="M10 20a2 2 0 0 0 4 0"/></svg>
            <?php if ($unread > 0): ?><span class="icon-badge"><?= $unread > 9 ? '৯+' : Bn::digits($unread) ?></span><?php endif; ?>
        </a>
    </header>

    <section class="hero-sum">
        <span>আজকের মোট বিল</span>
        <strong><?= $money($day['total']) ?></strong>
        <span><?= Bn::digits($deliveries) ?>টি ডেলিভারি<?= $day['sr_count'] > 0 ? ' · ' . Bn::digits($day['sr_count']) . ' জন SR-এর অর্ডার' : '' ?></span>
    </section>

    <?php if ($live !== null): ?>
        <a class="live" href="<?= e(url('/retailer/invoice?date=' . $date . '&order=' . $live['first'])) ?>">
            <span class="live-ic"><svg aria-hidden="true" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><?= $truck ?></svg><span class="pulse" aria-hidden="true"></span></span>
            <div class="live-t">
                <span class="live-k">● পথে আছে</span>
                <b><?= e($live['dm'] ?: 'ডেলিভারি ম্যান') ?> · <?= e($companiesOf($live)) ?></b>
                <span>নগদ রেডি রাখুন <b><?= $money($live['total']) ?></b></span>
            </div>
        </a>
    <?php endif; ?>

    <div class="stats">
        <div class="stat s-ok"><b><?= Bn::digits($c['arrived']) ?></b><span>এসেছে</span></div>
        <div class="stat s-way"><b><?= Bn::digits($c['onway']) ?></b><span>পথে</span></div>
        <div class="stat s-later"><b><?= Bn::digits($c['later']) ?></b><span>পরে আসবে</span></div>
    </div>

    <div class="sec"><b>আজকের মাল</b><span><?= Bn::digits($deliveries) ?>টি</span></div>

    <?php if ($day['cards'] === []): ?>
        <div class="card empty"><b>আজ কোনো মাল নেই</b><p>SR অর্ডার নিলে বা ডেলিভারি হলে এখানে দেখা যাবে।</p></div>
    <?php endif; ?>

    <?php foreach ($day['cards'] as $card):
        $width = ['arrived' => 100, 'onway' => 62, 'later' => 18][$card['stage']];
        ?>
        <a class="dcard st-<?= e($card['stage']) ?>" href="<?= e(url('/retailer/invoice?date=' . $date . '&order=' . $card['first'])) ?>">
            <div class="dc-h">
                <div class="dc-l"><b><?= e($card['title']) ?></b><span><?= $card['dm'] ? 'DM ' . e($card['dm']) : 'ডেলিভারি ম্যান ঠিক হয়নি' ?> · <?= e($card['partner']) ?></span></div>
                <div class="dc-r"><b><?= $money($card['total']) ?></b><span class="dc-chip"><?= e($card['chip']) ?></span></div>
            </div>
            <div class="track" aria-hidden="true">
                <span class="track-fill" style="width: <?= $width ?>%"></span>
                <?php if ($card['stage'] === 'onway'): ?>
                    <span class="track-van" style="left: calc(<?= $width ?>% - 13px)"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><?= $truck ?></svg></span>
                <?php endif; ?>
            </div>
            <div class="sr-chips">
                <?php foreach ($card['srs'] as $sr): ?>
                    <span class="sr-chip"><i><?= e($initial($sr)) ?></i><?= e($sr) ?></span>
                <?php endforeach; ?>
            </div>
        </a>
    <?php endforeach; ?>

    <form method="POST" action="<?= e(url('/retailer/logout')) ?>" class="logout-row">
        <?= csrf_field() ?>
        <button type="submit">সাইন আউট</button>
    </form>
</main>
<?php $this->endSection(); ?>
