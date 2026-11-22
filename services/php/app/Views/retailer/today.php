<?php
$this->extend('retailer.layouts.main');
use App\Support\Bn;

$money = static fn(float $v): string => '৳' . Bn::digits(number_format($v));
$chipClass = ['arrived' => 'chip-ok', 'onway' => 'chip-info', 'later' => 'chip-mute'];
$c = $day['counts'];
?>
<?php $this->section('content'); ?>
<header class="hero">
    <div>
        <p class="greet">আসসালামু আলাইকুম</p>
        <h1><?= e($currentRetailer['name']) ?></h1>
    </div>
    <a href="<?= e(url('/retailer/notifications')) ?>" class="bell" aria-label="নোটিফিকেশন">
        <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9M13.7 21a2 2 0 0 1-3.4 0"/></svg>
        <?php if ($unread > 0): ?><span class="bell-badge"><?= $unread > 9 ? '৯+' : Bn::digits($unread) ?></span><?php endif; ?>
    </a>
</header>
<main class="page">
    <section class="card summary">
        <div class="sum-top"><span>আজকের মোট বিল</span><strong><?= $money($day['total']) ?></strong></div>
        <div class="stats">
            <div class="stat s-ok"><b><?= Bn::digits($c['arrived']) ?></b><span>এসেছে</span></div>
            <div class="stat s-info"><b><?= Bn::digits($c['onway']) ?></b><span>পথে</span></div>
            <div class="stat s-mute"><b><?= Bn::digits($c['later']) ?></b><span>পরে আসবে</span></div>
        </div>
    </section>

    <h2 class="sec-title">আজকের মাল</h2>

    <?php if ($day['cards'] === []): ?>
        <div class="card empty"><b>আজ কোনো মাল নেই</b><p>SR অর্ডার নিলে বা ডেলিভারি হলে এখানে দেখা যাবে।</p></div>
    <?php endif; ?>

    <?php foreach ($day['cards'] as $card): ?>
        <a class="card dcard" href="<?= e(url('/retailer/invoice?date=' . $date . '&order=' . $card['first'])) ?>">
            <div class="d-head">
                <div><h3><?= e($card['title']) ?></h3><p><?= $card['dm'] ? 'ডেলিভারি ম্যান ' . e($card['dm']) : 'ডেলিভারি ম্যান ঠিক হয়নি' ?></p></div>
                <span class="chip <?= $chipClass[$card['stage']] ?>"><?= e($card['chip']) ?></span>
            </div>
            <?php foreach ($card['rows'] as $row): ?>
                <div class="d-row"><span><?= $row['sr'] === 'রেডি সেল' ? 'রেডি সেল' : 'SR ' . e($row['sr']) ?> · <?= e($row['company']) ?></span><span><?= $money($row['bill']) ?></span></div>
            <?php endforeach; ?>
            <div class="d-foot"><strong><?= $money($card['total']) ?></strong><em>ইনভয়েস দেখুন ›</em></div>
        </a>
    <?php endforeach; ?>

    <form method="POST" action="<?= e(url('/retailer/logout')) ?>" class="logout-row">
        <?= csrf_field() ?>
        <button type="submit">সাইন আউট</button>
    </form>
</main>
<?php $this->endSection(); ?>
