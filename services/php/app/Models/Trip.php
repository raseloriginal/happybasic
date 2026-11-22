<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Format;
use App\Support\HttpError;
use Core\Database;

/**
 * DSR trips: one trip per DSR per delivery date.
 * Assigning SRs moves their completed, unassigned orders of an order date onto the trip and
 * aggregates the ordered pieces into trip_van_stocks (ordered_pcs). The partner may change the
 * loaded qty (dispatched_pcs) and add extra products before dispatch. Dispatch consumes stock FIFO.
 */
final class Trip
{
    private static function db(): Database
    {
        return Database::getInstance();
    }

    /** @return array{srs:list<array<string, mixed>>, dsrs:list<array<string, mixed>>} */
    public static function planner(int $partnerId, string $orderDate, string $deliveryDate): array
    {
        $srs = self::db()->fetchAll(
            "SELECT s.id, s.name, s.area, c.name AS company, COUNT(o.id) AS orders, COALESCE(SUM(o.order_sr_total), 0) AS value,
                    COUNT(DISTINCT o.retailer_id) AS retailers,
                    (SELECT COUNT(DISTINCT oi.product_id) FROM order_items oi JOIN orders o2 ON o2.id = oi.order_id
                     WHERE o2.sr_id = s.id AND o2.order_date = ? AND o2.status = 'pending' AND o2.trip_id IS NULL) AS products,
                    (SELECT 1 FROM sr_order_days d WHERE d.sr_id = s.id AND d.order_date = ?) AS completed
             FROM salesmen s
             JOIN companies c ON c.id = s.company_id
             JOIN orders o ON o.sr_id = s.id AND o.order_date = ? AND o.status = 'pending' AND o.trip_id IS NULL
             WHERE s.partner_id = ? AND s.deleted_at IS NULL
             GROUP BY s.id, s.name, s.area, c.name
             ORDER BY completed DESC, s.name",
            [$orderDate, $orderDate, $orderDate, $partnerId]
        );

        $dsrs = self::db()->fetchAll(
            "SELECT dm.id, dm.name, dm.phone, t.trip_code, t.status AS trip_status,
                    (SELECT ot.trip_code FROM trips ot WHERE ot.dsr_id = dm.id AND ot.status IN ('dispatched', 'in_review') LIMIT 1) AS open_trip
             FROM delivery_men dm
             LEFT JOIN trips t ON t.dsr_id = dm.id AND t.trip_date = ?
             WHERE dm.partner_id = ? AND dm.status = 'active' AND dm.deleted_at IS NULL
             ORDER BY dm.name",
            [$deliveryDate, $partnerId]
        );

        return [
            'srs' => array_map(static fn(array $r): array => [
                'id' => (int) $r['id'],
                'name' => $r['name'],
                'area' => $r['area'] ?: $r['company'],
                'company' => $r['company'],
                'orders' => (int) $r['orders'],
                'retailers' => (int) $r['retailers'],
                'products' => (int) $r['products'],
                'value' => (float) $r['value'],
                'completed' => $r['completed'] !== null,
            ], $srs),
            'dsrs' => array_map(static fn(array $r): array => [
                'id' => (int) $r['id'],
                'name' => $r['name'],
                'phone' => \App\Support\Phone::format($r['phone']),
                'trip' => $r['trip_code'],
                'trip_status' => $r['trip_status'],
                'open_trip' => $r['open_trip'],
            ], $dsrs),
        ];
    }

    /** @return list<array<string, mixed>> trips of a delivery date */
    public static function forPartner(int $partnerId, string $date): array
    {
        $ids = array_column(self::db()->fetchAll(
            'SELECT id FROM trips WHERE partner_id = ? AND trip_date = ? ORDER BY id DESC',
            [$partnerId, $date]
        ), 'id');

        return array_map(static fn($id): array => self::detail($partnerId, (int) $id), $ids);
    }

