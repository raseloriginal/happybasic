<?php $this->extend('sr.layouts.main'); ?>

<?php $this->section('content'); ?>
<div
    class="order-map-stage"
    id="orderApp"
    data-fullscreen-map="1"
    data-sr-name="<?= e($currentSr['name'] ?? '') ?>"
    data-sr-company="<?= e($currentSr['company'] ?? '') ?>"
    data-sr-location="<?= e(json_encode($srLocation, JSON_UNESCAPED_UNICODE)) ?>"
    data-retailers="<?= e(json_encode($retailers, JSON_UNESCAPED_UNICODE)) ?>"
    data-products="<?= e(json_encode($products ?? [], JSON_UNESCAPED_UNICODE)) ?>"
    data-day="<?= e(json_encode($day, JSON_UNESCAPED_UNICODE)) ?>"
>
    <!-- Full-screen Map Container -->
    <div id="retailerMap" class="retailer-map" aria-label="দোকান ম্যাপ"></div>

    <!-- Floating Top Bar: Back + Search Pill + Today + Add Retailer -->
    <div class="map-topbar">
        <a href="<?= e(url('/sr/dashboard')) ?>" class="map-back-btn" aria-label="হোমে ফিরুন">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="m15 18-6-6 6-6"/></svg>
        </a>

        <div class="map-search-box" id="retailerSearchBox">
            <svg class="search-icon" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
            <input type="search" id="retailerSearchInput" placeholder="দোকান খুঁজুন (বাংলা / Banglish)…" autocomplete="off">
            <span class="search-spinner" id="retailerSearchSpinner" aria-hidden="true" hidden></span>
            <button type="button" class="search-clear-btn" id="retailerSearchClear" aria-label="খোঁজা মুছুন" hidden>&times;</button>
        </div>

        <button type="button" class="btn btn-secondary today-btn" id="openTodayOrdersBtn" title="আজকের অর্ডার">
            <span id="todayBtnLabel">আজ</span>
        </button>

        <button type="button" class="btn btn-navy" id="openAddRetailerBtn">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4"><path d="M12 5v14M5 12h14"/></svg>
            <span>নতুন দোকান</span>
        </button>

        <div class="search-suggest-box" id="retailerSuggestBox" role="listbox" aria-label="দোকানের সাজেশন" hidden></div>
    </div>

    <!-- Floating Pin-Placement Banner -->
    <div class="pin-picker-banner" id="pinPickerBanner" hidden>
        <div class="pin-picker-info">
            <strong>দোকানের পিন বসাতে ম্যাপে ট্যাপ করুন</strong>
            <span class="mono small" id="pinPickerCoords">ম্যাপের যেকোনো জায়গায় ট্যাপ করুন</span>
        </div>
        <div class="pin-picker-actions">
            <button type="button" class="btn btn-secondary btn-sm" id="cancelPinBtn">বাতিল</button>
            <button type="button" class="btn btn-cobalt btn-sm" id="confirmPinBtn" disabled>পিন নিশ্চিত করুন</button>
        </div>
    </div>

    <!-- Bottom Sheet: Nearby Retailers -->
    <section class="nearby-sheet" id="nearbySheet" aria-label="কাছাকাছি দোকান">
        <div class="nearby-sheet-head">
            <div class="nearby-title-wrap">
                <h2 class="section-title" id="nearbySheetTitle">কাছের দোকান</h2>
                <span class="nearby-pending-text tabular" id="nearbyPendingSummary">· ০টি</span>
                <span class="badge badge-info tabular" id="nearbyScopeBadge">৫০ মি.</span>
                <span class="nearby-sync-pill" id="nearbySyncPill" hidden>
                    <span class="sync-dot" aria-hidden="true"></span>
                    <span>লোড হচ্ছে…</span>
                </span>
                <span class="badge badge-neutral tabular" id="nearbyCount" hidden>০</span>
            </div>
            <div class="nearby-head-actions">
                <button type="button" class="btn btn-ghost btn-xs" id="recenterMapBtn" title="আমার অবস্থানে আনুন">সেন্টার</button>
                <button type="button" class="icon-btn icon-btn-round" id="toggleNearbyBtn" aria-expanded="true" aria-label="তালিকা ছোট/বড় করুন">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m6 9 6 6 6-6"/></svg>
                </button>
            </div>
        </div>

        <div class="nearby-list" id="nearbyRetailersList"></div>
    </section>
