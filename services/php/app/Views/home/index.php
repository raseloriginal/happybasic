<?php $this->extend('layouts.app'); ?>

<?php $this->section('content'); ?>
<section class="card">
    <h1>Welcome to <?= e(config('app.name', 'HappyBasic')) ?></h1>
    <p>Lightweight PHP 8.2+ MVC starter with built-in Router, Controller, Model, PDO Singleton, View, Session, Auth, CSRF, Validator, Request, Response, and helper functions.</p>
    <div class="actions">
        <a class="btn" href="<?= e(url('/partner')) ?>">Partner Panel</a>
        <a class="btn btn-secondary" href="<?= e(url('/sr')) ?>">SR Panel</a>
        <a class="btn btn-secondary" href="<?= e(url('/dsr')) ?>">DSR Panel</a>
        <a class="btn btn-secondary" href="<?= e(url('/admin/login')) ?>">Admin Login</a>
        <a class="btn btn-secondary" href="<?= e(url('/admin')) ?>">Admin Dashboard</a>
        <a class="btn btn-secondary" href="<?= e(url('/api/health')) ?>">JSON Health</a>
    </div>
</section>
<?php $this->endSection(); ?>
