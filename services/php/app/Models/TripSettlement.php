<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Format;
use App\Support\HttpError;
use App\Support\Phone;
use Core\Database;

/**
 * Trip cash settlement.
 *   System Cash = delivered (SR price) + ready sale + old due collected − damage − new due
 *   Net Pay     = System Cash − expenses
 * DSR submits (trip → in_review); partner verifies cash, returned stock & damage then approves (trip → settled)
 * or sends it back (trip → dispatched).
 * Approval: partner-counted unsold stock goes back to lots & warehouse stock, FIFO cost per sold line,
 * SR O/C ledger, retailer due balances, and verified damage claims on the company ledger.
 */
final class TripSettlement
{
    public const NOTES = [1000, 500, 200, 100, 50, 20, 10, 5, 2, 1];

    private static function db(): Database
    {
        return Database::getInstance();
    }

    /** @return array<string, mixed> live figures of a trip (any status) */
    public static function compute(int $tripId): array
    {
        $db = self::db();
        $t = $db->fetch(
            'SELECT t.*, dm.name AS dsr_name, ts.status AS settlement_status, ts.review_note, ts.cash_counted, ts.cash_diff,
                    ts.cash_notes_json, ts.dsr_note, ts.partner_cash_received, ts.partner_cash_diff,
                    ts.partner_damage_amount, ts.partner_damage_note,
                    ts.submitted_at, ts.approved_at, ts.net_payable AS submitted_net
             FROM trips t JOIN delivery_men dm ON dm.id = t.dsr_id LEFT JOIN trip_settlements ts ON ts.trip_id = t.id
             WHERE t.id = ?',
            [$tripId]
        );
        if ($t === null) {
            throw new HttpError('Trip not found.', 404);
        }

        $o = $db->fetch(
            "SELECT COUNT(*) AS orders,
                    COUNT(CASE WHEN status IN ('assigned', 'pending') THEN 1 END) AS pending,
                    COUNT(CASE WHEN status = 'cancelled' THEN 1 END) AS cancelled,
                    COALESCE(SUM(CASE WHEN is_ready_sale = 0 THEN order_sr_total END), 0) AS order_amount,
                    COALESCE(SUM(CASE WHEN is_ready_sale = 0 THEN delivered_base_total END), 0) AS delivered_base,
                    COALESCE(SUM(CASE WHEN is_ready_sale = 0 THEN delivered_sr_total END), 0) AS delivered_sr,
                    COALESCE(SUM(CASE WHEN is_ready_sale = 1 THEN delivered_sr_total END), 0) AS ready_sale,
                    COALESCE(SUM(delivery_oc), 0) AS delivery_oc,
                    COALESCE(SUM(damage_amount), 0) AS damage,
                    COALESCE(SUM(due_amount), 0) AS new_due,
                    COALESCE(SUM(paid_amount), 0) AS paid
             FROM orders WHERE trip_id = ?",
            [$tripId]
        );
        $stops = $db->fetch(
            "SELECT COUNT(*) AS total,
                    COALESCE(SUM(CASE WHEN pending_cnt = 0 THEN 1 ELSE 0 END), 0) AS done
             FROM (
                 SELECT COALESCE(retailer_id, id) AS stop_key,
                        SUM(CASE WHEN status IN ('assigned', 'pending') THEN 1 ELSE 0 END) AS pending_cnt
                 FROM orders
                 WHERE trip_id = ? AND is_ready_sale = 0
                 GROUP BY COALESCE(retailer_id, id)
             ) s",
            [$tripId]
        );
        $load = $db->fetch(
            'SELECT COALESCE(SUM(dispatched_pcs * base_rate_pc), 0) AS load_base,
                    COALESCE(SUM(GREATEST(dispatched_pcs - delivered_pcs, 0) * base_rate_pc), 0) AS return_base,
                    COALESCE(SUM(returned_pcs * base_rate_pc), 0) AS actual_return_base
             FROM trip_van_stocks WHERE trip_id = ?',
            [$tripId]
        );
        $prior = (float) $db->fetch('SELECT COALESCE(SUM(amount), 0) AS a FROM retailer_due_collections WHERE trip_id = ?', [$tripId])['a'];

        $expenseRows = $db->fetchAll(
            'SELECT title, category, amount, note FROM trip_expenses WHERE trip_id = ? ORDER BY expense_at, id',
            [$tripId]
        );
        $expense = round(array_sum(array_map(static fn(array $e): float => (float) $e['amount'], $expenseRows)), 2);
        $expenseCategories = array_values(array_unique(array_filter(array_map(
            static fn(array $e): string => trim((string) $e['category']),
            $expenseRows
        ))));

        $deliveredSr = (float) $o['delivered_sr'];
        $readySale = (float) $o['ready_sale'];
        $damage = round((float) ($db->fetch('SELECT COALESCE(SUM(amount), 0) AS a FROM delivery_damages WHERE trip_id = ?', [$tripId])['a'] ?? 0), 2);
        $newDue = (float) $o['new_due'];
        $systemCash = round($deliveredSr + $readySale + $prior - $damage - $newDue, 2);
        $net = round($systemCash - $expense, 2);

        $srRows = array_map(static fn(array $r): array => [
            'sr_name' => $r['name'],
            'area' => $r['area'] ?: $r['company'],
            'orders' => (int) $r['orders'],
            'order_oc' => (float) $r['order_oc'],
            'delivery_oc' => (float) $r['delivery_oc'],
        ], $db->fetchAll(
            "SELECT s.name, s.area, c.name AS company, COUNT(*) AS orders, SUM(o.order_oc) AS order_oc,
                    SUM(CASE WHEN o.status <> 'cancelled' THEN o.delivery_oc ELSE 0 END) AS delivery_oc
             FROM orders o JOIN salesmen s ON s.id = o.sr_id JOIN companies c ON c.id = s.company_id
             WHERE o.trip_id = ? GROUP BY s.id, s.name, s.area, c.name ORDER BY s.name",
            [$tripId]
        ));

        $dueRaw = $db->fetchAll(
            'SELECT o.*, r.phone, r.address FROM orders o LEFT JOIN retailers r ON r.id = o.retailer_id
             WHERE o.trip_id = ? AND o.due_amount > 0 ORDER BY o.retailer_name_snapshot',
            [$tripId]
        );
        $dueShopIds = [];
        $dues = [];
        foreach ($dueRaw as $r) {
            $dueShopIds[(string) ($r['retailer_id'] ?? $r['id'])] = true;
            $dues[] = [
                'order_id' => $r['order_code'],
                'retailer' => $r['retailer_name_snapshot'],
                'phone' => $r['phone'] ? Phone::format($r['phone']) : '',
                'area' => (string) $r['address'],
                'order_total' => round((float) $r['delivered_sr_total'] - (float) $r['damage_amount'], 2),
                'paid' => (float) $r['paid_amount'],
                'due' => (float) $r['due_amount'],
            ];
        }

        // Contextual reasons for unsold / returned van stock (cancelled orders or reduced deliveries)
        $reasonMap = [];
        foreach ($db->fetchAll(
            "SELECT oi.product_id, o.retailer_name_snapshot AS retailer, o.status, o.cancel_reason,
                    oi.ordered_pcs, oi.delivered_pcs
             FROM order_items oi
             JOIN orders o ON o.id = oi.order_id
             WHERE o.trip_id = ? AND o.is_ready_sale = 0
               AND (o.status = 'cancelled' OR (o.status NOT IN ('assigned', 'pending') AND oi.ordered_pcs > oi.delivered_pcs))
             ORDER BY o.id, oi.id",
            [$tripId]
        ) as $rr) {
            $pid = (int) $rr['product_id'];
            $shop = trim((string) $rr['retailer']);
            if ($rr['status'] === 'cancelled') {
                $why = preg_replace('/^DSR:\s*/i', '', trim((string) ($rr['cancel_reason'] ?? '')));
                $label = $why !== '' ? "{$shop} · {$why}" : "{$shop} · Cancelled";
            } else {
                $diffPcs = max(0, (int) $rr['ordered_pcs'] - (int) $rr['delivered_pcs']);
                $label = "{$shop} · Reduced ({$diffPcs} pcs)";
            }
            if (!isset($reasonMap[$pid])) {
                $reasonMap[$pid] = [];
            }
            if (!in_array($label, $reasonMap[$pid], true)) {
                $reasonMap[$pid][] = $label;
            }
        }

        $returnItems = [];
        foreach ($db->fetchAll(
            "SELECT v.*, p.name, p.unit_type, p.qty_per_unit, p.image_path, c.name AS company
             FROM trip_van_stocks v
             JOIN products p ON p.id = v.product_id
             JOIN companies c ON c.id = p.company_id
             WHERE v.trip_id = ?
             ORDER BY c.name, p.name",
            [$tripId]
        ) as $v) {
            $pid = (int) $v['product_id'];
            $dispatched = (int) $v['dispatched_pcs'];
            $delivered = (int) $v['delivered_pcs'];
            $expected = max(0, $dispatched - $delivered);
            $savedReturned = (int) $v['returned_pcs'];
            if ($expected === 0 && $savedReturned === 0) {
                continue;
            }
            $reasons = $reasonMap[$pid] ?? [];
            if ($reasons === []) {
                $reasons[] = $dispatched > (int) $v['ordered_pcs'] ? 'Extra van stock' : 'Unsold van stock';
            }
            $reasonSummary = count($reasons) <= 2
                ? implode(' / ', $reasons)
                : $reasons[0] . ' +' . (count($reasons) - 1) . ' more';

            $returnItems[] = Product::visual($pid, (string) $v['name'], $v['image_path']) + [
                'product_id' => $pid,
                'name' => $v['name'],
                'company' => $v['company'],
                'unit_type' => $v['unit_type'],
                'qty_per_unit' => max(1, (int) $v['qty_per_unit']),
                'base_rate' => (float) $v['base_rate_pc'],
                'dispatched_pcs' => $dispatched,
                'delivered_pcs' => $delivered,
                'expected_return_pcs' => $expected,
                'counted_return_pcs' => $t['status'] === 'settled' ? $savedReturned : $expected,
                'reason' => $reasonSummary,
            ];
        }

        $damageItems = array_map(static fn(array $r): array => [
            'id' => (int) $r['id'],
            'retailer' => $r['retailer_name'],
            'product' => $r['product_name'],
            'qty_pcs' => (int) $r['qty_pcs'],
            'amount' => (float) $r['amount'],
            'note' => $r['note'],
        ], $db->fetchAll(
            "SELECT d.id, d.qty_pcs, d.amount, d.note, p.name AS product_name, r.name AS retailer_name
             FROM delivery_damages d
             JOIN products p ON p.id = d.product_id
             JOIN retailers r ON r.id = d.retailer_id
             WHERE d.trip_id = ?
             ORDER BY d.id",
            [$tripId]
        ));

        $savedNotes = $t['cash_notes_json'] ? (json_decode((string) $t['cash_notes_json'], true) ?: []) : [];

        return [
            'trip' => [
                'id' => (int) $t['id'],
                'code' => $t['trip_code'],
                'date' => $t['trip_date'],
                'dsr' => $t['dsr_name'],
                'status_key' => $t['status'],
                'status' => Format::status(str_replace('_', ' ', (string) $t['status'])),
                'settlement_status' => $t['settlement_status'],
                'review_note' => $t['review_note'],
                'submitted_at' => $t['submitted_at'],
                'approved_at' => $t['approved_at'],
            ],
            'counts' => [
                'orders' => (int) $o['orders'],
                'pending' => (int) $o['pending'],
                'cancelled' => (int) $o['cancelled'],
                'stops_total' => (int) ($stops['total'] ?? 0),
                'stops_done' => (int) ($stops['done'] ?? 0),
                'due_shops' => count($dueShopIds),
            ],
            'summary' => [
                'order_amount' => (float) $o['order_amount'],
                'total_load' => round((float) $load['load_base'], 2),
                'return_amount' => round((float) ($t['status'] === 'settled' ? $load['actual_return_base'] : $load['return_base']), 2),
                'total_sales_base' => (float) $o['delivered_base'],
                'total_sales_sr' => $deliveredSr,
                'ready_sale' => $readySale,
                'prior_due_collected' => $prior,
                'system_cash' => $systemCash,
                'damaged_amount' => $damage,
                'daily_expenses' => $expense,
                'expense_categories' => $expenseCategories,
                'delivery_oc' => (float) $o['delivery_oc'],
                'retailer_due' => $newDue,
                'paid' => (float) $o['paid'],
                'net_pay' => $net,
            ],
            'cash' => [
                'counted' => $t['cash_counted'] !== null ? (float) $t['cash_counted'] : null,
                'diff' => $t['cash_diff'] !== null ? (float) $t['cash_diff'] : null,
                'dsr_note' => $t['dsr_note'] !== null && trim((string) $t['dsr_note']) !== '' ? trim((string) $t['dsr_note']) : null,
                'partner_received' => $t['partner_cash_received'] !== null ? (float) $t['partner_cash_received'] : null,
                'partner_diff' => $t['partner_cash_diff'] !== null ? (float) $t['partner_cash_diff'] : null,
            ],
            'damage_review' => [
                'dsr_amount' => $damage,
                'partner_amount' => $t['partner_damage_amount'] !== null ? (float) $t['partner_damage_amount'] : null,
                'partner_note' => $t['partner_damage_note'] !== null && trim((string) $t['partner_damage_note']) !== '' ? trim((string) $t['partner_damage_note']) : null,
                'items' => $damageItems,
            ],
            'return_items' => $returnItems,
            'expenses' => $expenseRows,
            'notes' => array_map(static fn(int $v): array => ['value' => $v, 'qty' => (int) ($savedNotes[(string) $v] ?? 0)], self::NOTES),
            'sr_oc_rows' => $srRows,
            'due_details' => $dues,
        ];
    }

