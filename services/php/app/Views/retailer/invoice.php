<?php $this->extend('retailer.layouts.main'); ?>
<?php $this->section('content'); ?>
<header class="plain-head back-head">
    <a href="<?= e($backUrl) ?>" class="back" aria-label="পেছনে"><svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="m15 5-7 7 7 7"/></svg></a>
    <div><h1>ইনভয়েস</h1><p>প্রতিটা কোম্পানির আলাদা ইনভয়েস</p></div>
</header>
<main class="page">
    <div class="tabs" id="invTabs"></div>
    <article class="card inv" id="invCard"></article>
    <div class="actions">
        <button class="btn-outline" type="button" onclick="window.print()">শেয়ার / PDF</button>
        <button class="btn-danger-soft" type="button" onclick="alert('সমস্যা জানাতে আপনার ডেলিভারি ম্যান বা SR-কে ফোন করুন।')">সমস্যা জানান</button>
    </div>
</main>
<script type="application/json" id="invData"><?= $invoiceJson ?></script>
<?php $this->endSection(); ?>
