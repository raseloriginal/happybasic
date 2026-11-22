<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <?= csrf_meta() ?>
    <title><?= e($title ?? config('app.name', 'HappyBasic')) ?></title>
    <link rel="icon" type="image/jpeg" href="<?= e(asset('images/logo.jpg')) ?>">
    <link rel="stylesheet" href="<?= e(asset('css/app.css')) ?>">
</head>
<body>
    <header class="navbar">
        <div class="container nav-inner">
            <a class="brand" href="<?= e(url('/')) ?>">
                <img class="brand-logo" src="<?= e(asset('images/logo.jpg')) ?>" alt="<?= e(config('app.name', 'HappyBasic')) ?>">
                <span><?= e(config('app.name', 'HappyBasic')) ?></span>
            </a>
            <nav class="nav-links">
                <a href="<?= e(url('/')) ?>">Home</a>
                <?php if ($user = auth()): ?>
                    <a href="<?= e(url('/dashboard')) ?>">Dashboard</a>
                    <form method="POST" action="<?= e(url('/logout')) ?>" class="inline-form">
                        <?= csrf_field() ?>
                        <button type="submit" class="link-btn">Logout (<?= e($user['name'] ?? '') ?>)</button>
                    </form>
                <?php else: ?>
                    <a href="<?= e(url('/login')) ?>">Login</a>
                    <a href="<?= e(url('/register')) ?>">Register</a>
                <?php endif; ?>
            </nav>
        </div>
    </header>

    <main class="container">
        <?php $this->include('partials.flash'); ?>
        <?= $this->yield('content') ?>
    </main>
</body>
</html>
