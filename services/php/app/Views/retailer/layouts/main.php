<?php
$active = $activeNav ?? 'today';
$navItems = [
    ['key' => 'today', 'label' => 'আজ', 'path' => '/retailer', 'icon' => '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5.5v-6.5h-5V21H4a1 1 0 0 1-1-1z"/>'],
    ['key' => 'history', 'label' => 'হিস্ট্রি', 'path' => '/retailer/history', 'icon' => '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 8h6M9 12h6M9 16h4"/>'],
];
?>
<!DOCTYPE html>
<html lang="bn">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
    <?= csrf_meta() ?>
    <title><?= e($title ?? 'দোকান') ?> — Happy</title>
    <link rel="icon" type="image/jpeg" href="<?= e(asset('images/logo.jpg')) ?>">
    <link rel="stylesheet" href="<?= e(asset('retailer/css/retailer.css')) ?>">
</head>
<body data-mode="<?= e($mode ?? '') ?>">
<div class="shell">
    <?= $this->yield('content') ?>
    <nav class="pill-nav" aria-label="নেভিগেশন">
        <?php foreach ($navItems as $it): ?>
            <a href="<?= e(url($it['path'])) ?>" class="pill-item <?= $active === $it['key'] ? 'is-active is-' . $it['key'] : '' ?>">
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><?= $it['icon'] ?></svg>
                <span><?= e($it['label']) ?></span>
            </a>
        <?php endforeach; ?>
    </nav>
</div>
<script src="<?= e(asset('retailer/js/retailer.js')) ?>"></script>
</body>
</html>
