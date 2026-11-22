<?php $this->extend('partner.layouts.main'); ?>

<?php use App\Support\Bn; ?>

<?php $this->section('topbar_actions'); ?>
<button type="button" class="btn btn-primary btn-sm" data-dsr-add>
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M12 5v14M5 12h14"/></svg>
    <span>DSR যোগ করুন</span>
</button>
<?php $this->endSection(); ?>

<?php $this->section('content'); ?>
<div class="toolbar-card">
    <div class="toolbar-filters">
        <div class="search-box">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
            <input type="search" id="dsrSearch" placeholder="DSR-এর নাম বা মোবাইল নম্বর খুঁজুন…" autocomplete="off">
        </div>
    </div>
    <span class="muted small tabular"><strong id="dsrCount"><?= Bn::num(count($deliveryMen)) ?></strong> জন ডেলিভারিম্যান</span>
</div>

<section class="staff-grid" id="dsrGrid">
    <?php foreach ($deliveryMen as $dsr): ?>
        <article
            class="card staff-card <?= $dsr['status'] === 'Active' ? '' : 'is-muted' ?>"
            data-dsr-card
            data-search="<?= e(strtolower($dsr['name'] . ' ' . $dsr['number'] . ' ' . $dsr['phone'])) ?>"
            data-dsr="<?= e(json_encode($dsr, JSON_UNESCAPED_UNICODE)) ?>"
        >
            <div class="staff-card-head">
                <div class="staff-identity">
                    <span class="avatar"><?= e(mb_strtoupper(mb_substr($dsr['name'], 0, 2))) ?></span>
                    <div>
                        <h3 class="staff-name"><?= e($dsr['name']) ?></h3>
                        <span class="muted small tabular">ডেলিভারিম্যান (DSR) · <?= Bn::num((int) $dsr['trips']) ?>টি ট্রিপ</span>
                    </div>
                </div>
                <span class="badge <?= $dsr['status'] === 'Active' ? 'badge-success' : 'badge-neutral' ?>"><?= e(Bn::status($dsr['status'])) ?></span>
            </div>

            <div class="staff-meta-list">
                <div class="staff-meta-row">
                    <span class="muted small">বেতন</span>
                    <strong class="tabular"><?= Bn::money((float) $dsr['salary']) ?>/মাস</strong>
                </div>
                <div class="staff-meta-row">
                    <span class="muted small">মোবাইল</span>
                    <strong class="tabular"><?= e(Bn::digits($dsr['number'])) ?></strong>
                </div>
            </div>

            <div class="card-actions">
                <button type="button" class="btn btn-secondary btn-xs" data-dsr-edit>সম্পাদনা</button>
                <button type="button" class="btn btn-secondary btn-xs" data-dsr-reset>পাসওয়ার্ড রিসেট</button>
                <button type="button" class="btn btn-secondary btn-xs" data-dsr-status><?= $dsr['status'] === 'Active' ? 'নিষ্ক্রিয় করুন' : 'সক্রিয় করুন' ?></button>
                <button type="button" class="btn btn-danger-soft btn-xs" data-dsr-delete>মুছুন</button>
            </div>
        </article>
    <?php endforeach; ?>
</section>

<div class="empty-state" id="dsrEmpty" <?= $deliveryMen ? 'hidden' : '' ?>>
    <p><?= $deliveryMen ? 'খোঁজের সাথে কোনো ডেলিভারিম্যান মিলছে না।' : 'এখনো কোনো ডেলিভারিম্যান নেই। প্রথম DSR যোগ করুন।' ?></p>
</div>

<!-- Add / Edit DSR Modal -->
<div class="modal-overlay" id="dsrModal" aria-hidden="true">
    <div class="modal-panel" role="dialog" aria-modal="true" aria-labelledby="dsrModalTitle">
        <div class="modal-head">
            <div>
                <h2 id="dsrModalTitle" class="section-title">ডেলিভারিম্যান (DSR) যোগ করুন</h2>
                <p class="section-subtitle">DSR এই মোবাইল নম্বর ও পাসওয়ার্ড দিয়ে লগইন করবেন</p>
            </div>
            <button type="button" class="icon-btn" data-modal-close aria-label="বন্ধ করুন">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>

        <form id="dsrForm" class="modal-form" novalidate>
            <input type="hidden" name="id" value="">
            <input type="hidden" name="status" value="Active">
            <div class="modal-body">
                <div class="form-group">
                    <label for="dsr_name">নাম <span class="req">*</span></label>
                    <input id="dsr_name" name="name" type="text" placeholder="যেমন: রুবেল মিয়া" maxlength="120" required>
                </div>
                <div class="form-grid">
                    <div class="form-group">
                        <label for="dsr_salary">বেতন (৳ / মাস) <span class="req">*</span></label>
                        <input id="dsr_salary" name="salary" type="number" min="0" step="0.01" placeholder="যেমন: ১৮০০০" required>
                    </div>
                    <div class="form-group">
                        <label for="dsr_number">মোবাইল নম্বর <span class="req">*</span></label>
                        <input id="dsr_number" name="number" type="tel" placeholder="01XXXXXXXXX" required>
                    </div>
                </div>
                <div class="form-group" data-create-only>
                    <div class="label-row">
                        <label for="dsr_password">পাসওয়ার্ড <span class="req">*</span></label>
                        <button type="button" class="text-link small" data-gen-pw="dsr_password">তৈরি করুন</button>
                    </div>
                    <div class="input-with-action">
                        <input id="dsr_password" name="password" type="password" placeholder="কমপক্ষে ৬ অক্ষর" minlength="6" autocomplete="new-password">
                        <button type="button" class="input-action-btn" data-toggle-input-pw="dsr_password">দেখুন</button>
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

<!-- Reset Password Modal -->
<div class="modal-overlay" id="dsrPasswordModal" aria-hidden="true">
    <div class="modal-panel" role="dialog" aria-modal="true" aria-labelledby="dsrPasswordTitle">
        <div class="modal-head">
            <div>
                <h2 id="dsrPasswordTitle" class="section-title">পাসওয়ার্ড রিসেট</h2>
                <p class="section-subtitle" id="dsrPasswordSub">নতুন পাসওয়ার্ড সেট করে DSR-কে দিন</p>
            </div>
            <button type="button" class="icon-btn" data-modal-close aria-label="বন্ধ করুন">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>
        <form id="dsrPasswordForm" class="modal-form" novalidate>
            <input type="hidden" name="id" value="">
            <div class="modal-body">
                <div class="form-group">
                    <div class="label-row">
                        <label for="dsr_new_password">নতুন পাসওয়ার্ড <span class="req">*</span></label>
                        <button type="button" class="text-link small" data-gen-pw="dsr_new_password">তৈরি করুন</button>
                    </div>
                    <div class="input-with-action">
                        <input id="dsr_new_password" name="password" type="password" placeholder="কমপক্ষে ৬ অক্ষর" minlength="6" autocomplete="new-password" required>
                        <button type="button" class="input-action-btn" data-toggle-input-pw="dsr_new_password">দেখুন</button>
                    </div>
                </div>
                <p class="muted small" style="margin:0">এতে DSR সব ডিভাইস থেকে লগ আউট হয়ে যাবেন।</p>
            </div>
            <div class="modal-error" data-form-error hidden></div>
            <div class="modal-foot">
                <button type="button" class="btn btn-secondary" data-modal-close>বাতিল</button>
                <button type="submit" class="btn btn-primary">রিসেট করুন</button>
            </div>
        </form>
    </div>
</div>
<?php $this->endSection(); ?>
