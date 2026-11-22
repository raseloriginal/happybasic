<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\HttpError;
use Core\Database;

/**
 * Stock received from a company. Quantities are entered in pieces and the company price is per piece.
 * Each lot_item is a FIFO layer (remaining_pcs is consumed oldest-first on trip dispatch).
 */
final class Lot
{
    private static function db(): Database
    {
        return Database::getInstance();
    }

    /** @return list<array<string, mixed>> */
    public static function forPartner(int $partnerId, ?int $lotId = null): array
    {
        $lots = self::db()->fetchAll(
            'SELECT l.*, c.name AS company FROM lots l JOIN companies c ON c.id = l.company_id
             WHERE l.partner_id = ? AND (? IS NULL OR l.id = ?) ORDER BY l.received_date DESC, l.id DESC',
            [$partnerId, $lotId, $lotId]
        );
        if ($lots === []) {
            return [];
        }

        $ids = array_map(static fn(array $l): int => (int) $l['id'], $lots);
        $items = self::db()->fetchAll(
            'SELECT li.*, p.name AS product, p.unit_type, p.qty_per_unit FROM lot_items li
             JOIN products p ON p.id = li.product_id
             WHERE li.lot_id IN (' . implode(',', $ids) . ') ORDER BY li.id'
        );
        $byLot = [];
        foreach ($items as $it) {
            $byLot[(int) $it['lot_id']][] = $it;
        }

        return array_map(static fn(array $l): array => self::present($l, $byLot[(int) $l['id']] ?? []), $lots);
    }

    /**
     * @param array<string, mixed> $l
     * @param list<array<string, mixed>> $items
     */
    private static function present(array $l, array $items): array
    {
        $rows = array_map(static fn(array $it): array => [
            'product' => $it['product'],
            'pcs' => (int) $it['qty_pcs'],
            'qty' => Product::unitPcs((int) $it['qty_pcs'], (int) $it['qty_per_unit'], (string) $it['unit_type']),
            'remaining_pcs' => (int) $it['remaining_pcs'],
            'company_price' => (float) $it['company_price_per_pc'],
            'subtotal' => round((int) $it['qty_pcs'] * (float) $it['company_price_per_pc'], 2),
            'expire_date' => $it['expire_date'],
        ], $items);
        $expiries = array_column($rows, 'expire_date');
        sort($expiries);
        $untouched = array_reduce($items, static fn(bool $ok, array $it): bool => $ok && (int) $it['remaining_pcs'] === (int) $it['qty_pcs'], true);

        return [
            'id' => (int) $l['id'],
            'code' => $l['lot_code'],
            'company_id' => (int) $l['company_id'],
            'company' => $l['company'],
            'date' => $l['received_date'],
            'notes' => $l['notes'],
            'items_count' => count($rows),
            'total_pcs' => array_sum(array_column($rows, 'pcs')),
            'total_value' => (float) $l['total_value'],
            'nearest_expiry' => $expiries[0] ?? null,
            'deletable' => $untouched,
            'rows' => $rows,
        ];
    }

