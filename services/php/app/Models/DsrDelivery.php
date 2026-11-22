<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\HttpError;
use App\Support\Phone;
use Core\Database;

/**
 * DSR side of a dispatched trip: retailer stops (all trip orders of one retailer), delivery,
 * cancellation, damage returns, payment + old-due collection, ready sale and trip expenses.
 *
 * Per order (1 company):  delivered_sr_total − damage_amount = bill;  bill = paid_amount + due_amount.
 * Cash for a stop = Σ paid_amount + old due collected (retailer_due_collections).
 * Stock return, retailer due balances and the SR O/C ledger are applied on partner approval (TripSettlement).
 */
final class DsrDelivery
{
    public const CANCEL_REASONS = [
        'Shop Closed',
        'Owner / Decision Maker Not Available',
        'Insufficient Cash / Credit Issue',
        'Old Due Not Cleared',
        'Ordered by Mistake',
        'Stock Not Needed Now',
        'Already Bought from Another Supplier',
        'Price Disagreement',
        'Wanted Different Product / Size',
        'Product Damaged / Expired in Van',
        'Wrong Product Loaded',
        'Shop Not Found / Wrong Location',
        'Delivery Too Late',
        'Road / Area Not Accessible',
        'Other',
    ];

    public const EXPENSE_CATEGORIES = ['Fuel', 'Helper', 'Food', 'Toll & Parking', 'Van Repair', 'Mobile / Communication', 'Other'];

    private static function db(): Database
    {
        return Database::getInstance();
    }

    // ------------------------------------------------------------------ trip

    /** @param array<string, mixed> $t @return array<string, mixed> */
    private static function formatTrip(array $t): array
    {
        return [
            'id' => (int) $t['id'],
            'code' => $t['trip_code'],
            'date' => $t['trip_date'],
            'partner_id' => (int) $t['partner_id'],
            'status_key' => $t['status'],
            'editable' => $t['status'] === 'dispatched',
            'settlement_status' => $t['settlement_status'],
            'review_note' => $t['review_note'],
            'dispatched_at' => $t['dispatched_at'],
            'sr_ids' => array_map('intval', array_filter(explode(',', (string) $t['sr_ids']))),
        ];
    }

    /** The DSR's open trip (dispatched or waiting for review), with its settlement row if any. */
    public static function activeTrip(int $dsrId): ?array
    {
        $t = self::db()->fetch(
            "SELECT t.*, ts.status AS settlement_status, ts.review_note,
                    (SELECT GROUP_CONCAT(x.sr_id) FROM trip_srs x WHERE x.trip_id = t.id) AS sr_ids
             FROM trips t LEFT JOIN trip_settlements ts ON ts.trip_id = t.id
             WHERE t.dsr_id = ? AND t.status IN ('dispatched', 'in_review')
             ORDER BY t.trip_date DESC, t.id DESC LIMIT 1",
            [$dsrId]
        );

        return $t === null ? null : self::formatTrip($t);
    }

    /** Any dispatched, in-review, or settled trip assigned to this DSR on the given date (YYYY-MM-DD). */
    public static function tripForDate(int $dsrId, string $date): ?array
    {
        $t = self::db()->fetch(
            "SELECT t.*, ts.status AS settlement_status, ts.review_note,
                    (SELECT GROUP_CONCAT(x.sr_id) FROM trip_srs x WHERE x.trip_id = t.id) AS sr_ids
             FROM trips t LEFT JOIN trip_settlements ts ON ts.trip_id = t.id
             WHERE t.dsr_id = ? AND t.trip_date = ? AND t.status IN ('dispatched', 'in_review', 'settled')
             ORDER BY FIELD(t.status, 'dispatched', 'in_review', 'settled'), t.id DESC LIMIT 1",
            [$dsrId, $date]
        );

        return $t === null ? null : self::formatTrip($t);
    }

    /** @return array<string, mixed> open trip that the DSR may still change */
    public static function editableTrip(int $dsrId): array
    {
        $trip = self::activeTrip($dsrId);
        if ($trip === null) {
            throw new HttpError('You have no dispatched trip.', 422);
        }
        if (!$trip['editable']) {
            throw new HttpError('This trip is submitted for settlement and waiting for partner review.', 422);
        }

        return $trip;
    }

