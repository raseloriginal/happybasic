<?php $this->extend('layouts.app'); ?>

<?php $this->section('content'); ?>
<section class="card">
    <h1>404 — Page Not Found</h1>
    <p>No route matched <code><?= e($path ?? '') ?></code>.</p>
    <a class="btn" href="<?= e(url('/')) ?>">Back Home</a>
</section>
<?php $this->endSection(); ?>
