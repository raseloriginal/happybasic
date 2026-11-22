<?php
$this->extend('retailer.layouts.main');
use App\Support\Bn;

$palette = ['PRAN' => 'orange'];
$tints = ['orange', 'blue', 'brown'];
?>
<?php $this->section('content'); ?>
<header class="plain-head back-head">
    <a href="<?= e(url('/retailer')) ?>" class="back" aria-label="পেছনে"><svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="m15 5-7 7 7 7"/></svg></a>
    <div><h1>নোটিফিকেশন</h1><p><?= $unread > 0 ? Bn::digits($unread) . 'টি নতুন' : 'সব দেখা হয়েছে' ?></p></div>
</header>
<main class="page" data-mark-seen="<?= e(url('/retailer/notifications/seen')) ?>">
    <?php if ($groups === []): ?>
        <div class="card empty"><b>এখনো কোনো নোটিফিকেশন নেই</b></div>
    <?php endif; ?>
    <?php foreach ($groups as $label => $events): ?>
        <h2 class="sec-title muted-title"><?= e($label) ?></h2>
        <?php foreach ($events as $e): ?>
            <div class="card nrow">
                <?php if ($e['kind'] === 'order'): ?>
                    <?php $tint = $tints[crc32((string) $e['company']) % 3]; ?>
                    <span class="av av-<?= $tint ?>"><?= e($e['initial']) ?><em><?= e(mb_strimwidth($e['company'], 0, 7, '')) ?></em></span>
                    <div><b><?= e($e['title']) ?></b><p class="ord"><?= e($e['sub']) ?></p><p><?= e($e['when']) ?></p></div>
                <?php else: ?>
                    <span class="nic <?= $e['kind'] === 'arrived' ? 'nic-green' : 'nic-blue' ?>"><?= $e['kind'] === 'arrived' ? '✓' : '🚚' ?></span>
                    <div><b><?= e($e['title']) ?></b><p><?= e($e['when']) ?></p></div>
                <?php endif; ?>
                <?php if ($e['unread']): ?><i class="dot"></i><?php endif; ?>
            </div>
        <?php endforeach; ?>
    <?php endforeach; ?>
</main>
<?php $this->endSection(); ?>