    /** @return array<int, array<string, mixed>> van stock per product_id with live delivered / available */
    public static function vanStock(int $tripId): array
    {
        $rows = self::db()->fetchAll(
            "SELECT v.*, p.name, p.unit_type, p.qty_per_unit, p.image_path, c.name AS company, p.company_id,
                    (SELECT COALESCE(SUM(oi.delivered_pcs), 0) FROM order_items oi JOIN orders o ON o.id = oi.order_id
                     WHERE o.trip_id = v.trip_id AND oi.product_id = v.product_id AND o.status <> 'cancelled') AS delivered,
                    (SELECT COALESCE(SUM(oi.delivered_pcs), 0) FROM order_items oi JOIN orders o ON o.id = oi.order_id
                     WHERE o.trip_id = v.trip_id AND oi.product_id = v.product_id AND o.is_ready_sale = 1) AS ready_sold,
                    (SELECT COALESCE(SUM(oi.delivery_oc), 0) FROM order_items oi JOIN orders o ON o.id = oi.order_id
                     WHERE o.trip_id = v.trip_id AND oi.product_id = v.product_id AND o.status <> 'cancelled') AS delivery_oc
             FROM trip_van_stocks v
             JOIN products p ON p.id = v.product_id
             JOIN companies c ON c.id = p.company_id
             WHERE v.trip_id = ? ORDER BY c.name, p.name",
            [$tripId]
        );

        $out = [];
        foreach ($rows as $r) {
            $dispatched = (int) $r['dispatched_pcs'];
            $delivered = (int) $r['delivered'];
            $out[(int) $r['product_id']] = Product::visual((int) $r['product_id'], (string) $r['name'], $r['image_path']) + [
                'id' => (int) $r['product_id'],
                'name' => $r['name'],
                'company' => $r['company'],
                'company_id' => (int) $r['company_id'],
                'unit_type' => $r['unit_type'],
                'qty_per_unit' => (int) $r['qty_per_unit'],
                'base_rate' => (float) $r['base_rate_pc'],
                'ordered_pcs' => (int) $r['ordered_pcs'],
                'dispatched_pcs' => $dispatched,
                'delivered_pcs' => $delivered,
                'ready_sold_pcs' => (int) $r['ready_sold'],
                'available_pcs' => $dispatched - $delivered,
                'delivery_oc' => round((float) $r['delivery_oc'], 2),
            ];
        }

        return $out;
    }

    /** Keeps trip_van_stocks.delivered_pcs / ready_sale_pcs in step with the orders. */
    private static function syncVan(Database $db, int $tripId): void
    {
        $db->execute(
            "UPDATE trip_van_stocks v SET
                delivered_pcs = (SELECT COALESCE(SUM(oi.delivered_pcs), 0) FROM order_items oi JOIN orders o ON o.id = oi.order_id
                                 WHERE o.trip_id = v.trip_id AND oi.product_id = v.product_id AND o.status <> 'cancelled'),
                ready_sale_pcs = (SELECT COALESCE(SUM(oi.delivered_pcs), 0) FROM order_items oi JOIN orders o ON o.id = oi.order_id
                                  WHERE o.trip_id = v.trip_id AND oi.product_id = v.product_id AND o.is_ready_sale = 1)
             WHERE v.trip_id = ?",
            [$tripId]
        );
    }

    /** Old due the DSR may still collect from a retailer (balance minus what open trips already collected). */
    private static function collectableDue(int $retailerId, int $tripId): float
    {
        $r = self::db()->fetch(
            "SELECT r.due_balance,
                    (SELECT COALESCE(SUM(c.amount), 0) FROM retailer_due_collections c JOIN trips t ON t.id = c.trip_id
                     WHERE c.retailer_id = r.id AND c.trip_id <> ? AND t.status <> 'settled') AS other_open
             FROM retailers r WHERE r.id = ?",
            [$tripId, $retailerId]
        );

        return $r === null ? 0.0 : max(0.0, round((float) $r['due_balance'] - (float) $r['other_open'], 2));
    }

    // ----------------------------------------------------------------- stops