    /**
     * @param array{company_id:int, received_date:string, notes:?string, items:list<array{product_id:int, pcs:int, price_pc:float, expire_date:string}>} $d
     * @return array<string, mixed>
     */
    public static function create(int $partnerId, array $d): array
    {
        $companyIds = array_column(Product::companyOptions($partnerId), 'id');
        if (!in_array($d['company_id'], $companyIds, true)) {
            throw new HttpError('Please select one of your companies.', 422, ['company_id' => ['Invalid company.']]);
        }

        $products = [];
        foreach (Product::forPartner($partnerId, $d['company_id']) as $p) {
            $products[$p['id']] = $p;
        }
        $seen = [];
        foreach ($d['items'] as $i => $it) {
            $p = $products[$it['product_id']] ?? null;
            $row = 'Row ' . ($i + 1) . ': ';
            if ($p === null) {
                throw new HttpError($row . 'select a product of the chosen company.', 422);
            }
            if (isset($seen[$it['product_id']])) {
                throw new HttpError($row . "\"{$p['name']}\" is added twice. Merge the rows.", 422);
            }
            $seen[$it['product_id']] = true;
            if ($it['pcs'] < 1) {
                throw new HttpError($row . 'quantity must be at least 1 piece.', 422);
            }
            if ($it['price_pc'] <= 0) {
                throw new HttpError($row . 'company price per piece must be greater than 0.', 422);
            }
            if ($it['expire_date'] < $d['received_date']) {
                throw new HttpError($row . 'expire date cannot be before the lot date.', 422);
            }
        }

        $total = round(array_sum(array_map(static fn(array $it): float => $it['pcs'] * $it['price_pc'], $d['items'])), 2);

        $lotId = self::db()->transaction(static function (Database $db) use ($partnerId, $d, $products, $total): int {
            $db->execute(
                'INSERT INTO lots (partner_id, company_id, lot_code, received_date, total_value, notes) VALUES (?, ?, ?, ?, ?, ?)',
                [$partnerId, $d['company_id'], 'TMP-' . bin2hex(random_bytes(8)), $d['received_date'], $total, $d['notes']]
            );
            $lotId = (int) $db->lastInsertId();
            $db->execute('UPDATE lots SET lot_code = ? WHERE id = ?', ['LOT-' . date('ymd', strtotime($d['received_date'])) . '-' . str_pad((string) $lotId, 4, '0', STR_PAD_LEFT), $lotId]);

            foreach ($d['items'] as $it) {
                $p = $products[$it['product_id']];
                $qpu = $p['qty_per_unit'];
                // Only the newest lot (by received date) sets the current buying / dealer price.
                $newer = $db->fetch(
                    'SELECT 1 FROM lot_items li JOIN lots l ON l.id = li.lot_id WHERE li.product_id = ? AND l.received_date > ? LIMIT 1',
                    [$it['product_id'], $d['received_date']]
                );

                $db->execute(
                    'INSERT INTO lot_items (lot_id, product_id, qty_units, qty_pcs, remaining_pcs, company_price, company_price_per_pc, expire_date)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                    [$lotId, $it['product_id'], intdiv($it['pcs'], $qpu), $it['pcs'], $it['pcs'], round($it['price_pc'] * $qpu, 2), $it['price_pc'], $it['expire_date']]
                );

                if ($newer === null) {
                    $db->execute(
                        'UPDATE products SET stock_pcs = stock_pcs + ?, company_price = ?, base_price = ? WHERE id = ?',
                        [$it['pcs'], $it['price_pc'], Product::dealerPrice($it['price_pc'], $p['dealer_margin']), $it['product_id']]
                    );
                } else {
                    $db->execute('UPDATE products SET stock_pcs = stock_pcs + ? WHERE id = ?', [$it['pcs'], $it['product_id']]);
                }
            }

            $db->execute(
                "INSERT INTO company_ledger (partner_id, company_id, ref_type, ref_id, debit, credit, note, entry_date)
                 VALUES (?, ?, 'lot_purchase', ?, ?, 0, ?, ?)",
                [$partnerId, $d['company_id'], $lotId, $total, 'Lot purchase', $d['received_date']]
            );

            return $lotId;
        });

        return self::find($partnerId, $lotId);
    }

    /** @return array<string, mixed> */
    public static function find(int $partnerId, int $id): array
    {
        return self::forPartner($partnerId, $id)[0] ?? throw new HttpError('Lot not found.', 404);
    }

    /** Removes a lot entered by mistake — only while none of its stock has been used. */
    public static function delete(int $partnerId, int $id): array
    {
        $lot = self::find($partnerId, $id);
        if (!$lot['deletable']) {
            throw new HttpError("Stock from {$lot['code']} has already been dispatched, so it cannot be deleted.", 422);
        }

        self::db()->transaction(static function (Database $db) use ($partnerId, $id): void {
            $items = $db->fetchAll('SELECT product_id, qty_pcs FROM lot_items WHERE lot_id = ?', [$id]);
            foreach ($items as $it) {
                $db->execute('UPDATE products SET stock_pcs = GREATEST(stock_pcs - ?, 0) WHERE id = ?', [$it['qty_pcs'], $it['product_id']]);
            }
            $db->execute("DELETE FROM company_ledger WHERE partner_id = ? AND ref_type = 'lot_purchase' AND ref_id = ?", [$partnerId, $id]);
            $db->execute('DELETE FROM lots WHERE id = ?', [$id]);

            // Restore each product's current price from its newest remaining lot.
            foreach ($items as $it) {
                $last = $db->fetch(
                    'SELECT li.company_price_per_pc FROM lot_items li JOIN lots l ON l.id = li.lot_id
                     WHERE li.product_id = ? ORDER BY l.received_date DESC, li.id DESC LIMIT 1',
                    [$it['product_id']]
                );
                $price = $last !== null ? (float) $last['company_price_per_pc'] : 0.0;
                $db->execute('UPDATE products SET company_price = ?, base_price = ROUND(? * (1 + dealer_margin / 100), 2) WHERE id = ?', [$price, $price, $it['product_id']]);
            }
        });

        return $lot;
    }
}
