<?php $this->extend('partner.layouts.main'); ?>

<?php use App\Support\Bn; ?>

<?php $this->section('topbar_actions'); ?>
<?php if ($summary !== []): ?>
<button type="button" class="btn btn-primary btn-sm" data-modal-open="ledgerEntryModal">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M12 5v14M5 12h14"/></svg>
    <span>পেমেন্ট / সমন্বয় যোগ করুন</span>
</button>
<?php endif; ?>
<?php $this->endSection(); ?>

<?php $this->section('content'); ?>
<?php if ($summary === []): ?>
    <div class="empty-state"><p>আপনার অ্যাকাউন্টের সাথে এখনো কোনো কোম্পানি যুক্ত নেই।</p></div>
<?php else: ?>
<section class="ledger-company-grid">
    <?php foreach ($summary as $c): ?>
        <a href="<?= e(url('/partner/company-ledger?company=' . $c['id'] . '&from=' . $from . '&to=' . $to)) ?>"
           class="card ledger-company-card <?= $companyId === $c['id'] ? 'is-active' : '' ?>">
            <span class="cell-primary"><?= e($c['name']) ?></span>
            <span class="kpi-label">পরিশোধযোগ্য ব্যালেন্স</span>
            <strong class="tabular <?= $c['balance'] > 0 ? 'is-warn' : 'is-ok' ?>"><?= Bn::money((float) $c['balance']) ?></strong>
            <span class="muted small tabular">ক্রয় <?= Bn::money((float) $c['purchases']) ?> · পরিশোধ <?= Bn::money((float) $c['payments']) ?></span>
        </a>
    <?php endforeach; ?>
</section>

<?php if ($statement !== null): ?>
<form class="toolbar-card" method="GET" action="<?= e(url('/partner/company-ledger')) ?>" data-spa-get>
    <input type="hidden" name="company" value="<?= (int) $companyId ?>">
    <div class="toolbar-filters">
        <label class="date-field"><span class="muted small">থেকে</span><input type="date" name="from" value="<?= e($from) ?>" class="select-input"></label>
        <label class="date-field"><span class="muted small">পর্যন্ত</span><input type="date" name="to" value="<?= e($to) ?>" class="select-input"></label>
        <button type="submit" class="btn btn-secondary btn-sm">দেখুন</button>
    </div>
    <span class="muted small tabular">শুরু <?= Bn::money((float) $statement['opening']) ?> · সমাপনী <strong><?= Bn::money((float) $statement['closing']) ?></strong></span>
</form>

<section class="panel">
    <div class="table-wrap">
        <table class="data-table">
            <thead>
                <tr>
                    <th>তারিখ</th>
                    <th>ধরন</th>
                    <th>রেফারেন্স / নোট</th>
                    <th class="text-right">ডেবিট (ক্রয়)</th>
                    <th class="text-right">ক্রেডিট (পরিশোধ)</th>
                    <th class="text-right">ব্যালেন্স</th>
                    <th></th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($statement['entries'] as $en): ?>
                    <tr>
                        <td class="tabular nowrap"><?= e(Bn::date($en['date'])) ?></td>
                        <td><span class="badge <?= $en['type_key'] === 'payment' ? 'badge-success' : ($en['type_key'] === 'lot_purchase' ? 'badge-info' : 'badge-neutral') ?>"><?= e(Bn::status($en['type_key'])) ?></span></td>
                        <td>
                            <?php if ($en['ref']): ?><div class="mono"><?= e(Bn::digits($en['ref'])) ?></div><?php endif; ?>
                            <div class="cell-sub"><?= e(Bn::digits($en['note'] ?? '')) ?></div>
                        </td>
                        <td class="text-right tabular"><?= $en['debit'] > 0 ? Bn::money((float) $en['debit']) : '—' ?></td>
                        <td class="text-right tabular"><?= $en['credit'] > 0 ? Bn::money((float) $en['credit']) : '—' ?></td>
                        <td class="text-right tabular"><strong><?= Bn::money((float) $en['balance']) ?></strong></td>
                        <td class="text-right">
                            <?php if ($en['manual']): ?>
                                <button type="button" class="btn btn-danger-soft btn-xs" data-delete-ledger="<?= (int) $en['id'] ?>">মুছুন</button>
                            <?php endif; ?>
                        </td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
            <tfoot>
                <tr>
                    <th colspan="3">সময়ের মোট হিসাব</th>
                    <th class="text-right tabular"><?= Bn::money((float) $statement['debit']) ?></th>
                    <th class="text-right tabular"><?= Bn::money((float) $statement['credit']) ?></th>
                    <th class="text-right tabular"><?= Bn::money((float) $statement['closing']) ?></th>
                    <th></th>
                </tr>
            </tfoot>
        </table>
    </div>
    <?php if ($statement['entries'] === []): ?>
        <div class="empty-state"><p>এই সময়ে কোনো লেনদেন নেই।</p></div>
    <?php endif; ?>
