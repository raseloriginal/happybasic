<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Format;
use App\Support\HttpError;
use Core\Database;

/**
 * Partner product catalog. Prices are stored PER PIECE:
 *  - company_price = buying price of the latest lot (set when a lot is saved)
 *  - base_price    = dealer price (base selling price to retailers) = company_price × (1 + dealer_margin%)
 * stock_pcs mirrors SUM(lot_items.remaining_pcs) (physical stock in the warehouse).
 */
final class Product
{
    private const TINTS = ['#eff6ff', '#fefce8', '#f0fdf4', '#fdf2f8', '#f5f3ff', '#ecfeff', '#ecfdf5', '#fff7ed'];

    /** Pieces ordered but not yet loaded on a dispatched van. */
    public const RESERVED_SQL = "(SELECT COALESCE(SUM(oi.ordered_pcs), 0) FROM order_items oi
            JOIN orders o ON o.id = oi.order_id
            LEFT JOIN trips t ON t.id = o.trip_id
            WHERE oi.product_id = p.id AND o.status IN ('pending', 'assigned') AND (o.trip_id IS NULL OR t.status = 'pending'))";

    private const SELECT = 'SELECT p.*, c.name AS company, cat.name AS category, ' . self::RESERVED_SQL . ' AS reserved_pcs,
            (SELECT COUNT(*) FROM lot_items li WHERE li.product_id = p.id) AS lot_rows
        FROM products p
        JOIN companies c ON c.id = p.company_id
        JOIN categories cat ON cat.id = p.category_id';

    public const UNIT_TYPES = ['Carton', 'Case', 'Box', 'Pack', 'Dozen', 'Sack', 'Bag', 'Piece'];

    private static function db(): Database
    {
        return Database::getInstance();
    }

    /** @return list<array<string, mixed>> */
    public static function forPartner(int $partnerId, ?int $companyId = null, bool $activeOnly = false): array
    {
        $sql = self::SELECT . ' WHERE p.partner_id = ? AND p.deleted_at IS NULL';
        $params = [$partnerId];
        if ($companyId !== null) {
            $sql .= ' AND p.company_id = ?';
            $params[] = $companyId;
        }
        if ($activeOnly) {
            $sql .= " AND p.status = 'active'";
        }

        return array_map([self::class, 'present'], self::db()->fetchAll($sql . ' ORDER BY p.name', $params));
    }

    /** "12 Carton 5 pcs" */
    public static function unitPcs(int $pcs, int $qtyPerUnit, string $unitType): string
    {
        $qpu = max(1, $qtyPerUnit);
        $sign = $pcs < 0 ? '-' : '';
        $pcs = abs($pcs);

        return $sign . intdiv($pcs, $qpu) . ' ' . $unitType . ' ' . ($pcs % $qpu) . ' pcs';
    }

    /** @return array{image:?string, code:string, tint:string} card visual: uploaded image or initials on a tint */
    public static function visual(int $id, string $name, ?string $imagePath): array
    {
        $words = preg_split('/\s+/', trim($name)) ?: [];
        $code = strtoupper(implode('', array_map(static fn(string $w): string => mb_substr($w, 0, 1), array_slice($words, 0, 2))));

        return [
            'image' => $imagePath ? url($imagePath) : null,
            'code' => $code !== '' ? $code : 'PR',
            'tint' => self::TINTS[$id % count(self::TINTS)],
        ];
    }

    /** @param array<string, mixed> $r */
    public static function present(array $r): array
    {
        $id = (int) $r['id'];
        $qpu = max(1, (int) $r['qty_per_unit']);
        $stock = (int) $r['stock_pcs'];
        $reserved = (int) ($r['reserved_pcs'] ?? 0);
        return self::visual($id, (string) $r['name'], $r['image_path']) + [
            'id' => $id,
            'company_id' => (int) $r['company_id'],
            'company' => $r['company'] ?? null,
            'category_id' => (int) $r['category_id'],
            'category' => $r['category'] ?? null,
            'name' => $r['name'],
            'sku' => $r['sku'],
            'unit_type' => $r['unit_type'],
            'qty_per_unit' => $qpu,
            'company_price_pc' => (float) $r['company_price'],
            'dealer_margin' => (float) $r['dealer_margin'],
            'dealer_price_pc' => (float) $r['base_price'],
            'company_price_unit' => round((float) $r['company_price'] * $qpu, 2),
            'dealer_price_unit' => round((float) $r['base_price'] * $qpu, 2),
            'stock_pcs' => $stock,
            'stock' => self::unitPcs($stock, $qpu, (string) $r['unit_type']),
            'reserved_pcs' => $reserved,
            'available_pcs' => $stock - $reserved,
            'mrp' => $r['mrp'] !== null ? (float) $r['mrp'] : null,
            'priced' => (float) $r['base_price'] > 0,
            'has_lots' => (int) ($r['lot_rows'] ?? 0) > 0,
            'status' => Format::status($r['status']),
        ];
    }

    /** @return array<string, mixed> */
    public static function findOrFail(int $partnerId, int $id): array
    {
        $row = self::db()->fetch(self::SELECT . ' WHERE p.id = ? AND p.partner_id = ? AND p.deleted_at IS NULL', [$id, $partnerId]);
        if ($row === null) {
            throw new HttpError('Product not found.', 404);
        }

        return $row;
    }

    public static function dealerPrice(float $companyPricePc, float $marginPct): float
    {
        return round($companyPricePc * (1 + $marginPct / 100), 2);
    }

    /** @return list<array{id:int, name:string}> companies connected to the partner (via SRs) */
    public static function companyOptions(int $partnerId): array
    {
        return array_map(static fn(array $r): array => ['id' => (int) $r['id'], 'name' => $r['name']], self::db()->fetchAll(
            "SELECT c.id, c.name FROM partner_companies pc JOIN companies c ON c.id = pc.company_id
             WHERE pc.partner_id = ? AND c.deleted_at IS NULL AND c.status = 'active' ORDER BY c.name",
            [$partnerId]
        ));
    }

    /** @return list<array{id:int, name:string}> */
    public static function categoryOptions(): array
    {
        return array_map(static fn(array $r): array => ['id' => (int) $r['id'], 'name' => $r['name']], self::db()->fetchAll(
            "SELECT id, name FROM categories WHERE deleted_at IS NULL AND status = 'active' ORDER BY name"
        ));
    }

    /** @param array<string, mixed> $d */
    private static function assertRefs(int $partnerId, array $d): void
    {
        $companyIds = array_column(self::companyOptions($partnerId), 'id');
        if (!in_array((int) $d['company_id'], $companyIds, true)) {
            throw new HttpError('Please select one of your companies.', 422, ['company_id' => ['Invalid company.']]);
        }
        if (!in_array((int) $d['category_id'], array_column(self::categoryOptions(), 'id'), true)) {
            throw new HttpError('Please select an active category.', 422, ['category_id' => ['Invalid category.']]);
        }
        if (!in_array($d['unit_type'], self::UNIT_TYPES, true)) {
            throw new HttpError('Invalid unit type.', 422, ['unit_type' => ['Invalid unit type.']]);
        }
        $dup = self::db()->fetch(
            'SELECT id FROM products WHERE partner_id = ? AND company_id = ? AND name = ? AND deleted_at IS NULL AND id <> ?',
            [$partnerId, $d['company_id'], $d['name'], $d['id'] ?? 0]
        );
        if ($dup !== null) {
            throw new HttpError('A product with this name already exists for the company.', 422, ['name' => ['Duplicate product name.']]);
        }
    }

    /** @param array<string, mixed> $d validated: company_id, category_id, name, sku, unit_type, qty_per_unit, dealer_margin, status, image_path */
    public static function create(int $partnerId, array $d): array
    {
        self::assertRefs($partnerId, $d);
        self::db()->execute(
            'INSERT INTO products (partner_id, company_id, category_id, sku, name, image_path, unit_type, qty_per_unit, dealer_margin, mrp, status)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [$partnerId, $d['company_id'], $d['category_id'], $d['sku'], $d['name'], $d['image_path'], $d['unit_type'], $d['qty_per_unit'], $d['dealer_margin'], $d['mrp'], $d['status']]
        );

        return self::findOrFail($partnerId, (int) self::db()->lastInsertId());
    }

    /** @param array<string, mixed> $d */
    public static function update(int $partnerId, int $id, array $d): array
    {
        $current = self::findOrFail($partnerId, $id);
        $d['id'] = $id;
        self::assertRefs($partnerId, $d);

        $hasHistory = (int) $current['lot_rows'] > 0;
        if ($hasHistory && (int) $d['company_id'] !== (int) $current['company_id']) {
            throw new HttpError('Company cannot change after lots were received for this product.', 422, ['company_id' => ['Locked by existing lots.']]);
        }
        if ($hasHistory && (int) $d['qty_per_unit'] !== (int) $current['qty_per_unit']) {
            throw new HttpError('Quantity per unit cannot change after lots were received for this product.', 422, ['quantity_per_unit' => ['Locked by existing lots.']]);
        }

        $base = self::dealerPrice((float) $current['company_price'], (float) $d['dealer_margin']);
        self::db()->execute(
            'UPDATE products SET company_id = ?, category_id = ?, sku = ?, name = ?, image_path = COALESCE(?, image_path), unit_type = ?,
                qty_per_unit = ?, dealer_margin = ?, mrp = ?, base_price = ?, status = ? WHERE id = ?',
            [$d['company_id'], $d['category_id'], $d['sku'], $d['name'], $d['image_path'], $d['unit_type'], $d['qty_per_unit'], $d['dealer_margin'], $d['mrp'], $base, $d['status'], $id]
        );

        return self::findOrFail($partnerId, $id);
    }

    public static function setStatus(int $partnerId, int $id, string $status): array
    {
        self::findOrFail($partnerId, $id);
        self::db()->execute('UPDATE products SET status = ? WHERE id = ?', [$status, $id]);

        return self::findOrFail($partnerId, $id);
    }

    public static function delete(int $partnerId, int $id): array
    {
        $row = self::findOrFail($partnerId, $id);
        if ((int) $row['stock_pcs'] > 0 || (int) $row['reserved_pcs'] > 0) {
            throw new HttpError("\"{$row['name']}\" still has stock or open orders. Deactivate it instead.", 422);
        }
        self::db()->execute("UPDATE products SET status = 'inactive', deleted_at = NOW() WHERE id = ?", [$id]);

        return $row;
    }
}
