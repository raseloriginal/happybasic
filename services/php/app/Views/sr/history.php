<?php $this->extend('sr.layouts.main'); ?>

<?php use App\Support\Bn; ?>

<?php $this->section('content'); ?>
<div
    id="historyApp"
    class="sr-history-page"
    data-default-date="<?= e($date) ?>"
    data-today="<?= e($today) ?>"
    data-sr-name="<?= e($currentSr['name'] ?? '') ?>"
    data-sr-company="<?= e($currentSr['company'] ?? '') ?>"
    data-sr-partner="<?= e($currentSr['partner'] ?? '') ?>"
    data-sr-area="<?= e($currentSr['area'] ?? '') ?>"
    data-orders="<?= e(json_encode($orders, JSON_UNESCAPED_UNICODE)) ?>"
>
    <div class="hp-sky" aria-hidden="true" style="--sky-h: 250px"></div>
    <h1 class="sr-plain-title">অর্ডার হিস্ট্রি</h1>

    <div class="hs-datebar">
        <button type="button" class="hs-arrow" id="historyPrevBtn" aria-label="আগের দিন">‹</button>
        <label class="hs-date" for="historyDateInput" title="তারিখ নির্বাচন করুন">
            <strong id="historyDateDisplay"><?= e(Bn::date($date)) ?></strong>
            <span id="historySubSummary">তারিখ বদলাতে ট্যাপ করুন</span>
            <input type="date" id="historyDateInput" value="<?= e($date) ?>" max="<?= e($today) ?>" class="date-hidden-input" aria-label="তারিখ নির্বাচন করুন">
        </label>
        <button type="button" class="hs-arrow" id="historyNextBtn" aria-label="পরের দিন">›</button>
    </div>

    <section class="hs-sum">
        <div class="hs-sum-l"><span>মোট অর্ডার</span><strong class="tabular" id="historyDayTotal">৳ ০</strong></div>
        <div class="hs-chip is-blue-soft"><b class="tabular" id="historyOrderCount">০</b><span>মেমো</span></div>
        <div class="hs-chip"><b class="tabular" id="historyDayOc">+৳ ০</b><span>নিট O/C</span></div>
    </section>

    <div class="hs-list" id="historyList"></div>
    <div class="card empty-state" id="historyEmpty" hidden>
        <p>এই তারিখে কোনো দোকানের অর্ডার পাওয়া যায়নি।</p>
    </div>
</div>

<!-- Order Detail & Cash Memo Modal (Screen 6 & 6b: আমার কপি | দোকানের কপি) -->
<div class="modal-overlay modal-top" id="orderDetailModal" aria-hidden="true">
    <div class="modal-panel modal-tall om-detail-modal" role="dialog" aria-modal="true" aria-labelledby="orderDetailRetailer">
        <div class="modal-head om-detail-head">
            <div class="modal-head-left">
                <button type="button" class="icon-btn icon-btn-round" data-modal-close aria-label="হিস্ট্রিতে ফিরুন">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="m15 18-6-6 6-6"/></svg>
                </button>
                <div>
                    <h2 id="orderDetailRetailer" class="section-title om-shop-title">দোকানের অর্ডার</h2>
                    <p id="orderDetailSub" class="section-subtitle tabular"></p>
                </div>
            </div>
            <span class="badge badge-neutral" id="orderDetailStatus">অপেক্ষমান</span>
        </div>

        <div class="om-tabs-wrap">
            <div class="om-tabs" role="tablist" aria-label="মেমো কপি বাছুন">
                <button type="button" class="om-tab-btn is-active" id="omTabMyBtn" data-om-tab="my" role="tab" aria-selected="true">আমার কপি</button>
                <button type="button" class="om-tab-btn" id="omTabShopBtn" data-om-tab="shop" role="tab" aria-selected="false">দোকানের কপি</button>
            </div>
        </div>

        <div class="modal-body om-detail-body" id="orderDetailPrintable">
            <!-- Tab 1: SR Personal Copy (Timeline + Per-item cards with Over/Commission + Summary) -->
            <div id="omPanelMy" class="om-panel">
                <div class="card om-timeline-card" id="omDetailTimeline"></div>
                <div class="om-items-cards" id="omDetailItemsCards"></div>
                <div class="card om-summary-card" id="omDetailSummaryCard"></div>
            </div>

            <!-- Tab 2: Formal Distributor / Shop Copy Memo -->
            <div id="omPanelShop" class="om-panel" hidden>
                <div class="shop-memo-sheet" id="omShopMemoSheet"></div>
            </div>
        </div>

        <div class="os-actions om-detail-foot">
            <button type="button" class="btn btn-secondary os-btn" id="omSecondaryBtn">
                <span>দোকানের কপি</span>
            </button>
            <button type="button" class="btn btn-navy os-btn" id="omPrintBtn">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 6 2 18 2 18 9"/><path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><rect x="6" y="14" width="12" height="8"/></svg>
                <span>প্রিন্ট</span>
            </button>
        </div>
    </div>
</div>
<?php $this->endSection(); ?>
