<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Format;
use App\Support\HttpError;
use Core\Auth;
use Core\Database;

/**
 * Platform fee per lakh sales, set on each partner <-> company connection (owned or via dealer).
 *
 * Changes never rewrite the past:
 *  - every change is appended to platform_fee_history, effective from the moment it is saved;
 *  - an order freezes its rate at creation: set orders.platform_fee_rate = PlatformFee::rateAt(...)
 *    and on delivery platform_fee_amount = PlatformFee::amount(SALES_COLUMN value, platform_fee_rate).
 */
final class PlatformFee
{
    /** Order statuses that count as a sale. */
    public const SALE_STATUSES = "'delivered', 'due', 'partial'";
    /** The order amount the fee is charged on. */
    public const SALES_COLUMN = 'delivered_base_total';

    private static function db(): Database
    {
        return Database::getInstance();
    }

    /** Fee per lakh in force for a partner+company at a moment (default: now). 0 if never set. */
    public static function rateAt(int $partnerId, int $companyId, ?string $at = null): float
    {
        $row = self::db()->fetch(
            'SELECT fee_per_lakh FROM platform_fee_history
             WHERE partner_id = ? AND company_id = ? AND effective_from <= COALESCE(?, NOW())
             ORDER BY effective_from DESC, id DESC LIMIT 1',
            [$partnerId, $companyId, $at]
        );

        return $row !== null ? (float) $row['fee_per_lakh'] : 0.0;
    }

    public static function amount(float $sales, float $feePerLakh): float
    {
        return round($sales * $feePerLakh / 100000, 2);
    }

    /** @return list<array<string, mixed>> every connection of non-deleted partners/companies */
    public static function links(): array
    {
        $rows = self::db()->fetchAll(
            'SELECT pc.partner_id, pc.company_id, pc.ownership, pc.dealer_profit_share, pc.partner_profit_share,
                    pc.platform_fee_per_lakh, c.name AS company, c.status AS company_status, d.name AS dealer,
                    (SELECT COUNT(*) FROM salesmen s WHERE s.company_id = pc.company_id AND s.partner_id = pc.partner_id AND s.deleted_at IS NULL) AS srs,
                    (SELECT MAX(h.effective_from) FROM platform_fee_history h WHERE h.partner_id = pc.partner_id AND h.company_id = pc.company_id) AS fee_since,
                    (SELECT COUNT(*) FROM platform_fee_history h WHERE h.partner_id = pc.partner_id AND h.company_id = pc.company_id) AS fee_changes
             FROM partner_companies pc
             JOIN partners p ON p.id = pc.partner_id AND p.deleted_at IS NULL
             JOIN companies c ON c.id = pc.company_id AND c.deleted_at IS NULL
             LEFT JOIN dealers d ON d.id = pc.dealer_id
             ORDER BY c.name'
        );

        return array_map(static fn(array $r): array => [
            'partner_id' => (int) $r['partner_id'],
            'company_id' => (int) $r['company_id'],
            'company' => $r['company'],
            'company_status' => Format::status($r['company_status']),
            'ownership' => Format::status($r['ownership']),
            'dealer' => $r['dealer'],
            'dealer_profit_share' => $r['dealer_profit_share'] !== null ? (float) $r['dealer_profit_share'] : null,
            'partner_profit_share' => $r['partner_profit_share'] !== null ? (float) $r['partner_profit_share'] : null,
            'platform_fee_per_lakh' => (float) $r['platform_fee_per_lakh'],
            'fee_since' => $r['fee_since'],
            'fee_changes' => (int) $r['fee_changes'],
            'srs' => (int) $r['srs'],
        ], $rows);
    }

