<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Bn;
use App\Support\Phone;
use Core\Database;

/**
 * Read-only data for the retailer (দোকান) panel. A retailer account is a phone number; it sees every
 * active shop record carrying that phone. "Day" of an order = its trip date, else its order date.
 */
final class RetailerPortal
{
    private const ARRIVED = ['delivered', 'due', 'partial'];
    private const MONTHS = [1 => 'জানু', 'ফেব্রু', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট', 'সেপ্টে', 'অক্টো', 'নভে', 'ডিসে'];
    private const DAY_SQL = 'COALESCE(t.trip_date, o.order_date)';
    private const BILL_SQL = "(CASE WHEN o.status IN ('delivered', 'due', 'partial') THEN o.delivered_sr_total - o.damage_amount ELSE o.order_sr_total END)";

    private static function db(): Database
    {
        return Database::getInstance();
    }

    /** @param list<int> $ids */
    private static function in(array $ids): string
    {
        return implode(',', array_map('intval', $ids)) ?: '0';
    }

    /** @return list<array<string, mixed>> */
    private static function orders(array $ids, string $date): array
    {
        $in = self::in($ids);
        $rows = self::db()->fetchAll(
            "SELECT o.*, c.name AS company, s.name AS sr_name, s.phone AS sr_phone, dm.phone AS dm_phone, t.status AS trip_status, t.dispatched_at, t.trip_date, t.dsr_id, r.lat AS shop_lat, r.lng AS shop_lng,
                    dm.name AS dm_name, pa.name AS partner_name, pa.address AS partner_address, pa.phone AS partner_phone,
                    r.name AS shop_name, r.address AS shop_address, r.phone AS shop_phone
             FROM orders o
             JOIN companies c ON c.id = o.company_id
             JOIN partners pa ON pa.id = o.partner_id
             JOIN retailers r ON r.id = o.retailer_id
             LEFT JOIN salesmen s ON s.id = o.sr_id
             LEFT JOIN trips t ON t.id = o.trip_id
             LEFT JOIN delivery_men dm ON dm.id = t.dsr_id
             WHERE o.retailer_id IN ({$in}) AND o.status <> 'cancelled' AND " . self::DAY_SQL . ' = ?
             ORDER BY o.id',
            [$date]
        );
        if ($rows === []) {
            return [];
        }

        $items = [];
        foreach (self::db()->fetchAll(
            'SELECT oi.*, p.name FROM order_items oi JOIN products p ON p.id = oi.product_id
             WHERE oi.order_id IN (' . self::in(array_column($rows, 'id')) . ') ORDER BY oi.id'
        ) as $it) {
            $items[(int) $it['order_id']][] = $it;
        }

        return array_map(static fn(array $o): array => self::present($o, $items[(int) $o['id']] ?? []), $rows);
    }

    /** @param array<string, mixed> $o @param list<array<string, mixed>> $items */
    private static function present(array $o, array $items): array
    {
        $arrived = in_array($o['status'], self::ARRIVED, true);
        $stage = $arrived ? 'arrived' : (in_array($o['trip_status'], ['dispatched', 'in_review', 'settled'], true) ? 'onway' : 'later');

        $lines = [];
        $sub = $profit = 0.0;
        $hasProfit = false;
        foreach ($items as $it) {
            $ordered = (int) $it['ordered_pcs'];
            $pcs = $arrived ? (int) $it['delivered_pcs'] : $ordered;
            $rate = (float) $it['sr_rate_pc'];
            $mrp = $it['mrp_pc'] !== null ? (float) $it['mrp_pc'] : null;
            $amount = round($pcs * $rate, 2);
            $gain = $mrp !== null ? round($pcs * ($mrp - $rate), 2) : null;
            $sub += $amount;
            if ($gain !== null) {
                $profit += $gain;
                $hasProfit = true;
            }
            $lines[] = [
                'name' => $it['name'], 'mrp' => $mrp, 'pcs' => $pcs, 'rate' => round($rate, 2),
                'amount' => $amount, 'gain' => $gain, 'short' => $arrived ? max(0, $ordered - $pcs) : 0,
            ];
        }
        $sub = round($sub, 2);
        $damage = $arrived ? (float) $o['damage_amount'] : 0.0;
        $total = round($sub - $damage, 2);
        $paid = $arrived ? (float) $o['paid_amount'] : 0.0;
        $due = $arrived ? (float) $o['due_amount'] : 0.0;

        if ($arrived) {
            [$label, $tone] = $due <= 0.004 ? ['পরিশোধিত', 'ok'] : ($paid > 0.004 ? ['আংশিক পরিশোধ', 'warn'] : ['বাকি', 'warn']);
        } else {
            [$label, $tone] = $stage === 'onway' ? ['পথে আছে', 'info'] : ['অপেক্ষমান', 'warn'];
        }

        return [
            'id' => (int) $o['id'],
            'code' => 'HB-' . Bn::digits(str_pad((string) $o['id'], 4, '0', STR_PAD_LEFT)),
            'company' => $o['company'],
            'sr' => $o['sr_name'] ?: 'রেডি সেল',
            'dm' => $o['dm_name'],
            'sr_phone' => $o['sr_phone'] ? Phone::format((string) $o['sr_phone']) : '',
            'dm_phone' => $o['dm_phone'] ? Phone::format((string) $o['dm_phone']) : '',
            'trip_id' => $o['trip_id'] !== null ? (int) $o['trip_id'] : 0,
            'eta' => $stage === 'onway' ? self::eta((int) $o['dsr_id'], (float) $o['shop_lat'], (float) $o['shop_lng']) : null,
            'stage' => $stage,
            'status' => $label,
            'tone' => $tone,
            'time' => $o['delivered_at'] ? date('g:i', strtotime((string) $o['delivered_at'])) : null,
            'delivered_at' => $o['delivered_at'],
            'date' => $o['trip_date'] ?? $o['order_date'],
            'bill' => $arrived ? $total : (float) $o['order_sr_total'],
            'shop' => ['name' => $o['shop_name'], 'address' => $o['shop_address'], 'phone' => $o['shop_phone'] ? Phone::format((string) $o['shop_phone']) : ''],
            'partner' => ['name' => $o['partner_name'], 'address' => $o['partner_address'], 'phone' => $o['partner_phone'] ? Phone::format((string) $o['partner_phone']) : ''],
            'items' => $lines,
            'subtotal' => $sub, 'damage' => $damage, 'total' => $total, 'paid' => $paid, 'due' => $due,
            'mrp_total' => $hasProfit ? round($sub + $profit, 2) : null,
            'profit' => $hasProfit ? round($profit, 2) : null,
            'profit_per_100' => $hasProfit && $sub > 0 ? (int) round($profit / $sub * 100) : null,
            'words' => self::words((int) round($total)),
        ];
    }

    /** @return array{orders: list<array<string, mixed>>, cards: list<array<string, mixed>>, total: float, counts: array<string, int>} */
    public static function day(array $ids, string $date): array
    {
        $orders = self::orders($ids, $date);

        $groups = [];
        foreach ($orders as $o) {
            $groups[$o['trip_id']][] = $o;
        }
        $cards = [];
        $counts = ['arrived' => 0, 'onway' => 0, 'later' => 0];
        $total = 0.0;
        foreach ($groups as $g) {
            $stages = array_column($g, 'stage');
            $stage = !array_diff($stages, ['arrived']) ? 'arrived' : (in_array('onway', $stages, true) ? 'onway' : 'later');
            $counts[$stage]++;
            $sum = round(array_sum(array_column($g, 'bill')), 2);
            $total += $sum;
            $latest = max(array_map(static fn(array $o): string => (string) $o['delivered_at'], $g));
            $companies = array_values(array_unique(array_column($g, 'company')));
            $cards[] = [
                'title' => implode(' + ', $companies) . '-এর মাল',
                'dm' => $g[0]['dm'],
                'stage' => $stage,
                'chip' => match ($stage) {
                    'arrived' => '✓ ' . Bn::digits(date('g:i', strtotime($latest ?: 'now'))) . '-তে এসেছে',
                    'onway' => $g[0]['eta'] !== null ? 'পথে · ' . Bn::digits((string) $g[0]['eta']) . ' মিনিটে' : 'পথে আছে',
                    default => 'পরে আসবে',
                },
                'rows' => array_map(static fn(array $o): array => ['sr' => $o['sr'], 'company' => $o['company'], 'bill' => $o['bill'], 'id' => $o['id']], $g),
                'partner' => $g[0]['partner']['name'],
                'eta' => $g[0]['eta'],
                'srs' => array_values(array_unique(array_map(static fn(array $o): string => ($o['sr'] === 'রেডি সেল' ? 'রেডি সেল' : 'SR ' . $o['sr']) . ' · ' . $o['company'], $g))),
                'total' => $sum,
                'first' => $g[0]['id'],
            ];
        }

        $srs = array_unique(array_filter(array_column($orders, 'sr'), static fn(string $n): bool => $n !== 'রেডি সেল'));

        return ['orders' => $orders, 'cards' => $cards, 'total' => round($total, 2), 'counts' => $counts, 'sr_count' => count($srs)];
    }

    /**
     * Minutes until the delivery man reaches the shop, from his last GPS point (≤15 min old): road ≈ 1.4 × straight
     * line at 18 km/h, at least 2 minutes. Null when unknown.
     */
    public static function eta(int $dsrId, float $lat, float $lng): ?int
    {
        static $cache = [];
        if ($dsrId <= 0 || $lat == 0.0) {
            return null;
        }
        $p = $cache[$dsrId] ??= self::db()->fetch(
            'SELECT lat, lng, recorded_at FROM dsr_locations WHERE dsr_id = ? ORDER BY recorded_at DESC LIMIT 1',
            [$dsrId]
        ) ?: [];
        if ($p === [] || time() - strtotime((string) $p['recorded_at']) > 15 * 60) {
            return null;
        }
        $x = deg2rad((float) $p['lng'] - $lng) * cos(deg2rad($lat));
        $y = deg2rad((float) $p['lat'] - $lat);
        $metres = sqrt($x * $x + $y * $y) * 6371000 * 1.4;

        return max(2, (int) ceil($metres / (18000 / 60)));
    }

    /** @return list<array<string, mixed>> */
    public static function history(array $ids): array
    {
        $in = self::in($ids);
        $rows = self::db()->fetchAll(
            'SELECT ' . self::DAY_SQL . ' AS d, COUNT(DISTINCT COALESCE(o.trip_id, 0)) AS deliveries,
                    COUNT(DISTINCT o.sr_id) AS srs, SUM(' . self::BILL_SQL . ") AS total
             FROM orders o LEFT JOIN trips t ON t.id = o.trip_id
             WHERE o.retailer_id IN ({$in}) AND o.status <> 'cancelled'
             GROUP BY d ORDER BY d DESC LIMIT 60"
        );
        $today = date('Y-m-d');

        return array_map(static function (array $r) use ($today): array {
            $ts = strtotime((string) $r['d']);
            $isToday = $r['d'] === $today;
            $sub = Bn::digits((int) $r['deliveries']) . 'টি ডেলিভারি';
            if ($isToday) {
                $sub = 'আজ · ' . $sub . ($r['srs'] > 0 ? ' · ' . Bn::digits((int) $r['srs']) . ' জন SR' : '');
            }

            return [
                'date' => $r['d'], 'day' => Bn::digits(date('d', $ts)), 'month' => self::MONTHS[(int) date('n', $ts)],
                'total' => (float) $r['total'], 'sub' => $sub, 'today' => $isToday,
            ];
        }, $rows);
    }

    /** Days of a period with their companies, bill and profit, plus the totals (R3). @return array<string, mixed> */
    public static function period(array $ids, string $from, string $to): array
    {
        $in = self::in($ids);
        $profitSql = "SUM(CASE WHEN oi.mrp_pc IS NULL THEN 0 ELSE (CASE WHEN o.status IN ('delivered', 'due', 'partial') THEN oi.delivered_pcs ELSE oi.ordered_pcs END) * (oi.mrp_pc - oi.sr_rate_pc) END)";
        $profit = [];
        foreach (self::db()->fetchAll(
            'SELECT ' . self::DAY_SQL . " AS d, {$profitSql} AS p FROM order_items oi JOIN orders o ON o.id = oi.order_id LEFT JOIN trips t ON t.id = o.trip_id
             WHERE o.retailer_id IN ({$in}) AND o.status <> 'cancelled' AND " . self::DAY_SQL . ' BETWEEN ? AND ? GROUP BY d',
            [$from, $to]
        ) as $r) {
            $profit[$r['d']] = (float) $r['p'];
        }
        $rows = self::db()->fetchAll(
            'SELECT ' . self::DAY_SQL . ' AS d, COUNT(DISTINCT COALESCE(o.trip_id, -o.id)) AS deliveries, SUM(' . self::BILL_SQL . ") AS total,
                    GROUP_CONCAT(DISTINCT c.name ORDER BY c.name SEPARATOR ' · ') AS companies
             FROM orders o LEFT JOIN trips t ON t.id = o.trip_id JOIN companies c ON c.id = o.company_id
             WHERE o.retailer_id IN ({$in}) AND o.status <> 'cancelled' AND " . self::DAY_SQL . ' BETWEEN ? AND ?
             GROUP BY d ORDER BY d DESC',
            [$from, $to]
        );
        $today = date('Y-m-d');
        $yesterday = date('Y-m-d', strtotime('-1 day'));
        $week = ['রবিবার', 'সোমবার', 'মঙ্গলবার', 'বুধবার', 'বৃহস্পতিবার', 'শুক্রবার', 'শনিবার'];
        $out = array_map(static function (array $r) use ($today, $yesterday, $week, $profit): array {
            $ts = strtotime((string) $r['d']);

            return [
                'date' => $r['d'], 'day' => Bn::digits(date('d', $ts)), 'month' => self::MONTHS[(int) date('n', $ts)],
                'title' => $r['d'] === $today ? 'আজ' : ($r['d'] === $yesterday ? 'গতকাল' : $week[(int) date('w', $ts)]),
                'companies' => (string) $r['companies'], 'deliveries' => (int) $r['deliveries'],
                'total' => round((float) $r['total'], 2), 'profit' => isset($profit[$r['d']]) ? round($profit[$r['d']], 2) : null, 'today' => $r['d'] === $today,
            ];
        }, $rows);

        return [
            'from' => $from, 'to' => $to, 'rows' => $out,
            'bought' => round(array_sum(array_column($out, 'total')), 2),
            'profit' => $profit === [] ? null : round(array_sum($profit), 2),
            'days' => count($out), 'deliveries' => array_sum(array_column($out, 'deliveries')),
        ];
    }

    /** Months that have orders, newest first (R3 month picker). @return list<array{value:string, label:string}> */
    public static function months(array $ids): array
    {
        $in = self::in($ids);
        $full = [1 => 'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'];
        $rows = self::db()->fetchAll(
            'SELECT DISTINCT DATE_FORMAT(' . self::DAY_SQL . ", '%Y-%m') AS m FROM orders o LEFT JOIN trips t ON t.id = o.trip_id
             WHERE o.retailer_id IN ({$in}) AND o.status <> 'cancelled' ORDER BY m DESC LIMIT 12"
        );
        $list = array_column($rows, 'm');
        if (!in_array(date('Y-m'), $list, true)) {
            array_unshift($list, date('Y-m'));
        }

        return array_map(static fn(string $m): array => ['value' => $m, 'label' => $full[(int) substr($m, 5, 2)] . ' ' . Bn::digits(substr($m, 0, 4))], $list);
    }

    /** Last 7 days (today included): bought total and profit at MRP. @return array{bought: float, profit: float|null} */
    public static function weekSummary(array $ids): array
    {
        $in = self::in($ids);
        $from = date('Y-m-d', strtotime('-6 days'));
        $bought = (float) (self::db()->fetch(
            'SELECT COALESCE(SUM(' . self::BILL_SQL . "), 0) AS v FROM orders o LEFT JOIN trips t ON t.id = o.trip_id
             WHERE o.retailer_id IN ({$in}) AND o.status <> 'cancelled' AND " . self::DAY_SQL . ' >= ?',
            [$from]
        )['v'] ?? 0);
        $profit = self::db()->fetch(
            "SELECT SUM((CASE WHEN o.status IN ('delivered', 'due', 'partial') THEN oi.delivered_pcs ELSE oi.ordered_pcs END) * (oi.mrp_pc - oi.sr_rate_pc)) AS v
             FROM order_items oi JOIN orders o ON o.id = oi.order_id LEFT JOIN trips t ON t.id = o.trip_id
             WHERE o.retailer_id IN ({$in}) AND o.status <> 'cancelled' AND oi.mrp_pc IS NOT NULL AND " . self::DAY_SQL . ' >= ?',
            [$from]
        )['v'] ?? null;

        return ['bought' => round($bought, 2), 'profit' => $profit !== null ? round((float) $profit, 2) : null];
    }

    public static function dateLabel(string $ymd): string
    {
        $ts = strtotime($ymd);

        return Bn::digits(date('j', $ts)) . ' ' . self::MONTHS[(int) date('n', $ts)] . ' ' . Bn::digits(date('Y', $ts));
    }

    /** @return list<array<string, mixed>> events newest first */
    public static function notifications(array $ids, ?string $seenAt): array
    {
        $in = self::in($ids);
        $since = date('Y-m-d H:i:s', strtotime('-14 days'));
        $ev = [];

        foreach (self::db()->fetchAll(
            "SELECT o.id, o.created_at, o.order_sr_total, c.name AS company, s.name AS sr, " . self::DAY_SQL . " AS d
             FROM orders o JOIN companies c ON c.id = o.company_id JOIN salesmen s ON s.id = o.sr_id LEFT JOIN trips t ON t.id = o.trip_id
             WHERE o.retailer_id IN ({$in}) AND o.status <> 'cancelled' AND o.created_at >= ? ORDER BY o.created_at DESC LIMIT 40",
            [$since]
        ) as $r) {
            $ev[] = ['kind' => 'order', 'at' => $r['created_at'], 'initial' => mb_substr((string) $r['sr'], 0, 1), 'company' => $r['company'],
                'date' => $r['d'], 'order_id' => (int) $r['id'],
                'title' => "SR {$r['sr']} · {$r['company']}",
                'sub' => 'অর্ডার নিয়েছে · ' . self::money((float) $r['order_sr_total']) . ' · মেমো ' . Bn::digits(str_pad((string) $r['id'], 4, '0', STR_PAD_LEFT))];
        }

        foreach (self::db()->fetchAll(
            "SELECT t.id, MAX(t.dispatched_at) AS dispatched_at, MAX(t.trip_date) AS trip_date, MAX(dm.name) AS dm, MAX(t.dsr_id) AS dsr_id, MAX(r.lat) AS lat, MAX(r.lng) AS lng, MAX(pa.name) AS partner, SUM(o.order_sr_total) AS total,
                    GROUP_CONCAT(DISTINCT c.name ORDER BY c.name SEPARATOR ' + ') AS companies
             FROM orders o JOIN trips t ON t.id = o.trip_id JOIN delivery_men dm ON dm.id = t.dsr_id JOIN companies c ON c.id = o.company_id
             JOIN partners pa ON pa.id = o.partner_id JOIN retailers r ON r.id = o.retailer_id
             WHERE o.retailer_id IN ({$in}) AND o.status <> 'cancelled' AND t.dispatched_at >= ?
             GROUP BY t.id ORDER BY MAX(t.dispatched_at) DESC",
            [$since]
        ) as $r) {
            $eta = $r['trip_date'] === date('Y-m-d') ? self::eta((int) $r['dsr_id'], (float) $r['lat'], (float) $r['lng']) : null;
            $ev[] = ['kind' => 'onway', 'at' => $r['dispatched_at'], 'title' => "{$r['dm']} আসছে · {$r['companies']}-এর মাল", 'eta' => $eta,
                'short' => "{$r['dm']} আসছে", 'detail' => "{$r['partner']} · {$r['companies']}" . ($eta !== null ? ' · ' . Bn::digits((string) $eta) . ' মিনিটে' : ' · ' . self::money((float) $r['total'])), 'date' => $r['trip_date']];
        }

        foreach (self::db()->fetchAll(
            "SELECT o.trip_id, dm.name AS dm, MAX(o.delivered_at) AS at, SUM(o.delivered_sr_total - o.damage_amount) AS total,
                    MAX(" . self::DAY_SQL . ") AS d, MAX(pa.name) AS partner, GROUP_CONCAT(DISTINCT c.name ORDER BY c.name SEPARATOR ' + ') AS companies
             FROM orders o LEFT JOIN trips t ON t.id = o.trip_id LEFT JOIN delivery_men dm ON dm.id = t.dsr_id
             JOIN partners pa ON pa.id = o.partner_id JOIN companies c ON c.id = o.company_id
             WHERE o.retailer_id IN ({$in}) AND o.status IN ('delivered', 'due', 'partial') AND o.delivered_at >= ?
             GROUP BY o.trip_id, dm.name ORDER BY at DESC",
            [$since]
        ) as $r) {
            $ev[] = ['kind' => 'arrived', 'at' => $r['at'], 'title' => ($r['dm'] ?: 'ডেলিভারি ম্যান') . ' মাল দিয়ে গেছে · ' . self::money((float) $r['total']),
                'short' => ($r['dm'] ?: 'ডেলিভারি ম্যান') . ' মাল দিয়ে গেছে', 'detail' => "{$r['partner']} · {$r['companies']} · " . self::money((float) $r['total']), 'date' => $r['d']];
        }

        usort($ev, static fn(array $a, array $b): int => strcmp((string) $b['at'], (string) $a['at']));
        $seen = $seenAt !== null ? strtotime($seenAt) : 0;
        $today = date('Y-m-d');
        $yesterday = date('Y-m-d', strtotime('-1 day'));

        return array_map(static function (array $e) use ($seen, $today, $yesterday): array {
            $ts = strtotime((string) $e['at']);
            $day = date('Y-m-d', $ts);
            $h = (int) date('G', $ts);
            $period = $h < 5 ? 'রাত' : ($h < 12 ? 'সকাল' : ($h < 16 ? 'দুপুর' : ($h < 18 ? 'বিকাল' : ($h < 20 ? 'সন্ধ্যা' : 'রাত'))));
            $e['unread'] = $ts > $seen;
            $e['group'] = $day === $today ? 'আজ' : ($day === $yesterday ? 'গতকাল' : self::dateLabel($day));
            $e['when'] = $day === $today && time() - $ts < 60 ? 'এইমাত্র' : ($e['kind'] === 'order' ? "{$period} " : '') . Bn::digits(date('g:i', $ts));

            return $e;
        }, array_slice($ev, 0, 50));
    }

    private static function money(float $v): string
    {
        return '৳' . Bn::digits(number_format($v));
    }

    /** Bangla words for a whole taka amount, e.g. 2484 → "দুই হাজার চারশত চুরাশি". */
    public static function words(int $n): string
    {
        static $w = [
            'শূন্য', 'এক', 'দুই', 'তিন', 'চার', 'পাঁচ', 'ছয়', 'সাত', 'আট', 'নয়', 'দশ', 'এগারো', 'বারো', 'তেরো', 'চৌদ্দ', 'পনেরো', 'ষোলো', 'সতেরো', 'আঠারো', 'উনিশ',
            'বিশ', 'একুশ', 'বাইশ', 'তেইশ', 'চব্বিশ', 'পঁচিশ', 'ছাব্বিশ', 'সাতাশ', 'আটাশ', 'ঊনত্রিশ', 'ত্রিশ', 'একত্রিশ', 'বত্রিশ', 'তেত্রিশ', 'চৌত্রিশ', 'পঁয়ত্রিশ', 'ছত্রিশ', 'সাঁইত্রিশ', 'আটত্রিশ', 'ঊনচল্লিশ',
            'চল্লিশ', 'একচল্লিশ', 'বিয়াল্লিশ', 'তেতাল্লিশ', 'চুয়াল্লিশ', 'পঁয়তাল্লিশ', 'ছেচল্লিশ', 'সাতচল্লিশ', 'আটচল্লিশ', 'ঊনপঞ্চাশ', 'পঞ্চাশ', 'একান্ন', 'বাহান্ন', 'তিপ্পান্ন', 'চুয়ান্ন', 'পঞ্চান্ন', 'ছাপ্পান্ন', 'সাতান্ন', 'আটান্ন', 'ঊনষাট',
            'ষাট', 'একষট্টি', 'বাষট্টি', 'তেষট্টি', 'চৌষট্টি', 'পঁয়ষট্টি', 'ছেষট্টি', 'সাতষট্টি', 'আটষট্টি', 'ঊনসত্তর', 'সত্তর', 'একাত্তর', 'বাহাত্তর', 'তিয়াত্তর', 'চুয়াত্তর', 'পঁচাত্তর', 'ছিয়াত্তর', 'সাতাত্তর', 'আটাত্তর', 'ঊনআশি',
            'আশি', 'একাশি', 'বিরাশি', 'তিরাশি', 'চুরাশি', 'পঁচাশি', 'ছিয়াশি', 'সাতাশি', 'আটাশি', 'ঊননব্বই', 'নব্বই', 'একানব্বই', 'বিরানব্বই', 'তিরানব্বই', 'চুরানব্বই', 'পঁচানব্বই', 'ছিয়ানব্বই', 'সাতানব্বই', 'আটানব্বই', 'নিরানব্বই',
        ];
        if ($n <= 0) {
            return 'শূন্য টাকা মাত্র';
        }
        $parts = [];
        foreach ([10000000 => 'কোটি', 100000 => 'লাখ', 1000 => 'হাজার'] as $unit => $name) {
            if ($n >= $unit) {
                $parts[] = $w[intdiv($n, $unit) % 100] . ' ' . $name;
                $n %= $unit;
            }
        }
        if ($n >= 100) {
            $parts[] = $w[intdiv($n, 100)] . 'শত';
            $n %= 100;
        }
        if ($n > 0) {
            $parts[] = $w[$n];
        }

        return implode(' ', $parts) . ' টাকা মাত্র';
    }
}
