<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\HttpError;
use Core\Database;

/**
 * Unpaid orders of a partner: approve, take the goods back, collect the money, undo.
 *
 * remaining = orders.due_amount − due_entries − old dues DSRs collected on trips (oldest settled order first).
 * Orders and closed days are never rewritten. Money and goods move only after the trip is settled, because the
 * due reaches retailers.due_balance at that moment; until then only approval is possible.
 */
final class Due
{
    private static function db(): Database
    {
        return Database::getInstance();
    }

    /** @return array{limit:float, days:int} */
    public static function settings(int $partnerId): array
    {
        $p = self::db()->fetch('SELECT due_limit, due_days FROM partners WHERE id = ?', [$partnerId]);

        return ['limit' => (float) $p['due_limit'], 'days' => (int) $p['due_days']];
    }

    public static function saveSettings(int $partnerId, float $limit, int $days): void
    {
        if ($limit < 0 || $limit > 99999999 || $days < 1 || $days > 365) {
            throw new HttpError('সীমা ০ বা তার বেশি এবং দিন ১–৩৬৫-এর মধ্যে দিন।', 422);
        }
        self::db()->execute('UPDATE partners SET due_limit = ?, due_days = ? WHERE id = ?', [round($limit, 2), $days, $partnerId]);
    }

    /** null = back to the default limit */
    public static function saveShopLimit(int $partnerId, int $retailerId, ?float $limit): void
    {
        Retailer::findForPartner($partnerId, $retailerId);
        if ($limit === null) {
            self::db()->execute('DELETE FROM due_limits WHERE partner_id = ? AND retailer_id = ?', [$partnerId, $retailerId]);
            return;
        }
        if ($limit < 0 || $limit > 99999999) {
            throw new HttpError('সঠিক সীমা দিন।', 422);
        }
        self::db()->execute(
            'INSERT INTO due_limits (partner_id, retailer_id, amount) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE amount = VALUES(amount)',
            [$partnerId, $retailerId, round($limit, 2)]
        );
    }