    /** @return list<array<string, mixed>> one stop per retailer, all of its trip orders grouped by company */
    public static function stops(array $trip): array
    {
        $db = self::db();
        $orders = $db->fetchAll(
            "SELECT o.*, c.name AS company, s.name AS sr_name,
                    r.name AS retailer_name, r.phone AS retailer_phone, r.address, r.lat, r.lng
             FROM orders o
             JOIN companies c ON c.id = o.company_id
             LEFT JOIN salesmen s ON s.id = o.sr_id
             LEFT JOIN retailers r ON r.id = o.retailer_id
             WHERE o.trip_id = ?
             ORDER BY o.is_ready_sale, o.id",
            [$trip['id']]
        );
        if ($orders === []) {
            return [];
        }

        $ids = implode(',', array_map(static fn(array $o): int => (int) $o['id'], $orders));
        $items = [];
        foreach ($db->fetchAll(
            "SELECT oi.*, p.name, p.unit_type, p.qty_per_unit FROM order_items oi JOIN products p ON p.id = oi.product_id
             WHERE oi.order_id IN ({$ids}) ORDER BY oi.id"
        ) as $it) {
            $items[(int) $it['order_id']][] = $it;
        }
        $damages = [];
        foreach ($db->fetchAll(
            "SELECT d.*, p.name FROM delivery_damages d JOIN products p ON p.id = d.product_id WHERE d.trip_id = ? ORDER BY d.id",
            [$trip['id']]
        ) as $d) {
            $damages[(int) $d['retailer_id']][] = [
                'order_id' => (int) $d['order_id'],
                'product_id' => (int) $d['product_id'],
                'name' => $d['name'],
                'pcs' => (int) $d['qty_pcs'],
                'amount' => (float) $d['amount'],
            ];
        }
        $collected = [];
        foreach ($db->fetchAll('SELECT retailer_id, SUM(amount) AS amt FROM retailer_due_collections WHERE trip_id = ? GROUP BY retailer_id', [$trip['id']]) as $c) {
            $collected[(int) $c['retailer_id']] = (float) $c['amt'];
        }
        $van = self::vanStock($trip['id']);

        $stops = [];
        foreach ($orders as $o) {
            $rid = (int) $o['retailer_id'];
            if (!isset($stops[$rid])) {
                $stops[$rid] = [
                    'id' => (string) $rid,
                    'retailer_name' => $o['retailer_name'] ?? $o['retailer_name_snapshot'],
                    'phone' => $o['retailer_phone'] ? Phone::format($o['retailer_phone']) : '',
                    'address' => (string) ($o['address'] ?? ''),
                    'lat' => (float) ($o['lat'] ?? 0),
                    'lng' => (float) ($o['lng'] ?? 0),
                    'sr_names' => [],
                    'companies' => [],
                    'damages' => $damages[$rid] ?? [],
                    'old_due_collected' => round($collected[$rid] ?? 0.0, 2),
                    'existing_due' => self::collectableDue($rid, $trip['id']),
                    'paid_amount' => 0.0,
                    'due_amount' => 0.0,
                    'cancel_reason' => '',
                ];
            }
            $st = &$stops[$rid];
            $resolved = !in_array($o['status'], ['assigned', 'pending'], true);
            if ($o['sr_name'] && !in_array($o['sr_name'], $st['sr_names'], true)) {
                $st['sr_names'][] = $o['sr_name'];
            }
            $st['companies'][] = [
                'id' => (string) $o['id'],
                'order_code' => $o['order_code'],
                'name' => $o['company'],
                'company_id' => (int) $o['company_id'],
                'sr' => $o['sr_name'] ?? 'Ready Sale',
                'ready_sale' => (bool) $o['is_ready_sale'],
                'status_key' => $o['status'],
                'cancelled' => $o['status'] === 'cancelled',
                'cancel_reason' => $o['cancel_reason'],
                'items' => array_map(static function (array $it) use ($resolved, $van): array {
                    $pid = (int) $it['product_id'];
                    $stock = ($van[$pid]['available_pcs'] ?? 0) + ($resolved ? (int) $it['delivered_pcs'] : 0);
                    // Not delivered yet: start from the ordered qty, but never more than the van holds
                    $qty = $resolved ? (int) $it['delivered_pcs'] : min((int) $it['ordered_pcs'], max(0, $stock));

                    return [
                        'product_id' => (string) $pid,
                        'name' => $it['name'],
                        'unit_type' => $it['unit_type'],
                        'qty_per_unit' => (int) $it['qty_per_unit'],
                        'ordered_qty' => (int) $it['ordered_pcs'],
                        'qty' => $qty,
                        'base_rate' => (float) $it['base_rate_pc'],
                        'sr_rate' => (float) $it['sr_rate_pc'],
                        // pieces left in the van that this line could still take
                        'stock' => $stock,
                    ];
                }, $items[(int) $o['id']] ?? []),
            ];
            $st['paid_amount'] = round($st['paid_amount'] + (float) $o['paid_amount'], 2);
            $st['due_amount'] = round($st['due_amount'] + (float) $o['due_amount'], 2);
            if ($o['status'] === 'cancelled' && $o['cancel_reason']) {
                $st['cancel_reason'] = $o['cancel_reason'];
            }
            unset($st);
        }

        foreach ($stops as &$st) {
            $keys = array_column($st['companies'], 'status_key');
            $st['status'] = match (true) {
                in_array('assigned', $keys, true) || in_array('pending', $keys, true) => 'Pending',
                count(array_filter($keys, static fn(string $k): bool => $k !== 'cancelled')) === 0 => 'Cancelled',
                $st['due_amount'] > 0.004 => 'Due',
                default => 'Delivered',
            };
            $st['editable'] = $trip['editable'] && count(array_filter($st['companies'], static fn(array $c): bool => !$c['ready_sale'])) > 0;
        }
        unset($st);

        return array_values($stops);
    }

