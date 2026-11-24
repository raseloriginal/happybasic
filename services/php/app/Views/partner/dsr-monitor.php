<?php $this->extend('partner.layouts.main'); ?>

<?php
use App\Support\Bn;
use App\Support\Phone;

$money = static fn(float $v): string => Bn::money(abs($v), true);
$signed = static fn(float $v): string => ($v < 0 ? '−' : '+') . Bn::money(abs($v), true);
$days = static fn(float $v): string => Bn::digits(rtrim(rtrim(number_format($v, 1, '.', ''), '0'), '.'));
$palette = ['#2563eb', '#7c3aed', '#059669', '#d97706', '#db2777', '#0891b2'];
$initial = static fn(string $n): string => mb_strtoupper(mb_substr(trim($n), 0, 1));
$partnerName = (string) ($currentPartner['name'] ?? '');
$weekdays = ['শনি', 'রবি', 'সোম', 'মঙ্গল', 'বুধ', 'বৃহঃ', 'শুক্র'];
$monthLabel = Bn::monthYear($month . '-01');
$link = static fn(int $id): string => url('/partner/dsr-monitor?month=' . $month . '&dsr=' . $id);
?>

<?php $this->section('topbar_actions'); ?>
<?php if ($sel): ?>
<button type="button" class="btn btn-primary btn-sm" data-modal-open="entryModal">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M12 5v14M5 12h14"/></svg>
    <span>অ্যাডভান্স / পেমেন্ট</span>
</button>
<?php endif; ?>
<?php $this->endSection(); ?>

<?php $this->section('content'); ?>
<div id="dsrMonitorApp"<?php if ($sel): ?> data-dsr-id="<?= (int) $sel['id'] ?>" data-dsr-name="<?= e($sel['name']) ?>" data-base="<?= e(url('/partner/dsr-monitor/' . $sel['id'])) ?>"<?php endif; ?>>

<form class="toolbar-card" method="GET" action="<?= e(url('/partner/dsr-monitor')) ?>" data-spa-get>
    <?php if ($sel): ?><input type="hidden" name="dsr" value="<?= (int) $sel['id'] ?>"><?php endif; ?>
    <div class="toolbar-filters">
        <label class="date-field"><span class="muted small">মাস</span><input type="month" name="month" value="<?= e($month) ?>" class="select-input"></label>
        <button type="submit" class="btn btn-secondary btn-sm">দেখুন</button>
    </div>
    <span class="muted small"><?= e($monthLabel) ?></span>
</form>

<section class="dm-kpis">
    <article class="dm-kpi dm-kpi-blue">
        <span class="dm-kpi-label">ডেলিভারি ম্যান</span>
        <strong class="dm-kpi-val"><?= Bn::digits($kpi['dsrs']) ?> জন</strong>
        <span class="dm-kpi-sub">আজ উপস্থিত <?= Bn::digits($kpi['in_today']) ?> জন</span>
    </article>
    <article class="dm-kpi">
        <span class="dm-kpi-label">এই মাসে মোট মজুরি</span>
        <strong class="dm-kpi-val tabular"><?= $money((float) $kpi['wage']) ?></strong>
        <span class="dm-kpi-sub"><?= Bn::digits($kpi['elapsed']) ?> দিন পর্যন্ত · হাজিরা অনুযায়ী</span>
    </article>
    <article class="dm-kpi dm-kpi-amber">
        <span class="dm-kpi-label">মোট অ্যাডভান্স দেওয়া</span>
        <strong class="dm-kpi-val tabular"><?= $money((float) $kpi['advance']) ?></strong>
        <span class="dm-kpi-sub">বেতন থেকে কাটা হবে</span>
    </article>
    <article class="dm-kpi dm-kpi-red">
        <span class="dm-kpi-label">মোট শর্ট</span>
        <strong class="dm-kpi-val tabular"><?= $money((float) $kpi['short']) ?></strong>
        <span class="dm-kpi-sub"><?= Bn::digits($kpi['short_people']) ?> জনের কাছে</span>
    </article>
</section>

<?php if ($rows === []): ?>
    <div class="card empty-state"><p>এখনো কোনো ডেলিভারি ম্যান নেই। আগে "ডেলিভারিম্যান (DSR)" থেকে যোগ করুন।</p></div>
<?php else: ?>