    /** Every order that was left unpaid, oldest first. @return list<array<string, mixed>> */
    public static function all(int $partnerId): array
    {
        $db = self::db();
        $set = self::settings($partnerId);
        $rows = $db->fetchAll(
            "SELECT o.id, o.order_code, o.order_date, o.delivered_at, o.retailer_id, o.retailer_name_snapshot, o.delivered_sr_total,
                    o.paid_amount, o.due_amount, t.trip_code, t.trip_date, t.status AS trip_status, dm.name AS dsr, s.name AS sr,
                    r.phone, a.amount AS approved_amount, l.amount AS shop_limit
             FROM orders o
             JOIN trips t ON t.id = o.trip_id
             JOIN delivery_men dm ON dm.id = t.dsr_id
             LEFT JOIN salesmen s ON s.id = o.sr_id
             LEFT JOIN retailers r ON r.id = o.retailer_id
             LEFT JOIN due_approvals a ON a.order_id = o.id
             LEFT JOIN due_limits l ON l.partner_id = o.partner_id AND l.retailer_id = o.retailer_id
             WHERE o.partner_id = ? AND o.due_amount > 0.004 AND o.status IN ('due', 'partial', 'delivered')
             ORDER BY o.order_date, o.id",
            [$partnerId]
        );

        $entries = [];
        foreach ($db->fetchAll('SELECT * FROM due_entries WHERE partner_id = ? ORDER BY id', [$partnerId]) as $e) {
            $entries[(int) $e['order_id']][] = $e;
        }
        $pool = [];
        foreach ($db->fetchAll(
            'SELECT c.retailer_id, SUM(c.amount) AS amt FROM retailer_due_collections c JOIN trips t ON t.id = c.trip_id
             WHERE t.partner_id = ? GROUP BY c.retailer_id',
            [$partnerId]
        ) as $c) {
            $pool[(int) $c['retailer_id']] = (float) $c['amt'];
        }
        $items = [];
        if ($rows !== []) {
            $ids = implode(',', array_map(static fn(array $r): int => (int) $r['id'], $rows));
            foreach ($db->fetchAll(
                "SELECT oi.order_id, oi.product_id, oi.delivered_pcs, oi.sr_rate_pc, p.name
                 FROM order_items oi JOIN products p ON p.id = oi.product_id WHERE oi.order_id IN ({$ids}) AND oi.delivered_pcs > 0 ORDER BY oi.id"
            ) as $it) {
                $items[(int) $it['order_id']][] = $it;
            }
        }

        $out = [];
        $shopTotal = [];
        foreach ($rows as $r) {
            $id = (int) $r['id'];
            $rid = (int) $r['retailer_id'];
            $collected = 0.0;
            $returned = 0.0;
            $back = [];
            foreach ($entries[$id] ?? [] as $e) {
                if ($e['kind'] === 'collect') {
                    $collected += (float) $e['amount'];
                    continue;
                }
                $returned += (float) $e['amount'];
                foreach (json_decode((string) $e['detail_json'], true)['items'] ?? [] as $pid => $pcs) {
                    $back[(int) $pid] = ($back[(int) $pid] ?? 0) + (int) $pcs;
                }
            }
            $remaining = round((float) $r['due_amount'] - $collected - $returned, 2);
            $byDsr = 0.0;
            if ($r['trip_status'] === 'settled' && $remaining > 0 && ($pool[$rid] ?? 0) > 0) {
                $byDsr = round(min($pool[$rid], $remaining), 2);
                $pool[$rid] = round($pool[$rid] - $byDsr, 2);
                $remaining = round($remaining - $byDsr, 2);
            }
            $approved = $r['approved_amount'] !== null && abs((float) $r['approved_amount'] - (float) $r['due_amount']) < 0.005;
            $shopTotal[$rid] = round(($shopTotal[$rid] ?? 0) + max(0.0, $remaining), 2);
            $date = substr((string) ($r['delivered_at'] ?? $r['trip_date']), 0, 10);
            $out[] = [
                'id' => $id,
                'code' => $r['order_code'],
                'date' => $date,
                'age' => max(0, (int) round((strtotime(date('Y-m-d')) - strtotime($date)) / 86400)),
                'retailer_id' => $rid,
                'retailer' => $r['retailer_name_snapshot'],
                'phone' => $r['phone'],
                'dsr' => $r['dsr'],
                'sr' => $r['sr'],
                'trip' => $r['trip_code'],
                'settled' => $r['trip_status'] === 'settled',
                'bill' => (float) $r['delivered_sr_total'],
                'paid' => (float) $r['paid_amount'],
                'due' => (float) $r['due_amount'],
                'collected' => round($collected + $byDsr, 2),
                'returned' => round($returned, 2),
                'remaining' => max(0.0, $remaining),
                'state' => $remaining <= 0.004 ? 'done' : ($approved ? 'approved' : 'pending'),
                'has_entry' => isset($entries[$id]),
                'limit' => $r['shop_limit'] !== null ? (float) $r['shop_limit'] : $set['limit'],
                'custom_limit' => $r['shop_limit'] !== null,
                'items' => array_map(static fn(array $it): array => [
                    'product_id' => (int) $it['product_id'],
                    'name' => $it['name'],
                    'pcs' => max(0, (int) $it['delivered_pcs'] - ($back[(int) $it['product_id']] ?? 0)),
                    'rate' => (float) $it['sr_rate_pc'],
                ], $items[$id] ?? []),
            ];
        }
        foreach ($out as &$o) {
            $o['shop_total'] = $shopTotal[$o['retailer_id']];
            $o['overdue'] = $o['state'] !== 'done' && $o['age'] > $set['days'];
            $o['over_limit'] = $o['state'] !== 'done' && $o['shop_total'] - $o['limit'] > 0.004;
            $o['near_limit'] = $o['state'] !== 'done' && !$o['over_limit'] && $o['shop_total'] >= 0.8 * $o['limit'];
        }
        unset($o);

        return $out;
    }

