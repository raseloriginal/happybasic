<?php $this->extend('partner.layouts.main'); ?>

<?php
use App\Support\Bn;

$money = static fn(float $v): string => Bn::money($v, true);
$open = array_values(array_filter($dues, static fn(array $d): bool => $d['state'] !== 'done'));
$pending = array_values(array_filter($dues, static fn(array $d): bool => $d['state'] === 'pending'));
$listed = array_merge(
    array_values(array_filter($dues, static fn(array $d): bool => $d['state'] === 'approved')),
    array_reverse(array_values(array_filter($dues, static fn(array $d): bool => $d['state'] === 'done')))
);
$shops = static fn(array $rows): int => count(array_unique(array_column($rows, 'retailer_id')));
$sum = static fn(array $rows): float => (float) array_sum(array_column($rows, 'remaining'));
$overdue = array_values(array_filter($open, static fn(array $d): bool => $d['overdue']));
$count = static fn(callable $f): string => Bn::digits(count(array_filter($listed, $f)));
$json = static fn(array $d): string => e(json_encode(['id' => $d['id'], 'retailer_id' => $d['retailer_id'], 'retailer' => $d['retailer'], 'remaining' => $d['remaining'], 'items' => $d['items'], 'limit' => $d['custom_limit'] ? $d['limit'] : null], JSON_UNESCAPED_UNICODE));
?>

<?php $this->section('content'); ?>
<div id="duesApp">
<section class="due-kpis">
    <article class="dm-kpi"><span class="dm-kpi-label">মোট বাকি</span><strong class="dm-kpi-val tabular"><?= $money($sum($open)) ?></strong><span class="dm-kpi-sub"><?= Bn::digits($shops($open)) ?>টি দোকান</span></article>
    <article class="dm-kpi dm-kpi-red"><span class="dm-kpi-label"><?= Bn::digits($settings['days']) ?> দিন পার</span><strong class="dm-kpi-val tabular"><?= $money($sum($overdue)) ?></strong><span class="dm-kpi-sub"><?= Bn::digits($shops($overdue)) ?>টি দোকান</span></article>
    <article class="dm-kpi due-kpi-green"><span class="dm-kpi-label">আজ আদায়</span><strong class="dm-kpi-val tabular"><?= $money($today['amount']) ?></strong><span class="dm-kpi-sub"><?= Bn::digits($today['shops']) ?>টি দোকান</span></article>
    <button type="button" class="dm-kpi due-kpi-btn" data-modal-open="dueSettingsModal"><span class="dm-kpi-label">ডিফল্ট সীমা</span><strong class="dm-kpi-val tabular"><?= $money($settings['limit']) ?></strong><span class="dm-kpi-sub">সর্বোচ্চ <?= Bn::digits($settings['days']) ?> দিন · বদলান</span></button>
</section>

<?php if ($pending !== []): ?>
<section class="due-pending">
    <div class="due-pending-head"><h2 class="section-title">অনুমোদনের অপেক্ষায় <span>(<?= Bn::digits(count($pending)) ?>)</span></h2></div>
    <?php foreach ($pending as $d): ?>
    <article class="due-ask" data-due="<?= $json($d) ?>">
        <div class="due-who">
            <strong><?= e($d['retailer']) ?></strong>
            <span class="muted small">DSR <?= e($d['dsr']) ?> · <?= e(Bn::date($d['date'])) ?> · <?= e(Bn::digits($d['code'])) ?></span>
        </div>
        <div class="due-what small">
            <span>বিল <?= $money($d['bill']) ?> · দিয়েছে <?= $money($d['paid'] + $d['collected']) ?> · <b>বাকি <?= $money($d['remaining']) ?></b></span>
            <span class="<?= $d['over_limit'] ? 'is-neg' : 'is-pos' ?>"><?= $d['over_limit'] ? 'সীমা পার' : 'সীমার মধ্যে' ?> (<?= $money($d['shop_total']) ?> / <?= $money($d['limit']) ?>)</span>
            <?php if (!$d['settled']): ?><span class="muted">সেটেলমেন্টের পর মাল ফেরত নেওয়া যাবে</span><?php endif; ?>
        </div>
        <div class="due-actions">
            <?php if ($d['has_entry']): ?><button type="button" class="btn btn-secondary btn-sm" data-due-undo>আনডু</button><?php endif; ?>
            <button type="button" class="btn btn-danger-soft btn-sm" data-due-return <?= $d['settled'] ? '' : 'disabled' ?>>মাল ফেরত</button>
            <button type="button" class="btn btn-sm due-ok" data-due-approve>অনুমোদন</button>
        </div>
    </article>
    <?php endforeach; ?>
</section>
<?php endif; ?>

<div class="due-tabs" role="group" aria-label="ফিল্টার">
    <button type="button" class="is-active" data-due-tab="open">অনুমোদিত (<?= $count(static fn($d) => $d['state'] === 'approved') ?>)</button>
    <button type="button" data-due-tab="overdue"><?= Bn::digits($settings['days']) ?> দিন পার (<?= $count(static fn($d) => $d['overdue']) ?>)</button>
    <button type="button" data-due-tab="near">সীমার কাছে (<?= $count(static fn($d) => $d['near_limit']) ?>)</button>
    <button type="button" data-due-tab="over">সীমা পার (<?= $count(static fn($d) => $d['over_limit']) ?>)</button>
    <button type="button" data-due-tab="done">সম্পন্ন (<?= $count(static fn($d) => $d['state'] === 'done') ?>)</button>
