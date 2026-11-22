<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Format;
use App\Support\HttpError;
use Core\Database;

/**
 * SR orders. One order = 1 retailer + the SR's company, for one order date.
 * Rates are frozen per item when first ordered (base_rate_pc = dealer price at that moment),
 * so later price changes never alter past sales, O/C or profit.
 *   order_oc (item) = SR total − ordered_pcs × base_rate_pc   (+ over, − commission)
 */
final class Order
{
    private static function db(): Database
    {
        return Database::getInstance();
    }

    // ---------------------------------------------------------------------
    // SR side
    // ---------------------------------------------------------------------

    public static function isDayCompleted(int $srId, string $date): bool
    {
        return self::db()->fetch('SELECT 1 FROM sr_order_days WHERE sr_id = ? AND order_date = ?', [$srId, $date]) !== null;
    }

    /** @return array{date:string, completed:bool, locked:bool, orders:list<array<string, mixed>>, totals:array<string, float|int>} */
    public static function srDay(array $sr, string $date): array
    {
        $orders = self::list(['o.sr_id = ?', 'o.order_date = ?', "o.status <> 'cancelled'"], [$sr['id'], $date], true);
        $locked = false;
        foreach ($orders as $o) {
            $locked = $locked || !$o['editable'];
        }

        return [
            'date' => $date,
            'completed' => self::isDayCompleted($sr['id'], $date),
            'locked' => $locked,
            'orders' => $orders,
            'totals' => [
                'orders' => count($orders),
                'value' => round(array_sum(array_column($orders, 'sr_total')), 2),
                'oc' => round(array_sum(array_column($orders, 'oc')), 2),
            ],
        ];
    }

    /**
     * Creates the retailer's order for today, or replaces the items of its open order.
     *
     * @param list<array{product_id:int, pcs:int, total:float}> $items
     * @return array{order:array<string, mixed>, warnings:list<string>}
     */
    public static function save(array $sr, int $retailerId, array $items, ?int $orderId = null): array
    {
        $date = date('Y-m-d');
        if (self::isDayCompleted($sr['id'], $date)) {
            throw new HttpError("Today's orders are already completed. Reopen the day to change orders.", 422);
        }
        $retailer = Retailer::findForPartner($sr['partner_id'], $retailerId);
        if ($items === []) {
            throw new HttpError('Add at least one product to the order.', 422);
        }

        $catalog = [];
        foreach (Product::forPartner($sr['partner_id'], $sr['company_id'], true) as $p) {
            $catalog[$p['id']] = $p;
        }

        $existing = $orderId !== null
            ? self::srOrderOrFail($sr, $orderId)
            : self::db()->fetch(
                "SELECT * FROM orders WHERE sr_id = ? AND retailer_id = ? AND order_date = ? AND status = 'pending' AND trip_id IS NULL",
                [$sr['id'], $retailerId, $date]
            );
        if ($existing !== null && ($existing['status'] !== 'pending' || $existing['trip_id'] !== null)) {
            throw new HttpError('This order is already assigned to a trip and can no longer be changed.', 422);
        }
        if ($existing !== null && $existing['order_date'] !== $date) {
            throw new HttpError('Only today\'s orders can be changed.', 422);
        }

        $frozen = [];
        $ownPcs = [];
        if ($existing !== null) {
            foreach (self::db()->fetchAll('SELECT product_id, ordered_pcs, base_rate_pc FROM order_items WHERE order_id = ?', [$existing['id']]) as $r) {
                $frozen[(int) $r['product_id']] = (float) $r['base_rate_pc'];
                $ownPcs[(int) $r['product_id']] = (int) $r['ordered_pcs'];
            }
        }

        $lines = [];
        $warnings = [];
        $seen = [];
        foreach ($items as $it) {
            $p = $catalog[$it['product_id']] ?? null;
            if ($p === null || !$p['priced']) {
                throw new HttpError('One of the products is no longer available. Reload and try again.', 422);
            }
            if (isset($seen[$p['id']])) {
                throw new HttpError("\"{$p['name']}\" is in the order twice.", 422);
            }
            $seen[$p['id']] = true;
            if ($it['pcs'] < 1) {
                throw new HttpError("Quantity for \"{$p['name']}\" must be at least 1 piece.", 422);
            }
            if ($it['total'] < 0) {
                throw new HttpError("Amount for \"{$p['name']}\" cannot be negative.", 422);
            }

            $base = $frozen[$p['id']] ?? $p['dealer_price_pc'];
            $total = round($it['total'], 2);
            $lines[] = [
                'product_id' => $p['id'],
                'pcs' => $it['pcs'],
                'base' => $base,
                'rate' => round($total / $it['pcs'], 4),
                'total' => $total,
                'oc' => round($total - $it['pcs'] * $base, 2),
                'base_total' => round($it['pcs'] * $base, 2),
            ];

            $available = $p['available_pcs'] + ($ownPcs[$p['id']] ?? 0);
            if ($it['pcs'] > $available) {
                $warnings[] = "{$p['name']}: ordered {$it['pcs']} pcs, only " . max(0, $available) . ' pcs in stock.';
            }
        }

        $baseTotal = round(array_sum(array_column($lines, 'base_total')), 2);
        $srTotal = round(array_sum(array_column($lines, 'total')), 2);
        $oc = round(array_sum(array_column($lines, 'oc')), 2);

        $id = self::db()->transaction(static function (Database $db) use ($sr, $retailer, $existing, $lines, $baseTotal, $srTotal, $oc, $date): int {
            if ($existing === null) {
                $db->execute(
                    "INSERT INTO orders (order_code, partner_id, company_id, sr_id, retailer_id, retailer_name_snapshot, order_date,
                        order_base_total, order_sr_total, order_oc, platform_fee_rate, status)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')",
                    ['TMP-' . bin2hex(random_bytes(8)), $sr['partner_id'], $sr['company_id'], $sr['id'], $retailer['id'], $retailer['name'], $date,
                        $baseTotal, $srTotal, $oc, PlatformFee::rateAt($sr['partner_id'], $sr['company_id'])]
                );
                $id = (int) $db->lastInsertId();
                $db->execute('UPDATE orders SET order_code = ? WHERE id = ?', ['ORD-' . date('ymd') . '-' . str_pad((string) $id, 5, '0', STR_PAD_LEFT), $id]);
            } else {
                $id = (int) $existing['id'];
                $db->execute(
                    'UPDATE orders SET order_base_total = ?, order_sr_total = ?, order_oc = ?, retailer_name_snapshot = ? WHERE id = ?',
                    [$baseTotal, $srTotal, $oc, $retailer['name'], $id]
                );
                $db->execute('DELETE FROM order_items WHERE order_id = ?', [$id]);
            }

            foreach ($lines as $l) {
                $db->execute(
                    'INSERT INTO order_items (order_id, product_id, ordered_pcs, base_rate_pc, sr_rate_pc, order_oc) VALUES (?, ?, ?, ?, ?, ?)',
                    [$id, $l['product_id'], $l['pcs'], $l['base'], $l['rate'], $l['oc']]
                );
            }

            return $id;
        });

