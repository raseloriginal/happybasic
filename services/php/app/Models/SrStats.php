<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Format;
use App\Support\Phone;
use Core\Database;

/** Figures for the SR dashboard and profile (cancelled orders never count). */
final class SrStats
{
    /** @return array<string, float|int> totals of the SR's orders between two dates */
    public static function range(int $srId, string $from, string $to): array
    {
        $r = Database::getInstance()->fetch(
            "SELECT COUNT(*) AS orders, COUNT(DISTINCT retailer_id) AS retailers,
                    COALESCE(SUM(order_sr_total), 0) AS value, COALESCE(SUM(order_oc), 0) AS oc,
                    COALESCE(SUM(CASE WHEN status IN ('delivered', 'due', 'partial') THEN order_sr_total END), 0) AS settled_value,
                    COALESCE(SUM(delivered_sr_total), 0) AS delivered, COALESCE(SUM(delivery_oc), 0) AS delivery_oc,
                    COUNT(CASE WHEN status = 'pending' THEN 1 END) AS pending,
                    COUNT(CASE WHEN status = 'assigned' THEN 1 END) AS assigned,
                    COUNT(CASE WHEN status IN ('delivered', 'due', 'partial') THEN 1 END) AS done
             FROM orders WHERE sr_id = ? AND order_date BETWEEN ? AND ? AND status <> 'cancelled'",
            [$srId, $from, $to]
        );
        $ocSplit = Database::getInstance()->fetch(
            "SELECT COALESCE(SUM(CASE WHEN oi.order_oc > 0 THEN oi.order_oc ELSE 0 END), 0) AS over_oc,
                    COALESCE(SUM(CASE WHEN oi.order_oc < 0 THEN oi.order_oc ELSE 0 END), 0) AS comm_oc
             FROM order_items oi
             JOIN orders o ON o.id = oi.order_id
             WHERE o.sr_id = ? AND o.order_date BETWEEN ? AND ? AND o.status <> 'cancelled'",
            [$srId, $from, $to]
        );
        $settled = (float) $r['settled_value'];

        return [
            'orders' => (int) $r['orders'],
            'retailers' => (int) $r['retailers'],
            'value' => (float) $r['value'],
            'oc' => (float) $r['oc'],
            'over_oc' => (float) ($ocSplit['over_oc'] ?? 0),
            'comm_oc' => (float) ($ocSplit['comm_oc'] ?? 0),
            'delivered' => (float) $r['delivered'],
            'delivery_oc' => (float) $r['delivery_oc'],
            'pending' => (int) $r['pending'],
            'assigned' => (int) $r['assigned'],
            'done' => (int) $r['done'],
            // delivered value against the value of orders that have been delivered (fully, partially or on due)
            'delivery_rate' => $settled > 0 ? round((float) $r['delivered'] / $settled * 100, 1) : 0.0,
        ];
    }

    /** @return array{date:string, stats:array<string, float|int>, products:list<array<string, mixed>>} */
    public static function daySummary(int $srId, string $date): array
    {
        $stats = self::range($srId, $date, $date);
        $rows = Database::getInstance()->fetchAll(
            "SELECT p.id, p.name, p.unit_type, p.qty_per_unit, p.image_path,
                    COALESCE(SUM(oi.ordered_pcs), 0) AS ordered_pcs,
                    COALESCE(SUM(CASE WHEN o.trip_id IS NOT NULL THEN oi.ordered_pcs ELSE 0 END), 0) AS dispatched_pcs,
                    COALESCE(SUM(CASE WHEN o.status IN ('delivered', 'due', 'partial') THEN oi.delivered_pcs ELSE 0 END), 0) AS delivered_pcs,
                    COALESCE(SUM(CASE
                        WHEN o.status = 'cancelled' AND o.trip_id IS NOT NULL THEN oi.ordered_pcs
                        WHEN o.status IN ('delivered', 'due', 'partial') THEN GREATEST(0, oi.ordered_pcs - oi.delivered_pcs)
                        ELSE 0
                    END), 0) AS returned_pcs
             FROM order_items oi
             JOIN orders o ON o.id = oi.order_id
             JOIN products p ON p.id = oi.product_id
             WHERE o.sr_id = ? AND o.order_date = ? AND (o.status <> 'cancelled' OR o.trip_id IS NOT NULL)
             GROUP BY p.id, p.name, p.unit_type, p.qty_per_unit, p.image_path
             ORDER BY ordered_pcs DESC, p.name ASC",
            [$srId, $date]
        );
        $products = array_map(static function (array $r): array {
            $vis = Product::visual((int) $r['id'], (string) $r['name'], $r['image_path'] ?? null);
            return [
                'id' => (int) $r['id'],
                'name' => $r['name'],
                'unit_type' => $r['unit_type'],
                'qty_per_unit' => (int) $r['qty_per_unit'],
                'ordered_pcs' => (int) $r['ordered_pcs'],
                'dispatched_pcs' => (int) $r['dispatched_pcs'],
                'delivered_pcs' => (int) $r['delivered_pcs'],
                'returned_pcs' => (int) $r['returned_pcs'],
                'image' => $vis['image'],
                'code' => $vis['code'],
                'tint' => $vis['tint'],
            ];
        }, $rows);

        return ['date' => $date, 'stats' => $stats, 'products' => $products];
    }

    /** @return array<string, mixed> profile fields of the signed-in SR */
    public static function profile(int $srId): array
    {
        $r = Database::getInstance()->fetch(
            'SELECT s.*, c.name AS company, p.name AS partner, a.name AS partner_area, u.email,
                    (SELECT COUNT(*) FROM retailers r WHERE r.created_by_sr_id = s.id) AS retailers_added
             FROM salesmen s
             JOIN companies c ON c.id = s.company_id
             JOIN partners p ON p.id = s.partner_id
             JOIN areas a ON a.id = p.area_id
             JOIN users u ON u.id = s.user_id
             WHERE s.id = ?',
            [$srId]
        );
        $words = preg_split('/\s+/', trim((string) $r['name'])) ?: [];

        return [
            'name' => $r['name'],
            'initials' => strtoupper(implode('', array_map(static fn(string $w): string => mb_substr($w, 0, 1), array_slice($words, 0, 2)))) ?: 'SR',
            'code' => $r['code'] ?: 'SR-' . str_pad((string) $r['id'], 4, '0', STR_PAD_LEFT),
            'phone' => Phone::format($r['phone']),
            'email' => $r['email'],
            'area' => $r['area'] ?: $r['partner_area'],
            'company' => $r['company'],
            'partner' => $r['partner'],
            'joining_date' => $r['joining_date'] ? date('d M Y', strtotime((string) $r['joining_date'])) : null,
            'daily_target' => (float) $r['daily_target'],
            'monthly_target' => (float) $r['monthly_target'],
            'oc_balance' => (float) $r['oc_balance'],
            'retailers_added' => (int) $r['retailers_added'],
            'status' => Format::status($r['status']),
        ];
    }
}
