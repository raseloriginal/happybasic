<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Bn;
use Core\Database;

/**
 * SR day report and the figures the SR app shows around it. Nothing here is stored: visits and duty come from the
 * SR's own GPS points (sr_locations) matched against shop locations, everything else from orders.
 */
final class SrReport
{
    private const DAYS = ['রবি', 'সোম', 'মঙ্গল', 'বুধ', 'বৃহস্পতি', 'শুক্র', 'শনি'];
    private const MONTHS = [1 => 'জানু', 'ফেব্রু', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট', 'সেপ্টে', 'অক্টো', 'নভে', 'ডিসে'];
    private const MONTHS_FULL = [1 => 'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'];
    /** A shop counts as visited when the SR's phone was this close to it. */
    private const VISIT_METRES = 40;
    /** Orders that count: not withdrawn by the SR (a cancel at delivery keeps its trip). */
    private const COUNTED = "(o.status <> 'cancelled' OR o.trip_id IS NOT NULL)";
    private const DONE = ['delivered', 'due', 'partial'];

    private static function db(): Database
    {
        return Database::getInstance();
    }

    // ---------------------------------------------------------------- duty and visits from GPS

    /** First and last GPS point of the day: auto attendance. @return array<string, mixed> */
    public static function duty(int $srId, string $date): array
    {
        $r = self::db()->fetch(
            'SELECT MIN(recorded_at) AS a, MAX(recorded_at) AS b FROM sr_locations WHERE sr_id = ? AND recorded_at BETWEEN ? AND ?',
            [$srId, "{$date} 00:00:00", "{$date} 23:59:59"]
        );
        if (empty($r['a'])) {
            return ['state' => 'out', 'start' => null, 'end' => null, 'minutes' => 0, 'label' => 'হাজিরা হয়নি', 'sub' => 'লোকেশন চালু হলে নিজে থেকে হাজিরা হবে'];
        }
        $a = strtotime((string) $r['a']);
        $b = strtotime((string) $r['b']);
        $live = $date === date('Y-m-d') && time() - $b < 30 * 60;
        $mins = (int) round((($live ? time() : $b) - $a) / 60);
        $span = Bn::digits(intdiv($mins, 60) . 'ঘ ' . ($mins % 60) . 'মি');

        return [
            'state' => $live ? 'in' : 'done',
            'start' => date('H:i', $a), 'end' => $live ? null : date('H:i', $b), 'minutes' => $mins, 'span' => $span,
            'label' => $live ? 'ডিউটিতে · শুরু ' . Bn::digits(date('g:i', $a)) : 'কাজ শেষ · ' . Bn::digits(date('g:i', $a) . ' – ' . date('g:i', $b)),
            'sub' => $live ? 'কাজ চলছে ' . $span : 'মোট ' . $span,
        ];
    }

    /**
     * Shops the SR stood at (GPS within 40 m) or took an order from on a day.
     * @return array<int, array{id:int, name:string, at:?string, ordered:bool}>
     */
    public static function visits(int $srId, string $date): array
    {
        $out = [];
        $pts = [];
        foreach (self::db()->fetchAll(
            'SELECT lat, lng, recorded_at FROM sr_locations WHERE sr_id = ? AND recorded_at BETWEEN ? AND ? ORDER BY recorded_at',
            [$srId, "{$date} 00:00:00", "{$date} 23:59:59"]
        ) as $p) {
            $k = round((float) $p['lat'], 4) . ',' . round((float) $p['lng'], 4);
            $pts[$k] ??= [(float) $p['lat'], (float) $p['lng'], (string) $p['recorded_at']];
        }
        if ($pts !== []) {
            $lats = array_column($pts, 0);
            $lngs = array_column($pts, 1);
            $pad = 0.0006;
            $shops = self::db()->fetchAll(
                "SELECT id, name, lat, lng FROM retailers WHERE status = 'active' AND lat IS NOT NULL AND lng IS NOT NULL AND lat <> 0
                   AND lat BETWEEN ? AND ? AND lng BETWEEN ? AND ?",
                [min($lats) - $pad, max($lats) + $pad, min($lngs) - $pad, max($lngs) + $pad]
            );
            foreach ($shops as $s) {
                $sl = (float) $s['lat'];
                $sg = (float) $s['lng'];
                foreach ($pts as [$la, $lg, $at]) {
                    if (abs($la - $sl) > 0.0005 || abs($lg - $sg) > 0.0005) {
                        continue;
                    }
                    if (self::metres($la, $lg, $sl, $sg) <= self::VISIT_METRES) {
                        $out[(int) $s['id']] = ['id' => (int) $s['id'], 'name' => (string) $s['name'], 'at' => $at, 'ordered' => false];
                        break;
                    }
                }
            }
        }
        foreach (self::db()->fetchAll(
            'SELECT o.retailer_id, MIN(o.created_at) AS at, MAX(o.retailer_name_snapshot) AS name FROM orders o
             WHERE o.sr_id = ? AND o.order_date = ? AND ' . self::COUNTED . ' GROUP BY o.retailer_id',
            [$srId, $date]
        ) as $o) {
            $id = (int) $o['retailer_id'];
            $out[$id] = ['id' => $id, 'name' => $out[$id]['name'] ?? (string) $o['name'], 'at' => $out[$id]['at'] ?? (string) $o['at'], 'ordered' => true];
        }
        uasort($out, static fn(array $a, array $b): int => strcmp((string) $a['at'], (string) $b['at']));

        return $out;
    }

    /** Visited shops that gave no order, for the order lists ("ভিজিট · অর্ডার দেয়নি"). @return list<array<string, mixed>> */
    public static function noOrder(int $srId, string $date): array
    {
        return array_values(array_map(
            static fn(array $v): array => ['id' => $v['id'], 'name' => $v['name'], 'time' => $v['at'] ? Bn::digits(date('g:i', strtotime($v['at']))) : ''],
            array_filter(self::visits($srId, $date), static fn(array $v): bool => !$v['ordered'])
        ));
    }

    private static function metres(float $a, float $b, float $c, float $d): float
    {
        $x = deg2rad($d - $b) * cos(deg2rad(($a + $c) / 2));
        $y = deg2rad($c - $a);

        return sqrt($x * $x + $y * $y) * 6371000;
    }

    // ---------------------------------------------------------------- one day

    /** @return list<array<string, mixed>> the SR's counted orders of a day */
    private static function orders(int $srId, string $date): array
    {
        return self::db()->fetchAll(
            'SELECT o.id, o.retailer_id, o.retailer_name_snapshot AS shop, o.status, o.trip_id, o.order_sr_total, o.delivered_sr_total,
                    o.damage_amount, o.order_oc, o.delivery_oc, o.cancel_reason,
                    (SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id) AS line_count
             FROM orders o WHERE o.sr_id = ? AND o.order_date = ? AND ' . self::COUNTED . ' ORDER BY o.id',
            [$srId, $date]
        );
    }

    /** @param list<array<string, mixed>> $orders @return array<string, mixed>|null figures of one day, null when nothing was ordered */
    private static function stat(int $srId, string $date, array $orders, bool $withVisits = true): ?array
    {
        if ($orders === []) {
            return null;
        }
        $o = $dl = $can = $part = $lines = 0.0;
        $settled = 0;
        foreach ($orders as $r) {
            $o += (float) $r['order_sr_total'];
            $lines += (int) $r['line_count'];
            if ($r['status'] === 'cancelled') {
                $can += (float) $r['order_sr_total'];
                $settled++;
            } elseif (in_array($r['status'], self::DONE, true)) {
                $dl += (float) $r['delivered_sr_total'];
                $part += max(0.0, (float) $r['order_sr_total'] - (float) $r['delivered_sr_total']);
                $settled++;
            }
        }
        $n = count($orders);
        $visits = $withVisits ? count(self::visits($srId, $date)) : $n;
        $oc = self::db()->fetch(
            'SELECT COALESCE(SUM(CASE WHEN oi.order_oc > 0 THEN oi.order_oc END), 0) AS ov, COALESCE(SUM(CASE WHEN oi.order_oc < 0 THEN oi.order_oc END), 0) AS cm
             FROM order_items oi JOIN orders o ON o.id = oi.order_id WHERE o.sr_id = ? AND o.order_date = ? AND o.status <> \'cancelled\'',
            [$srId, $date]
        );
        $new = (int) (self::db()->fetch(
            'SELECT COUNT(*) AS c FROM retailers WHERE created_by_sr_id = ? AND DATE(created_at) = ?',
            [$srId, $date]
        )['c'] ?? 0);

        return [
            'o' => round($o, 2), 'dl' => $settled === 0 ? null : round($dl, 2), 'can' => round($can, 2), 'part' => round($part, 2),
            'n' => $n, 'visit' => max($visits, $n), 'strike' => (int) round($n / max($visits, $n) * 100),
            'avg' => round($o / $n, 2), 'lines' => round($lines / $n, 1), 'nw' => $new,
            'ov' => round((float) $oc['ov'], 2), 'cm' => round(abs((float) $oc['cm']), 2),
        ];
    }

    private static function label(string $ymd): string
    {
        $t = strtotime($ymd);

        return self::DAYS[(int) date('w', $t)] . ', ' . Bn::digits(date('d', $t)) . ' ' . self::MONTHS[(int) date('n', $t)] . ' ' . Bn::digits(date('Y', $t));
    }

    private static function pct(float $a, float $b): int
    {
        return $b > 0 ? (int) round($a / $b * 100) : 0;
    }

    /** @return array<string, mixed> */
    public static function build(array $sr, string $date): array
    {
        $srId = (int) $sr['id'];
        $today = date('Y-m-d');
        $orders = self::orders($srId, $date);
        $cur = self::stat($srId, $date, $orders);
        $prevDate = self::db()->fetch(
            'SELECT MAX(o.order_date) AS d FROM orders o WHERE o.sr_id = ? AND o.order_date < ? AND ' . self::COUNTED,
            [$srId, $date]
        )['d'] ?? null;
        $pv = $prevDate ? self::stat($srId, (string) $prevDate, self::orders($srId, (string) $prevDate)) : null;

        // KPI table: [label, this day, previous day, higher is better, kind]
        $kpis = [];
        if ($cur !== null) {
            $wait = $cur['dl'] === null;
            $row = static function (string $l, $v, $p, bool $up, string $kind, $vn = null, $pn = null) use (&$kpis): void {
                $kpis[] = ['label' => $l, 'value' => $v, 'prev' => $p, 'up_good' => $up, 'kind' => $kind, 'vn' => $vn, 'pn' => $pn];
            };
            $row('অর্ডার', $cur['o'], $pv['o'] ?? null, true, 'money');
            $row('ডেলিভারি', $wait ? null : $cur['dl'], $pv['dl'] ?? null, true, 'money');
            $row('ডেলিভারি রেট', $wait ? null : self::pct($cur['dl'], $cur['o']), $pv && $pv['dl'] !== null ? self::pct($pv['dl'], $pv['o']) : null, true, 'pct');
            $row('বাতিল রেশিও', $wait ? null : self::pct($cur['can'], $cur['o']), $pv && $pv['dl'] !== null ? self::pct($pv['can'], $pv['o']) : null, false, 'pct');
            $row('স্ট্রাইক রেট', $cur['strike'], $pv['strike'] ?? null, true, 'pct');
            $row('ভিজিট / অর্ডার', $cur['visit'] . ' / ' . $cur['n'], $pv ? $pv['visit'] . ' / ' . $pv['n'] : null, true, 'pair', $cur['n'], $pv['n'] ?? null);
            $row('গড় অর্ডার', $cur['avg'], $pv['avg'] ?? null, true, 'money');
            $row('লাইন / অর্ডার', $cur['lines'], $pv['lines'] ?? null, true, 'num');
            $row('নতুন দোকান', $cur['nw'], $pv['nw'] ?? null, true, 'num');
        }

        // 1. Shops: order / delivered / cancelled / over-commission
        $shops = [];
        foreach ($orders as $r) {
            $id = (int) $r['retailer_id'];
            $done = in_array($r['status'], self::DONE, true);
            $s = $shops[$id] ?? ['name' => $r['shop'], 'order' => 0.0, 'delivered' => null, 'cancel' => 0.0, 'oc' => 0.0];
            $s['order'] += (float) $r['order_sr_total'];
            if ($done) {
                $s['delivered'] = ($s['delivered'] ?? 0) + (float) $r['delivered_sr_total'];
                $s['oc'] += (float) $r['delivery_oc'];
                $s['cancel'] += max(0.0, (float) $r['order_sr_total'] - (float) $r['delivered_sr_total']);
            } elseif ($r['status'] === 'cancelled') {
                $s['delivered'] = $s['delivered'] ?? 0.0;
                $s['cancel'] += (float) $r['order_sr_total'];
            } else {
                $s['oc'] += (float) $r['order_oc'];
            }
            $shops[$id] = $s;
        }
        $shops = array_values(array_map(static fn(array $s): array => array_map(static fn($v) => is_float($v) ? round($v, 2) : $v, $s), $shops));

        // 2. Why cancelled / took less
        $why = [];
        foreach ($orders as $r) {
            $lost = $r['status'] === 'cancelled' ? (float) $r['order_sr_total']
                : (in_array($r['status'], self::DONE, true) ? max(0.0, (float) $r['order_sr_total'] - (float) $r['delivered_sr_total']) : 0.0);
            if ($lost <= 0.004) {
                continue;
            }
            $raw = preg_replace('/^DSR:\s*/i', '', trim((string) $r['cancel_reason'])) ?: 'কারণ লেখা হয়নি';
            $base = explode(' (', $raw)[0];
            $label = $raw === 'Cancelled by SR' ? 'SR বাতিল করেছে' : Bn::cancelReason($base);
            $why[$label] = ($why[$label] ?? 0) + $lost;
        }
        arsort($why);
        $why = array_map(static fn(string $k, float $v): array => ['name' => $k, 'amount' => round($v, 2)], array_keys($why), $why);

        // 3. Products (delivered when delivery happened, else ordered)
        $waiting = $cur === null || $cur['dl'] === null;
        $prod = self::db()->fetchAll(
            'SELECT p.name, SUM(' . ($waiting ? 'oi.ordered_pcs' : "CASE WHEN o.status IN ('delivered','due','partial') THEN oi.delivered_pcs ELSE 0 END") . ') AS pcs,
                    SUM(' . ($waiting ? 'oi.ordered_pcs' : "CASE WHEN o.status IN ('delivered','due','partial') THEN oi.delivered_pcs ELSE 0 END") . ' * oi.sr_rate_pc) AS v
             FROM order_items oi JOIN orders o ON o.id = oi.order_id JOIN products p ON p.id = oi.product_id
             WHERE o.sr_id = ? AND o.order_date = ? AND ' . self::COUNTED . ' GROUP BY p.id, p.name HAVING v > 0 ORDER BY v DESC',
            [$srId, $date]
        );
        $products = array_map(static fn(array $p): array => ['name' => $p['name'], 'pcs' => (int) $p['pcs'], 'value' => round((float) $p['v'], 2)], array_slice($prod, 0, 5));
        if (count($prod) > 5) {
            $rest = array_slice($prod, 5);
            $products[] = ['name' => 'অন্যান্য', 'pcs' => (int) array_sum(array_column($rest, 'pcs')), 'value' => round(array_sum(array_map('floatval', array_column($rest, 'v'))), 2)];
        }

        // 5. Last 7 days ending on the date
        $week = [];
        for ($k = 6; $k >= 0; $k--) {
            $d = date('Y-m-d', strtotime("{$date} -{$k} days"));
            $s = self::stat($srId, $d, self::orders($srId, $d), false);
            $t = strtotime($d);
            $week[] = [
                'date' => $d, 'label' => self::DAYS[(int) date('w', $t)] . ' ' . Bn::digits(date('j', $t)),
                'order' => $s['o'] ?? null, 'delivered' => $s['dl'] ?? null, 'cancel' => $s ? $s['can'] + $s['part'] : null, 'off' => $s === null,
            ];
        }

        $ov = $cur['ov'] ?? 0.0;
        $cm = $cur['cm'] ?? 0.0;
        $t = strtotime($date);

        return [
            'date' => $date, 'today' => $today, 'label' => self::label($date),
            'no' => ($sr['code'] ?: 'SR-' . str_pad((string) $srId, 4, '0', STR_PAD_LEFT)) . '-' . date('dm', $t),
            'prev_date' => $prevDate, 'prev_label' => $prevDate ? self::label((string) $prevDate) : null,
            'waiting' => $waiting, 'empty' => $cur === null,
            'stat' => $cur, 'prev' => $pv, 'kpis' => $kpis,
            'flow' => $cur === null ? null : ['order' => $cur['o'], 'cancel' => $cur['can'], 'part' => $cur['part'], 'delivered' => $cur['dl']],
            'shops' => $shops,
            'totals' => ['over' => $ov, 'commission' => $cm, 'net' => round($ov - $cm, 2)],
            'reasons' => $why, 'products' => $products, 'week' => $week,
            'no_order' => self::noOrder($srId, $date),
            'duty' => self::duty($srId, $date),
            'target' => self::target($sr),
            'oc_month' => self::ocMonth($srId),
        ];
    }

    // ---------------------------------------------------------------- target (today / week / month)

    /** @return list<array<string, mixed>> */
    public static function target(array $sr): array
    {
        $srId = (int) $sr['id'];
        $daily = (float) ($sr['daily_target'] ?? 0);
        $today = date('Y-m-d');
        // Bangladesh work week: Saturday to Thursday (Friday off).
        $weekStart = date('Y-m-d', strtotime('-' . (((int) date('w')) + 1) % 7 . ' days'));
        $monthStart = date('Y-m-01');
        $periods = [
            ['আজ', $today, $today, $daily],
            ['সপ্তাহ', $weekStart, $today, $daily * 6],
            ['মাস', $monthStart, $today, self::monthGoal($sr)],
        ];
        $out = [];
        foreach ($periods as [$label, $from, $to, $goal]) {
            $r = self::db()->fetch(
                "SELECT COALESCE(SUM(order_sr_total), 0) AS v, COUNT(*) AS n FROM orders WHERE sr_id = ? AND order_date BETWEEN ? AND ? AND status <> 'cancelled'",
                [$srId, $from, $to]
            );
            $visits = 0;
            $orders = (int) $r['n'];
            for ($t = strtotime($from); $t <= strtotime($to); $t += 86400) {
                $visits += count(self::visits($srId, date('Y-m-d', $t)));
            }
            $visits = max($visits, $orders);
            $new = (int) (self::db()->fetch(
                'SELECT COUNT(*) AS c FROM retailers WHERE created_by_sr_id = ? AND DATE(created_at) BETWEEN ? AND ?',
                [$srId, $from, $to]
            )['c'] ?? 0);
            $tops = self::db()->fetchAll(
                "SELECT p.name, SUM(oi.ordered_pcs * oi.sr_rate_pc) AS v FROM order_items oi JOIN orders o ON o.id = oi.order_id JOIN products p ON p.id = oi.product_id
                 WHERE o.sr_id = ? AND o.order_date BETWEEN ? AND ? AND o.status <> 'cancelled' GROUP BY p.id, p.name ORDER BY v DESC LIMIT 3",
                [$srId, $from, $to]
            );
            $out[] = [
                'label' => $label, 'sold' => round((float) $r['v'], 2), 'goal' => round($goal, 2),
                'kpis' => [
                    ['v' => Bn::digits((string) $orders), 'l' => 'অর্ডার'],
                    ['v' => Bn::digits($orders . '/' . $visits), 'l' => 'ভিজিট'],
                    ['v' => Bn::digits((string) ($visits > 0 ? (int) round($orders / $visits * 100) : 0)) . '%', 'l' => 'স্ট্রাইক'],
                    ['v' => Bn::digits((string) $new), 'l' => 'নতুন দোকান'],
                ],
                'tops' => array_map(static fn(array $p): array => ['name' => $p['name'], 'value' => round((float) $p['v'], 2)], $tops),
            ];
        }

        return $out;
    }

    /** This month's goal: the monthly target, else the daily target on every working day (Friday off). */
    public static function monthGoal(array $sr): float
    {
        if ((float) ($sr['monthly_target'] ?? 0) > 0) {
            return (float) $sr['monthly_target'];
        }
        $n = 0;
        for ($t = strtotime(date('Y-m-01')); $t <= strtotime(date('Y-m-t')); $t += 86400) {
            $n += (int) date('w', $t) === 5 ? 0 : 1;
        }

        return round((float) ($sr['daily_target'] ?? 0) * $n, 2);
    }

    /** Over / commission for this month (settled at month end). @return array<string, mixed> */
    public static function ocMonth(int $srId): array
    {
        $r = SrStats::range($srId, date('Y-m-01'), date('Y-m-d'));
        $over = (float) $r['over_oc'];
        $comm = abs((float) $r['comm_oc']);

        return [
            'label' => self::MONTHS_FULL[(int) date('n')] . ' · ' . Bn::digits(date('t')) . ' তারিখ সেটেল',
            'over' => round($over, 2), 'commission' => round($comm, 2), 'net' => round($over - $comm, 2),
        ];
    }

    // ---------------------------------------------------------------- notifications

    /** @return list<array<string, mixed>> what happened to the SR's orders in the last 14 days, newest first */
    public static function notifications(array $sr, ?string $seenAt): array
    {
        $since = date('Y-m-d H:i:s', strtotime('-14 days'));
        $ev = [];
        foreach (self::db()->fetchAll(
            "SELECT o.id, o.retailer_name_snapshot AS shop, o.status, o.order_sr_total, o.delivered_sr_total, o.cancel_reason, o.delivered_at,
                    c.name AS company, dm.name AS dm
             FROM orders o JOIN companies c ON c.id = o.company_id LEFT JOIN trips t ON t.id = o.trip_id LEFT JOIN delivery_men dm ON dm.id = t.dsr_id
             WHERE o.sr_id = ? AND o.delivered_at >= ? AND (o.status IN ('delivered', 'due', 'partial') OR (o.status = 'cancelled' AND o.trip_id IS NOT NULL))
             ORDER BY o.delivered_at DESC LIMIT 60",
            [$sr['id'], $since]
        ) as $r) {
            $reason = preg_replace('/^DSR:\s*/i', '', trim((string) $r['cancel_reason']));
            $reason = $reason ? Bn::cancelReason(explode(' (', $reason)[0]) : '';
            $short = (float) $r['order_sr_total'] - (float) $r['delivered_sr_total'];
            [$kind, $what] = match (true) {
                $r['status'] === 'cancelled' => ['cancel', 'অর্ডার বাতিল' . ($reason ? " · {$reason}" : '')],
                $short > 0.5 => ['short', 'কম নিয়েছে · ' . self::money($short) . ' কম' . ($reason ? " · {$reason}" : '')],
                default => ['done', 'ডেলিভারি হয়েছে · ' . self::money((float) $r['delivered_sr_total'])],
            };
            $ev[] = [
                'kind' => $kind, 'at' => $r['delivered_at'], 'order_id' => (int) $r['id'],
                'title' => "{$r['shop']} · {$r['company']}", 'sub' => $what . ($r['dm'] ? " · DM {$r['dm']}" : ''),
                'initial' => mb_substr((string) $r['shop'], 0, 1),
            ];
        }
        $seen = $seenAt !== null ? strtotime($seenAt) : 0;
        $today = date('Y-m-d');
        $yesterday = date('Y-m-d', strtotime('-1 day'));

        return array_map(static function (array $e) use ($seen, $today, $yesterday): array {
            $ts = strtotime((string) $e['at']);
            $day = date('Y-m-d', $ts);
            $e['unread'] = $ts > $seen;
            $e['group'] = $day === $today ? 'আজ' : ($day === $yesterday ? 'গতকাল' : RetailerPortal::dateLabel($day));
            $e['when'] = $day === $today && time() - $ts < 60 ? 'এইমাত্র' : Bn::digits(date('g:i', $ts));

            return $e;
        }, $ev);
    }

    private static function money(float $v): string
    {
        return '৳' . Bn::digits(number_format($v));
    }
}
