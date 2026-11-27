<?php $this->extend('sr.layouts.main'); ?>

<?php
use App\Support\Bn;
$monthOrder = (float) $month['value'];
$monthTarget = (float) $profile['monthly_target'];
$monthPct = $monthTarget > 0 ? min(100, (int) round($monthOrder / $monthTarget * 100)) : 0;
$signed = static fn(float $v): string => Bn::signedMoney($v, true);
$dsStats = $daySummary['stats'];
$dsProducts = $daySummary['products'];
$netOc = (float) $dsStats['oc'];
?>

<?php $this->section('content'); ?>
<div
    class="sr-profile-page"
    id="profileApp"
    data-default-date="<?= e($date) ?>"
    data-today="<?= e($today) ?>"
>
    <div class="hp-sky" aria-hidden="true" style="--sky-h: 270px"></div>
    <header class="pf-top">
        <label class="pf-avatar profile-photo-btn" title="ছবি পরিবর্তন করুন">
            <?php if (!empty($currentSr['photo_path'])): ?><img src="<?= e(url($currentSr['photo_path'])) ?>" alt=""><?php else: ?><?= e(mb_substr((string) $profile['name'], 0, 1)) ?><?php endif; ?>
            <input type="file" id="srPhotoInput" accept="image/jpeg,image/png,image/webp" hidden>
            <span class="pf-cam" aria-hidden="true"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/></svg></span>
        </label>
        <div class="pf-top-t">
            <b><?= e($profile['name']) ?></b>
            <span>SR · <?= e($profile['company']) ?> · <?= e($profile['partner']) ?></span>
        </div>
        <form method="POST" action="<?= e(url('/sr/logout')) ?>" class="logout-form">
            <?= csrf_field() ?>
            <button type="submit" class="pf-logout">লগআউট</button>
        </form>
    </header>

    <div class="hs-datebar">
        <button type="button" class="hs-arrow" id="profPrevBtn" aria-label="আগের দিন">‹</button>
        <label class="hs-date" for="profDateInput" title="তারিখ নির্বাচন করুন">
            <strong id="profDateDisplay"><?= e(Bn::date($date)) ?><?= $date === $today ? ' (আজ)' : '' ?></strong>
            <span>অর্ডার সারাংশ</span>
            <input type="date" id="profDateInput" value="<?= e($date) ?>" max="<?= e($today) ?>" class="date-hidden-input" aria-label="তারিখ নির্বাচন করুন">
        </label>
        <button type="button" class="hs-arrow" id="profNextBtn" aria-label="পরের দিন" <?= $date >= $today ? 'disabled' : '' ?>>›</button>
    </div>

    <div class="sr-prof-body">
        <article class="pf-sum">
            <div class="pf-sum-top">
                <div class="pf-net"><span>নিট · আমার পাওনা</span><strong class="tabular <?= $netOc < 0 ? 'is-danger' : 'is-ok' ?>" id="profNetOc"><?= $signed($netOc) ?></strong></div>
                <div class="pf-total"><span><b id="profMemoCount"><?= Bn::num((int) $dsStats['orders']) ?>টি</b> মেমো · মোট অর্ডার</span><strong class="tabular" id="profOrderTotal"><?= Bn::money((float) $dsStats['value'], true) ?></strong></div>
            </div>
            <div class="pf-strip">
                <div><span>ওভার</span><strong class="tabular is-blue" id="profOverOc">+<?= Bn::money((float) $dsStats['over_oc'], true) ?></strong></div>
                <div><span>কমিশন</span><strong class="tabular is-red" id="profCommOc">−<?= Bn::money(abs((float) $dsStats['comm_oc']), true) ?></strong></div>
            </div>
        </article>

        <!-- Product Breakdown Table: কতটা গেছে, কতটা নিয়েছে -->
        <article class="card table-card-padless">
            <div class="prof-table-head">
                <h2 class="section-title">পণ্য · কতটা গেছে, কতটা নিয়েছে</h2>
            </div>
            <div class="table-wrap">
                <table class="data-table prof-prod-table">
                    <thead>
                        <tr>
                            <th>পণ্য</th>
                            <th class="text-center">অর্ডার</th>
                            <th class="text-center">গেছে</th>
                            <th class="text-center">নিয়েছে</th>
                            <th class="text-center">ফেরত</th>
                        </tr>
                    </thead>
                    <tbody id="profProductsBody">
                        <?php if ($dsProducts === []): ?>
                            <tr><td colspan="5" class="text-center muted small" style="padding:18px 10px;">এই তারিখে কোনো পণ্যের হিসাব নেই।</td></tr>
                        <?php else: ?>
                            <?php foreach ($dsProducts as $p): ?>
                                <tr>
                                    <td>
                                        <div class="prof-prod-cell">
                                            <span class="prof-prod-thumb" style="background:<?= e($p['tint']) ?>">
                                                <?php if ($p['image']): ?>
                                                    <img src="<?= e($p['image']) ?>" alt="<?= e($p['name']) ?>">
                                                <?php else: ?>
                                                    <span><?= e($p['code']) ?></span>
                                                <?php endif; ?>
                                            </span>
                                            <span class="prof-prod-name"><?= e($p['name']) ?></span>
                                        </div>
                                    </td>
                                    <td class="text-center tabular"><?= Bn::num((int) $p['ordered_pcs']) ?></td>
                                    <td class="text-center tabular"><?= $p['dispatched_pcs'] > 0 ? Bn::num((int) $p['dispatched_pcs']) : '—' ?></td>
                                    <td class="text-center tabular is-ok"><?= $p['delivered_pcs'] > 0 ? Bn::num((int) $p['delivered_pcs']) : '—' ?></td>
                                    <td class="text-center tabular <?= $p['returned_pcs'] > 0 ? 'is-danger' : '' ?>"><?= $p['returned_pcs'] > 0 ? Bn::num((int) $p['returned_pcs']) : '—' ?></td>
                                </tr>
                            <?php endforeach; ?>
                        <?php endif; ?>
                    </tbody>
                </table>
            </div>
        </article>

        <!-- Monthly Performance Card -->
        <article class="card profile-perf-card">
            <div class="card-head">
                <div>
                    <h3 class="section-title">মাসিক পারফরম্যান্স · <?= e(Bn::monthYear()) ?></h3>
                    <p class="section-subtitle">মাসিক লক্ষ্য অর্জন ও ডেলিভারি</p>
                </div>
                <?php if ($monthTarget > 0): ?>
                    <span class="badge badge-info tabular"><?= Bn::digits($monthPct) ?>% অর্জিত</span>
                <?php endif; ?>
            </div>

            <div class="perf-target-box">
                <div class="perf-target-top">
                    <span class="muted small">মাসিক অর্ডার মূল্য</span>
                    <strong class="tabular"><?= Bn::money($monthOrder) ?><?php if ($monthTarget > 0): ?> <span class="muted small">/ <?= Bn::money($monthTarget) ?></span><?php endif; ?></strong>
                </div>
                <div class="progress-track">
                    <div class="progress-fill is-emerald" style="width: <?= $monthPct ?>%"></div>
                </div>
            </div>

            <div class="perf-metrics-grid">
                <div class="metric-tile">
                    <span class="muted small">মাসের অর্ডার</span>
                    <strong class="tabular"><?= Bn::num((int) $month['orders']) ?></strong>
                </div>
                <div class="metric-tile">
                    <span class="muted small">সক্রিয় দোকান</span>
                    <strong class="tabular"><?= Bn::num((int) $month['retailers']) ?></strong>
                </div>
                <div class="metric-tile">
                    <span class="muted small">ডেলিভারি হার</span>
                    <strong class="tabular"><?= $month['done'] > 0 ? e(Bn::digits($month['delivery_rate'])) . '%' : '—' ?></strong>
                </div>
                <div class="metric-tile">
                    <span class="muted small">মোট O/C ব্যালেন্স</span>
                    <strong class="tabular <?= $profile['oc_balance'] < 0 ? 'is-danger' : 'is-ok' ?>"><?= $signed((float) $profile['oc_balance']) ?></strong>
                </div>
            </div>
        </article>

    </div>
</div>
<?php $this->endSection(); ?>
