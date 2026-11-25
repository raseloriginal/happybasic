<?php $this->extend('partner.layouts.main'); ?>

<?php
use App\Support\Bn;
$today = date('Y-m-d');
?>

<?php $this->section('content'); ?>
<div id="liveApp" class="lv"
     data-date="<?= e($date) ?>" data-today="<?= e($today) ?>"
     data-team="<?= e(json_encode($team, JSON_UNESCAPED_UNICODE)) ?>"
     data-leaflet-css="<?= e(asset('vendor/leaflet/leaflet.css')) ?>" data-leaflet-js="<?= e(asset('vendor/leaflet/leaflet.js')) ?>" data-tiles-js="<?= e(asset('shared/js/map-tiles.js')) ?>">

    <div class="lv-map" id="lvMap" aria-label="DSR ম্যাপ"></div>

    <aside class="lv-panel">
        <header class="lv-head">
            <div class="lv-date">
                <button type="button" class="lv-icon" id="lvPrev" aria-label="আগের দিন"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="m15 18-6-6 6-6"/></svg></button>
                <label class="lv-date-label"><strong id="lvDateText"><?= e(Bn::fullDate($date)) ?></strong><input type="date" id="lvDate" value="<?= e($date) ?>" max="<?= e($today) ?>" aria-label="তারিখ"></label>
                <button type="button" class="lv-icon" id="lvNext" aria-label="পরের দিন"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="m9 18 6-6-6-6"/></svg></button>
            </div>
            <div class="lv-mode"><span class="lv-live" id="lvLive"><i></i><b></b></span><button type="button" class="lv-today" id="lvToday" hidden>আজকের লাইভ</button></div>
        </header>
        <div class="lv-team" id="lvTeam"></div>
        <div class="lv-detail" id="lvDetail" hidden></div>
    </aside>

    <button type="button" class="lv-fit" id="lvFit" aria-label="সবাইকে দেখুন"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M8 3H5a2 2 0 0 0-2 2v3M16 3h3a2 2 0 0 1 2 2v3M8 21H5a2 2 0 0 1-2-2v-3M16 21h3a2 2 0 0 0 2-2v-3"/></svg></button>

    <div class="lv-player" id="lvPlayer" hidden>
        <button type="button" class="lv-play" id="lvPlay" aria-label="চালান"></button>
        <input type="range" id="lvSeek" min="0" max="1000" value="0" step="1" aria-label="সময়">
        <time id="lvClock" class="tabular"></time>
        <button type="button" class="lv-speed tabular" id="lvSpeed" aria-label="গতি"></button>
    </div>
</div>
<?php $this->endSection(); ?>