<section class="dm-cards">
    <?php foreach ($rows as $r): ?>
        <?php
        $t = $r['totals'];
        $pct = $t['workdays'] > 0 ? min(100, (int) round($t['worked'] / $t['workdays'] * 100)) : 0;
        $color = $palette[$r['id'] % count($palette)];
        ?>
        <a href="<?= e($link($r['id'])) ?>" class="dm-card <?= $sel && $sel['id'] === $r['id'] ? 'is-selected' : '' ?> <?= $r['active'] ? '' : 'is-off' ?>" data-spa-link>
            <div class="dm-card-head">
                <span class="dm-avatar" style="background:<?= $color ?>">
                    <?php if ($r['photo']): ?><img src="<?= e($r['photo']) ?>" alt=""><?php else: ?><?= e($initial($r['name'])) ?><?php endif; ?>
                    <?php if ($r['in_today']): ?><i class="dm-dot" title="আজ উপস্থিত"></i><?php endif; ?>
                </span>
                <div class="dm-card-id">
                    <strong><?= e($r['name']) ?></strong>
                    <span class="muted small"><?= e(trim(($r['vehicle'] ?: '') . ($r['vehicle'] && $r['zone'] ? ' · ' : '') . ($r['zone'] ?: '')) ?: ($r['active'] ? 'ডেলিভারি ম্যান' : 'নিষ্ক্রিয়')) ?></span>
                </div>
            </div>
            <div class="dm-card-att">
                <span class="muted small">হাজিরা</span>
                <span class="small tabular"><strong><?= $days($t['worked']) ?></strong>/<?= Bn::digits($t['workdays']) ?> দিন</span>
            </div>
            <div class="dm-bar"><span style="width:<?= $pct ?>%"></span></div>
            <div class="dm-pill <?= $r['net'] >= 0 ? 'is-get' : 'is-owe' ?> tabular"><?= $r['net'] >= 0 ? 'পাবে' : 'দেবে' ?> <?= $signed($r['net']) ?></div>
        </a>
    <?php endforeach; ?>
</section>