</div>

<!-- Add Retailer Modal -->
<div class="modal-overlay" id="addRetailerModal" aria-hidden="true">
    <div class="modal-panel" role="dialog" aria-modal="true" aria-labelledby="addRetailerTitle">
        <div class="sheet-handle-wrap"><span class="sheet-handle"></span></div>
        <div class="modal-head">
            <div>
                <h2 id="addRetailerTitle" class="section-title">নতুন দোকান যোগ করুন</h2>
                <p class="section-subtitle">নতুন দোকান নিবন্ধন করুন ও ম্যাপে অবস্থান পিন করুন</p>
            </div>
            <button type="button" class="icon-btn icon-btn-round" id="closeAddRetailerBtn" data-modal-close aria-label="বন্ধ করুন">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>

        <form id="addRetailerForm" class="modal-form" method="POST" action="<?= e(url('/sr/order/retailers')) ?>" novalidate>
            <?= csrf_field() ?>
            <input type="hidden" id="ret_lat" name="lat" value="">
            <input type="hidden" id="ret_lng" name="lng" value="">

            <div class="modal-body">
                <div class="form-group">
                    <label for="ret_name">দোকানের নাম <span class="req">*</span></label>
                    <input id="ret_name" name="name" type="text" placeholder="যেমন: এনামুল স্টোর" required>
                </div>

                <div class="form-group">
                    <div class="label-row">
                        <label for="ret_location">ঠিকানা / অবস্থান <span class="req">*</span></label>
                        <button type="button" class="text-link small" id="pickOnMapBtn">
                            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" style="vertical-align:-1px"><path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/></svg>
                            ম্যাপে পিন দিন
                        </button>
                    </div>
                    <div class="input-with-action">
                        <input id="ret_location" name="location" type="text" placeholder="ঠিকানা লিখুন বা ম্যাপে পিন দিন" required>
                        <button type="button" class="input-action-btn" id="pickOnMapInlineBtn" title="ম্যাপে পিন বসান">ম্যাপ পিন</button>
                    </div>
                    <small class="muted small" id="retPinHint">সঠিক লোকেশন দিতে "ম্যাপে পিন দিন" ব্যবহার করুন।</small>
                </div>
            </div>

            <div class="modal-error" id="addRetailerError" hidden></div>

            <div class="modal-foot">
                <button type="button" class="btn btn-secondary" id="cancelAddRetailerBtn" data-modal-close>বাতিল</button>
                <button type="submit" class="btn btn-cobalt" id="saveRetailerBtn">সংরক্ষণ করুন</button>
            </div>
        </form>
    </div>
</div>

