<?php
$this->extend('retailer.layouts.main');
use App\Support\Bn;

$tints = ['#5B4FE0', '#1F4FE0', '#1E8FE0', '#475273'];
$truck = '<path d="M3 6h11v10H3zM14 10h4l3 3v3h-7"/><circle cx="7" cy="18" r="2"/><circle cx="17" cy="18" r="2"/>';
$when = static fn(array $e): string => $e['group'] === 'আজ' ? $e['when'] : $e['group'] . ' · ' . $e['when'];
$showDm = $orders === [] && $dms !== [];
?>
<?php $this->section('content'); ?>
<div class="sky" aria-hidden="true" style="--sky-h: 230px"></div>
<main class="page" data-mark-seen="<?= e(url('/retailer/notifications/seen')) ?>">
    <header class="top">
        <a href="<?= e(url('/retailer')) ?>" class="icon-btn" aria-label="ফিরে যান"><svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M15 5l-7 7 7 7"/></svg></a>
        <div class="top-t"><span><?= $unread > 0 ? Bn::digits($unread) . 'টি নতুন' : 'সব দেখা হয়েছে' ?></span><b>নোটিফিকেশন</b></div>
    </header>

    <div class="seg" role="tablist">
        <button type="button" role="tab" data-ntab="sr" class="<?= $showDm ? '' : 'is-on' ?>" aria-selected="<?= $showDm ? 'false' : 'true' ?>">SR অর্ডার<?php if ($unreadOrders > 0): ?> <span class="seg-n"><?= Bn::digits($unreadOrders) ?></span><?php endif; ?></button>
        <button type="button" role="tab" data-ntab="dm" class="<?= $showDm ? 'is-on' : '' ?>" aria-selected="<?= $showDm ? 'true' : 'false' ?>">ডেলিভারি ম্যান<?php if ($unreadDms > 0): ?> <span class="seg-n"><?= Bn::digits($unreadDms) ?></span><?php endif; ?></button>
    </div>

    <div class="card list nlist" data-npanel="sr"<?= $showDm ? ' hidden' : '' ?>>
        <?php if ($orders === []): ?><p class="nempty">এখনো কোনো অর্ডার নেই</p><?php endif; ?>
        <?php foreach ($orders as $e):
            $tint = $tints[crc32((string) $e['company']) % count($tints)];
            ?>
            <a class="nrow<?= $e['unread'] ? ' is-new' : '' ?>" href="<?= e(url('/retailer/invoice?date=' . $e['date'] . '&order=' . $e['order_id'])) ?>">
                <span class="n-av" style="color: <?= $tint ?>; border-color: <?= $tint ?>"><?= e($e['initial']) ?></span>
                <span class="n-t"><b><?= e($e['title']) ?></b><span><?= e($e['sub']) ?></span></span>
                <span class="n-r"><span><?= e($when($e)) ?></span><?php if ($e['unread']): ?><i class="dot" aria-label="নতুন"></i><?php endif; ?></span>
            </a>
        <?php endforeach; ?>
    </div>

    <div class="card list nlist" data-npanel="dm"<?= $showDm ? '' : ' hidden' ?>>
        <?php if ($dms === []): ?><p class="nempty">এখনো কোনো ডেলিভারির খবর নেই</p><?php endif; ?>
        <?php foreach ($dms as $e):
            $arrived = $e['kind'] === 'arrived';
            $href = $arrived ? '/retailer/delivery-invoice?date=' . $e['date'] : '/retailer/invoice?date=' . $e['date'];
            ?>
            <a class="nrow<?= $e['unread'] ? ' is-new' : '' ?>" href="<?= e(url($href)) ?>">
                <span class="n-ic <?= $arrived ? 'n-done' : ($e['unread'] ? 'n-way' : 'n-old') ?>">
                    <?php if ($arrived): ?>
                        <svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12l5 5 9-10"/></svg>
                    <?php else: ?>
                        <svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><?= $truck ?></svg>
                    <?php endif; ?>
                </span>
                <span class="n-t"><b><?= e($e['short'] ?? $e['title']) ?></b><?php if (!empty($e['detail'])): ?><span><?= e($e['detail']) ?></span><?php endif; ?></span>
                <span class="n-r"><span><?= e($when($e)) ?></span><?php if ($e['unread']): ?><i class="dot" aria-label="নতুন"></i><?php endif; ?></span>
            </a>
        <?php endforeach; ?>
    </div>

    <div class="offer"><b>%</b>কোম্পানির অফার শীঘ্রই এখানে আসবে</div>
</main>
<?php $this->endSection(); ?>
