<?php $this->extend('dsr.layouts.main'); ?>

<?php
use App\Support\Bn;
$dsrLocJson = json_encode($dsrLocation ?? ['lat' => 23.8645, 'lng' => 90.4005], JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT);
$flags = JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT;
$tripJson = json_encode($trip, $flags);
$retailersJson = json_encode($retailers ?? [], $flags);
$damageProductsJson = json_encode($damageProducts ?? [], $flags);
$reasonsList = array_map(static fn(string $r): array => ['value' => $r, 'label' => Bn::cancelReason($r)], $cancelReasons ?? []);
$reasonsJson = json_encode($reasonsList, $flags);
$ordersJson = json_encode($orders ?? [], $flags);
$vanStockJson = json_encode($vanStock ?? [], $flags);
?>

<?php $this->section('content'); ?>
<?php
$activeDate = $selectedDate ?? ($trip['date'] ?? date('Y-m-d'));
$hasTrip = $trip !== null;
$bannerText = '';
$bannerClass = 'trip-state-banner';
if (!$hasTrip) {
    $bannerText = 'এই তারিখে কোনো ডিসপ্যাচ করা ট্রিপ নেই — অন্য তারিখ বাছুন।';
    $bannerClass .= ' is-muted';
} elseif (!$trip['editable']) {
    if ($trip['status_key'] === 'settled') {
        $bannerText = 'এই ট্রিপটি সেটেল হয়ে গেছে — শুধু দেখার জন্য।';
    } else {
        $bannerText = 'সেটেলমেন্টের জন্য জমা দেওয়া হয়েছে — পার্টনার যাচাই করছেন। এখন পরিবর্তন করা যাবে না।';
    }
} elseif ($trip['settlement_status'] === 'returned') {
    $bannerText = 'পার্টনার ফেরত পাঠিয়েছেন' . ($trip['review_note'] ? ': ' . $trip['review_note'] : '') . '। সংশোধন করে পুনরায় জমা দিন।';
    $bannerClass .= ' is-returned';
}
?>
<section
    class="delivery-map-stage"
    id="dsrDeliveryApp"
    data-dsr-location="<?= e($dsrLocJson) ?>"
    data-dsr-photo="<?= e(!empty($currentDsr['photo_path']) ? url($currentDsr['photo_path']) : '') ?>"
    data-trip="<?= e($tripJson) ?>"
    data-selected-date="<?= e($activeDate) ?>"
    data-reasons="<?= e($reasonsJson) ?>"
    data-orders="<?= e($ordersJson) ?>"
    data-van-stock="<?= e($vanStockJson) ?>"
    data-retailers="<?= e($retailersJson) ?>"
    data-damage-products="<?= e($damageProductsJson) ?>"