<!-- Step 2: Retailer Products Selection Modal (Grid / List + Sticky Bottom Bar) -->
<div class="modal-overlay" id="retailerProductsModal" aria-hidden="true">
    <div class="modal-panel modal-tall rp-modal-panel" role="dialog" aria-modal="true" aria-labelledby="rpRetailerName">
        <div class="modal-head rp-modal-head">
            <div class="modal-head-left">
                <button type="button" class="icon-btn icon-btn-round" data-close-modal="retailerProductsModal" aria-label="ম্যাপে ফিরুন">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="m15 18-6-6 6-6"/></svg>
                </button>
                <div>
                    <h2 id="rpRetailerName" class="section-title rp-shop-title">পণ্য নির্বাচন করুন</h2>
                    <p id="rpRetailerSub" class="section-subtitle"></p>
                </div>
            </div>
            <div class="rp-view-switch" role="group" aria-label="দেখার ধরন">
                <button type="button" class="rp-view-btn is-active" id="rpViewGridBtn" data-rp-view="grid">
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg>
                    <span>গ্রিড</span>
                </button>
                <button type="button" class="rp-view-btn" id="rpViewListBtn" data-rp-view="list">
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/></svg>
                    <span>লিস্ট</span>
                </button>
            </div>
        </div>

        <div class="rp-search-wrap">
            <div class="rp-search-box" id="rpProductSearchBox">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
                <input type="search" id="rpProductSearch" placeholder="পণ্য খুঁজুন (বাংলা / Banglish)…" autocomplete="off">
                <span class="search-spinner" id="rpProductSearchSpinner" aria-hidden="true" hidden></span>
                <button type="button" class="search-clear-btn" id="rpProductSearchClear" aria-label="খোঁজা মুছুন" hidden>&times;</button>
            </div>
            <div class="search-suggest-box" id="rpProductSuggestBox" role="listbox" aria-label="পণ্যের সাজেশন" hidden></div>
        </div>

        <div class="modal-body rp-body">
            <div class="sr-products-grid" id="srProductsGrid"></div>
        </div>

        <!-- Sticky Bottom Total + Send Order Bar -->
        <div class="rp-bottom-bar" id="floatingCartWrap">
            <div class="rp-bottom-left">
                <span class="rp-bottom-label">মোট</span>
                <div class="rp-bottom-val-row">
                    <strong class="rp-bottom-total tabular" id="rpCartTotal">৳ ০</strong>
                    <span class="rp-bottom-badge tabular" id="cartFloatBadge" hidden>০টি</span>
                </div>
            </div>
            <button type="button" class="btn btn-cobalt rp-send-btn" id="openCartReviewBtn" disabled>অর্ডার পাঠান</button>
        </div>
    </div>
</div>

<!-- Order Cart Review Bottom Sheet -->
<div class="modal-overlay modal-top" id="orderCartModal" aria-hidden="true">
    <div class="modal-panel" role="dialog" aria-modal="true" aria-labelledby="ocRetailerTitle">
        <div class="sheet-handle-wrap"><span class="sheet-handle"></span></div>
        <div class="modal-head oc-modal-head">
            <div class="oc-head-title">
                <svg class="oc-cart-svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1"><circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/><path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6"/></svg>
                <h2 id="ocRetailerTitle" class="section-title">অর্ডার সারাংশ</h2>
            </div>
            <button type="button" class="icon-btn icon-btn-round" data-close-modal="orderCartModal" aria-label="বন্ধ করুন">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>

        <div class="modal-body oc-modal-body">
            <div class="panel">
                <div class="table-wrap">
                    <table class="data-table cart-review-table">
                        <thead>
                            <tr>
                                <th>পণ্য</th>
                                <th class="text-center">পরিমাণ</th>
                                <th class="text-right">মূল্য</th>
                                <th class="text-center">মুছুন</th>
                            </tr>
                        </thead>
                        <tbody id="ocTableBody"></tbody>
                    </table>
                </div>
            </div>
        </div>

        <div class="oc-confirm-footer">
            <div class="cart-confirm-card">
                <div class="cart-confirm-meta">
                    <div class="cart-confirm-oc tabular" id="ocSummaryOc">O/C ০</div>
                    <div class="cart-confirm-sub">মোট: <strong class="tabular" id="ocSummarySubtotal">৳ ০</strong></div>
                </div>
                <button type="button" class="btn btn-cobalt btn-confirm-order" id="confirmOrderBtn">অর্ডার কনফার্ম</button>
            </div>
            <button type="button" class="btn btn-ghost btn-sm cancel-order-btn" id="cancelOrderBtn" hidden>অর্ডারটি বাতিল করুন</button>
        </div>
    </div>
</div>