    /**
     * Saves a retailer stop: delivered pieces per order line, cancelled orders, damage returns and the payment.
     *
     * @param array{orders:list<array{id:int, cancelled:bool, items:list<array{product_id:int, pcs:int}>}>, damages:list<array{order_id:int, product_id:int, pcs:int}>, paid:float, cancel_reason:?string} $d
     */
    public static function saveStop(array $dsr, int $retailerId, array $d): void
    {
        $trip = self::editableTrip($dsr['id']);
        $db = self::db();

        $orders = [];
        foreach ($db->fetchAll(
            'SELECT * FROM orders WHERE trip_id = ? AND retailer_id = ? AND is_ready_sale = 0',
            [$trip['id'], $retailerId]
        ) as $o) {
            $orders[(int) $o['id']] = $o;
        }
        if ($orders === []) {
            throw new HttpError('This retailer has no orders on your trip.', 404);
        }

        $input = [];
        foreach ($d['orders'] as $o) {
            if (!isset($orders[$o['id']])) {
                throw new HttpError('An order does not belong to this stop. Reload and try again.', 422);
            }
            $input[$o['id']] = $o;
        }
        if (count($input) !== count($orders)) {
            throw new HttpError('Every order of this retailer must be included. Reload and try again.', 422);
        }

        $reason = trim((string) ($d['cancel_reason'] ?? ''));
        $van = self::vanStock($trip['id']);
        $lines = [];
        $usedPcs = [];
        foreach ($input as $oid => $o) {
            $orderItems = [];
            foreach ($db->fetchAll('SELECT * FROM order_items WHERE order_id = ?', [$oid]) as $it) {
                $orderItems[(int) $it['product_id']] = $it;
            }
            if ($o['cancelled']) {
                if ($reason === '') {
                    throw new HttpError('Select a reason for the cancelled order(s).', 422);
                }
                continue;
            }
            foreach ($o['items'] as $it) {
                $row = $orderItems[$it['product_id']] ?? null;
                if ($row === null) {
                    throw new HttpError('A product is not part of the order. Use Ready Sale for extra products.', 422);
                }
                if ($it['pcs'] < 0) {
                    throw new HttpError('Quantity cannot be negative.', 422);
                }
                $lines[$oid][$it['product_id']] = $it['pcs'];
                $usedPcs[$it['product_id']] = ($usedPcs[$it['product_id']] ?? 0) + $it['pcs'];
            }
        }

        // Van availability: what other orders on the trip have not taken (this stop's old values are freed)
        foreach ($usedPcs as $pid => $pcs) {
            $own = 0;
            foreach ($orders as $oid => $o) {
                $own += (int) ($db->fetch('SELECT delivered_pcs FROM order_items WHERE order_id = ? AND product_id = ?', [$oid, $pid])['delivered_pcs'] ?? 0);
            }
            $free = ($van[$pid]['available_pcs'] ?? 0) + $own;
            if ($pcs > $free) {
                $name = $van[$pid]['name'] ?? 'A product';
                throw new HttpError("{$name}: only {$free} pcs left in the van.", 422);
            }
        }

        // Damage returns: accept any product from the trip's assigned SRs/partner; link to matching company order when bill covers it, else trip-level (order_id = NULL)
        $orderByCompany = [];
        foreach ($input as $oid => $o) {
            if (!$o['cancelled']) {
                $orderByCompany[(int) $orders[$oid]['company_id']] = (int) $oid;
            }
        }
        $damages = [];
        foreach ($d['damages'] as $dm) {
            if (($dm['pcs'] ?? 0) < 1) {
                throw new HttpError('ড্যামেজ পিসের সংখ্যা কমপক্ষে ১ হতে হবে।', 422);
            }
            $p = $db->fetch(
                'SELECT id, company_id, name, COALESCE(NULLIF(base_price, 0), company_price, 0) AS rate FROM products WHERE id = ? AND partner_id = ? AND deleted_at IS NULL',
                [$dm['product_id'], $trip['partner_id']]
            );
            if ($p === null) {
                throw new HttpError('ড্যামেজ পণ্যটি খুঁজে পাওয়া যায়নি।', 422);
            }
            $cid = (int) $p['company_id'];
            $linkedOid = null;
            if (!empty($dm['order_id']) && isset($orders[$dm['order_id']]) && empty($input[$dm['order_id']]['cancelled']) && (int) $orders[$dm['order_id']]['company_id'] === $cid) {
                $linkedOid = (int) $dm['order_id'];
            } elseif (isset($orderByCompany[$cid])) {
                $linkedOid = $orderByCompany[$cid];
            }
            $damages[] = [
                'order_id' => $linkedOid,
                'product_id' => (int) $p['id'],
                'pcs' => (int) $dm['pcs'],
                'amount' => round((int) $dm['pcs'] * (float) $p['rate'], 2),
                'company_id' => $cid,
            ];
        }

        // Bills per order: allocate order-linked damages first, then any cross-company/excess stop damages across remaining delivered value so bill = max(0, sum(sr) - sum(damage)) matches settlement cash
        $bills = [];
        foreach ($input as $oid => $o) {
            if ($o['cancelled']) {
                continue;
            }
            $base = 0.0;
            $sr = 0.0;
            foreach ($db->fetchAll('SELECT * FROM order_items WHERE order_id = ?', [$oid]) as $it) {
                $pcs = $lines[$oid][(int) $it['product_id']] ?? 0;
                $base += $pcs * (float) $it['base_rate_pc'];
                $sr += $pcs * (float) $it['sr_rate_pc'];
            }
            $srRounded = round($sr, 2);
            $orderDmg = 0.0;
            foreach ($damages as &$dmRef) {
                if ($dmRef['order_id'] === $oid) {
                    $take = min($dmRef['amount'], max(0.0, round($srRounded - $orderDmg, 2)));
                    $orderDmg = round($orderDmg + $take, 2);
                    if ($take + 0.004 < $dmRef['amount']) {
                        $dmRef['order_id'] = null;
                    }
                }
            }
            unset($dmRef);
            $bills[$oid] = ['base' => round($base, 2), 'sr' => $srRounded, 'damage' => $orderDmg, 'bill' => round($srRounded - $orderDmg, 2)];
        }
        $unlinkedDmgPool = round(array_sum(array_map(
            static fn(array $x): float => $x['order_id'] === null ? $x['amount'] : 0.0,
            $damages
        )), 2);
        // Also allocate partial overflow from linked damages if any
        $totalAllDmg = round(array_sum(array_column($damages, 'amount')), 2);
        $alreadyCredited = round(array_sum(array_column($bills, 'damage')), 2);
        $remainingDmgCredit = round(max(0.0, $totalAllDmg - $alreadyCredited), 2);
        if ($remainingDmgCredit > 0.004) {
            foreach ($bills as &$bRef) {
                if ($remainingDmgCredit <= 0.004) {
                    break;
                }
                $room = max(0.0, round($bRef['sr'] - $bRef['damage'], 2));
                $take = round(min($room, $remainingDmgCredit), 2);
                if ($take > 0.0) {
                    $bRef['damage'] = round($bRef['damage'] + $take, 2);
                    $bRef['bill'] = round($bRef['sr'] - $bRef['damage'], 2);
                    $remainingDmgCredit = round($remainingDmgCredit - $take, 2);
                }
            }
            unset($bRef);
        }
        unset($unlinkedDmgPool);

        $shouldPay = round(array_sum(array_column($bills, 'bill')), 2);
        $oldDue = self::collectableDue($retailerId, $trip['id']);
        $paid = round($d['paid'], 2);
        if ($paid < 0 || $paid - ($shouldPay + $oldDue) > 0.004) {
            throw new HttpError('Paid amount can be at most ৳ ' . number_format($shouldPay + $oldDue, 2) . ' (bill + old due).', 422);
        }
        $collect = round(max(0.0, $paid - $shouldPay), 2);
        $left = min($paid, $shouldPay);

        $db->transaction(static function (Database $db) use ($trip, $retailerId, $orders, $input, $lines, $bills, $damages, $left, $collect, $reason): void {
            foreach ($input as $oid => $o) {
                $order = $orders[$oid];
                if ($o['cancelled']) {
                    $db->execute(
                        "UPDATE orders SET status = 'cancelled', cancel_reason = ?, delivered_base_total = 0, delivered_sr_total = 0, delivery_oc = 0,
                            damage_amount = 0, paid_amount = 0, due_amount = 0, platform_fee_amount = 0, delivered_at = NOW() WHERE id = ?",
                        [mb_substr('DSR: ' . $reason, 0, 255), $oid]
                    );
                    $db->execute('UPDATE order_items SET delivered_pcs = 0, delivery_oc = 0 WHERE order_id = ?', [$oid]);
                    continue;
                }

                foreach ($db->fetchAll('SELECT * FROM order_items WHERE order_id = ?', [$oid]) as $it) {
                    $pcs = $lines[$oid][(int) $it['product_id']] ?? 0;
                    $db->execute(
                        'UPDATE order_items SET delivered_pcs = ?, delivery_oc = ? WHERE id = ?',
                        [$pcs, round($pcs * ((float) $it['sr_rate_pc'] - (float) $it['base_rate_pc']), 2), $it['id']]
                    );
                }

                $b = $bills[$oid];
                $pay = round(min($left, $b['bill']), 2);
                $left = round($left - $pay, 2);
                $due = round($b['bill'] - $pay, 2);
                $status = $due <= 0.004 ? 'delivered' : ($pay > 0 ? 'partial' : 'due');
                $fee = PlatformFee::amount($b['base'], (float) ($order['platform_fee_rate'] ?? 0));
                $db->execute(
                    'UPDATE orders SET status = ?, cancel_reason = NULL, delivered_base_total = ?, delivered_sr_total = ?, delivery_oc = ?,
                        damage_amount = ?, paid_amount = ?, due_amount = ?, platform_fee_amount = ?, delivered_at = NOW() WHERE id = ?',
                    [$status, $b['base'], $b['sr'], round($b['sr'] - $b['base'], 2), $b['damage'], $pay, max(0, $due), $fee, $oid]
                );
            }

            $db->execute('DELETE FROM delivery_damages WHERE trip_id = ? AND retailer_id = ?', [$trip['id'], $retailerId]);
            foreach ($damages as $dm) {
                $db->execute(
                    'INSERT INTO delivery_damages (trip_id, order_id, retailer_id, company_id, product_id, qty_pcs, amount) VALUES (?, ?, ?, ?, ?, ?, ?)',
                    [$trip['id'], $dm['order_id'], $retailerId, $dm['company_id'], $dm['product_id'], $dm['pcs'], $dm['amount']]
                );
            }
            $db->execute('DELETE FROM retailer_due_collections WHERE trip_id = ? AND retailer_id = ?', [$trip['id'], $retailerId]);
            if ($collect > 0) {
                $db->execute(
                    'INSERT INTO retailer_due_collections (trip_id, retailer_id, amount, note) VALUES (?, ?, ?, ?)',
                    [$trip['id'], $retailerId, $collect, 'Collected with delivery']
                );
            }
            self::syncVan($db, $trip['id']);
        });
    }

