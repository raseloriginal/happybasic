<?php $this->extend('partner.layouts.main'); ?>

<?php use App\Support\Bn; ?>

<?php $this->section('content'); ?>
<div id="attendanceApp" data-scan-path="<?= e($scanPath) ?>">
    <?php if ($settings['lat'] === null): ?>
        <div class="trip-state-banner is-inline" style="margin-bottom:12px">
            গোডাউনের লোকেশন এখনো সেট করা হয়নি। সেট না করলে যে কেউ QR-এর ছবি তুলে দূর থেকেও হাজিরা দিতে পারবে। নিচে "এই লোকেশন সেট করুন" চাপুন (গোডাউনে বসে)।
        </div>
    <?php endif; ?>

    <section class="att-grid">
        <article class="card att-qr-card">
            <h2 class="section-title">হাজিরার QR কোড</h2>
            <div class="att-qr" id="attQr" aria-label="হাজিরার QR কোড"></div>
            <p class="muted small att-qr-note" id="attQrNote" hidden></p>
            <div class="att-qr-actions">
                <button type="button" class="btn btn-primary btn-sm" id="attPrintBtn">প্রিন্ট করুন</button>
                <button type="button" class="btn btn-secondary btn-sm" id="attCopyBtn">লিংক কপি</button>
                <button type="button" class="btn btn-danger-soft btn-sm" id="attRegenBtn">নতুন QR তৈরি</button>
            </div>
        </article>

        <article class="card">
            <h2 class="section-title">গোডাউন লোকেশন ও সময়</h2>
            <form id="attSettingsForm" class="modal-form" novalidate>
                <div class="form-grid">
                    <div class="form-group">
                        <label for="att_lat">অক্ষাংশ (Latitude)</label>
                        <input id="att_lat" name="lat" type="number" step="any" value="<?= e($settings['lat'] ?? '') ?>" placeholder="যেমন: 23.8103">
                    </div>
                    <div class="form-group">
                        <label for="att_lng">দ্রাঘিমাংশ (Longitude)</label>
                        <input id="att_lng" name="lng" type="number" step="any" value="<?= e($settings['lng'] ?? '') ?>" placeholder="যেমন: 90.4125">
                    </div>
                </div>
                <button type="button" class="btn btn-primary btn-sm" id="attUseHereBtn">📍 গোডাউন লোকেশন পিন করুন</button>
                <div class="form-grid" style="margin-top:12px">
                    <div class="form-group">
                        <label for="att_radius">অনুমোদিত দূরত্ব (মিটার)</label>
                        <input id="att_radius" name="radius" type="number" min="30" max="5000" value="<?= (int) $settings['radius'] ?>" required>
                    </div>
                    <div class="form-group">
                        <label for="att_duty">ডিউটি শুরুর সময়</label>
                        <input id="att_duty" name="duty_start" type="time" value="<?= e($settings['duty_start']) ?>" required>
                    </div>
                </div>
                <div class="modal-error" data-form-error hidden></div>
                <button type="submit" class="btn btn-primary">সংরক্ষণ করুন</button>
            </form>
        </article>
    </section>

    <section class="panel" style="margin-top:16px">
        <div class="panel-head" style="padding:14px 16px 0">
            <h2 class="section-title">আজকের হাজিরা — <?= e(Bn::fullDate(date('Y-m-d'))) ?></h2>
        </div>
        <div class="table-wrap">
            <table class="data-table">
                <thead><tr><th>DSR</th><th>অবস্থা</th><th>সময়</th><th class="text-right">গোডাউন থেকে দূরত্ব</th></tr></thead>
                <tbody>
                <?php foreach ($roll as $r): ?>
                    <tr>
                        <td class="cell-primary"><?= e($r['name']) ?></td>
                        <?php if ($r['checked_in_at'] === null): ?>
                            <td><span class="badge badge-neutral">এখনো আসেননি</span></td>
                            <td>—</td>
                            <td class="text-right">—</td>
                        <?php else: ?>
                            <td><?php if ((int) $r['late_min'] > 0): ?><span class="badge badge-warning"><?= Bn::digits((int) $r['late_min']) ?> মিনিট দেরি</span><?php else: ?><span class="badge badge-success">সময়মতো</span><?php endif; ?></td>
                            <td class="tabular"><?= e(Bn::time($r['checked_in_at'])) ?></td>
                            <td class="text-right tabular"><?= $r['distance_m'] !== null ? Bn::digits((int) $r['distance_m']) . ' মি.' : '—' ?></td>
                        <?php endif; ?>
                    </tr>
                <?php endforeach; ?>
                <?php if ($roll === []): ?>
                    <tr><td colspan="4" class="muted" style="text-align:center">কোনো সক্রিয় DSR নেই।</td></tr>
                <?php endif; ?>
                </tbody>
            </table>
        </div>
    </section>
</div>
<?php $this->endSection(); ?>
