<?php
$this->extend('retailer.layouts.main');
use App\Support\Bn;

$colors = ['blue', 'orange', 'green', 'purple', 'pink', 'teal'];
?>
<?php $this->section('content'); ?>
<header class="plain-head"><h1>হিস্ট্রি</h1></header>
<main class="page">
    <?php if ($rows === []): ?>
        <div class="card empty"><b>এখনো কোনো হিস্ট্রি নেই</b><p>অর্ডার ও ডেলিভারি হলে দিন অনুযায়ী এখানে জমা হবে।</p></div>
    <?php endif; ?>
    <?php foreach ($rows as $i => $r):
        $href = $r['today'] ? '/retailer' : '/retailer/delivery-invoice?date=' . $r['date'];
        ?>
        <a class="card hrow" href="<?= e(url($href)) ?>">
            <div class="date c-<?= $colors[$i % count($colors)] ?>"><b><?= e($r['day']) ?></b><span><?= e($r['month']) ?></span></div>
            <div class="h-info"><strong>৳<?= Bn::digits(number_format($r['total'])) ?></strong><p><?= e($r['sub']) ?></p></div>
            <svg class="chev" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="m9 6 6 6-6 6"/></svg>
        </a>
    <?php endforeach; ?>
</main>
<?php $this->endSection(); ?>
