<?php $this->extend('admin.layouts.main'); ?>

<?php $this->section('content'); ?>
<div id="adminSettingsApp" data-base-url="<?= e(url('/admin/settings')) ?>">
<div class="tabs-bar" role="tablist" aria-label="Settings Sections">
    <button type="button" class="tab-btn is-active" role="tab" data-tab-target="sessions" aria-selected="true">
        Login Sessions
        <span class="tab-count" id="sessionCountBadge"><?= count($sessions) ?></span>
    </button>
    <button type="button" class="tab-btn" role="tab" data-tab-target="categories" aria-selected="false">
        Global Product Categories
        <span class="tab-count" id="categoryCountBadge"><?= count($categories) ?></span>
    </button>
    <button type="button" class="tab-btn" role="tab" data-tab-target="areas" aria-selected="false">
        Areas
        <span class="tab-count" id="areaCountBadge"><?= count($areas) ?></span>
    </button>
    <button type="button" class="tab-btn" role="tab" data-tab-target="logs" aria-selected="false">
        Activity Logs
        <span class="tab-count"><?= count($logs) ?></span>
    </button>
</div>

<!-- Tab 1: Login Sessions -->
<section class="panel tab-panel is-active" data-tab-panel="sessions">
    <div class="panel-head">
        <div>
            <h2 class="card-title">User Login Sessions</h2>
            <p class="card-subtitle">Monitor active sign-ins across admins, partners, dealers, SRs, and DSRs</p>
        </div>
        <button type="button" class="btn btn-danger-outline btn-sm" id="revokeAllSessionsBtn">Revoke All Others</button>
    </div>

    <div class="table-wrap">
        <table class="data-table">
            <thead>
                <tr>
                    <th>User</th>
                    <th>Role</th>
                    <th>Device &amp; Browser</th>
                    <th>IP Address</th>
                    <th>Last Active</th>
                    <th class="text-right">Action</th>
                </tr>
            </thead>
            <tbody id="sessionsTbody">
                <?php foreach ($sessions as $s): ?>
                    <tr data-session-row data-current="<?= $s['current'] ? '1' : '0' ?>">
                        <td>
                            <div class="cell-primary">
                                <?= e($s['user']) ?>
                                <?php if ($s['current']): ?>
                                    <span class="badge badge-success">Current</span>
                                <?php endif; ?>
                            </div>
                            <div class="cell-sub"><?= e($s['email']) ?></div>
                        </td>
                        <td><span class="badge badge-neutral"><?= e($s['role']) ?></span></td>
                        <td>
                            <div><?= e($s['device']) ?></div>
                            <?php if ($s['location'] !== ''): ?><div class="cell-sub"><?= e($s['location']) ?></div><?php endif; ?>
                        </td>
                        <td class="mono"><?= e($s['ip']) ?></td>
                        <td class="muted small nowrap"><?= e($s['last_active']) ?></td>
                        <td class="text-right nowrap">
                            <?php if ($s['current']): ?>
                                <span class="muted small">Active session</span>
                            <?php else: ?>
                                <button type="button" class="btn btn-danger-ghost btn-xs" data-revoke-session="<?= (int) $s['id'] ?>">Revoke</button>
                            <?php endif; ?>
                        </td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>
</section>

<!-- Tab 2: Global Product Categories -->
<section class="panel tab-panel" data-tab-panel="categories" hidden>
    <div class="panel-head">
        <div>
            <h2 class="card-title">Global Product Categories</h2>
            <p class="card-subtitle">Shared catalog taxonomy available across all companies and partners</p>
        </div>
    </div>

    <form id="addCategoryForm" class="inline-create-bar" method="POST" action="<?= e(url('/admin/settings/categories')) ?>">
        <?= csrf_field() ?>
        <input type="text" id="newCategoryName" name="name" maxlength="120" placeholder="New category name (e.g. Baby Care)" required>
        <select id="newCategoryStatus" name="status" class="select-input">
            <option value="Active">Active</option>
            <option value="Inactive">Inactive</option>
        </select>
        <button type="submit" class="btn btn-primary btn-sm">Add Category</button>
    </form>

    <div class="table-wrap">
        <table class="data-table">
            <thead>
                <tr>
                    <th>Category Name</th>
                    <th>Slug</th>
                    <th>Products</th>
                    <th>Status</th>
                    <th class="text-right">Actions</th>
                </tr>
            </thead>
            <tbody id="categoriesTbody">
                <?php foreach ($categories as $cat): ?>
                    <tr data-category-row data-id="<?= (int) $cat['id'] ?>" data-category="<?= e(json_encode($cat, JSON_UNESCAPED_UNICODE)) ?>">
                        <td class="cell-primary"><?= e($cat['name']) ?></td>
                        <td class="mono"><?= e($cat['slug']) ?></td>
                        <td class="tabular"><?= number_format((int) $cat['products']) ?></td>
                        <td>
                            <span class="badge <?= $cat['status'] === 'Active' ? 'badge-success' : 'badge-neutral' ?>" data-cat-status><?= e($cat['status']) ?></span>
                        </td>
                        <td class="text-right nowrap">
                            <button type="button" class="btn btn-ghost btn-xs" data-toggle-category>Toggle</button>
                            <button type="button" class="btn btn-danger-ghost btn-xs" data-delete-category>Delete</button>
                        </td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>
