<?php

declare(strict_types=1);

namespace App\Models;

use Core\Database;

/**
 * Partner Day Closing summary for a single date (trips by trip_date).
 * Aggregates goods out, returns, damages, dues, SR O/C, prior due collection,
 * expenses, expected vs received cash, per-trip & per-SR breakdowns, and FIFO P&L.
 */
final class DayClosing
{
    private static function db(): Database
    {
        return Database::getInstance();
    }

    /** @return array<string, mixed> */
    public static function forDate(int $partnerId, string $date): array
    {
        $db = self::db();

        $partner = $db->fetch(
            'SELECT p.id, p.name, p.phone, p.address, a.name AS area
             FROM partners p
             JOIN areas a ON a.id = p.area_id
             WHERE p.id = ?',
            [$partnerId]
        ) ?? ['id' => $partnerId, 'name' => 'পার্টনার', 'phone' => '', 'address' => '', 'area' => ''];

        $recentDates = array_column($db->fetchAll(
            "SELECT DISTINCT trip_date
             FROM trips
             WHERE partner_id = ? AND status IN ('dispatched', 'in_review', 'settled')
             ORDER BY trip_date DESC
             LIMIT 7",
            [$partnerId]
        ), 'trip_date');

        $pendingCount = (int) ($db->fetch(
            "SELECT COUNT(*) AS c FROM trips WHERE partner_id = ? AND trip_date = ? AND status = 'pending'",
            [$partnerId, $date]
        )['c'] ?? 0);

        $tripRows = $db->fetchAll(
            "SELECT t.id, t.trip_code, t.trip_date, t.status, t.dispatched_at, t.settled_at,
                    dm.name AS dsr_name,
                    ts.status AS settlement_status, ts.cash_counted, ts.cash_diff, ts.cash_notes_json,
                    ts.dsr_note, ts.review_note, ts.partner_cash_received, ts.partner_cash_diff,
                    ts.partner_damage_amount, ts.partner_damage_note, ts.submitted_at, ts.approved_at
             FROM trips t
             JOIN delivery_men dm ON dm.id = t.dsr_id
             LEFT JOIN trip_settlements ts ON ts.trip_id = t.id
             WHERE t.partner_id = ? AND t.trip_date = ? AND t.status IN ('dispatched', 'in_review', 'settled')
             ORDER BY t.id ASC",
            [$partnerId, $date]
        );

        $tripIds = array_map(static fn(array $r): int => (int) $r['id'], $tripRows);

        $trips = [];
        $srRows = [];
        $cashNotes = array_fill_keys(array_map('strval', TripSettlement::NOTES), 0);
        $hasCashNotes = false;

        $goodsOut = 0.0;
        $goodsReturn = 0.0;
        $returnPcs = 0;
        $deliveredBase = 0.0;
        $deliveredSr = 0.0;
        $readySale = 0.0;
        $srOver = 0.0;
        $srCommission = 0.0;
        $dsrDamageTotal = 0.0;
        $verifiedDamageTotal = 0.0;
        $damageClaimTotal = 0.0;
        $newDueTotal = 0.0;
        $dueShopsSet = [];
        $priorDueTotal = 0.0;
        $priorDueShopsSet = [];
        $expenseTotal = 0.0;
        $expenseCats = [];
        $platformFeeTotal = 0.0;
        $fifoCostTotal = 0.0;
        $expectedCashTotal = 0.0;
        $receivedCashTotal = 0.0;
        $unsubmittedCash = 0.0;

        $ordersTotal = 0;
        $ordersDelivered = 0;
        $ordersCancelled = 0;
        $ordersPending = 0;
        $settledCount = 0;
        $inReviewCount = 0;
        $dispatchedCount = 0;

        if ($tripIds !== []) {
            $idList = implode(',', $tripIds);

            // Per-trip order aggregates
            $orderByTrip = [];
            foreach ($db->fetchAll(
                "SELECT trip_id,
                        COUNT(*) AS orders_total,
                        COUNT(CASE WHEN status IN ('delivered', 'due', 'partial') THEN 1 END) AS orders_delivered,
                        COUNT(CASE WHEN status = 'cancelled' THEN 1 END) AS orders_cancelled,
                        COUNT(CASE WHEN status IN ('assigned', 'pending') THEN 1 END) AS orders_pending,
                        COALESCE(SUM(CASE WHEN status <> 'cancelled' THEN delivered_base_total ELSE 0 END), 0) AS delivered_base,
                        COALESCE(SUM(CASE WHEN status <> 'cancelled' AND is_ready_sale = 0 THEN delivered_sr_total ELSE 0 END), 0) AS delivered_sr,
                        COALESCE(SUM(CASE WHEN status <> 'cancelled' AND is_ready_sale = 1 THEN delivered_sr_total ELSE 0 END), 0) AS ready_sale,
                        COALESCE(SUM(CASE WHEN status <> 'cancelled' THEN due_amount ELSE 0 END), 0) AS new_due,
                        COALESCE(SUM(CASE WHEN status IN ('delivered', 'due', 'partial') THEN platform_fee_amount ELSE 0 END), 0) AS platform_fee
                 FROM orders
                 WHERE trip_id IN ({$idList})
                 GROUP BY trip_id"
            ) as $r) {
                $orderByTrip[(int) $r['trip_id']] = $r;
            }

            // Per-trip SR Over / Commission (line-level so positive over and negative commission never hide each other)
            $ocByTrip = [];
            foreach ($db->fetchAll(
                "SELECT o.trip_id,
                        COALESCE(SUM(CASE WHEN oi.delivery_oc > 0 THEN oi.delivery_oc ELSE 0 END), 0) AS sr_over,
                        COALESCE(SUM(CASE WHEN oi.delivery_oc < 0 THEN -oi.delivery_oc ELSE 0 END), 0) AS sr_commission,
                        COALESCE(SUM(oi.fifo_cost_total), 0) AS fifo_cost
                 FROM order_items oi
                 JOIN orders o ON o.id = oi.order_id
                 WHERE o.trip_id IN ({$idList}) AND o.status <> 'cancelled' AND oi.delivered_pcs > 0
                 GROUP BY o.trip_id"
            ) as $r) {
                $ocByTrip[(int) $r['trip_id']] = $r;
            }

            // Distinct shops given new due on these trips
            foreach ($db->fetchAll(
                "SELECT DISTINCT COALESCE(retailer_id, id) AS shop_key
                 FROM orders
                 WHERE trip_id IN ({$idList}) AND status <> 'cancelled' AND due_amount > 0"
            ) as $r) {
                $dueShopsSet[(string) $r['shop_key']] = true;
            }

            // Van load & return values per trip
            $vanByTrip = [];
            foreach ($db->fetchAll(
                "SELECT trip_id,
                        COALESCE(SUM(dispatched_pcs * base_rate_pc), 0) AS load_base,
                        COALESCE(SUM(GREATEST(dispatched_pcs - delivered_pcs, 0) * base_rate_pc), 0) AS expected_return_base,
                        COALESCE(SUM(returned_pcs * base_rate_pc), 0) AS actual_return_base,
                        COALESCE(SUM(GREATEST(dispatched_pcs - delivered_pcs, 0)), 0) AS expected_return_pcs,
                        COALESCE(SUM(returned_pcs), 0) AS actual_return_pcs
                 FROM trip_van_stocks
                 WHERE trip_id IN ({$idList})
                 GROUP BY trip_id"
            ) as $r) {
                $vanByTrip[(int) $r['trip_id']] = $r;
            }

            // Damages per trip (retailer deduction + company buying cost estimate)
            $dmgByTrip = [];
            foreach ($db->fetchAll(
                "SELECT d.trip_id,
                        COALESCE(SUM(d.amount), 0) AS dsr_damage,
                        COALESCE(SUM(d.qty_pcs * p.company_price), 0) AS est_company_cost
                 FROM delivery_damages d
                 JOIN products p ON p.id = d.product_id
                 WHERE d.trip_id IN ({$idList})
                 GROUP BY d.trip_id"
            ) as $r) {
                $dmgByTrip[(int) $r['trip_id']] = $r;
            }

            // Posted company damage claims on company_ledger for settled trips
            $claimByTrip = [];
            foreach ($db->fetchAll(
                "SELECT ref_id AS trip_id, COALESCE(SUM(credit), 0) AS claim
                 FROM company_ledger
                 WHERE partner_id = ? AND ref_type = 'damage_claim' AND ref_id IN ({$idList})
                 GROUP BY ref_id",
                [$partnerId]
            ) as $r) {
                $claimByTrip[(int) $r['trip_id']] = (float) $r['claim'];
            }

            // Prior due collections per trip + distinct retailers
            $priorByTrip = [];
            foreach ($db->fetchAll(
                "SELECT trip_id, retailer_id, amount
                 FROM retailer_due_collections
                 WHERE trip_id IN ({$idList})"
            ) as $r) {
                $tid = (int) $r['trip_id'];
                $priorByTrip[$tid] = round(($priorByTrip[$tid] ?? 0.0) + (float) $r['amount'], 2);
                $priorDueShopsSet[(string) $r['retailer_id']] = true;
            }

            // Expenses per trip + categories
            $expByTrip = [];
            foreach ($db->fetchAll(
                "SELECT trip_id, category, amount
                 FROM trip_expenses
                 WHERE trip_id IN ({$idList})
                 ORDER BY expense_at, id"
            ) as $r) {
                $tid = (int) $r['trip_id'];
                $expByTrip[$tid] = round(($expByTrip[$tid] ?? 0.0) + (float) $r['amount'], 2);
                $cat = trim((string) $r['category']);
                if ($cat !== '') {
                    $expenseCats[$cat] = true;
                }
            }

            // Live FIFO estimate for unsettled trips (settled trips already have order_items.fifo_cost_total)
            $unsettledIds = array_values(array_map(
                static fn(array $r): int => (int) $r['id'],
                array_filter($tripRows, static fn(array $r): bool => $r['status'] !== 'settled')
            ));
            $estimatedFifoByTrip = self::estimateFifoForTrips($unsettledIds);

            $seq = 0;
            foreach ($tripRows as $tr) {
                $seq++;
                $tid = (int) $tr['id'];
                $status = (string) $tr['status'];
                $isSettled = $status === 'settled';
                $isInReview = $status === 'in_review';

                if ($isSettled) {
                    $settledCount++;
                } elseif ($isInReview) {
                    $inReviewCount++;
                } else {
                    $dispatchedCount++;
                }

                $o = $orderByTrip[$tid] ?? [];
                $oc = $ocByTrip[$tid] ?? [];
                $v = $vanByTrip[$tid] ?? [];
                $d = $dmgByTrip[$tid] ?? [];

                $tLoad = round((float) ($v['load_base'] ?? 0), 2);
                $tReturn = round((float) ($isSettled ? ($v['actual_return_base'] ?? 0) : ($v['expected_return_base'] ?? 0)), 2);
                $tReturnPcs = (int) ($isSettled ? ($v['actual_return_pcs'] ?? 0) : ($v['expected_return_pcs'] ?? 0));

                $tDelBase = round((float) ($o['delivered_base'] ?? 0), 2);
                $tDelSr = round((float) ($o['delivered_sr'] ?? 0), 2);
                $tReady = round((float) ($o['ready_sale'] ?? 0), 2);
                $tDue = round((float) ($o['new_due'] ?? 0), 2);
                $tFee = round((float) ($o['platform_fee'] ?? 0), 2);

                $tOver = round((float) ($oc['sr_over'] ?? 0), 2);
                $tComm = round((float) ($oc['sr_commission'] ?? 0), 2);

                $tDsrDamage = round((float) ($d['dsr_damage'] ?? 0), 2);
                $tVerifiedDamage = $isSettled && $tr['partner_damage_amount'] !== null
                    ? round((float) $tr['partner_damage_amount'], 2)
                    : $tDsrDamage;

                if ($isSettled) {
                    $tDamageClaim = round((float) ($claimByTrip[$tid] ?? 0), 2);
                } else {
                    $tDamageClaim = round((float) ($d['est_company_cost'] ?? 0), 2);
                }

                $tPrior = round((float) ($priorByTrip[$tid] ?? 0), 2);
                $tExpense = round((float) ($expByTrip[$tid] ?? 0), 2);
                $tFifo = $isSettled
                    ? round((float) ($oc['fifo_cost'] ?? 0), 2)
                    : round((float) ($estimatedFifoByTrip[$tid] ?? 0), 2);

                $tExpected = round($tDelSr + $tReady + $tPrior - $tDsrDamage - $tDue - $tExpense, 2);

                $tReceived = null;
                if ($isSettled) {
                    $tReceived = $tr['partner_cash_received'] !== null
                        ? round((float) $tr['partner_cash_received'], 2)
                        : ($tr['cash_counted'] !== null ? round((float) $tr['cash_counted'], 2) : $tExpected);
                } elseif ($isInReview && $tr['cash_counted'] !== null) {
                    $tReceived = round((float) $tr['cash_counted'], 2);
                }

                $tDiff = $tReceived !== null ? round($tReceived - $tExpected, 2) : null;

                if (!empty($tr['cash_notes_json'])) {
                    $decoded = json_decode((string) $tr['cash_notes_json'], true);
                    if (is_array($decoded)) {
                        foreach (TripSettlement::NOTES as $denom) {
                            $k = (string) $denom;
                            $q = max(0, (int) ($decoded[$k] ?? 0));
                            if ($q > 0) {
                                $cashNotes[$k] += $q;
                                $hasCashNotes = true;
                            }
                        }
                    }
                }

                $goodsOut += $tLoad;
                $goodsReturn += $tReturn;
                $returnPcs += $tReturnPcs;
                $deliveredBase += $tDelBase;
                $deliveredSr += $tDelSr;
                $readySale += $tReady;
                $srOver += $tOver;
                $srCommission += $tComm;
                $dsrDamageTotal += $tDsrDamage;
                $verifiedDamageTotal += $tVerifiedDamage;
                $damageClaimTotal += $tDamageClaim;
                $newDueTotal += $tDue;
                $priorDueTotal += $tPrior;
                $expenseTotal += $tExpense;
                $platformFeeTotal += $tFee;
                $fifoCostTotal += $tFifo;
                $expectedCashTotal += $tExpected;

                if ($tReceived !== null) {
                    $receivedCashTotal += $tReceived;
                } else {
                    $unsubmittedCash += $tExpected;
                }

                $ordersTotal += (int) ($o['orders_total'] ?? 0);
                $ordersDelivered += (int) ($o['orders_delivered'] ?? 0);
                $ordersCancelled += (int) ($o['orders_cancelled'] ?? 0);
                $ordersPending += (int) ($o['orders_pending'] ?? 0);

                $trips[] = [
                    'id' => $tid,
                    'seq' => $seq,
                    'code' => (string) $tr['trip_code'],
                    'dsr' => (string) $tr['dsr_name'],
                    'status_key' => $status,
                    'load_base' => $tLoad,
                    'return_base' => $tReturn,
                    'return_pcs' => $tReturnPcs,
                    'delivered_base' => $tDelBase,
                    'damage' => $tDsrDamage,
                    'new_due' => $tDue,
                    'prior_due' => $tPrior,
                    'expense' => $tExpense,
                    'expected_cash' => $tExpected,
                    'received_cash' => $tReceived,
                    'cash_diff' => $tDiff,
                    'dsr_note' => $tr['dsr_note'] !== null && trim((string) $tr['dsr_note']) !== '' ? trim((string) $tr['dsr_note']) : null,
                    'submitted_at' => $tr['submitted_at'],
                    'approved_at' => $tr['approved_at'],
                ];
            }

            // Per-SR O/C breakdown across all trips of the day
            foreach ($db->fetchAll(
                "SELECT s.id AS sr_id, s.name AS sr_name, c.name AS company,
                        COUNT(DISTINCT o.id) AS orders,
                        COALESCE(SUM(o.delivered_base_total), 0) AS sales_base,
                        COALESCE(SUM(o.delivered_sr_total), 0) AS sales_sr,
                        COALESCE(SUM(o.delivery_oc), 0) AS net_oc
                 FROM orders o
                 JOIN salesmen s ON s.id = o.sr_id
                 JOIN companies c ON c.id = s.company_id
                 WHERE o.trip_id IN ({$idList}) AND o.sr_id IS NOT NULL AND o.status <> 'cancelled'
                 GROUP BY s.id, s.name, c.name
                 ORDER BY sales_sr DESC, s.name ASC"
            ) as $r) {
                $srRows[] = [
                    'sr_id' => (int) $r['sr_id'],
                    'sr_name' => (string) $r['sr_name'],
                    'company' => (string) $r['company'],
                    'orders' => (int) $r['orders'],
                    'sales_base' => round((float) $r['sales_base'], 2),
                    'sales_sr' => round((float) $r['sales_sr'], 2),
                    'net_oc' => round((float) $r['net_oc'], 2),
                ];
            }
        }

        $goodsOut = round($goodsOut, 2);
        $goodsReturn = round($goodsReturn, 2);
        $deliveredBase = round($deliveredBase, 2);
        $deliveredSr = round($deliveredSr, 2);
        $readySale = round($readySale, 2);
        $srOver = round($srOver, 2);
        $srCommission = round($srCommission, 2);
        $srNetOc = round($srOver - $srCommission, 2);
        $dsrDamageTotal = round($dsrDamageTotal, 2);
        $verifiedDamageTotal = round($verifiedDamageTotal, 2);
        $damageClaimTotal = round($damageClaimTotal, 2);
        $newDueTotal = round($newDueTotal, 2);
        $priorDueTotal = round($priorDueTotal, 2);
        $expenseTotal = round($expenseTotal, 2);
        $platformFeeTotal = round($platformFeeTotal, 2);
        $fifoCostTotal = round($fifoCostTotal, 2);
        $expectedCashTotal = round($expectedCashTotal, 2);
        $receivedCashTotal = round($receivedCashTotal, 2);
        $unsubmittedCash = round($unsubmittedCash, 2);
        $cashDiffTotal = round($receivedCashTotal - $expectedCashTotal, 2);

        // Reconciliation delta when partner return count differs from van expected or frozen order base rate != dispatch base rate
        $stockRateAdj = round($deliveredBase - ($goodsOut - $goodsReturn), 2);

        // Profit & Loss (exact FIFO)
        $grossMargin = round($deliveredBase - $fifoCostTotal, 2);
        $marginPct = $deliveredBase > 0 ? round(($grossMargin / $deliveredBase) * 100, 1) : 0.0;
        $damageNet = round(max(0.0, $verifiedDamageTotal - $damageClaimTotal), 2);
        $netProfit = round($grossMargin - $expenseTotal - $damageNet - $platformFeeTotal, 2);
        $avgFeeRate = $deliveredBase > 0 ? round(($platformFeeTotal / $deliveredBase) * 100000, 0) : 0.0;

        // Variance details for callout
        $variances = [];
        foreach ($trips as $t) {
            if ($t['cash_diff'] !== null && abs((float) $t['cash_diff']) >= 0.01) {
                $variances[] = [
                    'seq' => $t['seq'],
                    'code' => $t['code'],
                    'dsr' => $t['dsr'],
                    'diff' => (float) $t['cash_diff'],
                    'status_key' => $t['status_key'],
                    'note' => $t['dsr_note'],
                ];
            }
        }

        $expenseCategoriesBn = array_values(array_map(static function (string $cat): string {
            return match ($cat) {
                'Fuel' => 'তেল',
                'Helper' => 'হেল্পার',
                'Food' => 'খাবার',
                'Toll & Parking' => 'টোল ও পার্কিং',
                'Van Repair' => 'ভ্যান মেরামত',
                'Mobile / Communication' => 'মোবাইল',
                'Other' => 'অন্যান্য',
                default => $cat,
            };
        }, array_keys($expenseCats)));

        $ts = strtotime($date) ?: time();
        $code = 'DC-' . date('dm', $ts);

        $notesList = [];
        if ($hasCashNotes) {
            foreach (TripSettlement::NOTES as $denom) {
                $q = (int) ($cashNotes[(string) $denom] ?? 0);
                if ($q > 0) {
                    $notesList[] = ['value' => $denom, 'qty' => $q, 'total' => $denom * $q];
                }
            }
        }

        return [
            'code' => $code,
            'date' => $date,
            'partner' => [
                'id' => (int) $partner['id'],
                'name' => (string) $partner['name'],
                'phone' => (string) ($partner['phone'] ?? ''),
                'address' => trim((string) ($partner['address'] ?? '')),
                'area' => trim((string) ($partner['area'] ?? '')),
            ],
            'recent_dates' => $recentDates,
            'counts' => [
                'trips' => count($trips),
                'settled' => $settledCount,
                'in_review' => $inReviewCount,
                'dispatched' => $dispatchedCount,
                'pending_trips' => $pendingCount,
                'orders' => $ordersTotal,
                'delivered' => $ordersDelivered,
                'cancelled' => $ordersCancelled,
                'pending_orders' => $ordersPending,
                'due_shops' => count($dueShopsSet),
                'prior_due_shops' => count($priorDueShopsSet),
            ],
            'cash' => [
                'goods_out' => $goodsOut,
                'goods_return' => $goodsReturn,
                'return_pcs' => $returnPcs,
                'stock_rate_adj' => $stockRateAdj,
                'damage' => $dsrDamageTotal,
                'verified_damage' => $verifiedDamageTotal,
                'new_due' => $newDueTotal,
                'sr_commission' => $srCommission,
                'sr_over' => $srOver,
                'sr_net_oc' => $srNetOc,
                'prior_due' => $priorDueTotal,
                'expenses' => $expenseTotal,
                'expense_categories' => $expenseCategoriesBn,
                'expected' => $expectedCashTotal,
                'received' => $receivedCashTotal,
                'diff' => $cashDiffTotal,
                'unsubmitted' => $unsubmittedCash,
                'ready_sale' => $readySale,
                'delivered_sr' => $deliveredSr,
                'delivered_base' => $deliveredBase,
                'notes' => $notesList,
            ],
            'trips' => $trips,
            'sr_oc' => $srRows,
            'pnl' => [
                'delivered_base' => $deliveredBase,
                'fifo_cost' => $fifoCostTotal,
                'gross_margin' => $grossMargin,
                'margin_pct' => $marginPct,
                'expenses' => $expenseTotal,
                'damage' => $verifiedDamageTotal,
                'damage_claim' => $damageClaimTotal,
                'damage_net' => $damageNet,
                'sr_net_oc' => $srNetOc,
                'platform_fee' => $platformFeeTotal,
                'avg_fee_rate' => $avgFeeRate,
                'net_profit' => $netProfit,
                'is_estimated' => ($inReviewCount + $dispatchedCount) > 0,
            ],
            'variances' => $variances,
        ];
    }

