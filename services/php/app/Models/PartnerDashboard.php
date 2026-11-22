<?php

declare(strict_types=1);

namespace App\Models;

use Core\Database;

/** Partner dashboard figures for a date range (orders by order date, trips by delivery date). */
final class PartnerDashboard
{
    /** @return array<string, mixed> */
    public static function stats(int $partnerId, string $from, string $to): array
    {
        $db = Database::getInstance();
        $o = $db->fetch(
            "SELECT COUNT(*) AS orders, COUNT(DISTINCT retailer_id) AS retailers,
                    COALESCE(SUM(order_sr_total), 0) AS order_value, COALESCE(SUM(order_oc), 0) AS oc,
                    COALESCE(SUM(delivered_sr_total), 0) AS delivered, COALESCE(SUM(due_amount), 0) AS due,
                    COALESCE(SUM(CASE WHEN status = 'pending' THEN order_sr_total END), 0) AS unassigned_value,
                    COUNT(CASE WHEN status = 'pending' THEN 1 END) AS unassigned
             FROM orders WHERE partner_id = ? AND order_date BETWEEN ? AND ? AND status <> 'cancelled'",
            [$partnerId, $from, $to]
        );
        $stock = $db->fetch(
            'SELECT COALESCE(SUM(li.remaining_pcs * li.company_price_per_pc), 0) AS value
             FROM lot_items li JOIN lots l ON l.id = li.lot_id WHERE l.partner_id = ?',
            [$partnerId]
        );
        $purchases = $db->fetch(
            'SELECT COALESCE(SUM(total_value), 0) AS value FROM lots WHERE partner_id = ? AND received_date BETWEEN ? AND ?',
            [$partnerId, $from, $to]
        );

        $tripIds = array_column($db->fetchAll(
            'SELECT id FROM trips WHERE partner_id = ? AND trip_date BETWEEN ? AND ? ORDER BY trip_date DESC, id DESC',
            [$partnerId, $from, $to]
        ), 'id');

        $value = (float) $o['order_value'];

        return [
            'orders' => (int) $o['orders'],
            'retailers' => (int) $o['retailers'],
            'order_value' => $value,
            'oc' => (float) $o['oc'],
            'delivered' => (float) $o['delivered'],
            'delivered_pct' => $value > 0 ? round((float) $o['delivered'] / $value * 100, 1) : 0.0,
            'due' => (float) $o['due'],
            'unassigned' => (int) $o['unassigned'],
            'unassigned_value' => (float) $o['unassigned_value'],
            'stock_value' => round((float) $stock['value'], 2),
            'purchases' => (float) $purchases['value'],
            'trips' => array_map(static fn($id): array => Trip::detail($partnerId, (int) $id), $tripIds),
        ];
    }
}