<?php if ($sel): ?>
<?php
$t = $sel['totals'];
$color = $palette[$sel['id'] % count($palette)];
$base = max(1.0, $sel['wage'] + $sel['over'], $sel['advance'] + $sel['short'] + $sel['paid']);
$wAdv = round($sel['advance'] / $base * 100, 2);
$wShort = round($sel['short'] / $base * 100, 2);
$wPaid = round($sel['paid'] / $base * 100, 2);
$wRest = max(0.0, round(100 - $wAdv - $wShort - $wPaid, 2));
if ($sel['wage'] + $sel['over'] <= 0) { $wRest = 0.0; }
$offset = ((int) date('w', strtotime($month . '-01')) + 1) % 7; // week starts on Saturday
$today = date('Y-m-d');
$typeLabel = ['wage' => 'মজুরি', 'advance' => 'অ্যাডভান্স', 'short' => 'শর্ট', 'over' => 'ওভার', 'payment' => 'পেমেন্ট'];
$statusLabel = ['present' => 'উপস্থিত', 'half' => 'হাফ ডে', 'absent' => 'অনুপস্থিত', 'holiday' => 'ছুটি', 'pending' => 'আজ বাকি', 'future' => 'বাকি দিন', 'none' => 'যোগ দেওয়ার আগে'];
?>
<section class="dm-main">
    <article class="card dm-detail">
        <div class="dm-detail-head">
            <span class="dm-avatar dm-avatar-lg" style="background:<?= $color ?>"><?php if ($sel['photo']): ?><img src="<?= e($sel['photo']) ?>" alt=""><?php else: ?><?= e($initial($sel['name'])) ?><?php endif; ?></span>
            <div>
                <h2 class="dm-name"><?= e($sel['name']) ?></h2>
                <span class="muted small">ডেলিভারি ম্যান<?= $partnerName !== '' ? ' · ' . e($partnerName) : '' ?></span>
            </div>
            <?php if ($sel['active']): ?>
                <span class="badge <?= $sel['in_today'] ? 'badge-success' : 'badge-neutral' ?>"><?= $sel['in_today'] ? '● আজ উপস্থিত' : 'আজ আসেননি' ?></span>
            <?php else: ?><span class="badge badge-neutral">নিষ্ক্রিয়</span><?php endif; ?>
        </div>

        <dl class="dm-info">
            <div><dt>ফোন</dt><dd class="tabular"><?= e(Bn::digits(Phone::format((string) $sel['phone']))) ?></dd></div>
            <div><dt>যোগ দিয়েছে</dt><dd><?= e(Bn::monthYear($sel['joined'])) ?></dd></div>
            <div><dt>ভ্যান / রুট</dt><dd><?= e(trim(($sel['vehicle'] ?: '') . ($sel['vehicle'] && $sel['zone'] ? ' · ' : '') . ($sel['zone'] ?: '')) ?: '—') ?></dd></div>
            <div><dt>দৈনিক মজুরি</dt><dd class="tabular"><?= $sel['daily_wage'] > 0 ? $money($sel['daily_wage']) : 'দেওয়া হয়নি' ?></dd></div>
        </dl>
        <?php if ($sel['daily_wage'] <= 0): ?>
            <p class="dm-warn">দৈনিক মজুরি সেট করা নেই, তাই মজুরি ০ দেখাচ্ছে। "ডেলিভারিম্যান (DSR)" পেজ থেকে সম্পাদনা করে দিন।</p>
        <?php endif; ?>

        <div class="dm-summary">
            <h3 class="dm-sum-title">এই মাসের হিসাব · এক নজরে</h3>
            <div class="dm-tiles">
                <div class="dm-tile is-green"><span class="small">মজুরি · <?= $days($t['worked']) ?> দিন × <?= $money($sel['daily_wage']) ?></span><strong class="tabular">+<?= $money($sel['wage']) ?></strong></div>
                <div class="dm-tile is-yellow"><span class="small">ওভার / বোনাস</span><strong class="tabular">+<?= $money($sel['over']) ?></strong></div>
                <div class="dm-tile is-orange"><span class="small">অ্যাডভান্স নিয়েছে</span><strong class="tabular">−<?= $money($sel['advance']) ?></strong></div>
                <div class="dm-tile is-pink"><span class="small">শর্ট (টাকা কাটা)</span><strong class="tabular">−<?= $money($sel['short']) ?></strong></div>
            </div>
            <?php if ($sel['paid'] > 0): ?>
                <div class="dm-paid-row"><span class="small">বেতন দেওয়া হয়েছে</span><strong class="tabular">−<?= $money($sel['paid']) ?></strong></div>
            <?php endif; ?>
            <div class="dm-stack" aria-hidden="true">
                <span class="s-adv" style="width:<?= $wAdv ?>%"></span><span class="s-short" style="width:<?= $wShort ?>%"></span><span class="s-paid" style="width:<?= $wPaid ?>%"></span><span class="s-rest" style="width:<?= $wRest ?>%"></span>
            </div>
            <div class="dm-result <?= $sel['net'] >= 0 ? 'is-get' : 'is-owe' ?>">
                <span><?= $sel['net'] >= 0 ? 'পাবে' : '⚠ উল্টা দেবে' ?></span>
                <strong class="tabular"><?= $signed($sel['net']) ?></strong>
            </div>
            <?php if ($sel['net'] < 0): ?>
                <p class="muted small">নেগেটিভ: <?= e($sel['name']) ?> আপনাকে দেবে বা পরের মাসে কাটা হবে।</p>
            <?php endif; ?>
            <?php if ($settlementCash && ($settlementCash['short'] > 0 || $settlementCash['over'] > 0)): ?>
            <?php endif; ?>
        </div>
    </article>

    <div class="dm-side">
        <article class="card dm-cal">
            <div class="dm-cal-head">
                <h3 class="section-title">হাজিরা · <?= e($monthLabel) ?></h3>
                <span class="muted small tabular">উপস্থিত <?= Bn::digits($t['present']) ?> · হাফ ডে <?= Bn::digits($t['half']) ?> · অনুপস্থিত <?= Bn::digits($t['absent']) ?> · মোট <?= $days($t['worked']) ?> দিন</span>
            </div>
            <div class="dm-grid">
                <?php foreach ($weekdays as $w): ?><span class="dm-wd"><?= $w ?></span><?php endforeach; ?>
                <?php for ($i = 0; $i < $offset; $i++): ?><span></span><?php endfor; ?>
                <?php foreach ($sel['days'] as $d): ?>
                    <?php
                    $title = $statusLabel[$d['status']] . ($d['time'] ? ' · ' . Bn::time($d['time']) : '') . ($d['late_min'] > 0 ? ' · দেরি ' . Bn::digits($d['late_min']) . ' মি.' : '') . ($d['manual'] ? ' (হাতে দেওয়া)' : '');
                    $canEdit = $d['date'] <= $today && $d['status'] !== 'none';
                    ?>
                    <button type="button" class="dm-day is-<?= e($d['status']) ?> <?= $d['date'] === $today ? 'is-today' : '' ?>"
                        <?= $canEdit ? 'data-day="' . e($d['date']) . '" data-status="' . e($d['status']) . '"' : 'disabled' ?>
                        title="<?= e($title) ?>"><?= Bn::digits($d['day']) ?></button>
                <?php endforeach; ?>
            </div>
            <div class="dm-key">
                <span><i class="k-present"></i>উপস্থিত</span><span><i class="k-half"></i>হাফ ডে</span><span><i class="k-absent"></i>অনুপস্থিত</span><span><i class="k-holiday"></i>ছুটি / বাকি দিন</span>
            </div>
        </article>

        <article class="card dm-ledger">
            <h3 class="section-title">লেনদেন · অ্যাডভান্স, শর্ট, ওভার, পেমেন্ট</h3>
            <div class="table-wrap">
                <table class="data-table">
                    <thead><tr><th>তারিখ</th><th>বিবরণ</th><th class="text-right">টাকা</th><th class="text-right">ব্যালেন্স</th><th></th></tr></thead>
                    <tbody>
                    <?php foreach ($ledger as $e): ?>
                        <tr>
                            <td class="tabular nowrap"><?= $e['type'] === 'wage' ? e(Bn::digits((int) date('j', strtotime($e['from']))) . '–' . Bn::date($e['to'])) : e(Bn::date($e['date'])) ?></td>
                            <td><span class="dm-type is-<?= e($e['type']) ?>"><?= $typeLabel[$e['type']] ?></span>
                                <?= $e['type'] === 'wage' ? 'হাজিরার মজুরি (' . $days((float) $e['worked']) . ' দিন)' : e((string) ($e['note'] ?? '')) ?></td>
                            <td class="text-right tabular <?= $e['amount'] < 0 ? 'is-neg' : 'is-pos' ?>"><?= $signed((float) $e['amount']) ?></td>
                            <td class="text-right tabular <?= $e['balance'] < 0 ? 'is-neg' : '' ?>"><strong><?= $signed((float) $e['balance']) ?></strong></td>
                            <td class="text-right"><?php if ($e['id']): ?><button type="button" class="dm-x" title="মুছুন" data-del-entry="<?= e($e['kind']) ?>" data-id="<?= (int) $e['id'] ?>">×</button><?php endif; ?></td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </article>
    </div>
