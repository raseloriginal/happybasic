<?php $this->extend('layouts.app'); ?>

<?php $this->section('content'); ?>
<section class="card">
    <h1>500 — Server Error</h1>
    <?php if (isset($exception) && $exception instanceof Throwable): ?>
        <p><strong><?= e($exception::class) ?>:</strong> <?= e($exception->getMessage()) ?></p>
        <p><small><?= e($exception->getFile()) ?>:<?= e($exception->getLine()) ?></small></p>
        <pre class="trace"><?= e($exception->getTraceAsString()) ?></pre>
    <?php else: ?>
        <p>Something went wrong. Please try again later.</p>
    <?php endif; ?>
</section>
<?php $this->endSection(); ?>