    /** @return array<string, mixed> */
    public static function detail(int $partnerId, int $id): array
    {
        $t = self::db()->fetch(
            'SELECT t.*, dm.name AS dsr_name FROM trips t JOIN delivery_men dm ON dm.id = t.dsr_id WHERE t.id = ? AND t.partner_id = ?',
            [$id, $partnerId]
        );
        if ($t === null) {
            throw new HttpError('Trip not found.', 404);
        }

        $srs = self::db()->fetchAll(
            'SELECT s.id, s.name FROM trip_srs ts JOIN salesmen s ON s.id = ts.sr_id WHERE ts.trip_id = ? ORDER BY s.name',
            [$id]
        );
        $o = self::db()->fetch(
            "SELECT COUNT(*) AS orders, COUNT(DISTINCT retailer_id) AS retailers, COALESCE(SUM(order_sr_total), 0) AS value,
                    COUNT(DISTINCT CASE WHEN status IN ('delivered', 'due', 'partial') THEN retailer_id END) AS done_retailers,
                    MIN(order_date) AS order_date
             FROM orders WHERE trip_id = ? AND status <> 'cancelled'",
            [$id]
        );
        $items = self::db()->fetchAll(
            'SELECT v.*, p.name, p.unit_type, p.qty_per_unit, p.stock_pcs, p.image_path
             FROM trip_van_stocks v JOIN products p ON p.id = v.product_id WHERE v.trip_id = ? ORDER BY v.ordered_pcs = 0, p.name',
            [$id]
        );

        return [
            'id' => (int) $t['id'],
            'code' => $t['trip_code'],
            'date' => $t['trip_date'],
            'order_date' => $o['order_date'],
            'dsr_id' => (int) $t['dsr_id'],
            'dsr' => $t['dsr_name'],
            'status' => Format::status(str_replace('_', ' ', (string) $t['status'])),
            'status_key' => $t['status'],
            'dispatched_at' => $t['dispatched_at'],
            'srs' => array_map(static fn(array $s): array => ['id' => (int) $s['id'], 'name' => $s['name']], $srs),
            'orders' => (int) $o['orders'],
            'retailers' => (int) $o['retailers'],
            'done_retailers' => (int) $o['done_retailers'],
            'order_value' => (float) $o['value'],
            'items' => array_map(static function (array $v): array {
                return Product::visual((int) $v['product_id'], (string) $v['name'], $v['image_path']) + [
                    'product_id' => (int) $v['product_id'],
                    'name' => $v['name'],
                    'unit_type' => $v['unit_type'],
                    'qty_per_unit' => (int) $v['qty_per_unit'],
                    'ordered_pcs' => (int) $v['ordered_pcs'],
                    'loaded_pcs' => (int) $v['dispatched_pcs'],
                    'stock_pcs' => (int) $v['stock_pcs'],
                    'checked' => (bool) $v['is_checked'],
                    'extra' => (int) $v['ordered_pcs'] === 0,
                ];
            }, $items),
        ];
    }

    /** @return array<string, mixed> */
    private static function pendingOrFail(int $partnerId, int $id): array
    {
        $trip = self::detail($partnerId, $id);
        if ($trip['status_key'] !== 'pending') {
            throw new HttpError("{$trip['code']} is already dispatched and can no longer be changed.", 422);
        }

        return $trip;
    }

