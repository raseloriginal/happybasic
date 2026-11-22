<?php
$navItems = [
    ['key' => 'dashboard',  'label' => 'ড্যাশবোর্ড',   'path' => '/dsr/dashboard',  'icon' => '<rect x="3" y="3" width="7" height="9" rx="1.5"/><rect x="14" y="3" width="7" height="5" rx="1.5"/><rect x="14" y="12" width="7" height="9" rx="1.5"/><rect x="3" y="16" width="7" height="5" rx="1.5"/>'],
    ['key' => 'delivery',   'label' => 'ডেলিভারি',   'path' => '/dsr/delivery',   'icon' => '<path d="M10 17h4V5H2v12h3"/><path d="M20 17h2v-3.34a4 4 0 0 0-1.17-2.83L19 9h-5"/><circle cx="7.5" cy="17.5" r="2.5"/><circle cx="17.5" cy="17.5" r="2.5"/>'],
    ['key' => 'van_stock',  'label' => 'ভ্যান স্টক',   'path' => '/dsr/van-stock',  'icon' => '<path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/><path d="m3.3 7 8.7 5 8.7-5"/><path d="M12 22V12"/>'],
    ['key' => 'settlement', 'label' => 'সেটেলমেন্ট', 'path' => '/dsr/settlement', 'icon' => '<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M2 10h20"/><path d="M6 15h4"/>'],
    ['key' => 'expense',    'label' => 'খরচ',        'path' => '/dsr/expense',    'icon' => '<path d="M4 2v20l2-1 2 1 2-1 2 1 2-1 2 1 2-1 2 1V2l-2 1-2-1-2 1-2-1-2 1-2-1-2 1Z"/><path d="M8 7h8"/><path d="M8 11h8"/><path d="M8 15h5"/>'],
];
$isMapMode = ($activeNav ?? '') === 'delivery';
?>
<!DOCTYPE html>
<html lang="bn">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
    <?= csrf_meta() ?>
    <title><?= e($title ?? 'DSR') ?> — <?= e(config('app.name', 'HappyBasic')) ?> DSR</title>
    <link rel="icon" type="image/jpeg" href="<?= e(asset('images/logo.jpg')) ?>">
    <link rel="stylesheet" href="<?= e(asset('vendor/leaflet/leaflet.css')) ?>">
    <link rel="stylesheet" href="<?= e(asset('dsr/css/dsr.css')) ?>">
    <noscript><style>#appBootLoader{display:none!important;}</style></noscript>
</head>
<body>
<div class="app-shell">
    <div class="app-loader" id="appBootLoader" role="status" aria-live="polite" aria-label="DSR অ্যাপ লোড হচ্ছে">
        <div class="app-loader-box">
            <span class="brand-mark brand-mark-lg" aria-hidden="true"><img src="<?= e(asset('images/logo.jpg')) ?>" alt="<?= e(config('app.name', 'HappyBasic')) ?>"></span>
            <div class="app-loader-bar"><span></span></div>
            <span class="muted small">DSR অ্যাপ লোড হচ্ছে…</span>
        </div>
    </div>
    <div class="spa-progress" id="spaProgress" aria-hidden="true"></div>

    <!-- Main Content -->
    <div class="app-main <?= $isMapMode ? 'is-map-mode' : '' ?>" id="dsrAppMain">
        <header class="topbar">
            <div class="topbar-left">
                <a href="<?= e(url('/dsr/dashboard')) ?>" class="mobile-brand" aria-label="DSR হোম">
                    <img src="<?= e(asset('images/logo.jpg')) ?>" alt="<?= e(config('app.name', 'HappyBasic')) ?>">
                </a>
                <h1 class="page-title" id="dsrPageTitle"><?= e($title ?? 'ড্যাশবোর্ড') ?></h1>
            </div>
            <div class="topbar-right">
                <div id="dsrTopbarActions" class="topbar-actions"><?= $this->yield('topbar_actions') ?></div>
                <form method="POST" action="<?= e(url('/dsr/logout')) ?>" class="logout-form">
                    <?= csrf_field() ?>
                    <button type="submit" class="icon-btn" title="সাইন আউট <?= e($currentDsr['name'] ?? '') ?>" aria-label="সাইন আউট">
                        <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/></svg>
                    </button>
                </form>
            </div>
        </header>

        <main class="content" id="dsrContent">
            <?php $this->include('partials.flash'); ?>
            <?= $this->yield('content') ?>
        </main>
    </div>

    <nav class="bottom-nav" aria-label="DSR নেভিগেশন">
        <?php foreach ($navItems as $item): ?>
            <a href="<?= e(url($item['path'])) ?>" class="bottom-nav-item <?= ($activeNav ?? '') === $item['key'] ? 'is-active' : '' ?>" data-nav-key="<?= e($item['key']) ?>">
                <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><?= $item['icon'] ?></svg>
                <span><?= e($item['label']) ?></span>
            </a>
        <?php endforeach; ?>
    </nav>

    <div class="toast-stack" id="toastStack" aria-live="polite"></div>
</div>

<script src="<?= e(asset('vendor/leaflet/leaflet.js')) ?>"></script>
<script src="<?= e(asset('dsr/js/dsr.js')) ?>"></script>
</body>
</html>