</section>

<!-- Add advance / short / over / payment -->
<div class="modal-overlay" id="entryModal" aria-hidden="true">
    <div class="modal-panel" role="dialog" aria-modal="true">
        <div class="modal-head">
            <div>
                <h2 class="section-title">লেনদেন যোগ করুন — <?= e($sel['name']) ?></h2>
            </div>
            <button type="button" class="icon-btn" data-modal-close aria-label="বন্ধ করুন">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>
        <form id="entryForm" class="modal-form" novalidate>
            <div class="modal-body">
                <div class="dm-types" role="radiogroup">
                    <?php foreach ([['advance', 'অ্যাডভান্স', 'বেতন থেকে কাটবে'], ['short', 'শর্ট', 'টাকা কাটবে'], ['over', 'ওভার / বোনাস', 'যোগ হবে'], ['payment', 'বেতন পেমেন্ট', 'দেওয়া হয়েছে']] as $i => [$val, $lab, $hint]): ?>
                        <label class="dm-type-opt"><input type="radio" name="type" value="<?= $val ?>" <?= $i === 0 ? 'checked' : '' ?>><span><strong><?= $lab ?></strong><small><?= $hint ?></small></span></label>
                    <?php endforeach; ?>
                </div>
                <div class="form-grid">
                    <div class="form-group"><label>টাকা <span class="req">*</span></label><input name="amount" type="number" min="1" step="0.01" required></div>
                    <div class="form-group"><label>তারিখ</label><input name="date" type="date" value="<?= e(substr($today, 0, 7) === $month ? $today : $month . '-01') ?>" required></div>
                </div>
                <div class="form-group"><label>বিবরণ (ঐচ্ছিক)</label><input name="note" type="text" maxlength="255" placeholder="যেমন: bKash / প্লিন ২ · খুচরা কম"></div>
            </div>
            <div class="modal-error" data-form-error hidden></div>
            <div class="modal-foot">
                <button type="button" class="btn btn-secondary" data-modal-close>বাতিল</button>
                <button type="submit" class="btn btn-primary">সংরক্ষণ করুন</button>
            </div>
        </form>
    </div>
</div>

<!-- Set one day -->
<div class="modal-overlay" id="dayModal" aria-hidden="true">
    <div class="modal-panel" role="dialog" aria-modal="true">
        <div class="modal-head">
            <div>
                <h2 class="section-title" id="dayModalTitle">হাজিরা</h2>
            </div>
            <button type="button" class="icon-btn" data-modal-close aria-label="বন্ধ করুন">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
            </button>
        </div>
        <form id="dayForm" class="modal-form" novalidate>
            <input type="hidden" name="date" value="">
            <div class="modal-body">
                <div class="dm-types" role="radiogroup">
                    <?php foreach ([['present', 'উপস্থিত', 'পুরো দিনের মজুরি'], ['half', 'হাফ ডে', 'অর্ধেক মজুরি'], ['absent', 'অনুপস্থিত', 'মজুরি নেই'], ['holiday', 'ছুটি', 'মজুরি নেই'], ['auto', 'স্বয়ংক্রিয়', 'QR / শুক্রবার নিয়মে ফিরুন']] as [$val, $lab, $hint]): ?>
                        <label class="dm-type-opt"><input type="radio" name="status" value="<?= $val ?>"><span><strong><?= $lab ?></strong><small><?= $hint ?></small></span></label>
                    <?php endforeach; ?>
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
<?php endif; ?>
<?php endif; ?>
</div>
<?php $this->endSection(); ?>