    /**
     * @param list<int> $srIds
     * @return array<string, mixed> the trip
     */
    public static function assign(int $partnerId, string $orderDate, string $deliveryDate, int $dsrId, array $srIds): array
    {
        if ($deliveryDate < $orderDate) {
            throw new HttpError('Delivery date cannot be before the order date.', 422);
        }
        $dsr = self::db()->fetch("SELECT * FROM delivery_men WHERE id = ? AND partner_id = ? AND status = 'active' AND deleted_at IS NULL", [$dsrId, $partnerId]);
        if ($dsr === null) {
            throw new HttpError('Please select an active delivery man.', 422);
        }

        $open = self::db()->fetch(
            "SELECT trip_code FROM trips WHERE dsr_id = ? AND status IN ('dispatched', 'in_review') AND trip_date <> ? LIMIT 1",
            [$dsrId, $deliveryDate]
        );
        if ($open !== null) {
            throw new HttpError("{$dsr['name']} still has an unsettled trip ({$open['trip_code']}). Settle it before assigning a new one.", 422);
        }

        $planner = self::planner($partnerId, $orderDate, $deliveryDate);
        $eligible = [];
        foreach ($planner['srs'] as $sr) {
            $eligible[$sr['id']] = $sr;
        }
        foreach ($srIds as $srId) {
            $sr = $eligible[$srId] ?? null;
            if ($sr === null) {
                throw new HttpError('A selected SR has no unassigned orders on that date. Reload and try again.', 422);
            }
            if (!$sr['completed']) {
                throw new HttpError("{$sr['name']} has not completed the orders of {$orderDate} yet.", 422);
            }
        }

        $tripId = self::db()->transaction(static function (Database $db) use ($partnerId, $orderDate, $deliveryDate, $dsrId, $srIds): int {
            $trip = $db->fetch('SELECT * FROM trips WHERE dsr_id = ? AND trip_date = ? FOR UPDATE', [$dsrId, $deliveryDate]);
            if ($trip !== null && $trip['status'] !== 'pending') {
                throw new HttpError("This DSR's trip for {$deliveryDate} is already dispatched. Choose another DSR or date.", 422);
            }
            if ($trip === null) {
                $db->execute(
                    "INSERT INTO trips (trip_code, partner_id, dsr_id, trip_date, status) VALUES (?, ?, ?, ?, 'pending')",
                    ['TMP-' . bin2hex(random_bytes(8)), $partnerId, $dsrId, $deliveryDate]
                );
                $tripId = (int) $db->lastInsertId();
                $db->execute('UPDATE trips SET trip_code = ? WHERE id = ?', ['TRP-' . date('ymd', strtotime($deliveryDate)) . '-' . str_pad((string) $tripId, 4, '0', STR_PAD_LEFT), $tripId]);
            } else {
                $tripId = (int) $trip['id'];
            }

            foreach ($srIds as $srId) {
                $db->execute('INSERT IGNORE INTO trip_srs (trip_id, sr_id) VALUES (?, ?)', [$tripId, $srId]);
                $db->execute(
                    "UPDATE orders SET trip_id = ?, status = 'assigned'
                     WHERE partner_id = ? AND sr_id = ? AND order_date = ? AND status = 'pending' AND trip_id IS NULL",
                    [$tripId, $partnerId, $srId, $orderDate]
                );
            }
            self::syncOrdered($db, $tripId);

            return $tripId;
        });

        return self::detail($partnerId, $tripId);
    }

    /** Removes an SR (and its orders) from a pending trip. */
    public static function unassignSr(int $partnerId, int $tripId, int $srId): ?array
    {
        self::pendingOrFail($partnerId, $tripId);

        $deleted = self::db()->transaction(static function (Database $db) use ($tripId, $srId): bool {
            $db->execute("UPDATE orders SET trip_id = NULL, status = 'pending' WHERE trip_id = ? AND sr_id = ? AND status = 'assigned'", [$tripId, $srId]);
            $db->execute('DELETE FROM trip_srs WHERE trip_id = ? AND sr_id = ?', [$tripId, $srId]);
            self::syncOrdered($db, $tripId);

            $left = $db->fetch('SELECT (SELECT COUNT(*) FROM trip_srs WHERE trip_id = ?) + (SELECT COUNT(*) FROM trip_van_stocks WHERE trip_id = ?) AS n', [$tripId, $tripId]);
            if ((int) $left['n'] === 0) {
                $db->execute('DELETE FROM trips WHERE id = ?', [$tripId]);
                return true;
            }

            return false;
        });

        return $deleted ? null : self::detail($partnerId, $tripId);
    }

