<?php $this->extend('retailer.layouts.main'); ?>
<?php $this->section('content'); ?>
<div class="sky" aria-hidden="true" style="--sky-h: 240px"></div>
<main class="page">
    <header class="top">
        <a href="<?= e($backUrl) ?>" class="icon-btn" aria-label="ফিরে যান"><svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M15 5l-7 7 7 7"/></svg></a>
        <div class="top-t"><span id="invSub"><?= e($dateLabel) ?></span><b>ইনভয়েস · লাভসহ</b></div>
    </header>
    <div class="seg">
        <a href="<?= e(url('/retailer/invoice?date=' . $date . ($selected ? '&order=' . $selected : ''))) ?>" data-seg-link>অর্ডার ইনভয়েস</a>
        <a class="is-on" href="#" aria-current="page">ডেলিভারি ইনভয়েস</a>
    </div>
    <div class="pills" id="invTabs"></div>
    <article class="card inv" id="invCard"></article>
    <section class="gain-card" id="invProfit" hidden>
        <div><span>আমার লাভ</span><b data-profit></b></div>
        <div class="gain-r"><span>প্রতি ৳১০০ কেনায়</span><b data-per100></b></div>
    </section>
    <div class="actions">
        <button class="btn-line" type="button" data-report>সমস্যা জানান</button>
        <button class="btn-dark" type="button" data-share>শেয়ার / PDF</button>
    </div>
</main>
<script type="application/json" id="invData"><?= $invoiceJson ?></script>
<?php $this->endSection(); ?>