    /** @param array<int|string, int> $notes denomination => count */
    public static function submit(array $dsr, array $notes, ?string $dsrNote = null): array
    {
        $trip = DsrDelivery::editableTrip($dsr['id']);
        $s = self::compute($trip['id']);
        if ($s['counts']['pending'] > 0) {
            throw new HttpError("{$s['counts']['pending']} order(s) are not delivered or cancelled yet. Finish every stop first.", 422);
        }

        $clean = [];
        $counted = 0;
        foreach (self::NOTES as $v) {
            $qty = max(0, (int) ($notes[(string) $v] ?? $notes[$v] ?? 0));
            $clean[(string) $v] = $qty;
            $counted += $v * $qty;
        }
        $sum = $s['summary'];
        $net = $sum['net_pay'];
        $diff = round($counted - $net, 2);
        $noteVal = $dsrNote !== null && trim($dsrNote) !== '' ? mb_substr(trim($dsrNote), 0, 255) : null;

        self::db()->transaction(static function (Database $db) use ($trip, $sum, $net, $counted, $diff, $clean, $noteVal): void {
            $db->execute(
                "INSERT INTO trip_settlements (trip_id, total_load_base, return_base, delivered_base_total, delivered_sr_total, ready_sale_total,
                    prior_due_collected, delivery_oc_total, damage_total, expense_total, new_due_total, net_payable, cash_counted, cash_diff,
                    cash_notes_json, dsr_note, partner_cash_received, partner_cash_diff, partner_damage_amount, partner_damage_note,
                    status, review_note, submitted_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, 'submitted', NULL, NOW())
                 ON DUPLICATE KEY UPDATE total_load_base = VALUES(total_load_base), return_base = VALUES(return_base),
                    delivered_base_total = VALUES(delivered_base_total), delivered_sr_total = VALUES(delivered_sr_total),
                    ready_sale_total = VALUES(ready_sale_total), prior_due_collected = VALUES(prior_due_collected),
                    delivery_oc_total = VALUES(delivery_oc_total), damage_total = VALUES(damage_total), expense_total = VALUES(expense_total),
                    new_due_total = VALUES(new_due_total), net_payable = VALUES(net_payable), cash_counted = VALUES(cash_counted),
                    cash_diff = VALUES(cash_diff), cash_notes_json = VALUES(cash_notes_json), dsr_note = VALUES(dsr_note),
                    partner_cash_received = NULL, partner_cash_diff = NULL, partner_damage_amount = NULL, partner_damage_note = NULL,
                    status = 'submitted', review_note = NULL, submitted_at = NOW()",
                [$trip['id'], $sum['total_load'], $sum['return_amount'], $sum['total_sales_base'], $sum['total_sales_sr'], $sum['ready_sale'],
                    $sum['prior_due_collected'], $sum['delivery_oc'], $sum['damaged_amount'], $sum['daily_expenses'], $sum['retailer_due'],
                    $net, $counted, $diff, json_encode($clean), $noteVal]
            );
            $db->execute("UPDATE trips SET status = 'in_review' WHERE id = ?", [$trip['id']]);
        });