</div>

<section class="panel due-list">
    <?php foreach ($listed as $d): ?>
    <?php
    $done = $d['state'] === 'done';
    $tags = $done ? 'done' : trim('open' . ($d['overdue'] ? ' overdue' : '') . ($d['near_limit'] ? ' near' : '') . ($d['over_limit'] ? ' over' : ''));
    $pct = $d['limit'] > 0 ? min(100, (int) round($d['shop_total'] / $d['limit'] * 100)) : 100;
    ?>
    <article class="due-row" data-due="<?= $json($d) ?>" data-tags="<?= $tags ?>" <?= $done ? 'hidden' : '' ?>>
        <div class="due-who">
            <strong><?= e($d['retailer']) ?> <?php if ($d['over_limit']): ?><span class="badge badge-danger">সীমা পার</span><?php endif; ?></strong>
            <span class="muted small"><?= e(Bn::date($d['date'])) ?> · <?= e(Bn::digits($d['code'])) ?> · DSR <?= e($d['dsr']) ?><?= $d['sr'] ? ' · SR ' . e($d['sr']) : '' ?></span>
        </div>
        <div class="due-bar-wrap small">
            <?php if ($done): ?>
                <span>বাকি ছিল <?= $money($d['due']) ?><?= $d['collected'] > 0 ? ' · উত্তোলন ' . $money($d['collected']) : '' ?><?= $d['returned'] > 0 ? ' · মাল ফেরত ' . $money($d['returned']) : '' ?></span>
            <?php else: ?>
                <div class="due-bar-top"><b>বাকি <?= $money($d['remaining']) ?></b><span class="muted">দোকানে মোট <?= $money($d['shop_total']) ?> / সীমা <?= $money($d['limit']) ?></span></div>
                <div class="due-bar <?= $d['over_limit'] ? 'is-over' : '' ?>"><span style="width:<?= $pct ?>%"></span></div>
            <?php endif; ?>
        </div>
        <span class="badge <?= $done ? 'badge-success' : ($d['overdue'] ? 'badge-danger' : 'badge-neutral') ?>"><?= $done ? 'সম্পন্ন' : Bn::digits($d['age']) . ' দিন' ?></span>
        <div class="due-actions">
            <?php if (!$done || $d['has_entry']): ?><button type="button" class="btn btn-secondary btn-sm" data-due-undo>আনডু</button><?php endif; ?>
            <?php if (!$done): ?>
                <button type="button" class="btn btn-secondary btn-sm" data-due-limit>সীমা</button>
                <button type="button" class="btn btn-danger-soft btn-sm" data-due-return <?= $d['settled'] ? '' : 'disabled title="সেটেলমেন্ট অনুমোদনের পর"' ?>>মাল ফেরত</button>
                <button type="button" class="btn btn-sm due-ok" data-due-collect <?= $d['settled'] ? '' : 'disabled title="সেটেলমেন্ট অনুমোদনের পর"' ?>>টাকা উঠেছে</button>
            <?php endif; ?>
        </div>
    </article>
    <?php endforeach; ?>
    <p class="muted due-empty" id="dueEmpty" hidden>এখানে কোনো বাকি নেই।</p>
</section>

<?php foreach ([
    ['dueSettingsModal', 'dueSettingsForm', 'ডিফল্ট সীমা', '<div class="form-grid"><div class="form-group"><label for="due_def_limit">সীমা (৳)</label><input id="due_def_limit" name="limit" type="number" min="0" step="0.01" required value="' . e((string) $settings['limit']) . '"></div><div class="form-group"><label for="due_def_days">সর্বোচ্চ দিন</label><input id="due_def_days" name="days" type="number" min="1" max="365" required value="' . $settings['days'] . '"></div></div>'],
    ['dueLimitModal', 'dueLimitForm', 'দোকানের সীমা', '<div class="form-group"><label for="due_shop_limit">সীমা (৳) — খালি রাখলে ডিফল্ট</label><input id="due_shop_limit" name="limit" type="number" min="0" step="0.01"></div>'],
    ['dueCollectModal', 'dueCollectForm', 'টাকা উত্তোলন', '<div class="form-group"><label for="due_amount">কত টাকা উঠেছে (৳)</label><input id="due_amount" name="amount" type="number" min="0.01" step="0.01" required></div>'],
    ['dueReturnModal', 'dueReturnForm', 'মাল ফেরত', '<div id="dueReturnItems"></div><p class="small">ফেরত মালের দাম <b id="dueReturnValue" class="tabular"></b></p>'],
] as [$mid, $fid, $mtitle, $body]): ?>
<div class="modal-overlay" id="<?= $mid ?>" aria-hidden="true">
    <div class="modal-panel" role="dialog" aria-modal="true">
        <div class="modal-head">
            <div><h2 class="section-title"><?= $mtitle ?></h2><p class="section-subtitle" data-due-name></p></div>
            <button type="button" class="icon-btn" data-modal-close aria-label="বন্ধ করুন"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg></button>
        </div>
        <form id="<?= $fid ?>" class="modal-form" novalidate>
            <div class="modal-body"><?= $body ?></div>
            <div class="modal-error" data-form-error hidden></div>
            <div class="modal-foot"><button type="button" class="btn btn-secondary" data-modal-close>বন্ধ</button><button type="submit" class="btn btn-primary">সংরক্ষণ করুন</button></div>
        </form>
    </div>
</div>
<?php endforeach; ?>
</div>
<?php $this->endSection(); ?>
