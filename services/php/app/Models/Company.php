<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Format;
use App\Support\HttpError;
use Core\Database;

/** Global company catalog. Partner/dealer data is joined from partner_companies (created via SRs). */
final class Company
{
    private const SELECT = 'SELECT c.*,
            (SELECT COUNT(*) FROM products pr WHERE pr.company_id = c.id AND pr.status = \'active\') AS total_sku,
            (SELECT COALESCE(SUM(li.remaining_pcs * li.company_price_per_pc), 0)
               FROM lot_items li JOIN lots l ON l.id = li.lot_id WHERE l.company_id = c.id) AS stock_value,
            (SELECT COUNT(*) FROM salesmen s WHERE s.company_id = c.id AND s.deleted_at IS NULL) AS salesmen_count
        FROM companies c';

    private static function db(): Database
    {
        return Database::getInstance();
    }

    /** @return list<array<string, mixed>> */
    public static function all(): array
    {
        $rows = self::db()->fetchAll(self::SELECT . ' WHERE c.deleted_at IS NULL ORDER BY c.name');
        $links = self::linksByCompany();

        return array_map(static fn(array $r): array => self::present($r, $links[(int) $r['id']] ?? []), $rows);
    }

    /** @return list<array{id:int,name:string,status:string}> */
    public static function options(): array
    {
        return array_map(static fn(array $r): array => [
            'id' => (int) $r['id'],
            'name' => (string) $r['name'],
            'status' => Format::status($r['status']),
        ], self::db()->fetchAll('SELECT id, name, status FROM companies WHERE deleted_at IS NULL ORDER BY name'));
    }

    /** @return array<int, list<array<string, mixed>>> partner links grouped by company id */
    private static function linksByCompany(?int $companyId = null): array
    {
        $rows = self::db()->fetchAll(
            'SELECT pc.*, p.name AS partner_name, d.name AS dealer_name,
                    (SELECT COUNT(*) FROM salesmen s WHERE s.company_id = pc.company_id AND s.partner_id = pc.partner_id AND s.deleted_at IS NULL) AS srs
             FROM partner_companies pc
             JOIN partners p ON p.id = pc.partner_id AND p.deleted_at IS NULL
             LEFT JOIN dealers d ON d.id = pc.dealer_id
             WHERE ? IS NULL OR pc.company_id = ?
             ORDER BY p.name',
            [$companyId, $companyId]
        );

        $grouped = [];
        foreach ($rows as $r) {
            $grouped[(int) $r['company_id']][] = [
                'partner_id' => (int) $r['partner_id'],
                'partner_name' => $r['partner_name'],
                'ownership' => Format::status($r['ownership']),
                'dealer_id' => $r['dealer_id'] !== null ? (int) $r['dealer_id'] : null,
                'dealer' => $r['dealer_name'],
                'dealer_profit_share' => $r['dealer_profit_share'] !== null ? (float) $r['dealer_profit_share'] : null,
                'partner_profit_share' => $r['partner_profit_share'] !== null ? (float) $r['partner_profit_share'] : null,
                'platform_fee_per_lakh' => (float) $r['platform_fee_per_lakh'],
                'srs' => (int) $r['srs'],
            ];
        }

        return $grouped;
    }

    /** @param array<string, mixed> $r @param list<array<string, mixed>>|null $links */
    public static function present(array $r, ?array $links = null): array
    {
        $links ??= self::linksByCompany((int) $r['id'])[(int) $r['id']] ?? [];

        return [
            'id' => (int) $r['id'],
            'name' => $r['name'],
            'total_sku' => (int) $r['total_sku'],
            'stock_value' => round((float) $r['stock_value'], 2),
            'salesmen' => (int) $r['salesmen_count'],
            'links' => $links,
            'status' => Format::status($r['status']),
        ];
    }

    public static function findOrFail(int $id): array
    {
        $row = self::db()->fetch(self::SELECT . ' WHERE c.id = ? AND c.deleted_at IS NULL', [$id]);
        if ($row === null) {
            throw new HttpError('Company not found.', 404);
        }

        return $row;
    }

    private static function assertUniqueName(string $name, int $ignoreId = 0): void
    {
        $dup = self::db()->fetch('SELECT id FROM companies WHERE name = ? AND deleted_at IS NULL AND id <> ?', [$name, $ignoreId]);
        if ($dup !== null) {
            throw new HttpError('A company with this name already exists.', 422, ['name' => ['A company with this name already exists.']]);
        }
    }

    /** @param array{name:string,status:string} $d */
    public static function create(array $d): array
    {
        self::assertUniqueName($d['name']);
        self::db()->execute(
            'INSERT INTO companies (name, status) VALUES (?, ?)',
            [$d['name'], $d['status']]
        );

        return self::findOrFail((int) self::db()->lastInsertId());
    }

    /** @param array{name:string,status:string} $d */
    public static function update(int $id, array $d): array
    {
        self::findOrFail($id);
        self::assertUniqueName($d['name'], $id);
        self::db()->execute(
            'UPDATE companies SET name = ?, status = ? WHERE id = ?',
            [$d['name'], $d['status'], $id]
        );

        return self::findOrFail($id);
    }

    public static function setStatus(int $id, string $status): array
    {
        self::findOrFail($id);
        self::db()->execute('UPDATE companies SET status = ? WHERE id = ?', [$status, $id]);
        return self::findOrFail($id);
    }

    public static function delete(int $id): array
    {
        $row = self::findOrFail($id);
        if ((int) $row['salesmen_count'] > 0) {
            throw new HttpError("Company \"{$row['name']}\" has {$row['salesmen_count']} SR(s) assigned. Reassign or delete them first, or deactivate the company.", 409);
        }

        self::db()->execute("UPDATE companies SET status = 'inactive', deleted_at = NOW() WHERE id = ?", [$id]);
        return $row;
    }
}
