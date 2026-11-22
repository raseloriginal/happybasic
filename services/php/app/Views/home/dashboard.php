<?php $this->extend('layouts.app'); ?>

<?php $this->section('content'); ?>
<section class="card">
    <h1>Dashboard</h1>
    <p>Signed in as <strong><?= e($user['name'] ?? '') ?></strong> (<?= e($user['email'] ?? '') ?>).</p>
</section>
<?php $this->endSection(); ?>
