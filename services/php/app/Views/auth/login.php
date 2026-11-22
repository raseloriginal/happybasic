<?php $this->extend('layouts.app'); ?>

<?php $this->section('content'); ?>
<section class="card auth-card">
    <h1>Login</h1>
    <form method="POST" action="<?= e(url('/login')) ?>">
        <?= csrf_field() ?>

        <div class="field">
            <label for="email">Email</label>
            <input id="email" type="email" name="email" value="<?= e(old('email')) ?>" required>
            <?php if ($err = error('email')): ?>
                <small class="field-error"><?= e($err) ?></small>
            <?php endif; ?>
        </div>

        <div class="field">
            <label for="password">Password</label>
            <input id="password" type="password" name="password" required>
            <?php if ($err = error('password')): ?>
                <small class="field-error"><?= e($err) ?></small>
            <?php endif; ?>
        </div>

        <button type="submit" class="btn">Sign In</button>
    </form>
</section>
<?php $this->endSection(); ?>