>
    <!-- Floating Top Bar: Interactive Date Switcher + Ready Sale -->
    <div class="map-topbar">
        <div class="map-date-nav" title="তারিখ পরিবর্তন করুন">
            <button type="button" class="map-date-arrow" id="deliveryPrevDateBtn" aria-label="আগের দিন">&lsaquo;</button>
            <label class="map-date-picker-label" for="deliveryDateInput">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/></svg>
                <span class="map-date-texts">
                    <strong class="tabular" id="deliveryDateDisplay"><?= e(Bn::date($activeDate)) ?></strong>
                    <small class="tabular" id="deliveryTripCodeDisplay"><?= $hasTrip ? e(Bn::digits($trip['code'])) : 'ট্রিপ নেই' ?></small>
                </span>
                <input type="date" id="deliveryDateInput" value="<?= e($activeDate) ?>" class="date-hidden-input" aria-label="তারিখ নির্বাচন করুন">
            </label>
            <button type="button" class="map-date-arrow" id="deliveryNextDateBtn" aria-label="পরের দিন">&rsaquo;</button>
        </div>

        <button type="button" class="btn btn-primary btn-sm map-ready-btn" id="openReadySaleBtn" <?= ($hasTrip && $trip['editable']) ? '' : 'disabled' ?>>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M12 5v14M5 12h14"/></svg>
            <span>রেডি সেল</span>
        </button>
    </div>

    <div class="<?= e($bannerClass) ?>" id="tripStateBanner" <?= $bannerText === '' ? 'hidden' : '' ?>><?= e($bannerText) ?></div>

    <!-- Recenter Button -->
    <button type="button" class="map-recenter-btn" id="recenterDeliveryMapBtn" title="সব দোকান দেখুন" aria-label="সব দোকান দেখুন">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/><circle cx="12" cy="12" r="7" stroke-dasharray="2 2"/></svg>
    </button>

    <!-- Full-Screen Map -->
    <div id="deliveryMap" class="delivery-map" role="region" aria-label="ডেলিভারি ম্যাপ"></div>

    <!-- Bottom Panel: Nearby Retailers as Quick-Click Cards -->
    <div class="nearby-cards-dock" id="nearbyCardsDock">
        <div class="nearby-dock-head">
            <div class="nearby-dock-title">
                <strong>কাছাকাছি অর্ডার</strong>
                <span class="badge badge-neutral tabular" id="deliveryNearbyCount">০</span>
            </div>
            <span class="muted small tabular" id="deliveryDateSummary"></span>
        </div>
        <div class="nearby-cards-rail" id="deliveryQuickCards"></div>
    </div>
</section>

<!-- Retailer Delivery Modal -->
<div class="modal-overlay modal-fullscreen-sheet" id="deliveryOrderModal" aria-hidden="true">
    <div class="modal-panel do-modal-panel" role="dialog" aria-modal="true" aria-labelledby="doRetailerName">
        <div class="do-undo-bar" id="doUndoBar" hidden>
            <div class="do-undo-info">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 7v6h6"/><path d="M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13"/></svg>
                <span id="doUndoLabel">সংরক্ষিত</span>
            </div>
            <button type="button" class="btn btn-sm do-undo-btn" id="doTopUndoBtn">পূর্বাবস্থায় নিন</button>
        </div>

        <div class="modal-head do-modal-head">
            <div class="do-head-main">
                <div class="do-head-title-row">
                    <h2 id="doRetailerName" class="section-title">দোকান</h2>
                    <span class="badge" id="doHeadStatusBadge">অপেক্ষমান</span>
                </div>
                <p id="doRetailerMeta" class="section-subtitle"></p>
            </div>
            <button type="button" class="btn btn-secondary btn-sm" id="doHeaderCancelBtn">বন্ধ</button>
        </div>

        <div class="modal-body do-modal-body">
            <section class="do-damage-box" id="doDamageBox">
                <button type="button" class="btn btn-sm do-damage-open-btn" id="doOpenDamageModalBtn">+ ড্যামেজ সংগ্রহ</button>
                <div class="do-damage-list" id="doDamageList" hidden></div>
            </section>

            <div id="doCompaniesContainer"></div>
        </div>

        <div class="do-footer">
            <div class="do-existing-due-alert" id="doExistingDueAlert" hidden>
                <span>পূর্বের বকেয়া (আগের বাকি):</span>
                <strong class="tabular" id="doExistingDueAmt">৳ ০</strong>
            </div>

            <div class="do-paid-due-bar">
                <div class="do-pd-item">
                    <span class="muted small">জমা</span>
                    <strong class="tabular is-ok" id="doFooterPaid">৳ ০</strong>
                </div>
                <div class="do-pd-divider"></div>
                <div class="do-pd-item">
                    <span class="muted small">বাকি</span>
                    <strong class="tabular is-warn" id="doFooterDue">৳ ০</strong>
                </div>
                <div class="do-pd-divider"></div>
                <div class="do-pd-item">
                    <span class="muted small">ডেলিভারি O/C</span>
                    <strong class="tabular" id="doFooterOc">৳ ০</strong>
                </div>
            </div>

            <div class="do-summary-table-wrap">
                <table class="do-summary-table">
                    <thead>
                        <tr>
                            <th>স্ট্যাটাস</th>
                            <th class="text-right">অর্ডার</th>
                            <th class="text-right">প্রদেয় বিল</th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr>
                            <td id="doStatusCell"><span class="badge badge-warning">অপেক্ষমান</span></td>
                            <td class="text-right tabular" id="doOrderTotalCell">৳ ০</td>
                            <td class="text-right tabular"><strong id="doShouldPayCell">৳ ০</strong></td>
                        </tr>
                    </tbody>
                </table>
            </div>

            <div class="do-bottom-actions">
                <button type="button" class="btn btn-danger-outline" id="doCancelOrderBtn">বাতিল</button>
                <button type="button" class="btn btn-primary" id="doOpenPayBtn">টাকা নিন</button>
            </div>
        </div>
    </div>