    /** Undo: puts the stop's orders back to "not delivered yet". */
    public static function resetStop(array $dsr, int $retailerId): void
    {
        $trip = self::editableTrip($dsr['id']);
        self::db()->transaction(static function (Database $db) use ($trip, $retailerId): void {
            $ids = array_column($db->fetchAll(
                'SELECT id FROM orders WHERE trip_id = ? AND retailer_id = ? AND is_ready_sale = 0',
                [$trip['id'], $retailerId]
            ), 'id');
            if ($ids === []) {
                throw new HttpError('This retailer has no orders on your trip.', 404);
            }
            $in = implode(',', array_map('intval', $ids));
            $db->execute(
                "UPDATE orders SET status = 'assigned', cancel_reason = NULL, delivered_base_total = 0, delivered_sr_total = 0, delivery_oc = 0,
                    damage_amount = 0, paid_amount = 0, due_amount = 0, platform_fee_amount = 0, delivered_at = NULL WHERE id IN ({$in})"
            );
            $db->execute("UPDATE order_items SET delivered_pcs = 0, delivery_oc = 0 WHERE order_id IN ({$in})");
            $db->execute('DELETE FROM delivery_damages WHERE trip_id = ? AND retailer_id = ?', [$trip['id'], $retailerId]);
            $db->execute('DELETE FROM retailer_due_collections WHERE trip_id = ? AND retailer_id = ?', [$trip['id'], $retailerId]);
            self::syncVan($db, $trip['id']);
        });
    }

