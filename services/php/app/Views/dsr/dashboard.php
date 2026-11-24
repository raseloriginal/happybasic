<?php $this->extend('dsr.layouts.main'); ?>

<?php
use App\Support\Bn;
$s = $stats;
$total = max(1, (int) $s['stops'] - (int) $s['cancelled']);
$pct = $s['stops'] > 0 ? min(100, (int) round($s['delivered'] / $total * 100)) : 0;
$sum = $settlement ?? [];
?>

<?php $this->section('topbar_actions'); ?>
<?php if ($trip !== null): ?>
<a href="<?= e(url('/dsr/delivery')) ?>" class="btn btn-primary btn-sm">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1"><path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/></svg>
    <span>ডেলিভারি শুরু করুন</span>
</a>
<?php endif; ?>
<?php $this->endSection(); ?>

<?php $this->section('content'); ?>
<section class="dsr-dash-stack" id="dsrDashboardApp">
    <?php $this->include('dsr.partials.date_nav', ['selectedDate' => $selectedDate ?? null]); ?>
    <?php if ($trip === null): ?>
        <article class="card empty-trip-card">
            <h2 class="section-title">কোনো ডিসপ্যাচ করা ট্রিপ নেই</h2>
        </article>
    <?php else: ?>
        <?php if (!$trip['editable']): ?>
            <div class="trip-state-banner is-inline">সেটেলমেন্ট জমা দেওয়া হয়েছে — পার্টনারের যাচাইয়ের অপেক্ষায়।</div>
        <?php elseif ($trip['settlement_status'] === 'returned'): ?>
            <div class="trip-state-banner is-inline is-returned">সেটেলমেন্ট ফেরত পাঠানো হয়েছে<?= $trip['review_note'] ? ': ' . e($trip['review_note']) : '' ?>। সংশোধন করে পুনরায় জমা দিন।</div>
        <?php endif; ?>

        <article class="card target-card">
            <div class="target-card-head">
                <div>
                    <span class="kpi-label">মোট দোকান</span>
                    <div class="kpi-value-lg tabular"><?= Bn::num((int) $s['stops']) ?></div>
                    <div class="dash-delivered-sub tabular"><?= Bn::num((int) $s['delivered']) ?> / <?= Bn::num($total) ?>টি ডেলিভারি হয়েছে</div>
                </div>
                <div class="target-badges">
                    <span class="badge <?= $pct >= 100 ? 'badge-success' : 'badge-info' ?> tabular"><?= Bn::digits($pct) ?>% সম্পন্ন</span>
                    <span class="muted small tabular"><?= e(Bn::date($trip['date'])) ?></span>
                </div>
            </div>
            <div class="target-progress-wrap">
                <div class="progress-track" role="progressbar" aria-valuenow="<?= $pct ?>" aria-valuemin="0" aria-valuemax="100" aria-label="ডেলিভারি অগ্রগতি">
                    <div class="progress-fill <?= $pct >= 100 ? 'is-complete' : '' ?>" style="width: <?= $pct ?>%"></div>
                </div>
                <div class="target-progress-meta">
                    <span class="muted small">ডেলিভারি: <strong class="tabular"><?= Bn::num((int) $s['delivered']) ?></strong> (বাকি <?= Bn::num((int) $s['due']) ?>)</span>
                    <span class="muted small">অপেক্ষায়: <strong class="tabular"><?= Bn::num((int) $s['pending']) ?></strong> · বাতিল: <strong class="tabular"><?= Bn::num((int) $s['cancelled']) ?></strong></span>
                </div>
            </div>
        </article>

        <div class="dsr-mini-grid">
            <article class="card mini-stat-card">
                <span class="muted small">চলমান ট্রিপ</span>
                <strong class="mini-stat-val tabular"><?= e(Bn::digits($trip['code'])) ?></strong>
                <span class="muted small tabular">ভ্যানে বাকি <?= Bn::num((int) $s['available_pcs']) ?> / <?= Bn::num((int) $s['dispatched_pcs']) ?> পিস</span>
            </article>
            <article class="card mini-stat-card">
                <span class="muted small">জমা দেওয়ার ক্যাশ</span>
                <strong class="mini-stat-val tabular"><?= Bn::money((float) ($sum['net_pay'] ?? 0)) ?></strong>
                <span class="muted small tabular">খরচ <?= Bn::money((float) ($sum['daily_expenses'] ?? 0)) ?> · বাকি <?= Bn::money((float) ($sum['retailer_due'] ?? 0)) ?></span>
            </article>
        </div>
    <?php endif; ?>

    <div class="quick-links-grid">
        <a href="<?= e(url('/dsr/attendance' . (($selectedDate ?? date('Y-m-d')) !== date('Y-m-d') ? '?date=' . $selectedDate : ''))) ?>" class="card quick-link-card">
            <div class="quick-link-icon">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3h-3zM20 14v.01M14 20v.01M20 20h-3v-3"/></svg>
            </div>
            <div class="quick-link-body">
                <strong>হাজিরা — <?= $attendance ? (($selectedDate ?? date('Y-m-d')) === date('Y-m-d') ? 'আজ ' : '') . e(Bn::time($attendance['checked_in_at'])) . '-এ সম্পন্ন' : 'QR স্ক্যান করুন' ?></strong>
            </div>
            <span class="quick-arrow">→</span>
        </a>
        <a href="<?= e(url('/dsr/delivery')) ?>" class="card quick-link-card">
            <div class="quick-link-icon">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><path d="M10 17h4V5H2v12h3"/><path d="M20 17h2v-3.34a4 4 0 0 0-1.17-2.83L19 9h-5"/><circle cx="7.5" cy="17.5" r="2.5"/><circle cx="17.5" cy="17.5" r="2.5"/></svg>
            </div>
            <div class="quick-link-body">
                <strong>ডেলিভারি ম্যাপ ও দোকান</strong>
            </div>
            <span class="quick-arrow">→</span>
        </a>
        <a href="<?= e(url('/dsr/van-stock')) ?>" class="card quick-link-card">
            <div class="quick-link-icon">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/><path d="m3.3 7 8.7 5 8.7-5"/><path d="M12 22V12"/></svg>
            </div>
            <div class="quick-link-body">
                <strong>ভ্যান স্টক সারাংশ</strong>
            </div>
            <span class="quick-arrow">→</span>
        </a>
        <a href="<?= e(url('/dsr/settlement')) ?>" class="card quick-link-card">
            <div class="quick-link-icon">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><rect x="2" y="5" width="20" height="14" rx="2"/><path d="M2 10h20"/><path d="M6 15h4"/></svg>
            </div>
            <div class="quick-link-body">
                <strong>ট্রিপ সেটেলমেন্ট ও নোট গণনা</strong>
            </div>
            <span class="quick-arrow">→</span>
        </a>
        <a href="<?= e(url('/dsr/expense')) ?>" class="card quick-link-card">
            <div class="quick-link-icon">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><path d="M4 2v20l2-1 2 1 2-1 2 1 2-1 2 1 2-1 2 1V2l-2 1-2-1-2 1-2-1-2 1-2-1-2 1Z"/><path d="M8 7h8"/><path d="M8 11h8"/></svg>
            </div>
            <div class="quick-link-body">
                <strong>ট্রিপ খরচ</strong>
            </div>
            <span class="quick-arrow">→</span>
        </a>
    </div>
</section>
<?php $this->endSection(); ?>