</div>

<!-- Cancel Order Reason-Selection Dialog -->
<div class="modal-overlay modal-top modal-center" id="cancelReasonModal" aria-hidden="true">
    <div class="modal-panel dialog-card" role="dialog" aria-modal="true" aria-labelledby="crTitle">
        <div class="modal-head">
            <div>
                <h3 id="crTitle" class="section-title">সম্পূর্ণ অর্ডার বাতিল</h3>
            </div>
            <button type="button" class="icon-btn" data-close-modal="cancelReasonModal" aria-label="বন্ধ করুন">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>
        <form id="cancelReasonForm" class="dialog-form">
            <div class="modal-body">
                <div class="reason-list" id="cancelReasonList"></div>
                <div class="form-group" style="margin-top:10px;">
                    <label for="cancelNoteInput">নোট (ঐচ্ছিক)</label>
                    <input id="cancelNoteInput" type="text" placeholder="অতিরিক্ত তথ্য থাকলে লিখুন">
                </div>
                <div class="alert alert-error" id="cancelReasonError" hidden></div>
            </div>
            <div class="modal-foot">
                <button type="button" class="btn btn-secondary" data-close-modal="cancelReasonModal">ফিরুন</button>
                <button type="submit" class="btn btn-danger" id="confirmCancelOrderBtn">বাতিল নিশ্চিত করুন</button>
            </div>
        </form>
    </div>
</div>

<!-- Payment Dialog -->
<div class="modal-overlay modal-top modal-center" id="paymentModal" aria-hidden="true">
    <div class="modal-panel dialog-card" role="dialog" aria-modal="true" aria-labelledby="payTitle">
        <div class="modal-head">
            <div>
                <h3 id="payTitle" class="section-title">টাকা গ্রহণ</h3>
                <p class="section-subtitle" id="payRetailerSubtitle"></p>
            </div>
            <button type="button" class="icon-btn" data-close-modal="paymentModal" aria-label="বন্ধ করুন">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>
        <form id="paymentForm" class="dialog-form">
            <div class="modal-body">
                <div class="pay-existing-due-box" id="payExistingDueBox" hidden>
                    <div>
                        <span class="pay-due-tag">পূর্বের বকেয়া</span>
                    </div>
                    <strong class="tabular" id="payExistingDueVal">৳ ০</strong>
                </div>

                <div class="form-group">
                    <div class="label-row">
                        <label for="payAmountInput">প্রাপ্ত টাকা (৳)</label>
                        <div class="pay-quick-chips">
                            <button type="button" class="chip-btn" id="payZeroBtn">সম্পূর্ণ বাকি (০)</button>
                            <button type="button" class="chip-btn" id="payFullBtn">সম্পূর্ণ পেমেন্ট</button>
                        </div>
                    </div>
                    <input id="payAmountInput" type="number" min="0" step="0.01" inputmode="decimal" required>
                    <small class="muted small tabular" id="payCapHint">সর্বোচ্চ গ্রহণযোগ্য: ৳ ০</small>
                </div>

                <div class="pay-breakdown-card">
                    <div class="pay-row">
                        <span>মোট প্রদেয় বিল</span>
                        <strong class="tabular" id="payShouldPayVal">৳ ০</strong>
                    </div>
                    <div class="pay-row" id="payOldDueRow" hidden>
                        <span>আগের বাকি আদায়</span>
                        <strong class="tabular is-ok" id="payOldDueVal">৳ ০</strong>
                    </div>
                    <div class="pay-row">
                        <span>মোট জমা</span>
                        <strong class="tabular is-ok" id="payPaidVal">৳ ০</strong>
                    </div>
                    <div class="pay-row pay-row-total">
                        <span>নতুন বাকি</span>
                        <strong class="tabular is-warn" id="payDueVal">৳ ০</strong>
                    </div>
                </div>
                <p class="muted small" id="payStatusHint" style="margin:8px 0 0;"></p>
            </div>
            <div class="modal-foot">
                <button type="button" class="btn btn-secondary" data-close-modal="paymentModal">বাতিল</button>
                <button type="submit" class="btn btn-primary" id="confirmPayBtn">নিশ্চিত করুন</button>
            </div>
        </form>
    </div>