        return ['net' => $net, 'counted' => $counted, 'diff' => $diff];
    }

    // ---------------------------------------------------------------- partner

    /** @return list<array<string, mixed>> trips that are in review / dispatched / settled in a date range */
    public static function forPartner(int $partnerId, string $from, string $to): array
    {
        return array_map(
            static fn(array $r): array => self::compute((int) $r['id']),
            self::db()->fetchAll(
                "SELECT id FROM trips WHERE partner_id = ? AND status IN ('dispatched', 'in_review', 'settled')
                   AND (status IN ('in_review', 'dispatched') OR trip_date BETWEEN ? AND ?)
                 ORDER BY FIELD(status, 'in_review', 'dispatched', 'settled'), trip_date DESC, id DESC",
                [$partnerId, $from, $to]
            )
        );
    }

    private static function reviewable(int $partnerId, int $tripId): array
    {
        $t = self::db()->fetch('SELECT * FROM trips WHERE id = ? AND partner_id = ? FOR UPDATE', [$tripId, $partnerId]);
        if ($t === null) {
            throw new HttpError('Trip not found.', 404);
        }
        if ($t['status'] !== 'in_review') {
            throw new HttpError("{$t['trip_code']} is not waiting for review.", 422);
        }

        return $t;
    }

    public static function sendBack(int $partnerId, int $tripId, string $note): void
    {
        self::db()->transaction(static function (Database $db) use ($partnerId, $tripId, $note): void {
            self::reviewable($partnerId, $tripId);
            $db->execute("UPDATE trip_settlements SET status = 'returned', review_note = ? WHERE trip_id = ?", [$note, $tripId]);
            $db->execute("UPDATE trips SET status = 'dispatched' WHERE id = ?", [$tripId]);
        });
    }

    /**
     * Partner approves a submitted settlement with verified cash received, counted returned goods, and verified damage.
     *
     * @param array{cash_received?:float|int|string|null, returns?:array<int|string, int|string>, damage_amount?:float|int|string|null, damage_note?:?string} $input
     * @return array{cash_received:float, cash_diff:float, restocked_pcs:int, damage_amount:float}
     */
    public static function approve(int $partnerId, int $tripId, int $approverUserId, array $input = []): array
    {
        return self::db()->transaction(static function (Database $db) use ($partnerId, $tripId, $approverUserId, $input): array {
            $trip = self::reviewable($partnerId, $tripId);
            $ts = $db->fetch('SELECT * FROM trip_settlements WHERE trip_id = ? FOR UPDATE', [$tripId]);
            if ($ts === null) {
                throw new HttpError('Settlement submission record not found.', 422);
            }

            $netPay = (float) $ts['net_payable'];
            $dsrCash = (float) $ts['cash_counted'];
            $dsrDamage = (float) $ts['damage_total'];

            $cashReceived = $dsrCash;
            if (array_key_exists('cash_received', $input) && $input['cash_received'] !== null && $input['cash_received'] !== '') {
                if (!is_numeric($input['cash_received']) || (float) $input['cash_received'] < 0) {
                    throw new HttpError('Enter a valid cash amount received.', 422);
                }
                $cashReceived = round((float) $input['cash_received'], 2);
            }
            $partnerCashDiff = round($cashReceived - $netPay, 2);

            $partnerDamage = $dsrDamage;
            if (array_key_exists('damage_amount', $input) && $input['damage_amount'] !== null && $input['damage_amount'] !== '') {
                if (!is_numeric($input['damage_amount']) || (float) $input['damage_amount'] < 0) {
                    throw new HttpError('Enter a valid damage value.', 422);
                }
                $partnerDamage = round((float) $input['damage_amount'], 2);
            }
            $damageNoteRaw = trim((string) ($input['damage_note'] ?? ''));
            $partnerDamageNote = $damageNoteRaw !== '' ? mb_substr($damageNoteRaw, 0, 255) : null;

            $returnsInput = is_array($input['returns'] ?? null) ? $input['returns'] : [];

            // 1. Partner-counted unsold stock back to lots (newest allocations first) + FIFO cost of sold lines
            $vans = $db->fetchAll('SELECT * FROM trip_van_stocks WHERE trip_id = ?', [$tripId]);
            $totalRestocked = 0;
            $actualReturnBase = 0.0;
            foreach ($vans as $v) {
                $pid = (int) $v['product_id'];
                $dispatched = (int) $v['dispatched_pcs'];
                $expected = max(0, $dispatched - (int) $v['delivered_pcs']);

                $rawReturn = $returnsInput[(string) $pid] ?? $returnsInput[$pid] ?? null;
                if ($rawReturn !== null && $rawReturn !== '') {
                    if (!is_numeric($rawReturn) || (int) $rawReturn < 0 || (int) $rawReturn > $dispatched) {
                        throw new HttpError("Returned count must be between 0 and {$dispatched} pcs.", 422);
                    }
                    $return = (int) $rawReturn;
                } else {
                    $return = $expected;
                }

                $allocs = $db->fetchAll(
                    'SELECT a.*, l.received_date FROM trip_stock_allocations a JOIN lot_items li ON li.id = a.lot_item_id JOIN lots l ON l.id = li.lot_id
                     WHERE a.trip_id = ? AND a.product_id = ? ORDER BY l.received_date DESC, a.lot_item_id DESC',
                    [$tripId, $pid]
                );
                $left = $return;
                $soldLayers = [];
                foreach ($allocs as $a) {
                    $back = min($left, (int) $a['dispatched_pcs']);
                    $left -= $back;
                    $sold = (int) $a['dispatched_pcs'] - $back;
                    $db->execute('UPDATE trip_stock_allocations SET returned_pcs = ?, sold_pcs = ? WHERE id = ?', [$back, $sold, $a['id']]);
                    if ($back > 0) {
                        $db->execute('UPDATE lot_items SET remaining_pcs = remaining_pcs + ? WHERE id = ?', [$back, $a['lot_item_id']]);
                    }
                    if ($sold > 0) {
                        $soldLayers[] = ['pcs' => $sold, 'cost' => (float) $a['company_price_per_pc']];
                    }
                }
                if ($return > 0) {
                    $db->execute('UPDATE products SET stock_pcs = stock_pcs + ? WHERE id = ?', [$return, $pid]);
                }
                $db->execute('UPDATE trip_van_stocks SET returned_pcs = ? WHERE id = ?', [$return, $v['id']]);
                $totalRestocked += $return;
                $actualReturnBase += $return * (float) $v['base_rate_pc'];

                // Oldest layers to earliest order lines
                $soldLayers = array_reverse($soldLayers);
                foreach ($db->fetchAll(
                    "SELECT oi.id, oi.delivered_pcs FROM order_items oi JOIN orders o ON o.id = oi.order_id
                     WHERE o.trip_id = ? AND oi.product_id = ? AND o.status <> 'cancelled' AND oi.delivered_pcs > 0 ORDER BY o.id, oi.id",
                    [$tripId, $pid]
                ) as $line) {
                    $need = (int) $line['delivered_pcs'];
                    $cost = 0.0;
                    while ($need > 0 && $soldLayers !== []) {
                        $take = min($need, $soldLayers[0]['pcs']);
                        $cost += $take * $soldLayers[0]['cost'];
                        $need -= $take;
                        $soldLayers[0]['pcs'] -= $take;
                        if ($soldLayers[0]['pcs'] === 0) {
                            array_shift($soldLayers);
                        }
                    }
                    $db->execute('UPDATE order_items SET fifo_cost_total = ? WHERE id = ?', [round($cost, 2), $line['id']]);
                }
            }

            // 2. SR O/C ledger (delivery O/C of each SR on this trip)
            foreach ($db->fetchAll(
                "SELECT sr_id, SUM(delivery_oc) AS oc FROM orders WHERE trip_id = ? AND sr_id IS NOT NULL AND status <> 'cancelled' GROUP BY sr_id",
                [$tripId]
            ) as $r) {
                $oc = round((float) $r['oc'], 2);
                if (abs($oc) < 0.005) {
                    continue;
                }
                $db->execute(
                    "INSERT INTO sr_oc_ledger (partner_id, sr_id, trip_id, entry_type, amount, note) VALUES (?, ?, ?, 'delivery_oc', ?, ?)",
                    [$partnerId, $r['sr_id'], $tripId, $oc, 'Delivery O/C ' . $trip['trip_code']]
                );
                $db->execute('UPDATE salesmen SET oc_balance = oc_balance + ? WHERE id = ?', [$oc, $r['sr_id']]);
            }

            // 3. Retailer due balances: + new due, − old due collected
            foreach ($db->fetchAll(
                "SELECT retailer_id, SUM(due_amount) AS due FROM orders WHERE trip_id = ? AND retailer_id IS NOT NULL AND due_amount > 0 GROUP BY retailer_id",
                [$tripId]
            ) as $r) {
                $db->execute('UPDATE retailers SET due_balance = due_balance + ? WHERE id = ?', [$r['due'], $r['retailer_id']]);
            }
            foreach ($db->fetchAll('SELECT retailer_id, SUM(amount) AS amt FROM retailer_due_collections WHERE trip_id = ? GROUP BY retailer_id', [$tripId]) as $r) {
                $db->execute('UPDATE retailers SET due_balance = GREATEST(due_balance - ?, 0) WHERE id = ?', [$r['amt'], $r['retailer_id']]);
            }

            // 4. Damage claims: company bears verified damage cost (scaled proportionally if partner adjusted total)
            if ($partnerDamage > 0) {
                $ratio = ($dsrDamage > 0 && abs($partnerDamage - $dsrDamage) > 0.004)
                    ? ($partnerDamage / $dsrDamage)
                    : 1.0;
                foreach ($db->fetchAll(
                    'SELECT d.company_id, SUM(d.qty_pcs * p.company_price) AS cost FROM delivery_damages d JOIN products p ON p.id = d.product_id
                     WHERE d.trip_id = ? AND d.claimed_to_company = 0 GROUP BY d.company_id',
                    [$tripId]
                ) as $r) {
                    $claim = round((float) $r['cost'] * $ratio, 2);
                    if ($claim <= 0) {
                        continue;
                    }
                    $db->execute(
                        "INSERT INTO company_ledger (partner_id, company_id, ref_type, ref_id, debit, credit, note, entry_date)
                         VALUES (?, ?, 'damage_claim', ?, 0, ?, ?, ?)",
                        [$partnerId, $r['company_id'], $tripId, $claim, 'Damage returns ' . $trip['trip_code'], date('Y-m-d')]
                    );
                }
            }
            $db->execute('UPDATE delivery_damages SET claimed_to_company = 1 WHERE trip_id = ?', [$tripId]);

            $db->execute(
                "UPDATE trip_settlements
                 SET return_base = ?, partner_cash_received = ?, partner_cash_diff = ?,
                     partner_damage_amount = ?, partner_damage_note = ?,
                     status = 'approved', approved_by = ?, approved_at = NOW()
                 WHERE trip_id = ?",
                [round($actualReturnBase, 2), $cashReceived, $partnerCashDiff, $partnerDamage, $partnerDamageNote, $approverUserId, $tripId]
            );
            $db->execute("UPDATE trips SET status = 'settled', settled_at = NOW() WHERE id = ?", [$tripId]);

            return [
                'cash_received' => $cashReceived,
                'cash_diff' => $partnerCashDiff,
                'restocked_pcs' => $totalRestocked,
                'damage_amount' => $partnerDamage,
            ];
        });
    }
}
