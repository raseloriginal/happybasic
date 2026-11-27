<?php
$this->extend('retailer.layouts.main');
use App\Support\Bn;

$money = static fn(float $v): string => '৳' . Bn::digits(number_format(abs($v)));
$max = max(1.0, ...array_map(static fn(array $r): float => (float) $r['total'], $rows ?: [['total' => 1]]));
?>
<?php $this->section('content'); ?>
<div class="sky" aria-hidden="true" style="--sky-h: 250px"></div>
<main class="page">
    <h1 class="page-title">হিস্ট্রি</h1>

    <section class="card week">
        <div><span>শেষ ৭ দিনে কেনা</span><b><?= $money($week['bought']) ?></b></div>
        <?php if ($week['profit'] !== null): ?>
            <div class="week-r"><span>৭ দিনে লাভ</span><b class="blue"><?= $week['profit'] < 0 ? '−' : '+' ?><?= $money($week['profit']) ?></b></div>
        <?php endif; ?>
    </section>

    <?php if ($rows === []): ?>
        <div class="card empty"><b>এখনো কোনো হিস্ট্রি নেই</b><p>অর্ডার ও ডেলিভারি হলে দিন অনুযায়ী এখানে জমা হবে।</p></div>
    <?php else: ?>
        <div class="card list">
            <?php foreach ($rows as $r):
                $href = ($r['today'] ? '/retailer/invoice?date=' : '/retailer/delivery-invoice?date=') . $r['date'];
                ?>
                <a class="hrow" href="<?= e(url($href)) ?>">
                    <span class="date<?= $r['today'] ? ' is-today' : '' ?>"><b><?= e($r['day']) ?></b><span><?= e($r['month']) ?></span></span>
                    <span class="h-mid"><span><?= e($r['sub']) ?></span><span class="bar"><span style="width: <?= max(4, (int) round($r['total'] / $max * 100)) ?>%"></span></span></span>
                    <b class="h-amt"><?= $money($r['total']) ?></b>
                    <svg aria-hidden="true" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" class="chev"><path d="M9 5l7 7-7 7"/></svg>
                </a>
            <?php endforeach; ?>
        </div>
    <?php endif; ?>
</main>
<?php $this->endSection(); ?>
