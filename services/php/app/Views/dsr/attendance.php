<?php $this->extend('dsr.layouts.main'); ?>

<?php use App\Support\Bn; ?>

<?php $this->section('content'); ?>
<section class="dsr-dash-stack" id="dsrAttendanceApp" data-token="<?= e($token) ?>" data-done="<?= $today ? '1' : '0' ?>">
    <?php $this->include('dsr.partials.date_nav', ['selectedDate' => $selectedDate ?? null]); ?>
    <article class="card att-status-card" id="attStatus">
        <?php if ($today): ?>
            <span class="badge <?= (int) $today['late_min'] > 0 ? 'badge-warning' : 'badge-success' ?>"><?= $isToday ? 'আজকের' : e(Bn::date($selectedDate)) . '-এর' ?> হাজিরা সম্পন্ন</span>
            <strong class="att-big tabular"><?= e(Bn::time($today['checked_in_at'])) ?></strong>
            <span class="muted small"><?= (int) $today['late_min'] > 0 ? Bn::digits((int) $today['late_min']) . ' মিনিট দেরি' : 'সময়মতো' ?></span>
        <?php else: ?>
            <span class="badge badge-neutral"><?= $isToday ? 'আজ এখনো হাজিরা হয়নি' : 'এই দিনে হাজিরা নেই' ?></span>
            <?php if ($isToday): ?>
            <strong class="att-big">গোডাউনের QR স্ক্যান করুন</strong>
            <span class="muted small">গোডাউনে পৌঁছে ফোনের লোকেশন চালু রেখে স্ক্যান করুন।</span>
            <?php endif; ?>
        <?php endif; ?>
        <p class="att-msg" id="attMsg" hidden></p>
    </article>

    <?php if (!$today && $isToday): ?>
    <article class="card att-scan-card">
        <button type="button" class="btn btn-primary" id="attScanBtn">QR স্ক্যান করুন</button>
        <p class="muted small">ক্যামেরা না খুললে ফোনের নিজের ক্যামেরা অ্যাপ দিয়ে QR স্ক্যান করুন — লিংকটি এই অ্যাপে খুলবে।</p>
        <div class="att-video-wrap" id="attVideoWrap" hidden>
            <video id="attVideo" playsinline muted></video>
        </div>
    </article>
    <?php endif; ?>

    <article class="card">
        <h2 class="section-title">এই মাসের হাজিরা</h2>
        <div class="att-days">
            <?php foreach ($days as $d): ?>
                <?php
                $label = match ($d['status']) {
                    'present' => $d['time'] ? e(Bn::time($d['time'])) . ($d['late_min'] > 0 ? ' · দেরি ' . Bn::digits($d['late_min']) . ' মি.' : '') : 'উপস্থিত',
                    'half' => 'হাফ ডে',
                    'holiday' => 'ছুটি',
                    'pending' => 'আজ বাকি',
                    default => 'অনুপস্থিত',
                };
                $cls = match ($d['status']) {
                    'present' => $d['late_min'] > 0 ? 'is-late' : 'is-ok',
                    'half' => 'is-late',
                    default => 'is-none',
                };
                ?>
                <div class="att-day <?= $cls ?>">
                    <span class="tabular"><?= e(Bn::date($d['date'])) ?></span>
                    <span class="tabular"><?= $label ?></span>
                </div>
            <?php endforeach; ?>
        </div>
    </article>
</section>
<?php $this->endSection(); ?>
