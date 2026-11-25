<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <?= csrf_meta() ?>
    <title><?= e($title ?? 'Admin') ?> — <?= e(config('app.name', 'HappyBasic')) ?></title>
    <link rel="icon" type="image/jpeg" href="<?= e(asset('images/logo.jpg')) ?>">
    <link rel="stylesheet" href="<?= e(asset('admin/css/admin.css')) ?>">
    <noscript><style>#appBootLoader{display:none!important;}</style></noscript>
</head>
<body>
<div class="app-loader" id="appBootLoader" role="status" aria-live="polite" aria-label="Loading workspace">
    <div class="app-loader-box">
        <span class="brand-mark brand-mark-lg" aria-hidden="true"><img src="<?= e(asset('images/logo.jpg')) ?>" alt="<?= e(config('app.name', 'HappyBasic')) ?>"></span>
        <div class="app-loader-bar"><span></span></div>
        <span class="muted small">Loading workspace…</span>
    </div>
</div>
<div class="spa-progress" id="spaProgress" aria-hidden="true"></div>
<div class="app-shell">
    <div class="sidebar-backdrop" data-sidebar-close></div>

    <aside class="sidebar" id="sidebar">
        <div class="sidebar-brand">
            <a href="<?= e(url('/admin')) ?>" class="brand-link">
                <span class="brand-mark" aria-hidden="true"><img src="<?= e(asset('images/logo.jpg')) ?>" alt="<?= e(config('app.name', 'HappyBasic')) ?>"></span>
                <span class="brand-text">
                    <strong><?= e(config('app.name', 'HappyBasic')) ?></strong>
                    <small>Admin Console</small>
                </span>
            </a>
            <button type="button" class="icon-btn mobile-only" data-sidebar-close aria-label="Close navigation">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>

        <nav class="sidebar-nav" aria-label="Admin Navigation">
            <span class="nav-label">Workspace</span>

            <a href="<?= e(url('/admin/dashboard')) ?>" class="nav-item <?= ($activeNav ?? '') === 'dashboard' ? 'is-active' : '' ?>">
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
                    <rect x="3" y="3" width="7" height="9" rx="1.5"/><rect x="14" y="3" width="7" height="5" rx="1.5"/>
                    <rect x="14" y="12" width="7" height="9" rx="1.5"/><rect x="3" y="16" width="7" height="5" rx="1.5"/>
                </svg>
                <span>Dashboard</span>
            </a>

            <a href="<?= e(url('/admin/partners')) ?>" class="nav-item <?= ($activeNav ?? '') === 'partners' ? 'is-active' : '' ?>">
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
                    <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/>
                    <path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>
                </svg>
                <span>Partners</span>
            </a>

            <a href="<?= e(url('/admin/companies')) ?>" class="nav-item <?= ($activeNav ?? '') === 'companies' ? 'is-active' : '' ?>">
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
                    <path d="M3 21h18M5 21V7l8-4v18M19 21V11l-6-4"/>
                </svg>
                <span>Companies</span>
            </a>

            <a href="<?= e(url('/admin/dealers')) ?>" class="nav-item <?= ($activeNav ?? '') === 'dealers' ? 'is-active' : '' ?>">
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
                    <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>
                </svg>
                <span>Dealers</span>
            </a>

            <a href="<?= e(url('/admin/salesmen')) ?>" class="nav-item <?= ($activeNav ?? '') === 'salesmen' ? 'is-active' : '' ?>">
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
                    <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/>
                    <path d="M22 11h-6M19 8v6"/>
                </svg>
                <span>Salesmen (SR)</span>
            </a>

            <a href="<?= e(url('/admin/platform-fees')) ?>" class="nav-item <?= ($activeNav ?? '') === 'platform-fees' ? 'is-active' : '' ?>">
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
                    <line x1="19" y1="5" x2="5" y2="19"/><circle cx="6.5" cy="6.5" r="2.5"/><circle cx="17.5" cy="17.5" r="2.5"/>
                </svg>
                <span>Platform Fees</span>
            </a>

            <a href="<?= e(url('/admin/app')) ?>" class="nav-item <?= ($activeNav ?? '') === 'app' ? 'is-active' : '' ?>">
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
                    <rect x="6" y="2" width="12" height="20" rx="2.5"/><path d="M11 18h2"/>
                </svg>
                <span>Mobile App</span>
            </a>

            <a href="<?= e(url('/admin/settings')) ?>" class="nav-item <?= ($activeNav ?? '') === 'settings' ? 'is-active' : '' ?>">
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
                    <circle cx="12" cy="12" r="3"/>
                    <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33h.08a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82v.08a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>
                </svg>
                <span>Settings</span>
            </a>
        </nav>

        <div class="sidebar-footer">
            <?php
                $adminName = (string) ($adminUser['name'] ?? 'Admin');
                $initials = strtoupper(implode('', array_map(static fn($w) => mb_substr($w, 0, 1), array_slice(preg_split('/\s+/', trim($adminName)) ?: [], 0, 2))));
            ?>
            <div class="admin-profile">
                <span class="avatar"><?= e($initials ?: 'A') ?></span>
                <div class="admin-meta">
                    <strong><?= e($adminName) ?></strong>
                    <small><?= e($adminUser['email'] ?? '') ?></small>
                </div>
                <form method="POST" action="<?= e(url('/admin/logout')) ?>" data-no-spa>
                    <?= csrf_field() ?>
                    <button type="submit" class="icon-btn" title="Sign out" aria-label="Sign out">
                        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
                            <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/>
                        </svg>
                    </button>
                </form>
            </div>
        </div>
    </aside>

    <div class="app-main">
        <header class="topbar">
            <div class="topbar-left">
                <button type="button" class="icon-btn mobile-only" data-sidebar-open aria-label="Open navigation">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 12h18M3 6h18M3 18h18"/></svg>
                </button>
                <div>
                    <h1 class="page-title" id="adminPageTitle"><?= e($title ?? 'Dashboard') ?></h1>
                </div>
            </div>
            <div class="topbar-right">
                <?php $sysOk = ($systemStatus ?? 'Operational') === 'Operational'; ?>
                <span class="status-chip"><span class="dot <?= $sysOk ? 'dot-ok' : 'dot-warn' ?>"></span><?= $sysOk ? 'All Systems Operational' : 'System ' . e($systemStatus) ?></span>
                <div id="adminTopbarActions" class="topbar-actions"><?= $this->yield('topbar_actions') ?></div>
            </div>
        </header>

        <main class="content" id="adminContent">
            <?php $this->include('partials.flash'); ?>
            <?= $this->yield('content') ?>
        </main>
    </div>
</div>

<div class="toast-stack" id="toastStack" aria-live="polite"></div>

<script src="<?= e(asset('admin/js/admin.js')) ?>"></script>
<script src="<?= e(asset('admin/js/pages/dashboard.js')) ?>"></script>
<script src="<?= e(asset('admin/js/pages/partners.js')) ?>"></script>
<script src="<?= e(asset('admin/js/pages/companies.js')) ?>"></script>
<script src="<?= e(asset('admin/js/pages/dealers.js')) ?>"></script>
<script src="<?= e(asset('admin/js/pages/salesmen.js')) ?>"></script>
<script src="<?= e(asset('admin/js/pages/platform-fees.js')) ?>"></script>
<script src="<?= e(asset('admin/js/pages/settings.js')) ?>"></script>
<script src="<?= e(asset('admin/js/pages/app.js')) ?>"></script>
</body>
</html>
