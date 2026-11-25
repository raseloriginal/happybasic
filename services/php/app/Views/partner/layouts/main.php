<?php
$navItems = [
    ['key' => 'dashboard',      'label' => 'ড্যাশবোর্ড',       'path' => '/partner/dashboard',      'icon' => '<rect x="3" y="3" width="7" height="9" rx="1.5"/><rect x="14" y="3" width="7" height="5" rx="1.5"/><rect x="14" y="12" width="7" height="9" rx="1.5"/><rect x="3" y="16" width="7" height="5" rx="1.5"/>'],
    ['key' => 'trips',          'label' => 'ট্রিপ',            'path' => '/partner/trips',          'icon' => '<rect x="1" y="3" width="15" height="13" rx="1.5"/><path d="M16 8h4l3 3v5h-7V8z"/><circle cx="5.5" cy="18.5" r="2.5"/><circle cx="18.5" cy="18.5" r="2.5"/>'],
    ['key' => 'settlements',    'label' => 'ট্রিপ সেটেলমেন্ট',  'path' => '/partner/settlements',    'icon' => '<path d="M12 2v20M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>'],
    ['key' => 'day-closing',    'label' => 'ডে ক্লোজিং',        'path' => '/partner/day-closing',    'icon' => '<path d="M9 5H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2"/><rect x="9" y="3" width="6" height="4" rx="1"/><path d="m9 14 2 2 4-4"/>'],
    ['key' => 'lots',           'label' => 'লট ও স্টক',        'path' => '/partner/lots',           'icon' => '<path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/><path d="m3.3 7 8.7 5 8.7-5M12 22V12"/>'],
    ['key' => 'products',       'label' => 'পণ্য',             'path' => '/partner/products',       'icon' => '<path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z"/><path d="M3 6h18"/><path d="M16 10a4 4 0 0 1-8 0"/>'],
    ['key' => 'company-ledger', 'label' => 'কোম্পানি খাতা',    'path' => '/partner/company-ledger', 'icon' => '<path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1 0-5H20"/>'],
    ['key' => 'orders',         'label' => 'অর্ডার',           'path' => '/partner/orders',         'icon' => '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M16 13H8M16 17H8M10 9H8"/>'],
    ['key' => 'live', 'label' => 'লাইভ লোকেশন', 'path' => '/partner/live', 'icon' => '<path d="M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/>'],
    ['key' => 'dues', 'label' => 'বাকি', 'path' => '/partner/dues', 'icon' => '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'],
    ['key' => 'dsr-monitor',    'label' => 'ডেলিভারি ম্যান হিসাব', 'path' => '/partner/dsr-monitor',    'icon' => '<path d="M3 3v18h18"/><path d="m7 15 4-4 3 3 5-6"/>'],
    ['key' => 'attendance',     'label' => 'হাজিরা ও QR',      'path' => '/partner/attendance',     'icon' => '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3h-3zM20 14v.01M14 20v.01M20 20h-3v-3"/>'],
    ['key' => 'delivery-men',   'label' => 'ডেলিভারিম্যান (DSR)', 'path' => '/partner/delivery-men',   'icon' => '<circle cx="12" cy="7" r="4"/><path d="M5.5 21a6.5 6.5 0 0 1 13 0"/>'],
];
?>
<!DOCTYPE html>
<html lang="bn">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <?= csrf_meta() ?>
    <title><?= e($title ?? 'ড্যাশবোর্ড') ?> — <?= e(config('app.name', 'HappyBasic')) ?> পার্টনার</title>
    <link rel="icon" type="image/jpeg" href="<?= e(asset('images/logo.jpg')) ?>">
    <link rel="stylesheet" href="<?= e(asset('partner/css/partner.css')) ?>">
    <noscript><style>#appBootLoader{display:none!important;}</style></noscript>