    /** Recomputes ordered_pcs from the trip's orders; shifts the loaded qty by the same difference. */
    private static function syncOrdered(Database $db, int $tripId): void
    {
        $ordered = [];
        foreach ($db->fetchAll(
            "SELECT oi.product_id, SUM(oi.ordered_pcs) AS pcs FROM order_items oi JOIN orders o ON o.id = oi.order_id
             WHERE o.trip_id = ? AND o.status <> 'cancelled' GROUP BY oi.product_id",
            [$tripId]
        ) as $r) {
            $ordered[(int) $r['product_id']] = (int) $r['pcs'];
        }

        $rows = [];
        foreach ($db->fetchAll('SELECT * FROM trip_van_stocks WHERE trip_id = ?', [$tripId]) as $r) {
            $rows[(int) $r['product_id']] = $r;
        }

        foreach ($rows as $pid => $r) {
            $new = $ordered[$pid] ?? 0;
            $old = (int) $r['ordered_pcs'];
            if ($new === $old) {
                continue;
            }
            $loaded = max(0, (int) $r['dispatched_pcs'] + $new - $old);
            if ($new === 0 && $loaded === 0) {
                $db->execute('DELETE FROM trip_van_stocks WHERE id = ?', [$r['id']]);
                continue;
            }
            $db->execute('UPDATE trip_van_stocks SET ordered_pcs = ?, dispatched_pcs = ?, is_checked = 0 WHERE id = ?', [$new, $loaded, $r['id']]);
        }

        foreach ($ordered as $pid => $pcs) {
            if (!isset($rows[$pid])) {
                $db->execute(
                    'INSERT INTO trip_van_stocks (trip_id, product_id, ordered_pcs, dispatched_pcs, base_rate_pc)
                     SELECT ?, id, ?, ?, base_price FROM products WHERE id = ?',
                    [$tripId, $pcs, $pcs, $pid]
                );
            }
        }
    }

    /** Sets the loaded qty and/or the checked flag of one checklist row. */
    public static function updateItem(int $partnerId, int $tripId, int $productId, ?int $loadedPcs, ?bool $checked): array
    {
        self::pendingOrFail($partnerId, $tripId);
        $row = self::db()->fetch('SELECT * FROM trip_van_stocks WHERE trip_id = ? AND product_id = ?', [$tripId, $productId]);
        if ($row === null) {
            throw new HttpError('Product is not on this trip.', 404);
        }
        if ($loadedPcs !== null && $loadedPcs < 0) {
            throw new HttpError('Loaded quantity cannot be negative.', 422);
        }

        self::db()->execute(
            'UPDATE trip_van_stocks SET dispatched_pcs = COALESCE(?, dispatched_pcs), is_checked = COALESCE(?, is_checked) WHERE id = ?',
            [$loadedPcs, $checked === null ? null : (int) $checked, $row['id']]
        );

        return self::detail($partnerId, $tripId);
    }

    /** Adds an extra (not ordered) product to the van for ready sale. */
    public static function addItem(int $partnerId, int $tripId, int $productId, int $pcs): array
    {
        self::pendingOrFail($partnerId, $tripId);
        if ($pcs < 1) {
            throw new HttpError('Quantity must be at least 1 piece.', 422);
        }
        $p = self::db()->fetch(
            "SELECT id, name, base_price FROM products WHERE id = ? AND partner_id = ? AND status = 'active' AND deleted_at IS NULL",
            [$productId, $partnerId]
        );
        if ($p === null || (float) $p['base_price'] <= 0) {
            throw new HttpError('Select an active product that has stock received through a lot.', 422);
        }
        if (self::db()->fetch('SELECT 1 FROM trip_van_stocks WHERE trip_id = ? AND product_id = ?', [$tripId, $productId]) !== null) {
            throw new HttpError("\"{$p['name']}\" is already on this trip. Change its loaded quantity instead.", 422);
        }
        self::db()->execute(
            'INSERT INTO trip_van_stocks (trip_id, product_id, ordered_pcs, dispatched_pcs, base_rate_pc) VALUES (?, ?, 0, ?, ?)',
            [$tripId, $productId, $pcs, $p['base_price']]
        );

        return self::detail($partnerId, $tripId);
    }