    // ------------------------------------------------------------ ready sale

    /** @return list<array<string, mixed>> partner retailers for the Ready Sale picker */
    public static function retailers(int $partnerId, array $prioritySrIds = [], ?float $lat = null, ?float $lng = null, ?int $limit = null): array
    {
        $list = Retailer::forSrMap($partnerId, $lat, $lng, $limit);
        $byId = [];
        foreach ($list as $r) {
            $id = (string) $r['id'];
            $byId[$id] = ['id' => $id] + $r;
        }

        $srIds = array_values(array_filter(array_map('intval', $prioritySrIds), static fn(int $v): bool => $v > 0));
        if ($limit !== null && $srIds !== []) {
            $in = implode(',', $srIds);
            $srRows = self::db()->fetchAll(
                "SELECT id, partner_id, created_by_sr_id, name, phone, address, lat, lng, due_balance
                 FROM retailers
                 WHERE partner_id = ? AND status = 'active' AND created_by_sr_id IN ({$in})
                 ORDER BY id DESC",
                [$partnerId]
            );
            foreach ($srRows as $r) {
                $id = (string) $r['id'];
                if (!isset($byId[$id])) {
                    $byId[$id] = [
                        'id' => $id,
                        'name' => $r['name'],
                        'phone' => $r['phone'] ? Phone::format($r['phone']) : '',
                        'address' => $r['address'],
                        'lat' => (float) $r['lat'],
                        'lng' => (float) $r['lng'],
                        'sr_id' => isset($r['created_by_sr_id']) ? (int) $r['created_by_sr_id'] : null,
                        'due' => (float) $r['due_balance'],
                    ];
                }
            }
        }

        return array_values($byId);
    }