<!-- Product Quantity / Price / O/C Modal -->
<div class="modal-overlay modal-top" id="productOrderModal" aria-hidden="true">
    <div class="modal-panel" role="dialog" aria-modal="true" aria-labelledby="poProductName">
        <div class="sheet-handle-wrap"><span class="sheet-handle"></span></div>
        <div class="modal-head">
            <div>
                <h2 id="poProductName" class="section-title">পণ্য</h2>
                <p id="poProductSub" class="section-subtitle"></p>
            </div>
            <button type="button" class="icon-btn icon-btn-round" data-close-modal="productOrderModal" aria-label="বন্ধ করুন">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>

        <form id="productOrderForm" class="modal-form" novalidate>
            <div class="modal-body">
                <div class="form-group">
                    <label>অর্ডারের ধরন</label>
                    <div class="unit-toggle" role="radiogroup" aria-label="ইউনিট বা পিস">
                        <button type="button" class="unit-toggle-btn is-active" data-order-mode="unit" id="poModeUnitBtn">ইউনিট</button>
                        <button type="button" class="unit-toggle-btn" data-order-mode="pcs" id="poModePcsBtn">পিস</button>
                    </div>
                </div>

                <div class="po-unit-pcs-grid" id="poUnitQtyGroup">
                    <div class="form-group">
                        <label for="poUnitQtyInput" id="poUnitQtyLabel">ইউনিট</label>
                        <div class="qty-stepper qty-stepper-sm">
                            <button type="button" class="qty-step-btn" id="poUnitMinus" aria-label="ইউনিট কমান">−</button>
                            <input id="poUnitQtyInput" type="number" min="0" step="1" value="1" inputmode="numeric">
                            <button type="button" class="qty-step-btn" id="poUnitPlus" aria-label="ইউনিট বাড়ান">+</button>
                        </div>
                    </div>

                    <div class="form-group">
                        <label for="poExtraPcsInput">পিস</label>
                        <div class="qty-stepper qty-stepper-sm">
                            <button type="button" class="qty-step-btn" id="poExtraPcsMinus" aria-label="অতিরিক্ত পিস কমান">−</button>
                            <input id="poExtraPcsInput" type="number" min="0" step="1" value="0" inputmode="numeric">
                            <button type="button" class="qty-step-btn" id="poExtraPcsPlus" aria-label="অতিরিক্ত পিস বাড়ান">+</button>
                        </div>
                    </div>
                </div>

                <div class="form-group" id="poPcsQtyGroup" hidden>
                    <label for="poQtyInput">পরিমাণ (পিস)</label>
                    <div class="qty-stepper">
                        <button type="button" class="qty-step-btn" id="poQtyMinus" aria-label="পরিমাণ কমান">−</button>
                        <input id="poQtyInput" type="number" min="1" step="1" value="1" inputmode="numeric">
                        <button type="button" class="qty-step-btn" id="poQtyPlus" aria-label="পরিমাণ বাড়ান">+</button>
                    </div>
                </div>

                <div class="po-price-grid">
                    <div class="form-group">
                        <div class="label-row">
                            <label for="poRateInput" id="poRateLabel">প্রতি ইউনিট দর (৳)</label>
                        </div>
                        <input id="poRateInput" type="number" min="0" step="0.01" inputmode="decimal" required>
                        <small class="muted small tabular" id="poBaseRateHint">বেজ: ৳ ০</small>
                    </div>

                    <div class="form-group">
                        <div class="label-row">
                            <label for="poTotalInput">মোট টাকা (৳)</label>
                        </div>
                        <input id="poTotalInput" type="number" min="0" step="0.01" inputmode="decimal" required>
                        <small class="muted small tabular" id="poStdTotalHint">নির্ধারিত: ৳ ০</small>
                    </div>
                </div>

                <div class="oc-summary-box" id="poOcBox">
                    <div>
                        <span class="muted small">হিসাবকৃত O/C</span>
                        <small class="oc-caption" id="poOcCaption">নির্ধারিত দর</small>
                    </div>
                    <strong class="oc-amount tabular" id="poOcValue">৳ ০</strong>
                </div>
            </div>

            <div class="modal-foot po-modal-foot">
                <button type="button" class="btn btn-danger-ghost btn-sm" id="poRemoveItemBtn" hidden>সরান</button>
                <div class="po-foot-right">
                    <button type="button" class="btn btn-secondary" data-close-modal="productOrderModal">বাতিল</button>
                    <button type="submit" class="btn btn-cobalt" id="poSaveItemBtn">অর্ডারে যোগ করুন</button>
                </div>
            </div>
        </form>
    </div>
