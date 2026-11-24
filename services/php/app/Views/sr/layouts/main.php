<?php
$navItems = [
    [
        'key' => 'dashboard',
        'label' => 'আজ',
        'path' => '/sr/dashboard',
        'icon' => '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5.5v-6.5h-5V21H4a1 1 0 0 1-1-1z"/>',
    ],
    [
        'key' => 'order',
        'label' => 'অর্ডার',
        'path' => '/sr/order',
        'isCenter' => true,
        'icon' => '<path d="M12 5v14M5 12h14"/>',
    ],
    [
        'key' => 'history',
        'label' => 'হিস্ট্রি',
        'path' => '/sr/history',
        'icon' => '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 8h6M9 12h6M9 16h4"/>',
    ],
    [
        'key' => 'profile',
        'label' => 'আমি',
        'path' => '/sr/profile',
        'icon' => '<circle cx="12" cy="8" r="4"/><path d="M4 20a8 8 0 0 1 16 0"/>',
    ],
];
$active = $activeNav ?? 'dashboard';
$isMapMode = $active === 'order';
$hasCustomHeader = in_array($active, ['dashboard', 'order', 'history', 'profile'], true);
?>
<!DOCTYPE html>
<html lang="bn">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
    <?= csrf_meta() ?>
    <title><?= e($title ?? 'SR') ?> — <?= e(config('app.name', 'HappyBasic')) ?> SR</title>
    <link rel="icon" type="image/jpeg" href="<?= e(asset('images/logo.jpg')) ?>">
    <link rel="preconnect" href="https://mt0.google.com">
    <link rel="preconnect" href="https://mt1.google.com">
    <link rel="stylesheet" href="<?= e(asset('vendor/leaflet/leaflet.css')) ?>">
    <link rel="stylesheet" href="<?= e(asset('sr/css/sr.css')) ?>">
    <noscript><style>#appBootLoader{display:none!important;}</style></noscript>
</head>
<body data-hb-user="<?= (int) ($currentSr['user_id'] ?? 0) ?>">
<div class="app-shell">
    <div class="app-loader" id="appBootLoader" role="status" aria-live="polite" aria-label="SR অ্যাপ লোড হচ্ছে">
        <div class="app-loader-box">
            <span class="brand-mark brand-mark-lg" aria-hidden="true"><img src="<?= e(asset('images/logo.jpg')) ?>" alt="<?= e(config('app.name', 'HappyBasic')) ?>"></span>
            <div class="app-loader-bar"><span></span></div>
            <span class="muted small">SR অ্যাপ লোড হচ্ছে…</span>
        </div>
    </div>
    <div class="spa-progress" id="spaProgress" aria-hidden="true"></div>

    <div class="app-main <?= $isMapMode ? 'is-map-mode' : '' ?> <?= $hasCustomHeader ? 'has-custom-header' : '' ?>" id="srAppMain">
        <header class="topbar">
            <div class="topbar-left">
                <a href="<?= e(url('/sr/dashboard')) ?>" class="mobile-brand" aria-label="SR হোম">
                    <img src="<?= e(asset('images/logo.jpg')) ?>" alt="<?= e(config('app.name', 'HappyBasic')) ?>">
                </a>
                <h1 class="page-title" id="srPageTitle"><?= e($title ?? 'ড্যাশবোর্ড') ?></h1>
            </div>
            <div class="topbar-right">
                <div id="srTopbarActions" class="topbar-actions"><?= $this->yield('topbar_actions') ?></div>
                <form method="POST" action="<?= e(url('/sr/logout')) ?>" class="logout-form">
                    <?= csrf_field() ?>
                    <button type="submit" class="icon-btn" title="সাইন আউট <?= e($currentSr['name'] ?? '') ?>" aria-label="সাইন আউট">
                        <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/></svg>
                    </button>
                </form>
            </div>
        </header>

        <main class="content" id="srContent">
            <?php $this->include('partials.flash'); ?>
            <?= $this->yield('content') ?>
        </main>
    </div>

    <nav class="bottom-nav" aria-label="SR নেভিগেশন">
        <?php foreach ($navItems as $item): ?>
            <?php $isAct = $active === $item['key']; ?>
            <a href="<?= e(url($item['path'])) ?>"
               class="bottom-nav-item <?= $isAct ? 'is-active' : '' ?> <?= !empty($item['isCenter']) ? 'is-center-action' : '' ?>"
               data-nav-key="<?= e($item['key']) ?>">
                <span class="bnav-icon-wrap" aria-hidden="true">
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><?= $item['icon'] ?></svg>
                </span>
                <span class="bnav-label"><?= e($item['label']) ?></span>
            </a>
        <?php endforeach; ?>
    </nav>

    <div class="toast-stack" id="toastStack" aria-live="polite"></div>
</div>

<script src="<?= e(asset('vendor/leaflet/leaflet.js')) ?>"></script>
<script src="<?= e(asset('shared/js/offline-store.js')) ?>"></script>
<script src="<?= e(asset('shared/js/geo-filter.js')) ?>"></script>
<script src="<?= e(asset('shared/js/map-tiles.js')) ?>"></script>
<script src="<?= e(asset('sr/js/sr.js')) ?>"></script>
</body>
</html>
