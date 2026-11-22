<?php $this->extend('admin.layouts.main'); ?>

<?php $this->section('topbar_actions'); ?>
<a href="<?= e(url('/admin/partners')) ?>" class="btn btn-primary btn-sm">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M12 5v14M5 12h14"/></svg>
    <span>Manage Partners</span>
</a>
<?php $this->endSection(); ?>

<?php $this->section('content'); ?>
<section class="bento-grid">
    <!-- Row 1-2 Left: Hero Partners Bento Card -->
    <article class="bento-card bento-hero">
        <div class="bento-head">
            <span class="bento-eyebrow">Network Overview</span>
            <span class="badge badge-success"><?= e($metrics['partners']['delta']) ?></span>
        </div>
        <div class="hero-metric">
            <div class="kpi-value kpi-value-lg"><?= number_format((int) $metrics['partners']['value']) ?></div>
            <div class="kpi-label"><?= e($metrics['partners']['label']) ?></div>
        </div>
        <div class="mini-bars" aria-label="Monthly partner growth">
            <?php foreach ($growth as $i => $g): ?>
                <div class="mini-bar<?= $i === count($growth) - 1 ? ' is-current' : '' ?>" style="height:<?= max(4, (int) round($g['value'] / $growthMax * 100)) ?>%" title="<?= e($g['label']) ?>: <?= (int) $g['value'] ?>"></div>
            <?php endforeach; ?>
        </div>
        <div class="bento-foot">
            <span class="muted">Active across <?= (int) $activeZones ?> distribution zone<?= $activeZones === 1 ? '' : 's' ?></span>
            <a href="<?= e(url('/admin/partners')) ?>" class="text-link">View directory →</a>
        </div>
    </article>

    <!-- Row 1 Right: Companies & Shared Dealers -->
    <div class="bento-right-stack">
        <div class="bento-subgrid bento-cols-1">
            <article class="bento-card kpi-card">
                <div class="kpi-top">
                    <span class="kpi-label"><?= e($metrics['companies']['label']) ?></span>
                    <span class="kpi-icon">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M3 21h18M5 21V7l8-4v18M19 21V11l-6-4"/><path d="M9 9h.01M9 13h.01M9 17h.01"/></svg>
                    </span>
                </div>
                <div class="kpi-value"><?= number_format((int) $metrics['companies']['value']) ?></div>
                <span class="kpi-delta"><?= e($metrics['companies']['delta']) ?></span>
            </article>

        </div>

        <!-- Row 2 Right: SR, DSR, Products -->
        <div class="bento-subgrid bento-cols-3">
            <article class="bento-card kpi-card">
                <div class="kpi-top">
                    <span class="kpi-label"><?= e($metrics['sr']['label']) ?></span>
                    <span class="kpi-icon">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 11h-6M19 8v6"/></svg>
                    </span>
                </div>
                <div class="kpi-value"><?= number_format((int) $metrics['sr']['value']) ?></div>
                <span class="kpi-delta is-up"><?= e($metrics['sr']['delta']) ?></span>
            </article>

            <article class="bento-card kpi-card">
                <div class="kpi-top">
                    <span class="kpi-label"><?= e($metrics['dsr']['label']) ?></span>
                    <span class="kpi-icon">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="1" y="3" width="15" height="13" rx="1.5"/><path d="M16 8h4l3 3v5h-7V8z"/><circle cx="5.5" cy="18.5" r="2.5"/><circle cx="18.5" cy="18.5" r="2.5"/></svg>
                    </span>
                </div>
                <div class="kpi-value"><?= number_format((int) $metrics['dsr']['value']) ?></div>
                <span class="kpi-delta"><?= e($metrics['dsr']['delta']) ?></span>
            </article>

            <article class="bento-card kpi-card">
                <div class="kpi-top">
                    <span class="kpi-label"><?= e($metrics['products']['label']) ?></span>
                    <span class="kpi-icon">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="m16.5 9.4-9-5.19M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><path d="M3.27 6.96 12 12.01l8.73-5.05M12 22.08V12"/></svg>
                    </span>
                </div>
                <div class="kpi-value"><?= number_format((int) $metrics['products']['value']) ?></div>
                <span class="kpi-delta"><?= e($metrics['products']['delta']) ?></span>
            </article>
        </div>
    </div>

    <!-- Row 3 Left: System Health Bento Card -->
    <article class="bento-card bento-span-7" id="systemHealthCard">
        <div class="bento-head">
            <div>
                <h2 class="card-title">System Health</h2>
                <p class="card-subtitle">Runtime diagnostics, database responsiveness, and resource headroom</p>
            </div>
            <div class="bento-head-actions">
                <?php $healthOk = $health['overall'] === 'Operational'; ?>
                <span class="badge <?= $healthOk ? 'badge-success' : 'badge-warning' ?>" id="healthStatusBadge"><span class="dot <?= $healthOk ? 'dot-ok' : 'dot-warn' ?>"></span><?= e($health['overall']) ?></span>
                <button
                    type="button"
                    class="btn btn-ghost btn-xs"
                    id="refreshHealthBtn"
                    data-health-url="<?= e(url('/admin/health')) ?>"
                    title="Re-check system health"
                >Refresh</button>
            </div>
        </div>

        <div class="health-body" id="systemHealthBody">
        <div class="health-summary">
            <div class="health-stat">
                <span class="muted">Database Size</span>
                <strong id="healthDbSizeVal"><?= e($health['db_size']) ?></strong>
            </div>
            <div class="health-stat">
                <span class="muted">Avg Latency</span>
                <strong id="healthLatencyVal"><?= e($health['latency']) ?></strong>
            </div>
            <div class="health-stat">
                <span class="muted">PHP Runtime</span>
                <strong><?= e($health['php_version']) ?></strong>
            </div>
            <div class="health-stat">
                <span class="muted">Memory</span>
                <strong id="healthMemoryVal"><?= e($health['memory_usage']) ?></strong>
            </div>
        </div>

        <div class="health-list" id="healthChecksList">
            <?php foreach ($health['checks'] as $check): ?>
                <div class="health-row">
                    <div class="health-row-info">
                        <span class="dot <?= $check['status'] === 'healthy' ? 'dot-ok' : 'dot-warn' ?>"></span>
                        <div>
                            <div class="health-name"><?= e($check['name']) ?></div>
                            <div class="muted small"><?= e($check['detail']) ?></div>
                        </div>
                    </div>
                    <div class="health-meter">
                        <div class="meter-track">
                            <div class="meter-fill <?= $check['load'] >= 65 ? 'is-warn' : '' ?>" style="width: <?= (int) $check['load'] ?>%"></div>
                        </div>
                        <span class="meter-val"><?= (int) $check['load'] ?>%</span>
                    </div>
                </div>
            <?php endforeach; ?>
        </div>
        </div>
    </article>

    <!-- Row 3 Right: Partners by Area -->
    <article class="bento-card bento-span-5">
        <div class="bento-head">
            <div>
                <h2 class="card-title">Partners by Area</h2>
                <p class="card-subtitle">Regional distribution across active territories</p>
            </div>
            <span class="badge badge-neutral"><?= count($areaBreakdown) ?> zone<?= count($areaBreakdown) === 1 ? '' : 's' ?></span>
        </div>

        <div class="area-list">
            <?php if (!$areaBreakdown): ?>
                <p class="muted small">No areas yet. Add areas in Settings → Areas.</p>
            <?php endif; ?>
            <?php foreach ($areaBreakdown as $row): ?>
                <div class="area-row">
                    <div class="area-row-top">
                        <span><?= e($row['area']) ?></span>
                        <span class="muted tabular"><?= (int) $row['partners'] ?> <small>(<?= (int) $row['pct'] ?>%)</small></span>
                    </div>
                    <div class="meter-track">
                        <div class="meter-fill" style="width: <?= (int) $row['bar'] ?>%"></div>
                    </div>
                </div>
            <?php endforeach; ?>
        </div>
    </article>

    <!-- Row 4 Left: Recent Activity -->
    <article class="bento-card bento-span-8">
        <div class="bento-head">
            <div>
                <h2 class="card-title">Recent Activity</h2>
                <p class="card-subtitle">Latest operational events across partners and system settings</p>
            </div>
            <a href="<?= e(url('/admin/settings')) ?>#logs" class="text-link">All logs →</a>
        </div>

        <div class="activity-list">
            <?php if (!$recentEvents): ?>
                <p class="muted small">No activity recorded yet.</p>
            <?php endif; ?>
            <?php foreach ($recentEvents as $event): ?>
                <div class="activity-row">
                    <div class="activity-left">
                        <span class="activity-dot"></span>
                        <div>
                            <div class="activity-title"><?= e($event['title']) ?></div>
                            <div class="muted small"><?= e($event['meta']) ?></div>
                        </div>
                    </div>
                    <span class="muted small tabular"><?= e($event['time']) ?></span>
                </div>
            <?php endforeach; ?>
        </div>
    </article>

    <!-- Row 4 Right: Quick Shortcuts -->
    <article class="bento-card bento-span-4">
        <div class="bento-head">
            <div>
                <h2 class="card-title">Quick Actions</h2>
                <p class="card-subtitle">Jump to core administration tasks</p>
            </div>
        </div>

        <div class="quick-links">
            <a href="<?= e(url('/admin/partners')) ?>#add" class="quick-link">
                <div>
                    <strong>Add New Partner</strong>
                    <small class="muted">Register license, NID, TIN & area</small>
                </div>
                <span>→</span>
            </a>
            <a href="<?= e(url('/admin/settings')) ?>#sessions" class="quick-link">
                <div>
                    <strong>Manage Login Sessions</strong>
                    <small class="muted">Inspect or revoke active user tokens</small>
                </div>
                <span>→</span>
            </a>
            <a href="<?= e(url('/admin/settings')) ?>#categories" class="quick-link">
                <div>
                    <strong>Global Product Categories</strong>
                    <small class="muted">Organize catalog taxonomy</small>
                </div>
                <span>→</span>
            </a>
        </div>
    </article>
</section>
<?php $this->endSection(); ?>