    /**
     * Fee periods (newest first) with the sales and fee earned inside each period.
     * Fee earned uses each order's frozen amount, so later changes cannot alter it.
     *
     * @return array{company:string, periods:list<array<string, mixed>>, totals:array{sales:float, fee:float, orders:int}}
     */
    public static function history(int $partnerId, int $companyId): array
    {
        $link = self::db()->fetch(
            'SELECT c.name FROM partner_companies pc JOIN companies c ON c.id = pc.company_id
             WHERE pc.partner_id = ? AND pc.company_id = ?',
            [$partnerId, $companyId]
        );
        if ($link === null) {
            throw new HttpError('This company is not connected to the partner.', 404);
        }

        $rows = self::db()->fetchAll(
            'SELECT h.id, h.fee_per_lakh, h.effective_from, u.name AS changed_by,
                    LEAD(h.effective_from) OVER (ORDER BY h.effective_from, h.id) AS effective_to
             FROM platform_fee_history h LEFT JOIN users u ON u.id = h.changed_by
             WHERE h.partner_id = ? AND h.company_id = ?
             ORDER BY h.effective_from, h.id',
            [$partnerId, $companyId]
        );

        $sales = 'SELECT COUNT(*) AS orders, COALESCE(SUM(' . self::SALES_COLUMN . '), 0) AS sales,
                         COALESCE(SUM(platform_fee_amount), 0) AS fee
                  FROM orders
                  WHERE partner_id = ? AND company_id = ? AND status IN (' . self::SALE_STATUSES . ')
                    AND created_at >= ? AND (? IS NULL OR created_at < ?)';

        $periods = [];
        $totals = ['sales' => 0.0, 'fee' => 0.0, 'orders' => 0];
        foreach ($rows as $r) {
            $s = self::db()->fetch($sales, [$partnerId, $companyId, $r['effective_from'], $r['effective_to'], $r['effective_to']]);
            $periods[] = [
                'fee_per_lakh' => (float) $r['fee_per_lakh'],
                'from' => $r['effective_from'],
                'to' => $r['effective_to'],
                'changed_by' => $r['changed_by'],
                'orders' => (int) $s['orders'],
                'sales' => round((float) $s['sales'], 2),
                'fee' => round((float) $s['fee'], 2),
            ];
            $totals['orders'] += (int) $s['orders'];
            $totals['sales'] += (float) $s['sales'];
            $totals['fee'] += (float) $s['fee'];
        }

        $totals['sales'] = round($totals['sales'], 2);
        $totals['fee'] = round($totals['fee'], 2);

        return ['company' => $link['name'], 'periods' => array_reverse($periods), 'totals' => $totals];
    }

    /**
     * Appends a history row for every fee that actually changed; past rows are never edited.
     *
     * @param array<int, float> $fees company_id => fee
     * @return int number of fees changed
     */
    public static function save(int $partnerId, array $fees): int
    {
        $db = self::db();
        if ($db->fetch('SELECT id FROM partners WHERE id = ? AND deleted_at IS NULL', [$partnerId]) === null) {
            throw new HttpError('Partner not found.', 404);
        }

        $current = [];
        foreach ($db->fetchAll('SELECT company_id, platform_fee_per_lakh FROM partner_companies WHERE partner_id = ?', [$partnerId]) as $r) {
            $current[(int) $r['company_id']] = (float) $r['platform_fee_per_lakh'];
        }
        if (array_diff(array_keys($fees), array_keys($current))) {
            throw new HttpError('Some companies are not connected to this partner. Reload the page and try again.', 422);
        }

        $userId = Auth::id() !== null ? (int) Auth::id() : null;

        return $db->transaction(static function (Database $db) use ($partnerId, $fees, $current, $userId): int {
            $changed = 0;
            foreach ($fees as $companyId => $fee) {
                $hasHistory = $db->fetch(
                    'SELECT id FROM platform_fee_history WHERE partner_id = ? AND company_id = ? LIMIT 1',
                    [$partnerId, $companyId]
                ) !== null;
                if ($hasHistory && abs($current[$companyId] - $fee) < 0.005) {
                    continue;
                }

                $db->execute(
                    'UPDATE partner_companies SET platform_fee_per_lakh = ? WHERE partner_id = ? AND company_id = ?',
                    [$fee, $partnerId, $companyId]
                );
                $db->execute(
                    'INSERT INTO platform_fee_history (partner_id, company_id, fee_per_lakh, effective_from, changed_by) VALUES (?, ?, ?, NOW(), ?)',
                    [$partnerId, $companyId, $fee, $userId]
                );
                $changed++;
            }

            return $changed;
        });
    }
}
