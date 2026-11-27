<?php
$active = $activeNav ?? 'today';
$navItems = [
    ['key' => 'today', 'label' => 'আজ', 'path' => '/retailer', 'icon' => '<path d="M4 11l8-6 8 6v8a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1z"/>'],
    ['key' => 'history', 'label' => 'হিস্ট্রি', 'path' => '/retailer/history', 'icon' => '<path d="M8 6h12M8 12h12M8 18h12"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/>'],
];
?>
<!DOCTYPE html>
<html lang="bn">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
    <meta name="theme-color" content="#1A3FD6">
    <?= csrf_meta() ?>
    <title><?= e($title ?? 'দোকান') ?> — Happy</title>
    <link rel="icon" type="image/jpeg" href="<?= e(asset('images/logo.jpg')) ?>">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Hind+Siliguri:wght@400;500;600;700&family=Inter:wght@400;600;700;800&display=swap">
    <link rel="stylesheet" href="<?= e(asset('retailer/css/retailer.css')) ?>">
</head>
<body data-mode="<?= e($mode ?? '') ?>">
<div class="shell">
    <?= $this->yield('content') ?>
    <nav class="tabbar" aria-label="নেভিগেশন">
        <?php foreach ($navItems as $it): ?>
            <a href="<?= e(url($it['path'])) ?>" class="tab-item<?= $active === $it['key'] ? ' is-active' : '' ?>"<?= $active === $it['key'] ? ' aria-current="page"' : '' ?>>
                <span class="tab-ic"><svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><?= $it['icon'] ?></svg></span>
                <?= e($it['label']) ?>
            </a>
        <?php endforeach; ?>
    </nav>
</div>
<script src="<?= e(asset('retailer/js/retailer.js')) ?>"></script>
</body>
</html>