    /**
     * Estimates FIFO COGS for unsettled trips using trip_stock_allocations (oldest lot first).
     *
     * @param list<int> $tripIds
     * @return array<int, float>
     */
    private static function estimateFifoForTrips(array $tripIds): array
    {
        if ($tripIds === []) {
            return [];
        }

        $db = self::db();
        $idList = implode(',', $tripIds);

        // Delivered pcs per trip + product (regular + ready sale, non-cancelled)
        $deliveredByTripProd = [];
        foreach ($db->fetchAll(
            "SELECT o.trip_id, oi.product_id, SUM(oi.delivered_pcs) AS pcs, MAX(p.company_price) AS fallback_cost
             FROM order_items oi
             JOIN orders o ON o.id = oi.order_id
             JOIN products p ON p.id = oi.product_id
             WHERE o.trip_id IN ({$idList}) AND o.status <> 'cancelled' AND oi.delivered_pcs > 0
             GROUP BY o.trip_id, oi.product_id"
        ) as $r) {
            $deliveredByTripProd[(int) $r['trip_id']][(int) $r['product_id']] = [
                'pcs' => (int) $r['pcs'],
                'fallback' => (float) $r['fallback_cost'],
            ];
        }

        // Allocations ordered oldest lot first
        $allocsByTripProd = [];
        foreach ($db->fetchAll(
            "SELECT a.trip_id, a.product_id, a.dispatched_pcs, a.company_price_per_pc
             FROM trip_stock_allocations a
             JOIN lot_items li ON li.id = a.lot_item_id
             JOIN lots l ON l.id = li.lot_id
             WHERE a.trip_id IN ({$idList})
             ORDER BY l.received_date ASC, a.lot_item_id ASC"
        ) as $a) {
            $allocsByTripProd[(int) $a['trip_id']][(int) $a['product_id']][] = [
                'pcs' => (int) $a['dispatched_pcs'],
                'cost' => (float) $a['company_price_per_pc'],
            ];
        }

        $out = [];
        foreach ($deliveredByTripProd as $tid => $prods) {
            $tripCost = 0.0;
            foreach ($prods as $pid => $info) {
                $need = $info['pcs'];
                $layers = $allocsByTripProd[$tid][$pid] ?? [];
                foreach ($layers as $layer) {
                    if ($need <= 0) {
                        break;
                    }
                    $take = min($need, $layer['pcs']);
                    $tripCost += $take * $layer['cost'];
                    $need -= $take;
                }
                if ($need > 0) {
                    $tripCost += $need * $info['fallback'];
                }
            }
            $out[$tid] = round($tripCost, 2);
        }

        return $out;
    }
}