    /**
     * Sells one or multiple van stock products at dealer price (cash). Supports multi-company cart cleanly.
     *
     * @param array{
     *     retailer_id:?int,
     *     new_retailer:?array{name:string, phone:?string, address:string, lat:float, lng:float},
     *     items?:list<array{product_id:int, pcs:int}>,
     *     product_id?:int,
     *     pcs?:int
     * } $d
     */
    public static function readySale(array $dsr, array $d): array
    {
        $trip = self::editableTrip($dsr['id']);
        $van = self::vanStock($trip['id']);

        $rawItems = !empty($d['items']) && is_array($d['items'])
            ? $d['items']
            : [['product_id' => (int) ($d['product_id'] ?? 0), 'pcs' => (int) ($d['pcs'] ?? 0)]];

        $merged = [];
        foreach ($rawItems as $it) {
            $pid = (int) ($it['product_id'] ?? 0);
            $pcs = (int) ($it['pcs'] ?? 0);
            if ($pid < 1 || $pcs < 1) {
                continue;
            }
            $merged[$pid] = ($merged[$pid] ?? 0) + $pcs;
        }
        if ($merged === []) {
            throw new HttpError('ভ্যান থেকে অন্তত ১টি পণ্য ও পরিমাণ নির্বাচন করুন।', 422);
        }

        $byCompany = [];
        foreach ($merged as $pid => $pcs) {
            $p = $van[$pid] ?? null;
            if ($p === null) {
                throw new HttpError('ভ্যানে লোড করা পণ্য থেকে নির্বাচন করুন।', 422);
            }
            if ($pcs > $p['available_pcs']) {
                throw new HttpError("{$p['name']}: ভ্যানে মাত্র {$p['available_pcs']} পিস বাকি আছে।", 422);
            }
            $byCompany[(int) $p['company_id']][] = ['product' => $p, 'pcs' => $pcs];
        }

        return self::db()->transaction(static function (Database $db) use ($dsr, $trip, $d, $byCompany): array {
            if ($d['new_retailer'] !== null) {
                $r = $d['new_retailer'];
                if ($r['lat'] == 0.0 && $r['lng'] == 0.0) {
                    throw new HttpError('দোকানের অবস্থান পাওয়া যায়নি। লোকেশন অ্যাক্সেস চালু করুন।', 422);
                }
                $db->execute(
                    'INSERT INTO retailers (partner_id, name, phone, address, lat, lng) VALUES (?, ?, ?, ?, ?, ?)',
                    [$trip['partner_id'], $r['name'], $r['phone'], $r['address'], $r['lat'], $r['lng']]
                );
                $retailerId = (int) $db->lastInsertId();
            } else {
                $retailerId = (int) $d['retailer_id'];
            }
            $retailer = Retailer::findForPartner($trip['partner_id'], $retailerId);

            $grandTotal = 0.0;
            $createdOrders = [];
            $receiptItems = [];

            foreach ($byCompany as $companyId => $lines) {
                $companyTotal = 0.0;
                foreach ($lines as $line) {
                    $companyTotal += $line['pcs'] * (float) $line['product']['base_rate'];
                }
                $companyTotal = round($companyTotal, 2);
                $rate = PlatformFee::rateAt($trip['partner_id'], $companyId);

                $db->execute(
                    "INSERT INTO orders (order_code, partner_id, company_id, sr_id, retailer_id, retailer_name_snapshot, trip_id, order_date, is_ready_sale,
                        order_base_total, order_sr_total, order_oc, delivered_base_total, delivered_sr_total, delivery_oc, paid_amount, due_amount,
                        platform_fee_rate, platform_fee_amount, status, notes, delivered_at)
                     VALUES (?, ?, ?, NULL, ?, ?, ?, ?, 1, ?, ?, 0, ?, ?, 0, ?, 0, ?, ?, 'delivered', ?, NOW())",
                    [
                        'TMP-' . bin2hex(random_bytes(8)),
                        $trip['partner_id'],
                        $companyId,
                        $retailerId,
                        $retailer['name'],
                        $trip['id'],
                        $trip['date'],
                        $companyTotal,
                        $companyTotal,
                        $companyTotal,
                        $companyTotal,
                        $companyTotal,
                        $rate,
                        PlatformFee::amount($companyTotal, $rate),
                        'Ready sale by DSR ' . $dsr['name'],
                    ]
                );
                $oid = (int) $db->lastInsertId();
                $code = 'RS-' . date('ymd', strtotime($trip['date'])) . '-' . str_pad((string) $oid, 5, '0', STR_PAD_LEFT);
                $db->execute('UPDATE orders SET order_code = ? WHERE id = ?', [$code, $oid]);

                foreach ($lines as $line) {
                    $p = $line['product'];
                    $pcs = $line['pcs'];
                    $db->execute(
                        'INSERT INTO order_items (order_id, product_id, ordered_pcs, delivered_pcs, base_rate_pc, sr_rate_pc) VALUES (?, ?, ?, ?, ?, ?)',
                        [$oid, $p['id'], $pcs, $pcs, $p['base_rate'], $p['base_rate']]
                    );
                    $receiptItems[] = [
                        'name' => $p['name'],
                        'pcs' => $pcs,
                        'rate' => $p['base_rate'],
                        'total' => round($pcs * (float) $p['base_rate'], 2),
                    ];
                }

                $grandTotal = round($grandTotal + $companyTotal, 2);
                $createdOrders[] = ['id' => $oid, 'code' => $code, 'total' => $companyTotal];
            }

            self::syncVan($db, $trip['id']);

            return [
                'retailer' => $retailer['name'],
                'retailer_id' => $retailerId,
                'total' => $grandTotal,
                'order_id' => $createdOrders[0]['id'] ?? 0,
                'codes' => array_column($createdOrders, 'code'),
                'items' => $receiptItems,
                'new_retailer' => $d['new_retailer'] !== null ? [
                    'id' => (string) $retailer['id'],
                    'name' => $retailer['name'],
                    'phone' => $retailer['phone'] ? Phone::format($retailer['phone']) : '',
                    'address' => $retailer['address'],
                    'lat' => (float) $retailer['lat'],
                    'lng' => (float) $retailer['lng'],
                    'sr_id' => isset($retailer['created_by_sr_id']) ? (int) $retailer['created_by_sr_id'] : null,
                    'due' => (float) $retailer['due_balance'],
                ] : null,
            ];
        });
    }

    public static function deleteReadySale(array $dsr, int $orderId): void
    {
        $trip = self::editableTrip($dsr['id']);
        self::db()->transaction(static function (Database $db) use ($trip, $orderId): void {
            $n = $db->execute('DELETE FROM orders WHERE id = ? AND trip_id = ? AND is_ready_sale = 1', [$orderId, $trip['id']]);
            if ($n === 0) {
                throw new HttpError('Ready sale not found.', 404);
            }
            self::syncVan($db, $trip['id']);
        });
    }

    /** @return list<array<string, mixed>> all products of the trip's assigned SRs' companies (not limited to van stock) */
    public static function damageProducts(int $partnerId, array $srIds = []): array
    {
        $srList = array_values(array_filter(array_map('intval', $srIds), static fn(int $v): bool => $v > 0));
        $companyFilterSql = '';
        if ($srList !== []) {
            $in = implode(',', $srList);
            $compIds = array_values(array_unique(array_filter(array_map('intval', array_column(
                self::db()->fetchAll("SELECT DISTINCT company_id FROM salesmen WHERE id IN ({$in}) AND partner_id = ? AND deleted_at IS NULL", [$partnerId]),
                'company_id'
            )))));
            if ($compIds !== []) {
                $companyFilterSql = ' AND p.company_id IN (' . implode(',', $compIds) . ')';
            }
        }

        return array_map(static fn(array $r): array => Product::visual((int) $r['id'], (string) $r['name'], $r['image_path']) + [
            'id' => (string) $r['id'],
            'name' => $r['name'],
            'company_id' => (int) $r['company_id'],
            'company' => $r['company'],
            'unit_type' => $r['unit_type'],
            'qty_per_unit' => (int) $r['qty_per_unit'],
            'rate' => (float) $r['rate'],
        ], self::db()->fetchAll(
            "SELECT p.id, p.name, p.company_id, c.name AS company,
                    COALESCE(NULLIF(p.base_price, 0), p.company_price, 0) AS rate,
                    p.unit_type, p.qty_per_unit, p.image_path
             FROM products p
             JOIN companies c ON c.id = p.company_id
             WHERE p.partner_id = ? AND p.deleted_at IS NULL AND p.status = 'active'{$companyFilterSql}
             ORDER BY c.name, p.name",
            [$partnerId]
        ));
    }

    /**
     * Direct damage submission for a retailer on the editable trip (supports any assigned SR product, even if not on van or not ordered).
     *
     * @param list<array{product_id:int, pcs:int}> $items
     * @return array{count:int, total:float, retailer:string}
     */
    public static function saveDamages(array $dsr, int $retailerId, array $items): array
    {
        $trip = self::editableTrip($dsr['id']);
        $retailer = Retailer::findForPartner($trip['partner_id'], $retailerId);

        $merged = [];
        foreach ($items as $it) {
            $pid = (int) ($it['product_id'] ?? 0);
            $pcs = (int) ($it['pcs'] ?? 0);
            if ($pid < 1 || $pcs < 1) {
                continue;
            }
            $merged[$pid] = ($merged[$pid] ?? 0) + $pcs;
        }

        $allowed = [];
        foreach (self::damageProducts($trip['partner_id'], $trip['sr_ids'] ?? []) as $ap) {
            $allowed[(int) $ap['id']] = $ap;
        }

        $totalAmt = 0.0;
        $clean = [];
        foreach ($merged as $pid => $pcs) {
            $p = $allowed[$pid] ?? null;
            if ($p === null) {
                throw new HttpError('নির্বাচিত পণ্যটি এই ট্রিপের SR-এর তালিকায় নেই।', 422);
            }
            $amt = round($pcs * (float) $p['rate'], 2);
            $totalAmt = round($totalAmt + $amt, 2);
            $clean[] = [
                'product_id' => $pid,
                'company_id' => (int) $p['company_id'],
                'pcs' => $pcs,
                'amount' => $amt,
            ];
        }

        self::db()->transaction(static function (Database $db) use ($trip, $retailerId, $clean): void {
            $orderByComp = [];
            foreach ($db->fetchAll(
                "SELECT id, company_id, status, delivered_sr_total, order_sr_total
                 FROM orders
                 WHERE trip_id = ? AND retailer_id = ? AND is_ready_sale = 0 AND status <> 'cancelled'
                 ORDER BY id",
                [$trip['id'], $retailerId]
            ) as $o) {
                $cid = (int) $o['company_id'];
                if (!isset($orderByComp[$cid])) {
                    $orderByComp[$cid] = [
                        'id' => (int) $o['id'],
                        'status' => $o['status'],
                        'sr_val' => $o['status'] === 'assigned' ? (float) $o['order_sr_total'] : (float) $o['delivered_sr_total'],
                        'used' => 0.0,
                    ];
                }
            }

            $db->execute('DELETE FROM delivery_damages WHERE trip_id = ? AND retailer_id = ?', [$trip['id'], $retailerId]);
            foreach ($clean as $dm) {
                $cid = $dm['company_id'];
                $oid = null;
                if (isset($orderByComp[$cid]) && $orderByComp[$cid]['status'] === 'assigned'
                    && $orderByComp[$cid]['used'] + $dm['amount'] - $orderByComp[$cid]['sr_val'] <= 0.004) {
                    $oid = $orderByComp[$cid]['id'];
                    $orderByComp[$cid]['used'] = round($orderByComp[$cid]['used'] + $dm['amount'], 2);
                }
                $db->execute(
                    'INSERT INTO delivery_damages (trip_id, order_id, retailer_id, company_id, product_id, qty_pcs, amount) VALUES (?, ?, ?, ?, ?, ?, ?)',
                    [$trip['id'], $oid, $retailerId, $cid, $dm['product_id'], $dm['pcs'], $dm['amount']]
                );
            }
        });

        return ['count' => count($clean), 'total' => $totalAmt, 'retailer' => $retailer['name']];
    }

    // -------------------------------------------------------------- expenses

    /** @return list<array<string, mixed>> */
    public static function expenses(int $tripId): array
    {
        return array_map(static fn(array $e): array => [
            'id' => (int) $e['id'],
            'title' => $e['title'],
            'category' => $e['category'],
            'amount' => (float) $e['amount'],
            'note' => $e['note'],
            'time' => date('h:i A', strtotime((string) $e['expense_at'])),
            'date' => date('Y-m-d', strtotime((string) $e['expense_at'])),
        ], self::db()->fetchAll('SELECT * FROM trip_expenses WHERE trip_id = ? ORDER BY expense_at DESC, id DESC', [$tripId]));
    }

    /** @param array{title:string, category:string, amount:float, note:?string} $d */
    public static function addExpense(array $dsr, array $d): void
    {
        $trip = self::editableTrip($dsr['id']);
        if (!in_array($d['category'], self::EXPENSE_CATEGORIES, true)) {
            throw new HttpError('Select a valid category.', 422);
        }
        if ($d['amount'] <= 0 || $d['amount'] > 1000000) {
            throw new HttpError('Enter a valid amount.', 422);
        }
        self::db()->execute(
            'INSERT INTO trip_expenses (trip_id, dsr_id, title, category, amount, note) VALUES (?, ?, ?, ?, ?, ?)',
            [$trip['id'], $dsr['id'], $d['title'], $d['category'], round($d['amount'], 2), $d['note']]
        );
    }

    public static function deleteExpense(array $dsr, int $id): void
    {
        $trip = self::editableTrip($dsr['id']);
        if (self::db()->execute('DELETE FROM trip_expenses WHERE id = ? AND trip_id = ?', [$id, $trip['id']]) === 0) {
            throw new HttpError('Expense not found.', 404);
        }
    }
}