</head>
<body>
<div class="app-loader" id="appBootLoader" role="status" aria-live="polite" aria-label="পার্টনার প্যানেল লোড হচ্ছে">
    <div class="app-loader-box">
        <span class="brand-mark brand-mark-lg" aria-hidden="true"><img src="<?= e(asset('images/logo.jpg')) ?>" alt="<?= e(config('app.name', 'HappyBasic')) ?>"></span>
        <div class="app-loader-bar"><span></span></div>
        <span class="muted small">পার্টনার প্যানেল লোড হচ্ছে…</span>
    </div>
</div>
<div class="spa-progress" id="spaProgress" aria-hidden="true"></div>

<div class="app-shell">
    <div class="sidebar-backdrop" data-sidebar-close></div>

    <aside class="sidebar" id="sidebar">
        <div class="sidebar-brand">
            <a href="<?= e(url('/partner/dashboard')) ?>" class="brand-link">
                <span class="brand-mark" aria-hidden="true"><img src="<?= e(asset('images/logo.jpg')) ?>" alt="<?= e(config('app.name', 'HappyBasic')) ?>"></span>
                <span class="brand-text">
                    <strong><?= e(config('app.name', 'HappyBasic')) ?></strong>
                    <small>পার্টনার প্যানেল</small>
                </span>
            </a>
            <button type="button" class="icon-btn mobile-only" data-sidebar-close aria-label="মেনু বন্ধ করুন">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>

        <nav class="sidebar-nav" aria-label="পার্টনার নেভিগেশন">
            <span class="nav-label">অপারেশনস</span>
            <?php foreach ($navItems as $item): ?>
                <a href="<?= e(url($item['path'])) ?>" class="nav-item <?= ($activeNav ?? '') === $item['key'] ? 'is-active' : '' ?>" data-nav-key="<?= e($item['key']) ?>">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><?= $item['icon'] ?></svg>
                    <span><?= e($item['label']) ?></span>
                </a>
            <?php endforeach; ?>
        </nav>

        <div class="sidebar-footer">
            <?php $pName = (string) ($currentPartner['name'] ?? 'পার্টনার'); ?>
            <div class="profile-row">
                <span class="avatar"><?= e(mb_strtoupper(mb_substr($pName, 0, 2))) ?></span>
                <div class="profile-meta">
                    <strong><?= e($pName) ?></strong>
                    <small><?= e($currentPartner['area'] ?? '') ?></small>
                </div>
                <form method="POST" action="<?= e(url('/partner/logout')) ?>" class="logout-form">
                    <?= csrf_field() ?>
                    <button type="submit" class="icon-btn" title="লগ আউট" aria-label="লগ আউট">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/></svg>
                    </button>
                </form>
            </div>
        </div>
    </aside>

    <div class="app-main">
        <header class="topbar">
            <div class="topbar-left">
                <button type="button" class="icon-btn mobile-only" data-sidebar-open aria-label="মেনু খুলুন">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 12h18M3 6h18M3 18h18"/></svg>
                </button>
                <h1 class="page-title" id="partnerPageTitle"><?= e($title ?? 'ড্যাশবোর্ড') ?></h1>
            </div>
            <div class="topbar-right">
                <div id="partnerTopbarActions" class="topbar-actions"><?= $this->yield('topbar_actions') ?></div>
            </div>
        </header>

        <main class="content" id="partnerContent">
            <?php $this->include('partials.flash'); ?>
            <?= $this->yield('content') ?>
        </main>
    </div>
</div>

<div class="toast-stack" id="toastStack" aria-live="polite"></div>

<script src="<?= e(asset('partner/js/partner.js')) ?>"></script>
<?php foreach (['trips', 'settlements', 'products', 'lots', 'delivery-men', 'orders-ledger', 'attendance', 'dsr-monitor', 'dues', 'live'] as $pageJs): ?>
<script src="<?= e(asset("partner/js/pages/{$pageJs}.js")) ?>"></script>
<?php endforeach; ?>
</body>
</html>
