<?php $this->extend('partner.layouts.main'); ?>

<?php
use App\Support\Bn;
use App\Support\Product as _;
$extraProducts = array_map(static fn(array $p): array => [
    'id' => $p['id'], 'name' => $p['name'], 'company' => $p['company'], 'unit_type' => $p['unit_type'],
    'qty_per_unit' => $p['qty_per_unit'], 'stock_pcs' => $p['stock_pcs'],
], $products);
?>

<?php $this->section('topbar_actions'); ?>
<button type="button" class="btn btn-primary btn-sm" data-new-trip>
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M12 5v14M5 12h14"/></svg>
    <span>নতুন ট্রিপ</span>
</button>
<?php $this->endSection(); ?>

<?php $this->section('content'); ?>
<div
    id="tripsApp"
    data-date="<?= e($date) ?>"
    data-trips="<?= e(json_encode($trips, JSON_UNESCAPED_UNICODE)) ?>"
    data-products="<?= e(json_encode($extraProducts, JSON_UNESCAPED_UNICODE)) ?>"
>
    <section id="tripsGridSection">
        <form class="toolbar-card" method="GET" action="<?= e(url('/partner/trips')) ?>" data-spa-get>
            <div class="toolbar-filters">
                <label class="date-field"><span class="muted small">ডেলিভারি তারিখ</span><input type="date" name="date" value="<?= e($date) ?>" class="select-input" data-auto-submit></label>
                <a href="<?= e(url('/partner/trips')) ?>" class="text-link small">আজ</a>
            </div>
            <span class="muted small tabular"><strong><?= Bn::num(count($trips)) ?></strong>টি ট্রিপ</span>
        </form>

        <div class="trips-grid" id="tripsGrid">
            <button type="button" class="trip-box trip-new-box" data-new-trip>
                <span class="trip-new-icon" aria-hidden="true">
                    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 5v14M5 12h14"/></svg>
                </span>
                <strong>+ নতুন ট্রিপ</strong>
                <span class="muted small">SR-এর অর্ডার DSR-কে দিন</span>
            </button>
        </div>
    </section>

    <section id="tripDetailSection" hidden>
        <div class="detail-bar">
            <button type="button" class="btn btn-secondary btn-sm" id="backToTripsBtn">← ট্রিপ তালিকায় ফিরুন</button>
            <div class="detail-bar-meta">
                <span id="tripDetailStatusBadge" class="badge badge-warning">অপেক্ষমান</span>
                <span class="muted small tabular" id="tripCheckCounter">০ / ০ যাচাইকৃত</span>
            </div>
        </div>

        <article class="card trip-detail-card">
            <div class="trip-detail-head">
                <div>
                    <h2 class="section-title" id="tripDetailTitle">DSR ট্রিপ</h2>
                    <p class="section-subtitle" id="tripDetailSubtitle"></p>
                    <div class="trip-sr-pills" id="tripDetailSrs"></div>
                </div>
                <button type="button" class="btn btn-primary" id="dispatchTripBtn" disabled>ডিসপ্যাচ করুন</button>
            </div>

            <div class="checklist-head" aria-hidden="true">
                <span></span><span>পণ্য</span><span class="text-right">অর্ডার</span><span>লোড (পিস)</span><span class="text-right">পার্থক্য</span><span></span>
            </div>
            <div class="checklist-wrap" id="tripProductList"></div>

            <div class="trip-add-extra" id="tripAddExtra">
                <select id="extraProductSelect" class="select-input" aria-label="অতিরিক্ত পণ্য"></select>
                <input type="number" id="extraProductPcs" class="select-input" min="1" step="1" placeholder="পিস" aria-label="অতিরিক্ত পিস">
                <button type="button" class="btn btn-secondary btn-sm" id="addExtraBtn">+ পণ্য যোগ করুন</button>
                <span class="muted small">রেডি সেলের জন্য ভ্যানে অতিরিক্ত পণ্য যোগ করুন</span>
            </div>
        </article>
    </section>
</div>

<!-- New Trip Modal -->
<div class="modal-overlay" id="newTripModal" aria-hidden="true">
    <div class="modal-panel modal-lg" role="dialog" aria-modal="true" aria-labelledby="newTripModalTitle">
        <div class="modal-head">
            <div>
                <h2 id="newTripModalTitle" class="section-title">ট্রিপ তৈরি / যুক্ত করুন</h2>
                <p class="section-subtitle">অর্ডার তারিখের SR অর্ডার নির্বাচন করে একটি DSR-এর ডেলিভারি ট্রিপে দিন</p>
            </div>
            <button type="button" class="icon-btn" data-modal-close aria-label="বন্ধ করুন">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>

        <form id="newTripForm" class="modal-form">
            <div class="two-col-picker">
                <div class="picker-col">
                    <div class="picker-col-head">
                        <strong>সেলসম্যান (SR)</strong>
                        <span class="muted small">একাধিক নির্বাচন · <span id="selectedSrCount">০</span>টি নির্বাচিত</span>
                    </div>
                    <label class="picker-date"><span class="muted small">অর্ডার তারিখ</span><input type="date" id="tripOrderDate" class="select-input" value="<?= date('Y-m-d') ?>"></label>
                    <div class="picker-list" id="srPickerList"></div>
                </div>
                <div class="picker-col">
                    <div class="picker-col-head">
                        <strong>ডেলিভারিম্যান (DSR)</strong>
                        <span class="muted small">একজন নির্বাচন করুন</span>
                    </div>
                    <label class="picker-date"><span class="muted small">ডেলিভারি তারিখ</span><input type="date" id="tripDeliveryDate" class="select-input" value="<?= e(max($date, date('Y-m-d'))) ?>"></label>
                    <div class="picker-list" id="dsrPickerList"></div>
                </div>
            </div>
            <div class="modal-error" id="newTripError" hidden></div>
            <div class="modal-foot">
                <button type="button" class="btn btn-secondary" data-modal-close>বাতিল</button>
                <button type="submit" class="btn btn-primary" id="createTripSubmitBtn">DSR-কে অর্ডার দিন</button>
            </div>
        </form>
    </div>
</div>
<?php $this->endSection(); ?>
