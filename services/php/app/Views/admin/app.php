<?php $this->extend('admin.layouts.main'); ?>

<?php $this->section('content'); ?>
<div id="adminAppPage" data-base-url="<?= e(url('/admin/app')) ?>">
<section class="panel">
    <div class="panel-head">
        <div>
            <h2 class="card-title">Mobile App (Android)</h2>
            <p class="card-subtitle">One app for SR, DSR and retailers — upload a build, then share the link below.</p>
        </div>
    </div>
    <div style="padding:0 20px 20px">
        <label class="muted small" for="appShareUrl">Public download page</label>
        <div style="display:flex;gap:8px;margin-top:6px;flex-wrap:wrap">
            <input class="input" id="appShareUrl" type="text" readonly value="<?= e($shareUrl) ?>" style="flex:1;min-width:240px">
            <button type="button" class="btn btn-sm" id="copyShareUrl">Copy link</button>
            <a class="btn btn-sm btn-secondary" href="<?= e(url('/app')) ?>" target="_blank" rel="noopener" data-no-spa>Open</a>
        </div>
        <?php if ($minCode > 0): ?><p class="muted small" style="margin-top:8px">Builds below <strong><?= (int) $minCode ?></strong> are blocked by the server (APP_MIN_VERSION_CODE).</p><?php endif; ?>
    </div>
</section>

<section class="panel">
    <div class="panel-head"><div><h2 class="card-title">Upload new build</h2>
        <p class="card-subtitle">Build number must be higher than the previous one (it is the number in pubspec.yaml after the +).</p></div></div>
    <form id="appUploadForm" style="padding:0 20px 20px;display:grid;gap:12px;max-width:520px" enctype="multipart/form-data">
        <div><label class="muted small">Version name (e.g. 1.0.0)</label><input class="input" name="version_name" required maxlength="20"></div>
        <div><label class="muted small">Build number (e.g. 1)</label><input class="input" name="version_code" type="number" min="1" required></div>
        <div><label class="muted small">What's new</label><input class="input" name="notes" maxlength="500"></div>
        <div><label class="muted small">APK file</label><input class="input" name="apk" type="file" accept=".apk,application/vnd.android.package-archive" required></div>
        <label style="display:flex;gap:8px;align-items:center"><input type="checkbox" name="force_update" value="1"> Force update (users cannot skip)</label>
        <div><button type="submit" class="btn" id="appUploadBtn">Upload</button></div>
    </form>
</section>

<section class="panel">
    <div class="panel-head"><div><h2 class="card-title">Builds</h2></div></div>
    <div class="table-wrap">
        <table class="data-table">
            <thead><tr><th>Version</th><th>Build</th><th>Size</th><th>Uploaded</th><th>Status</th><th class="text-right">Action</th></tr></thead>
            <tbody>
            <?php if ($releases === []): ?>
                <tr><td colspan="6" class="muted">No build uploaded yet.</td></tr>
            <?php endif; ?>
            <?php foreach ($releases as $r): ?>
                <tr>
                    <td><strong><?= e($r['version_name']) ?></strong><?php if ($r['notes']): ?><div class="muted small"><?= e($r['notes']) ?></div><?php endif; ?></td>
                    <td><?= (int) $r['version_code'] ?><?= $r['force_update'] ? ' <span class="badge badge-neutral">forced</span>' : '' ?></td>
                    <td><?= e(number_format($r['apk_size'] / 1048576, 1)) ?> MB</td>
                    <td><?= e(date('d M Y, g:i A', strtotime((string) $r['created_at']))) ?></td>
                    <td><span class="badge <?= $r['status'] === 'active' ? 'badge-success' : 'badge-neutral' ?>"><?= e(ucfirst($r['status'])) ?></span></td>
                    <td class="text-right">
                        <a class="btn btn-sm btn-secondary" href="<?= e(url('/' . $r['apk_path'])) ?>" data-no-spa>Download</a>
                        <button type="button" class="btn btn-sm btn-secondary" data-release-status="<?= (int) $r['id'] ?>" data-to="<?= $r['status'] === 'active' ? 'inactive' : 'active' ?>"><?= $r['status'] === 'active' ? 'Deactivate' : 'Activate' ?></button>
                        <button type="button" class="btn btn-sm btn-danger-outline" data-release-delete="<?= (int) $r['id'] ?>">Delete</button>
                    </td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
    </div>
</section>
</div>
<?php $this->endSection(); ?>
