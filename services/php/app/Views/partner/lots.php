<?php $this->extend('partner.layouts.main'); ?>

<?php
use App\Support\Bn;
$lotProducts = array_map(static fn(array $p): array => [
    'id' => $p['id'], 'company_id' => $p['company_id'], 'name' => $p['name'], 'unit_type' => $p['unit_type'],
    'qty_per_unit' => $p['qty_per_unit'], 'company_price_pc' => $p['company_price_pc'],
], $products);
?>

<?php $this->section('topbar_actions'); ?>
<button type="button" class="btn btn-primary btn-sm" data-lot-add>
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M12 5v14M5 12h14"/></svg>
    <span>লট যোগ করুন</span>
</button>
<?php $this->endSection(); ?>

<?php $this->section('content'); ?>
<section class="panel" id="lotsApp" data-products="<?= e(json_encode($lotProducts, JSON_UNESCAPED_UNICODE)) ?>">
    <div class="toolbar">
        <div class="toolbar-filters">
            <div class="search-box">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
                <input type="search" id="lotSearch" placeholder="লট আইডি বা কোম্পানি খুঁজুন…" autocomplete="off">
            </div>
            <select id="lotCompanyFilter" class="select-input" aria-label="কোম্পানি অনুযায়ী ফিল্টার">
                <option value="">সব কোম্পানি</option>
                <?php foreach ($companies as $cmp): ?>
                    <option value="<?= (int) $cmp['id'] ?>"><?= e($cmp['name']) ?></option>
                <?php endforeach; ?>
            </select>
        </div>
        <span class="muted small tabular"><strong id="lotCount"><?= Bn::num(count($lots)) ?></strong>টি লট</span>
    </div>

    <div class="table-wrap">
        <table class="data-table">
            <thead>
                <tr>
                    <th>লট আইডি</th>
                    <th>কোম্পানি</th>
                    <th>তারিখ</th>
                    <th class="text-right">পণ্য</th>
                    <th class="text-right">মোট পিস</th>
                    <th class="text-right">মোট মূল্য</th>
                    <th>নিকটতম মেয়াদ</th>
                    <th class="text-right">অ্যাকশন</th>
                </tr>
            </thead>
            <tbody id="lotsTbody">
                <?php foreach ($lots as $lot): ?>
                    <tr
                        data-lot-row
                        data-company="<?= (int) $lot['company_id'] ?>"
                        data-search="<?= e(strtolower($lot['code'] . ' ' . $lot['company'] . ' ' . $lot['date'])) ?>"
                        data-lot="<?= e(json_encode($lot, JSON_UNESCAPED_UNICODE)) ?>"
                    >
                        <td class="mono"><?= e(Bn::digits($lot['code'])) ?></td>
                        <td class="cell-primary"><?= e($lot['company']) ?></td>
                        <td class="tabular nowrap"><?= e(Bn::date($lot['date'])) ?></td>
                        <td class="text-right tabular"><?= Bn::num((int) $lot['items_count']) ?></td>
                        <td class="text-right tabular"><?= Bn::num((int) $lot['total_pcs']) ?></td>
                        <td class="text-right tabular"><strong><?= Bn::money((float) $lot['total_value']) ?></strong></td>
                        <td class="tabular nowrap"><?= e($lot['nearest_expiry'] ? Bn::date($lot['nearest_expiry']) : '—') ?></td>
                        <td class="text-right nowrap">
                            <button type="button" class="btn btn-secondary btn-xs" data-view-lot>পণ্য দেখুন</button>
                            <?php if ($lot['deletable']): ?>
                                <button type="button" class="btn btn-danger-soft btn-xs" data-delete-lot>মুছুন</button>
                            <?php endif; ?>
                        </td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>

    <div class="empty-state" id="lotsEmpty" <?= $lots ? 'hidden' : '' ?>>
        <p><?= $lots ? 'ফিল্টারের সাথে কোনো লট মিলছে না।' : 'এখনো কোনো লট গ্রহণ করা হয়নি।' ?></p>
    </div>