</section>

<!-- Tab 3: Areas -->
<section class="panel tab-panel" data-tab-panel="areas" hidden>
    <div class="panel-head">
        <div>
            <h2 class="card-title">Areas</h2>
            <p class="card-subtitle">Distribution zones partners can be assigned to</p>
        </div>
    </div>

    <form id="addAreaForm" class="inline-create-bar" method="POST" action="<?= e(url('/admin/settings/areas')) ?>">
        <?= csrf_field() ?>
        <input type="text" id="newAreaName" name="name" maxlength="100" placeholder="New area name (e.g. Dhaka North)" required>
        <select id="newAreaStatus" name="status" class="select-input">
            <option value="Active">Active</option>
            <option value="Inactive">Inactive</option>
        </select>
        <button type="submit" class="btn btn-primary btn-sm">Add Area</button>
    </form>

    <div class="table-wrap">
        <table class="data-table">
            <thead>
                <tr>
                    <th>Area Name</th>
                    <th>Partners</th>
                    <th>Status</th>
                    <th class="text-right">Actions</th>
                </tr>
            </thead>
            <tbody id="areasTbody">
                <?php foreach ($areas as $area): ?>
                    <tr data-area-row data-id="<?= (int) $area['id'] ?>" data-area="<?= e(json_encode($area, JSON_UNESCAPED_UNICODE)) ?>">
                        <td class="cell-primary"><?= e($area['name']) ?></td>
                        <td class="tabular"><?= number_format((int) $area['partners']) ?></td>
                        <td>
                            <span class="badge <?= $area['status'] === 'Active' ? 'badge-success' : 'badge-neutral' ?>"><?= e($area['status']) ?></span>
                        </td>
                        <td class="text-right nowrap">
                            <button type="button" class="btn btn-ghost btn-xs" data-toggle-area>Toggle</button>
                            <button type="button" class="btn btn-danger-ghost btn-xs" data-delete-area>Delete</button>
                        </td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>
</section>

<!-- Tab 4: Activity Logs -->
<section class="panel tab-panel" data-tab-panel="logs" hidden>
    <div class="toolbar">
        <div class="toolbar-filters">
            <div class="search-box">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
                <input type="search" id="logSearch" placeholder="Search actor, details, IP..." autocomplete="off">
            </div>

            <select id="logModuleFilter" class="select-input" aria-label="Filter by module">
                <option value="">All Modules</option>
                <?php foreach ($logModules as $module): ?>
                    <option value="<?= e($module) ?>"><?= e($module) ?></option>
                <?php endforeach; ?>
            </select>
        </div>

        <div class="toolbar-meta">
            <span class="muted small"><strong id="logCount"><?= count($logs) ?></strong> events<?= count($logs) >= $logLimit ? ' (latest ' . (int) $logLimit . ')' : '' ?></span>
        </div>
    </div>

    <div class="table-wrap">
        <table class="data-table">
            <thead>
                <tr>
                    <th>Timestamp</th>
                    <th>Actor</th>
                    <th>Action</th>
                    <th>Module</th>
                    <th>Details</th>
                    <th>IP</th>
                </tr>
            </thead>
            <tbody id="logsTbody">
                <?php foreach ($logs as $log): ?>
                    <?php
                        $badgeClass = match ($log['action']) {
                            'Created', 'Login' => 'badge-success',
                            'Revoked', 'Deleted', 'Failed' => 'badge-danger',
                            'Updated' => 'badge-warning',
                            default => 'badge-neutral',
                        };
                    ?>
                    <tr
                        data-module="<?= e($log['module']) ?>"
                        data-search="<?= e(strtolower($log['actor'] . ' ' . $log['action'] . ' ' . $log['module'] . ' ' . $log['detail'] . ' ' . $log['ip'])) ?>"
                    >
                        <td class="mono nowrap"><?= e($log['time']) ?></td>
                        <td class="cell-primary nowrap"><?= e($log['actor']) ?></td>
                        <td><span class="badge <?= $badgeClass ?>"><?= e($log['action']) ?></span></td>
                        <td class="muted"><?= e($log['module']) ?></td>
                        <td><?= e($log['detail']) ?></td>
                        <td class="mono nowrap"><?= e($log['ip']) ?></td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>
</section>
</div>
<?php $this->endSection(); ?>