</div>

<!-- Step 3: Order Confirmed & Memo Receipt Screen -->
<div class="modal-overlay modal-top" id="orderSuccessModal" aria-hidden="true">
    <div class="modal-panel modal-tall os-receipt-modal" role="dialog" aria-modal="true" aria-labelledby="osTitle">
        <div class="modal-body os-receipt-scroll">
            <div class="os-hero-clean">
                <div class="os-check-circle" aria-hidden="true">
                    <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                </div>
                <h2 id="osTitle" class="os-title">অর্ডার পাঠানো হয়েছে</h2>
                <p class="os-subtitle" id="osRetailerSubtitle">অর্ডার কনফার্ম হয়েছে</p>
            </div>

            <!-- Memo / Order Receipt Card -->
            <div class="os-memo-card">
                <div class="os-memo-head">
                    <div>
                        <span class="os-memo-kicker">অর্ডার রসিদ</span>
                        <strong class="os-memo-shop" id="osReceiptRetailer">দোকান</strong>
                    </div>
                    <div class="text-right">
                        <span class="os-memo-kicker">মেমো নং</span>
                        <strong class="os-memo-code tabular" id="osReceiptCode">—</strong>
                    </div>
                </div>

                <div class="os-memo-meta">
                    <span class="tabular" id="osReceiptTime">আজ</span>
                    <span id="osReceiptSr">SR: <?= e($currentSr['name'] ?? '') ?> · <?= e($currentSr['company'] ?? '') ?></span>
                </div>

                <div class="os-memo-table-wrap">
                    <table class="data-table os-items-table">
                        <thead>
                            <tr>
                                <th>বিবরণ</th>
                                <th class="text-center">পরিমাণ</th>
                                <th class="text-right">টাকা</th>
                            </tr>
                        </thead>
                        <tbody id="osItemsBody"></tbody>
                    </table>
                </div>

                <div class="os-memo-footer">
                    <div>
                        <span class="os-memo-foot-title">দোকানের মোট</span>
                        <span class="os-memo-foot-sub tabular" id="osTotalOcWrap">ডেলিভারিতে নগদ · O/C <strong id="osTotalOc">৳ ০</strong></span>
                    </div>
                    <strong class="os-memo-grand tabular" id="osTotalCost">৳ ০</strong>
                </div>
            </div>
        </div>

        <div class="os-actions">
            <button type="button" class="btn btn-secondary os-btn" id="undoConfirmedOrderBtn">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 7v6h6"/><path d="M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13"/></svg>
                <span>সম্পাদনা / ফেরত</span>
            </button>
            <button type="button" class="btn btn-cobalt os-btn" id="nextShopBtn">
                <span>অন্য দোকানে যান</span>
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></svg>
            </button>
        </div>
    </div>
</div>

<!-- Today's Orders Sheet -->
<div class="modal-overlay modal-top" id="todayOrdersModal" aria-hidden="true">
    <div class="modal-panel" role="dialog" aria-modal="true" aria-labelledby="todayOrdersTitle">
        <div class="sheet-handle-wrap"><span class="sheet-handle"></span></div>
        <div class="modal-head">
            <div>
                <h2 id="todayOrdersTitle" class="section-title">আজকের অর্ডারসমূহ</h2>
                <p class="section-subtitle" id="todayOrdersSub"></p>
            </div>
            <button type="button" class="icon-btn icon-btn-round" data-close-modal="todayOrdersModal" aria-label="বন্ধ করুন">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>
        <div class="modal-body">
            <div class="day-status" id="dayStatusBox"></div>
            <div class="today-orders-list" id="todayOrdersList"></div>
        </div>
        <div class="oc-confirm-footer">
            <button type="button" class="btn btn-cobalt btn-block" id="completeDayBtn">আজকের অর্ডার সম্পন্ন করুন</button>
            <button type="button" class="btn btn-secondary btn-block" id="reopenDayBtn" hidden>আজকের দিন পুনরায় খুলুন</button>
        </div>
    </div>
</div>
<?php $this->endSection(); ?>