</div>

<!-- Modern Multi-Step Ready Sale Studio Sheet -->
<div class="modal-overlay modal-fullscreen-sheet modal-top" id="readySaleModal" aria-hidden="true">
    <div class="modal-panel do-modal-panel rs-sheet-panel" role="dialog" aria-modal="true" aria-labelledby="rsTitle">
        <header class="rs-head">
            <div class="rs-head-left">
                <button type="button" class="rs-icon-btn" id="rsHeadBackBtn" aria-label="পেছনে যান">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3"><path d="m15 18-6-6 6-6"/></svg>
                </button>
                <div class="rs-head-text">
                    <h3 id="rsTitle" class="rs-head-title">রেডি সেল</h3>
                    <p class="rs-head-sub" id="rsHeadSub" hidden></p>
                </div>
            </div>
            <div class="rs-head-right">
                <span class="rs-van-pill tabular" id="rsVanTotalPill">ভ্যান ০ পিস</span>
                <button type="button" class="rs-icon-btn" data-close-modal="readySaleModal" aria-label="বন্ধ করুন">
                    <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M18 6 6 18M6 6l12 12"/></svg>
                </button>
            </div>
        </header>

        <!-- Clean 2-Step Progress Pills -->
        <div class="rs-stepper" id="rsStepper">
            <button type="button" class="rs-step-pill is-active" id="rsStepPill1" data-rs-step="1">
                <span class="rs-step-num">১</span>
                <span>দোকান বাছুন / যোগ</span>
            </button>
            <span class="rs-step-sep">›</span>
            <button type="button" class="rs-step-pill" id="rsStepPill2" data-rs-step="2" disabled>
                <span class="rs-step-num">২</span>
                <span>পণ্য ও কার্ট</span>
            </button>
        </div>

        <!-- STEP 1: RETAILER PICKER (Search Banglish + Nearby + Quick New Shop) -->
        <div class="rs-stage" id="rsStepShop">
            <div class="rs-seg-wrap">
                <div class="rs-seg" role="tablist" aria-label="দোকানের ধরন">
                    <button type="button" class="rs-seg-btn is-active" id="rsModeExistingBtn" data-rs-mode="existing" role="tab" aria-selected="true">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
                        <span>দোকান বাছুন</span>
                    </button>
                    <button type="button" class="rs-seg-btn" id="rsModeNewBtn" data-rs-mode="new" role="tab" aria-selected="false">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3"><path d="M12 5v14M5 12h14"/></svg>
                        <span>নতুন দোকান</span>
                    </button>
                </div>
            </div>

            <!-- Existing Retailer Directory (List + Map View) -->
            <div class="rs-shop-panel" id="rsExistingGroup">
                <div class="rs-search-bar-wrap">
                    <div class="rs-search-row">
                        <div class="rs-search-box is-flex">
                            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
                            <input type="search" id="rsRetailerSearch" placeholder="দোকান খুঁজুন (বাংলা / Banglish)…" autocomplete="off">
                            <span class="rs-spinner" id="rsRetSpinner" aria-hidden="true" hidden></span>
                            <button type="button" class="rs-clear-btn" id="rsRetClearBtn" aria-label="মুছুন" hidden>&times;</button>
                        </div>
                        <div class="rs-view-switch" role="group" aria-label="দোকান দেখার ধরন">
                            <button type="button" class="rs-view-btn is-active" id="rsShopViewListBtn" data-rs-shop-view="list" title="লিস্ট">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/></svg>
                            </button>
                            <button type="button" class="rs-view-btn" id="rsShopViewMapBtn" data-rs-shop-view="map" title="ম্যাপ">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1"><polygon points="1 6 1 22 8 18 16 22 23 18 23 2 16 6 8 2 1 6"/><line x1="8" y1="2" x2="8" y2="18"/><line x1="16" y1="6" x2="16" y2="22"/></svg>
                            </button>
                        </div>
                    </div>
                    <div class="rs-dir-meta" id="rsRetMetaRow">
                        <span id="rsRetListLabel">কাছের দোকান</span>
                        <span class="rs-sync-chip" id="rsRetSyncChip" hidden>
                            <span class="rs-sync-dot" aria-hidden="true"></span>
                            <span>সব দোকান লোড হচ্ছে…</span>
                        </span>
                    </div>
                </div>
                <div class="rs-shop-results" id="rsRetailerResults"></div>
                <div class="rs-shop-map-wrap" id="rsRetailerMapWrap" hidden>
                    <div class="rs-shop-map" id="rsRetailerMap" aria-label="দোকানের ম্যাপ"></div>
                    <button type="button" class="rs-map-recenter-btn" id="rsRetMapRecenterBtn" title="আমার অবস্থানে যান">সেন্টার</button>
                    <div class="rs-map-pick-card" id="rsMapSelectedCard" hidden>
                        <div class="rs-map-pick-info">
                            <strong id="rsMapSelName">দোকান</strong>
                            <span class="tabular" id="rsMapSelSub"></span>
                        </div>
                        <button type="button" class="btn rs-map-pick-btn" id="rsMapPickBtn">বাছুন →</button>
                    </div>
                </div>
            </div>

            <!-- Quick New Retailer with Interactive Pin Picker -->
            <div class="rs-new-panel" id="rsNewGroup" hidden>
                <div class="rs-new-pin-card" id="rsNewPinCard">
                    <div class="rs-new-pin-head">
                        <div class="rs-new-pin-status">
                            <span class="rs-gps-dot" aria-hidden="true"></span>
                            <div>
                                <strong id="rsNewPinTitle">ম্যাপে দোকানের পিন সেট করুন</strong>
                                <span class="mono small muted" id="rsNewGpsCoords">লোকেশন নেওয়া হচ্ছে…</span>
                            </div>
                        </div>
                        <div class="rs-new-pin-actions">
                            <button type="button" class="rs-mini-pill-btn" id="rsNewGpsResetBtn">আমার GPS</button>
                            <button type="button" class="rs-mini-pill-btn" id="rsNewPinExpandBtn">বড় ম্যাপ</button>
                        </div>
                    </div>
                    <div class="rs-new-pin-map" id="rsNewPinMap" aria-label="নতুন দোকানের লোকেশন পিন ম্যাপ"></div>
                </div>

                <div class="rs-new-form-card">
                    <div class="form-group">
                        <label for="rsShopName">দোকানের নাম <span class="req">*</span></label>
                        <input id="rsShopName" type="text" maxlength="150" placeholder="যেমন: রহমান স্টোর">
                    </div>
                    <div class="form-group">
                        <label for="rsShopPhone">মোবাইল নম্বর (ঐচ্ছিক)</label>
                        <input id="rsShopPhone" type="tel" inputmode="tel" placeholder="01XXXXXXXXX">
                    </div>
                    <div class="form-group" style="margin-bottom:0;">
                        <label for="rsShopAddress">ঠিকানা / বাজার (ঐচ্ছিক)</label>
                        <input id="rsShopAddress" type="text" maxlength="255" placeholder="রোড / বাজার / মোড়">
                    </div>
                </div>

                <div class="alert alert-error" id="rsNewShopError" hidden></div>

                <button type="button" class="btn rs-primary-cta" id="rsContinueNewShopBtn">
                    <span>এই দোকানে পণ্য বাছুন</span>
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3"><path d="m9 18 6-6-6-6"/></svg>
                </button>
            </div>
        </div>

        <!-- STEP 2: VISUAL VAN STOCK PICKER + MULTI-ITEM CART -->
        <div class="rs-stage" id="rsStepProducts" hidden>
            <div class="rs-chosen-shop-bar">
                <div class="rs-chosen-avatar" id="rsChosenAvatar">দ</div>
                <div class="rs-chosen-info">
                    <div class="rs-chosen-name" id="rsChosenShopName">দোকান</div>
                    <div class="rs-chosen-sub tabular" id="rsChosenShopSub"></div>
                </div>
                <button type="button" class="rs-change-btn" id="rsChangeShopBtn">বদলান</button>
            </div>

            <div class="rs-prod-toolbar">
                <div class="rs-search-box is-compact">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
                    <input type="search" id="rsProductSearch" placeholder="পণ্য খুঁজুন (বাংলা / Banglish)…" autocomplete="off">
                    <span class="rs-spinner" id="rsProdSpinner" aria-hidden="true" hidden></span>
                    <button type="button" class="rs-clear-btn" id="rsProdClearBtn" aria-label="মুছুন" hidden>&times;</button>
                </div>
                <div class="rs-view-switch" role="group" aria-label="দেখার ধরন">
                    <button type="button" class="rs-view-btn is-active" id="rsViewGridBtn" data-rs-view="grid" title="গ্রিড">
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg>
                    </button>
                    <button type="button" class="rs-view-btn" id="rsViewListBtn" data-rs-view="list" title="লিস্ট">
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/></svg>
                    </button>
                </div>
            </div>

            <div class="rs-products-scroll">
                <div class="rs-products-grid" id="rsProductsGrid"></div>
            </div>

            <!-- Sticky Checkout Footer + Expandable Mini-Cart Drawer -->
            <div class="rs-checkout-dock">
                <div class="rs-cart-drawer" id="rsCartDrawer" hidden>
                    <div class="rs-cart-drawer-head">
                        <strong>নির্বাচিত পণ্য (<span id="rsDrawerCount">০</span>)</strong>
                        <button type="button" class="rs-clear-cart-btn" id="rsClearCartBtn">সব মুছুন</button>
                    </div>
                    <div class="rs-cart-drawer-list" id="rsCartDrawerList"></div>
                </div>

                <div class="alert alert-error rs-inline-error" id="rsError" hidden></div>

                <div class="rs-dock-row">
                    <button type="button" class="rs-cart-summary-btn" id="rsToggleDrawerBtn" disabled>
                        <span class="rs-cart-count-badge tabular" id="rsCartBadge">০টি পণ্য · ০ পিস</span>
                        <strong class="rs-cart-total-val tabular" id="rsTotalAmount">৳ ০</strong>
                    </button>
                    <button type="button" class="btn rs-checkout-btn" id="rsSubmitBtn" disabled>
                        <span>নগদে বিক্রি সম্পন্ন</span>
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4"><path d="M20 6 9 17l-5-5"/></svg>
                    </button>
                </div>
            </div>
        </div>

        <div class="rs-stage rs-success-stage" id="rsStepSuccess" hidden>
            <div class="rs-success-card">
                <div class="rs-success-check" aria-hidden="true">
                    <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8"><path d="M20 6 9 17l-5-5"/></svg>
                </div>
                <h3 class="rs-success-title">রেডি সেল সম্পন্ন হয়েছে!</h3>
                <p class="rs-success-sub" id="rsReceiptMeta"></p>

                <div class="rs-receipt-box">
                    <div class="rs-receipt-head">
                        <strong id="rsReceiptShop">দোকান</strong>
                        <span class="badge badge-success">নগদ পরিশোধ</span>
                    </div>
                    <div class="rs-receipt-items" id="rsReceiptItems"></div>
                    <div class="rs-receipt-total-row">
                        <span>মোট নগদ আদায়</span>
                        <strong class="tabular" id="rsReceiptTotal">৳ ০</strong>
                    </div>
                </div>

                <div class="rs-success-actions">
                    <button type="button" class="btn btn-secondary" id="rsAnotherSaleBtn">+ আরেকটি রেডি সেল</button>
                    <button type="button" class="btn rs-primary-cta" id="rsDoneSaleBtn">ম্যাপে ফিরুন</button>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- Dedicated Damage Collection Modal -->