    /** Money collected today: by the partner here + old dues collected by DSRs. @return array{amount:float, shops:int} */
    public static function collectedToday(int $partnerId): array
    {
        $r = self::db()->fetch(
            "SELECT COALESCE(SUM(x.amount), 0) AS amt, COUNT(DISTINCT x.rid) AS shops FROM (
                SELECT e.amount, o.retailer_id AS rid FROM due_entries e JOIN orders o ON o.id = e.order_id
                WHERE e.partner_id = ? AND e.kind = 'collect' AND DATE(e.created_at) = ?
                UNION ALL
                SELECT c.amount, c.retailer_id FROM retailer_due_collections c JOIN trips t ON t.id = c.trip_id
                WHERE t.partner_id = ? AND DATE(c.collected_at) = ?) x",
            [$partnerId, date('Y-m-d'), $partnerId, date('Y-m-d')]
        );

        return ['amount' => (float) $r['amt'], 'shops' => (int) $r['shops']];
    }

    /** Locks the order (and its shop) and returns its current row of all(). @return array<string, mixed> */
    private static function locked(Database $db, int $partnerId, int $orderId): array
    {
        $o = $db->fetch('SELECT id, retailer_id FROM orders WHERE id = ? AND partner_id = ? FOR UPDATE', [$orderId, $partnerId]);
        if ($o !== null) {
            $db->fetch('SELECT id FROM retailers WHERE id = ? FOR UPDATE', [$o['retailer_id']]);
            foreach (self::all($partnerId) as $row) {
                if ($row['id'] === $orderId) {
                    return $row;
                }
            }
        }
        throw new HttpError('এই অর্ডারে কোনো বাকি নেই।', 404);
    }

    public static function approve(int $partnerId, int $orderId, int $userId): array
    {
        return self::db()->transaction(static function (Database $db) use ($partnerId, $orderId, $userId): array {
            $row = self::locked($db, $partnerId, $orderId);
            if ($row['state'] !== 'pending') {
                throw new HttpError('এই বাকি অনুমোদনের অপেক্ষায় নেই।', 422);
            }
            $db->execute(
                'INSERT INTO due_approvals (order_id, amount, approved_by) VALUES (?, ?, ?)
                 ON DUPLICATE KEY UPDATE amount = VALUES(amount), approved_by = VALUES(approved_by), approved_at = NOW()',
                [$orderId, $row['due'], $userId]
            );

            return $row;
        });
    }

    private static function needMovable(Database $db, array $row, float $amount): void
    {
        if (!$row['settled']) {
            throw new HttpError('ট্রিপটির সেটেলমেন্ট এখনো অনুমোদন হয়নি। আগে সেটেলমেন্ট অনুমোদন করুন, অথবা DSR তার অ্যাপ থেকে ঠিক করুক।', 422);
        }
        if ($amount <= 0 || $amount - $row['remaining'] > 0.004) {
            throw new HttpError('পরিমাণ ০-এর বেশি এবং বাকি ৳ ' . number_format($row['remaining'], 2) . '-এর মধ্যে হতে হবে।', 422);
        }
        // A DSR on an open trip may already hold part of this shop's old due
        $free = $db->fetch(
            "SELECT r.due_balance - (SELECT COALESCE(SUM(c.amount), 0) FROM retailer_due_collections c JOIN trips t ON t.id = c.trip_id
                WHERE c.retailer_id = r.id AND t.status <> 'settled') AS f FROM retailers r WHERE r.id = ?",
            [$row['retailer_id']]
        );
        if ($amount - (float) ($free['f'] ?? 0) > 0.004) {
            throw new HttpError('দোকানের ব্যালেন্সে এত বাকি নেই — DSR হয়তো চলমান ট্রিপে টাকা নিয়েছে।', 422);
        }
    }

    private static function post(Database $db, int $partnerId, array $row, string $kind, float $amount, float $oc, ?array $detail, int $userId): void
    {
        $db->execute(
            'INSERT INTO due_entries (partner_id, order_id, kind, amount, sr_oc, detail_json, created_by) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [$partnerId, $row['id'], $kind, $amount, $oc, $detail !== null ? json_encode($detail) : null, $userId]
        );
        $db->execute('UPDATE retailers SET due_balance = due_balance - ? WHERE id = ?', [$amount, $row['retailer_id']]);
    }

    public static function collect(int $partnerId, int $orderId, float $amount, int $userId): array
    {
        return self::db()->transaction(static function (Database $db) use ($partnerId, $orderId, $amount, $userId): array {
            $row = self::locked($db, $partnerId, $orderId);
            if ($row['state'] !== 'approved') {
                throw new HttpError('আগে বাকিটি অনুমোদন করুন।', 422);
            }
            $amount = round($amount, 2);
            self::needMovable($db, $row, $amount);
            self::post($db, $partnerId, $row, 'collect', $amount, 0.0, null, $userId);

            return $row;
        });
    }

    /** Goods taken back: stock returns to the lots they were sold from, due and SR O/C go down. @param array<int|string, mixed> $pcsByProduct */
    public static function takeBack(int $partnerId, int $orderId, array $pcsByProduct, int $userId): array
    {
        return self::db()->transaction(static function (Database $db) use ($partnerId, $orderId, $pcsByProduct, $userId): array {
            $row = self::locked($db, $partnerId, $orderId);
            $have = array_column($row['items'], null, 'product_id');
            $items = [];
            $value = 0.0;
            foreach ($pcsByProduct as $pid => $pcs) {
                if ($pcs === '' || $pcs === null || (int) $pcs === 0) {
                    continue;
                }
                if (!is_numeric($pcs) || !isset($have[(int) $pid]) || (int) $pcs < 0 || (int) $pcs > $have[(int) $pid]['pcs']) {
                    throw new HttpError('ফেরতের পিস সংখ্যা সঠিক নয়।', 422);
                }
                $items[(int) $pid] = (int) $pcs;
                $value += (int) $pcs * $have[(int) $pid]['rate'];
            }
            if ($items === []) {
                throw new HttpError('কোন পণ্য কত পিস ফেরত এসেছে লিখুন।', 422);
            }
            $value = round($value, 2);
            if ($value - $row['remaining'] > 0.004) {
                throw new HttpError('ফেরত মালের দাম ৳ ' . number_format($value, 2) . ', কিন্তু বাকি ৳ ' . number_format($row['remaining'], 2) . '। পিস কমান।', 422);
            }
            self::needMovable($db, $row, $value);

            $o = $db->fetch('SELECT trip_id, sr_id, order_code FROM orders WHERE id = ?', [$orderId]);
            $used = [];
            foreach ($db->fetchAll(
                "SELECT e.detail_json FROM due_entries e JOIN orders o ON o.id = e.order_id WHERE o.trip_id = ? AND e.kind = 'return'",
                [$o['trip_id']]
            ) as $e) {
                foreach (json_decode((string) $e['detail_json'], true)['lots'] ?? [] as $m) {
                    $used[$m['lot']] = ($used[$m['lot']] ?? 0) + $m['pcs'];
                }
            }
            $lots = [];
            $oc = 0.0;
            foreach ($items as $pid => $pcs) {
                $left = $pcs;
                foreach ($db->fetchAll(
                    'SELECT lot_item_id, sold_pcs FROM trip_stock_allocations WHERE trip_id = ? AND product_id = ? AND sold_pcs > 0 ORDER BY lot_item_id DESC FOR UPDATE',
                    [$o['trip_id'], $pid]
                ) as $a) {
                    $lot = (int) $a['lot_item_id'];
                    $take = min($left, (int) $a['sold_pcs'] - ($used[$lot] ?? 0));
                    if ($take < 1) {
                        continue;
                    }
                    $lots[] = ['lot' => $lot, 'product' => $pid, 'pcs' => $take];
                    $db->execute('UPDATE lot_items SET remaining_pcs = remaining_pcs + ? WHERE id = ?', [$take, $lot]);
                    $left -= $take;
                }
                if ($left > 0) {
                    throw new HttpError("{$have[$pid]['name']}: এই ট্রিপে এত পিস বিক্রির হিসাব নেই।", 422);
                }
                $db->execute('UPDATE products SET stock_pcs = stock_pcs + ? WHERE id = ?', [$pcs, $pid]);
                $rate = $db->fetch('SELECT sr_rate_pc - base_rate_pc AS d FROM order_items WHERE order_id = ? AND product_id = ?', [$orderId, $pid]);
                $oc += $pcs * (float) $rate['d'];
            }
            $oc = $o['sr_id'] !== null ? round($oc, 2) : 0.0;
            self::srOc($db, $partnerId, $o, -$oc, 'Goods returned ');
            self::post($db, $partnerId, $row, 'return', $value, $oc, ['items' => $items, 'lots' => $lots], $userId);

            return $row;
        });
    }

    private static function srOc(Database $db, int $partnerId, array $o, float $amount, string $note): void
    {
        if ($o['sr_id'] === null || abs($amount) < 0.005) {
            return;
        }
        $db->execute(
            "INSERT INTO sr_oc_ledger (partner_id, sr_id, trip_id, entry_type, amount, note) VALUES (?, ?, ?, 'adjustment', ?, ?)",
            [$partnerId, $o['sr_id'], $o['trip_id'], $amount, $note . $o['order_code']]
        );
        $db->execute('UPDATE salesmen SET oc_balance = oc_balance + ? WHERE id = ?', [$amount, $o['sr_id']]);
    }

    /** Undoes the last step: the latest collection / goods return, else the approval. */
    public static function undo(int $partnerId, int $orderId): array
    {
        return self::db()->transaction(static function (Database $db) use ($partnerId, $orderId): array {
            $row = self::locked($db, $partnerId, $orderId);
            $e = $db->fetch('SELECT * FROM due_entries WHERE order_id = ? ORDER BY id DESC LIMIT 1 FOR UPDATE', [$orderId]);
            if ($e === null) {
                if ($row['state'] !== 'approved') {
                    throw new HttpError('ফেরানোর মতো কিছু নেই।', 422);
                }
                $db->execute('DELETE FROM due_approvals WHERE order_id = ?', [$orderId]);

                return $row;
            }
            if ($e['kind'] === 'return') {
                foreach (json_decode((string) $e['detail_json'], true)['lots'] as $m) {
                    $ok = $db->execute('UPDATE lot_items SET remaining_pcs = remaining_pcs - ? WHERE id = ? AND remaining_pcs >= ?', [$m['pcs'], $m['lot'], $m['pcs']])
                        && $db->execute('UPDATE products SET stock_pcs = stock_pcs - ? WHERE id = ? AND stock_pcs >= ?', [$m['pcs'], $m['product'], $m['pcs']]);
                    if (!$ok) {
                        throw new HttpError('ফেরত আসা মাল ইতিমধ্যে আবার বের হয়ে গেছে, তাই আনডু করা যাবে না।', 422);
                    }
                }
                $o = $db->fetch('SELECT trip_id, sr_id, order_code FROM orders WHERE id = ?', [$orderId]);
                self::srOc($db, $partnerId, $o, (float) $e['sr_oc'], 'Undo goods return ');
            }
            $db->execute('DELETE FROM due_entries WHERE id = ?', [$e['id']]);
            $db->execute('UPDATE retailers SET due_balance = due_balance + ? WHERE id = ?', [$e['amount'], $row['retailer_id']]);

            return $row;
        });
    }
}