    public static function removeItem(int $partnerId, int $tripId, int $productId): array
    {
        self::pendingOrFail($partnerId, $tripId);
        $n = self::db()->execute('DELETE FROM trip_van_stocks WHERE trip_id = ? AND product_id = ? AND ordered_pcs = 0', [$tripId, $productId]);
        if ($n === 0) {
            throw new HttpError('Only extra products can be removed. Set the loaded quantity to 0 instead.', 422);
        }

        return self::detail($partnerId, $tripId);
    }

    /** Loads the van: allocates each loaded qty from the oldest lots first and reduces stock. */
    public static function dispatch(int $partnerId, int $tripId): array
    {
        $trip = self::pendingOrFail($partnerId, $tripId);
        if ($trip['items'] === [] || array_sum(array_column($trip['items'], 'loaded_pcs')) === 0) {
            throw new HttpError('Nothing is loaded on this trip.', 422);
        }
        foreach ($trip['items'] as $it) {
            if (!$it['checked']) {
                throw new HttpError('Check every product before dispatching.', 422);
            }
        }
        $open = self::db()->fetch(
            "SELECT trip_code FROM trips WHERE dsr_id = ? AND id <> ? AND status IN ('dispatched', 'in_review') LIMIT 1",
            [$trip['dsr_id'], $tripId]
        );
        if ($open !== null) {
            throw new HttpError("{$trip['dsr']} still has an unsettled trip ({$open['trip_code']}). Settle it before dispatching another.", 422);
        }

        self::db()->transaction(static function (Database $db) use ($tripId): void {
            $rows = $db->fetchAll(
                'SELECT v.*, p.name, p.stock_pcs, p.base_price FROM trip_van_stocks v JOIN products p ON p.id = v.product_id
                 WHERE v.trip_id = ? ORDER BY v.product_id FOR UPDATE',
                [$tripId]
            );

            $short = [];
            foreach ($rows as $r) {
                $need = (int) $r['dispatched_pcs'];
                if ($need === 0) {
                    continue;
                }
                $layers = $db->fetchAll(
                    'SELECT li.id, li.remaining_pcs, li.company_price_per_pc FROM lot_items li JOIN lots l ON l.id = li.lot_id
                     WHERE li.product_id = ? AND li.remaining_pcs > 0 ORDER BY l.received_date, li.id FOR UPDATE',
                    [$r['product_id']]
                );
                $have = array_sum(array_map(static fn(array $l): int => (int) $l['remaining_pcs'], $layers));
                if ($have < $need) {
                    $short[] = "{$r['name']} (need {$need}, have {$have} pcs)";
                    continue;
                }

                foreach ($layers as $l) {
                    if ($need === 0) {
                        break;
                    }
                    $take = min($need, (int) $l['remaining_pcs']);
                    $db->execute('UPDATE lot_items SET remaining_pcs = remaining_pcs - ? WHERE id = ?', [$take, $l['id']]);
                    $db->execute(
                        'INSERT INTO trip_stock_allocations (trip_id, lot_item_id, product_id, dispatched_pcs, company_price_per_pc) VALUES (?, ?, ?, ?, ?)',
                        [$tripId, $l['id'], $r['product_id'], $take, $l['company_price_per_pc']]
                    );
                    $need -= $take;
                }

                $db->execute('UPDATE products SET stock_pcs = stock_pcs - ? WHERE id = ?', [$r['dispatched_pcs'], $r['product_id']]);
                // extra (not ordered) products are sold at the dealer price in force at dispatch
                $db->execute(
                    'UPDATE trip_van_stocks SET base_rate_pc = IF(ordered_pcs = 0, ?, base_rate_pc) WHERE id = ?',
                    [$r['base_price'], $r['id']]
                );
            }

            if ($short !== []) {
                throw new HttpError('Not enough stock: ' . implode('; ', $short) . '. Reduce the loaded qty or receive a lot first.', 422);
            }

            $db->execute("UPDATE trips SET status = 'dispatched', dispatched_at = NOW() WHERE id = ?", [$tripId]);
        });

        return self::detail($partnerId, $tripId);
    }
}