</section>

<!-- Add Lot Modal -->
<div class="modal-overlay" id="addLotModal" aria-hidden="true">
    <div class="modal-panel modal-xl" role="dialog" aria-modal="true" aria-labelledby="addLotModalTitle">
        <div class="modal-head">
            <div>
                <h2 id="addLotModalTitle" class="section-title">নতুন লট যোগ করুন</h2>
            </div>
            <button type="button" class="icon-btn" data-modal-close aria-label="বন্ধ করুন">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>

        <form id="addLotForm" class="modal-form" novalidate>
            <div class="modal-body">
                <div class="form-grid">
                    <div class="form-group">
                        <label for="lot_company">কোম্পানি <span class="req">*</span></label>
                        <select id="lot_company" name="company_id" required>
                            <option value="">কোম্পানি নির্বাচন করুন</option>
                            <?php foreach ($companies as $cmp): ?>
                                <option value="<?= (int) $cmp['id'] ?>"><?= e($cmp['name']) ?></option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    <div class="form-group">
                        <label for="lot_date">গ্রহণের তারিখ <span class="req">*</span></label>
                        <input id="lot_date" name="lot_date" type="date" value="<?= date('Y-m-d') ?>" max="<?= date('Y-m-d') ?>" required>
                    </div>
                    <div class="form-group span-2">
                        <label for="lot_notes">নোট</label>
                        <input id="lot_notes" name="notes" type="text" maxlength="255" placeholder="ঐচ্ছিক (ইনভয়েস নং, গাড়ি নং…)">
                    </div>
                </div>

                <div class="lot-rows-section">
                    <div class="lot-rows-head">
                        <strong>লটের পণ্যসমূহ</strong>
                        <button type="button" class="btn btn-secondary btn-xs" id="addLotRowBtn">+ নতুন সারি</button>
                    </div>
                    <div class="lot-rows-labels" aria-hidden="true">
                        <span>পণ্য</span>
                        <span>পরিমাণ (পিস)</span>
                        <span>কোম্পানি মূল্য / পিস (৳)</span>
                        <span>মেয়াদ শেষের তারিখ</span>
                        <span></span>
                    </div>
                    <div class="lot-rows-list" id="lotRowsContainer"></div>
                    <div class="lot-total-bar">
                        <span class="muted small">মোট লট মূল্য</span>
                        <strong class="tabular" id="lotEstimatedTotal">৳ ০</strong>
                    </div>
                </div>
            </div>
            <div class="modal-error" data-form-error hidden></div>
            <div class="modal-foot">
                <button type="button" class="btn btn-secondary" data-modal-close>বাতিল</button>
                <button type="submit" class="btn btn-primary">লট সংরক্ষণ করুন</button>
            </div>
        </form>
    </div>
</div>

<!-- Lot Items Detail Modal -->
<div class="modal-overlay" id="lotDetailModal" aria-hidden="true">
    <div class="modal-panel modal-lg" role="dialog" aria-modal="true" aria-labelledby="lotDetailTitle">
        <div class="modal-head">
            <div>
                <h2 id="lotDetailTitle" class="section-title">লটের বিবরণ</h2>
                <p id="lotDetailSub" class="section-subtitle"></p>
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
                            <th class="text-right">অবশিষ্ট</th>
                            <th class="text-right">দর / পিস</th>
                            <th class="text-right">মোট</th>
                            <th>মেয়াদ</th>
                        </tr>
                    </thead>
                    <tbody id="lotDetailTbody"></tbody>
                </table>
            </div>
        </div>
        <div class="modal-foot">
            <button type="button" class="btn btn-secondary" data-modal-close>বন্ধ করুন</button>
        </div>
    </div>
</div>
<?php $this->endSection(); ?>