<div class="modal-overlay modal-fullscreen-sheet modal-top" id="damageCollectionModal" aria-hidden="true">
    <div class="modal-panel do-modal-panel rs-sheet-panel" role="dialog" aria-modal="true" aria-labelledby="dmgTitle">
        <header class="dmg-head">
            <div class="rs-head-left">
                <button type="button" class="rs-icon-btn" data-close-modal="damageCollectionModal" aria-label="পেছনে যান">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3"><path d="m15 18-6-6 6-6"/></svg>
                </button>
                <div class="rs-head-text">
                    <h3 id="dmgTitle" class="rs-head-title">ড্যামেজ ফেরত সংগ্রহ</h3>
                    <p class="rs-head-sub" id="dmgRetailerSub"></p>
                </div>
            </div>
            <div class="rs-head-right">
                <span class="rs-van-pill tabular" id="dmgHeadTotalBadge">− ৳ ০</span>
            </div>
        </header>

        <div class="dmg-toolbar">
            <div class="rs-search-row">
                <div class="rs-search-box is-compact is-flex">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
                    <input type="search" id="dmgProductSearch" placeholder="ড্যামেজ পণ্য খুঁজুন (বাংলা / Banglish)…" autocomplete="off">
                    <span class="rs-spinner" id="dmgProdSpinner" aria-hidden="true" hidden></span>
                    <button type="button" class="rs-clear-btn" id="dmgProdClearBtn" aria-label="মুছুন" hidden>&times;</button>
                </div>
                <div class="rs-view-switch" role="group" aria-label="দেখার ধরন">
                    <button type="button" class="rs-view-btn is-active" id="dmgViewGridBtn" data-dmg-view="grid" title="গ্রিড">
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg>
                    </button>
                    <button type="button" class="rs-view-btn" id="dmgViewListBtn" data-dmg-view="list" title="লিস্ট">
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/></svg>
                    </button>
                </div>
            </div>
            <div class="dmg-chip-rail" id="dmgCompanyChips" hidden></div>
        </div>

        <div class="rs-products-scroll">
            <div class="dmg-selected-banner" id="dmgSelectedSummary" hidden>
                <span class="tabular" id="dmgSelectedText">০টি পণ্য নির্বাচিত</span>
                <button type="button" class="rs-clear-cart-btn" id="dmgClearAllBtn">সব মুছুন</button>
            </div>
            <div class="rs-products-grid" id="dmgProductsGrid"></div>
        </div>

        <div class="rs-checkout-dock">
            <div class="alert alert-error rs-inline-error" id="dmgError" hidden></div>
            <div class="dmg-foot-summary tabular">
                <div class="dmg-foot-stat">
                    <span>সরবরাহ মূল্য</span>
                    <strong id="dmgFootGross">৳ ০</strong>
                </div>
                <div class="dmg-foot-stat is-danger">
                    <span>ড্যামেজ বাদ</span>
                    <strong id="dmgFootDeduct">− ৳ ০</strong>
                </div>
                <div class="dmg-foot-stat is-net">
                    <span>নতুন প্রদেয়</span>
                    <strong id="dmgFootNet">৳ ০</strong>
                </div>
            </div>
            <button type="button" class="btn dmg-apply-btn" id="dmgApplyBtn">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4"><path d="M20 6 9 17l-5-5"/></svg>
                <span>ড্যামেজ সাবমিট করুন</span>
            </button>
        </div>
    </div>
</div>
<?php $this->endSection(); ?>
