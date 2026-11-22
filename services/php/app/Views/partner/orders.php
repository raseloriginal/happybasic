<?php $this->extend('partner.layouts.main'); ?>

<?php use App\Support\Bn; ?>

<?php $this->section('content'); ?>
<?php $f = $filters; ?>
<form class="toolbar-card" method="GET" action="<?= e(url('/partner/orders')) ?>" data-spa-get>
    <div class="toolbar-filters">
        <label class="date-field"><span class="muted small">থেকে</span><input type="date" name="from" value="<?= e($f['from']) ?>" class="select-input"></label>
        <label class="date-field"><span class="muted small">পর্যন্ত</span><input type="date" name="to" value="<?= e($f['to']) ?>" class="select-input"></label>
        <select name="sr" class="select-input" aria-label="SR">
            <option value="">সব SR</option>
            <?php foreach ($srs as $sr): ?>
                <option value="<?= (int) $sr['id'] ?>" <?= (int) $f['sr_id'] === (int) $sr['id'] ? 'selected' : '' ?>><?= e($sr['name']) ?></option>
            <?php endforeach; ?>
        </select>
        <select name="company" class="select-input" aria-label="কোম্পানি">
            <option value="">সব কোম্পানি</option>
            <?php foreach ($companies as $c): ?>
                <option value="<?= (int) $c['id'] ?>" <?= (int) $f['company_id'] === $c['id'] ? 'selected' : '' ?>><?= e($c['name']) ?></option>
            <?php endforeach; ?>
        </select>
        <select name="status" class="select-input" aria-label="স্ট্যাটাস">
            <option value="">সব স্ট্যাটাস</option>
            <?php foreach ($statuses as $st): ?>
                <option value="<?= e($st) ?>" <?= $f['status'] === $st ? 'selected' : '' ?>><?= e(Bn::status($st)) ?></option>
            <?php endforeach; ?>
        </select>
        <button type="submit" class="btn btn-secondary btn-sm">দেখুন</button>
    </div>
    <span class="muted small tabular"><strong><?= Bn::num((int) $totals['count']) ?></strong>টি অর্ডার · <?= Bn::money((float) $totals['value']) ?> · O/C <?= Bn::signedMoney((float) $totals['oc']) ?></span>
</form>

<section class="panel">
    <div class="table-wrap">
        <table class="data-table">
            <thead>
                <tr>
                    <th>অর্ডার</th>
                    <th>দোকান</th>
                    <th>SR / কোম্পানি</th>
                    <th class="text-right">পণ্য</th>
                    <th class="text-right">বেজ মোট</th>
                    <th class="text-right">SR মোট</th>
                    <th class="text-right">O/C</th>
                    <th>ট্রিপ</th>
                    <th>স্ট্যাটাস</th>
                    <th></th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($orders as $o): ?>
                    <?php
                        $badge = match ($o['status_key']) {
                            'pending' => 'badge-warning',
                            'assigned' => 'badge-info',
                            'delivered' => 'badge-success',
                            'cancelled' => 'badge-neutral',
                            default => 'badge-danger',
                        };
                    ?>
                    <tr data-order="<?= e(json_encode($o, JSON_UNESCAPED_UNICODE)) ?>" class="<?= $o['status_key'] === 'cancelled' ? 'is-muted' : '' ?>">
                        <td>
                            <div class="mono"><?= e(Bn::digits($o['code'])) ?></div>
                            <div class="cell-sub tabular"><?= e(Bn::date($o['date'])) ?> · <?= e(Bn::digits($o['time'])) ?></div>
                        </td>
                        <td>
                            <div class="cell-primary"><?= e($o['retailer']) ?></div>
                            <div class="cell-sub cell-truncate"><?= e($o['retailer_address'] ?? '') ?></div>
                        </td>
                        <td>
                            <div><?= e($o['sr']) ?></div>
                            <div class="cell-sub"><?= e($o['company']) ?></div>
                        </td>
                        <td class="text-right tabular"><?= Bn::num(count($o['items'])) ?></td>
                        <td class="text-right tabular"><?= Bn::money((float) $o['base_total']) ?></td>
                        <td class="text-right tabular"><strong><?= Bn::money((float) $o['sr_total']) ?></strong></td>
                        <td class="text-right tabular <?= $o['oc'] > 0 ? 'is-ok' : ($o['oc'] < 0 ? 'is-danger' : '') ?>"><?= Bn::signedMoney((float) $o['oc']) ?></td>
                        <td class="mono"><?= e($o['trip'] ? Bn::digits($o['trip']) : '—') ?></td>
                        <td><span class="badge <?= $badge ?>"><?= e(Bn::status($o['status_key'])) ?></span></td>
                        <td class="text-right"><button type="button" class="btn btn-secondary btn-xs" data-view-order>পণ্য দেখুন</button></td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>
    <?php if ($orders === []): ?>
        <div class="empty-state"><p>এই ফিল্টারে কোনো অর্ডার নেই।</p></div>
    <?php endif; ?>
</section>

<div class="modal-overlay" id="orderDetailModal" aria-hidden="true">
    <div class="modal-panel modal-lg" role="dialog" aria-modal="true" aria-labelledby="orderDetailTitle">
        <div class="modal-head">
            <div>
                <h2 id="orderDetailTitle" class="section-title">অর্ডার</h2>
                <p id="orderDetailSub" class="section-subtitle"></p>
            </div>
            <button type="button" class="icon-btn" data-modal-close aria-label="বন্ধ করুন">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>
        <div class="modal-body" style="padding:0">
            <div class="table-wrap">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>পণ্য</th>
                            <th class="text-right">পরিমাণ</th>
                            <th class="text-right">বেজ / পিস</th>
                            <th class="text-right">SR / পিস</th>
                            <th class="text-right">মোট</th>
                            <th class="text-right">O/C</th>
                        </tr>
                    </thead>
                    <tbody id="orderDetailTbody"></tbody>
                </table>
            </div>
        </div>
        <div class="modal-foot">
            <button type="button" class="btn btn-secondary" data-modal-close>বন্ধ করুন</button>
        </div>
    </div>
</div>
<?php $this->endSection(); ?>