        return ['order' => self::srOrder($sr, $id), 'warnings' => $warnings];
    }

    public static function cancel(array $sr, int $orderId): array
    {
        $order = self::srOrderOrFail($sr, $orderId);
        if ($order['status'] !== 'pending' || $order['trip_id'] !== null) {
            throw new HttpError('This order is already assigned to a trip and cannot be cancelled.', 422);
        }
        if (self::isDayCompleted($sr['id'], (string) $order['order_date'])) {
            throw new HttpError('Orders of a completed day cannot be cancelled. Reopen the day first.', 422);
        }
        self::db()->execute("UPDATE orders SET status = 'cancelled', cancel_reason = 'Cancelled by SR' WHERE id = ?", [$orderId]);

        return $order;
    }

    public static function completeDay(array $sr, string $date): void
    {
        $count = self::db()->fetch("SELECT COUNT(*) AS n FROM orders WHERE sr_id = ? AND order_date = ? AND status <> 'cancelled'", [$sr['id'], $date]);
        if ((int) $count['n'] === 0) {
            throw new HttpError('There are no orders to complete for this day.', 422);
        }
        self::db()->execute('INSERT IGNORE INTO sr_order_days (sr_id, order_date) VALUES (?, ?)', [$sr['id'], $date]);
    }

    public static function reopenDay(array $sr, string $date): void
    {
        $assigned = self::db()->fetch("SELECT 1 FROM orders WHERE sr_id = ? AND order_date = ? AND trip_id IS NOT NULL AND status <> 'cancelled' LIMIT 1", [$sr['id'], $date]);
        if ($assigned !== null) {
            throw new HttpError('Orders of this day are already assigned to a trip, so the day cannot be reopened.', 422);
        }
        self::db()->execute('DELETE FROM sr_order_days WHERE sr_id = ? AND order_date = ?', [$sr['id'], $date]);
    }

    /** @return list<array<string, mixed>> all of an SR's orders of a date, cancelled included (history view) */
    public static function srHistory(array $sr, string $date): array
    {
        return self::list(['o.sr_id = ?', 'o.order_date = ?'], [$sr['id'], $date], true);
    }

    /** @return array<string, mixed> */
    private static function srOrderOrFail(array $sr, int $id): array
    {
        $row = self::db()->fetch("SELECT * FROM orders WHERE id = ? AND sr_id = ? AND status <> 'cancelled'", [$id, $sr['id']]);
        if ($row === null) {
            throw new HttpError('Order not found.', 404);
        }

        return $row;
    }

    /** @return array<string, mixed> */
    private static function srOrder(array $sr, int $id): array
    {
        return self::list(['o.id = ?', 'o.sr_id = ?'], [$id, $sr['id']], true)[0];
    }

    // ---------------------------------------------------------------------
    // Partner side
    // ---------------------------------------------------------------------

    /**
     * @param array{from?:string, to?:string, sr_id?:int|null, company_id?:int|null, status?:string|null, q?:string|null} $f
     * @return list<array<string, mixed>>
     */
    public static function forPartner(int $partnerId, array $f): array
    {
        $where = ['o.partner_id = ?', 'o.order_date BETWEEN ? AND ?'];
        $params = [$partnerId, $f['from'], $f['to']];
        if (!empty($f['sr_id'])) {
            $where[] = 'o.sr_id = ?';
            $params[] = $f['sr_id'];
        }
        if (!empty($f['company_id'])) {
            $where[] = 'o.company_id = ?';
            $params[] = $f['company_id'];
        }
        if (!empty($f['status'])) {
            $where[] = 'o.status = ?';
            $params[] = $f['status'];
        }

        return self::list($where, $params, true);
    }

    /**
     * @param list<string> $where
     * @param list<mixed> $params
     * @return list<array<string, mixed>>
     */
    private static function list(array $where, array $params, bool $withItems): array
    {
        $rows = self::db()->fetchAll(
            'SELECT o.*, s.name AS sr_name, c.name AS company, t.trip_code, t.status AS trip_status, t.trip_date, dm.name AS dsr_name,
                    r.address AS retailer_address, r.phone AS retailer_phone, r.lat, r.lng
             FROM orders o
             JOIN companies c ON c.id = o.company_id
             LEFT JOIN salesmen s ON s.id = o.sr_id
             LEFT JOIN trips t ON t.id = o.trip_id
             LEFT JOIN delivery_men dm ON dm.id = t.dsr_id
             LEFT JOIN retailers r ON r.id = o.retailer_id
             WHERE ' . implode(' AND ', $where) . '
             ORDER BY o.order_date DESC, o.id DESC',
            $params
        );
        if ($rows === []) {
            return [];
        }

        $items = [];
        if ($withItems) {
            $ids = implode(',', array_map(static fn(array $r): int => (int) $r['id'], $rows));
            foreach (self::db()->fetchAll(
                "SELECT oi.*, p.name, p.unit_type, p.qty_per_unit, p.image_path FROM order_items oi JOIN products p ON p.id = oi.product_id
                 WHERE oi.order_id IN ({$ids}) ORDER BY oi.id"
            ) as $it) {
                $pcs = (int) $it['ordered_pcs'];
                $vis = Product::visual((int) $it['product_id'], (string) $it['name'], $it['image_path'] ?? null);
                $items[(int) $it['order_id']][] = [
                    'product_id' => (int) $it['product_id'],
                    'name' => $it['name'],
                    'unit_type' => $it['unit_type'],
                    'qty_per_unit' => (int) $it['qty_per_unit'],
                    'pcs' => $pcs,
                    'qty' => Product::unitPcs($pcs, (int) $it['qty_per_unit'], (string) $it['unit_type']),
                    'delivered_pcs' => (int) $it['delivered_pcs'],
                    'base_rate_pc' => (float) $it['base_rate_pc'],
                    'sr_rate_pc' => (float) $it['sr_rate_pc'],
                    'total' => round($pcs * (float) $it['sr_rate_pc'], 2),
                    'oc' => (float) $it['order_oc'],
                    'image' => $vis['image'],
                    'code' => $vis['code'],
                    'tint' => $vis['tint'],
                ];
            }
        }

        return array_map(static function (array $o) use ($items): array {
            $editable = $o['status'] === 'pending' && $o['trip_id'] === null;

            return [
                'id' => (int) $o['id'],
                'code' => $o['order_code'],
                'date' => $o['order_date'],
                'time' => date('h:i A', strtotime((string) $o['created_at'])),
                'sr_id' => $o['sr_id'] !== null ? (int) $o['sr_id'] : null,
                'sr' => $o['sr_name'] ?? ($o['is_ready_sale'] ? 'Ready Sale' : '—'),
                'company_id' => (int) $o['company_id'],
                'company' => $o['company'],
                'retailer_id' => $o['retailer_id'] !== null ? (int) $o['retailer_id'] : null,
                'retailer' => $o['retailer_name_snapshot'],
                'retailer_address' => $o['retailer_address'],
                'retailer_phone' => $o['retailer_phone'] ? \App\Support\Phone::format($o['retailer_phone']) : null,
                'trip' => $o['trip_code'],
                'trip_date' => $o['trip_date'],
                'dsr' => $o['dsr_name'],
                'base_total' => (float) $o['order_base_total'],
                'sr_total' => (float) $o['order_sr_total'],
                'oc' => (float) $o['order_oc'],
                'delivered_total' => (float) $o['delivered_sr_total'],
                'paid' => (float) $o['paid_amount'],
                'due' => (float) $o['due_amount'],
                'damage' => (float) $o['damage_amount'],
                'notes' => $o['notes'],
                'cancel_reason' => $o['cancel_reason'],
                'status' => Format::status($o['status']),
                'status_key' => $o['status'],
                'editable' => $editable,
                'items' => $items[(int) $o['id']] ?? [],
            ];
        }, $rows);
    }
}