</section>
<?php endif; ?>

<div class="modal-overlay" id="ledgerEntryModal" aria-hidden="true">
    <div class="modal-panel" role="dialog" aria-modal="true" aria-labelledby="ledgerEntryTitle">
        <div class="modal-head">
            <div>
                <h2 id="ledgerEntryTitle" class="section-title">খাতায় লেনদেন যোগ করুন</h2>
                <p class="section-subtitle">পেমেন্ট যোগ করলে দেনা কমে। লট ক্রয় স্বয়ংক্রিয়ভাবে খাতায় যুক্ত হয়।</p>
            </div>
            <button type="button" class="icon-btn" data-modal-close aria-label="বন্ধ করুন">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>
        <form id="ledgerEntryForm" class="modal-form" novalidate>
            <div class="modal-body">
                <div class="form-grid">
                    <div class="form-group span-2">
                        <label for="le_company">কোম্পানি <span class="req">*</span></label>
                        <select id="le_company" name="company_id" required>
                            <?php foreach ($summary as $c): ?>
                                <option value="<?= (int) $c['id'] ?>" <?= $companyId === $c['id'] ? 'selected' : '' ?>><?= e($c['name']) ?></option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    <div class="form-group">
                        <label for="le_type">ধরন <span class="req">*</span></label>
                        <select id="le_type" name="type">
                            <option value="payment">কোম্পানিকে পেমেন্ট</option>
                            <option value="adjustment">সমন্বয় (Adjustment)</option>
                        </select>
                    </div>
                    <div class="form-group" data-adjust-only hidden>
                        <label for="le_side">সমন্বয়ের দিক</label>
                        <select id="le_side" name="side">
                            <option value="credit">ক্রেডিট (দেনা কমান)</option>
                            <option value="debit">ডেবিট (দেনা বাড়ান)</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label for="le_amount">পরিমাণ (৳) <span class="req">*</span></label>
                        <input id="le_amount" name="amount" type="number" min="0.01" step="0.01" required>
                    </div>
                    <div class="form-group">
                        <label for="le_date">তারিখ <span class="req">*</span></label>
                        <input id="le_date" name="date" type="date" value="<?= date('Y-m-d') ?>" max="<?= date('Y-m-d') ?>" required>
                    </div>
                    <div class="form-group span-2">
                        <label for="le_note">নোট</label>
                        <input id="le_note" name="note" type="text" maxlength="255" placeholder="যেমন: বিকাশ / ব্যাংক রেফারেন্স">
                    </div>
                </div>
            </div>
            <div class="modal-error" data-form-error hidden></div>
            <div class="modal-foot">
                <button type="button" class="btn btn-secondary" data-modal-close>বাতিল</button>
                <button type="submit" class="btn btn-primary">সংরক্ষণ করুন</button>
            </div>
        </form>
    </div>
</div>
<?php endif; ?>
<?php $this->endSection(); ?>
