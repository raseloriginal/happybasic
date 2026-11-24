<?php
use App\Support\Bn;
$navDate = $selectedDate ?? date('Y-m-d');
$navToday = date('Y-m-d');
?>
<div class="page-date-nav" data-date-nav>
    <button type="button" class="map-date-arrow" data-date-shift="-1" aria-label="আগের দিন">&lsaquo;</button>
    <label class="map-date-picker-label" data-date-label>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/></svg>
        <span class="map-date-texts">
            <strong class="tabular"><?= e(Bn::date($navDate)) ?></strong>
            <?php if ($navDate === $navToday): ?><small>আজ</small><?php endif; ?>
        </span>
        <input type="date" value="<?= e($navDate) ?>" class="date-hidden-input" data-date-input aria-label="তারিখ নির্বাচন করুন">
    </label>
    <button type="button" class="map-date-arrow" data-date-shift="1" aria-label="পরের দিন">&rsaquo;</button>
    <?php if ($navDate !== $navToday): ?>
        <button type="button" class="page-date-today" data-date-today="<?= e($navToday) ?>">আজ</button>
    <?php endif; ?>
</div>
