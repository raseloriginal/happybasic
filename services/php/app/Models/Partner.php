<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Format;
use App\Support\HttpError;
use App\Support\Phone;
use Core\Database;

final class Partner
{
    private const SELECT = 'SELECT p.*, a.name AS area_name,
            (SELECT COUNT(*) FROM partner_companies pc JOIN companies c ON c.id = pc.company_id WHERE pc.partner_id = p.id AND c.deleted_at IS NULL) AS companies_count,
            (SELECT COUNT(*) FROM dealers d WHERE d.partner_id = p.id AND d.deleted_at IS NULL) AS dealers_count,
            (SELECT COUNT(*) FROM salesmen s WHERE s.partner_id = p.id AND s.deleted_at IS NULL) AS salesmen_count
        FROM partners p JOIN areas a ON a.id = p.area_id';

    private static function db(): Database
    {
        return Database::getInstance();
    }

    /** @return list<array<string, mixed>> */
    public static function all(): array
    {
        return array_map(
            [self::class, 'present'],
            self::db()->fetchAll(self::SELECT . ' WHERE p.deleted_at IS NULL ORDER BY p.id DESC')
        );
    }

    /** Lightweight list for dropdowns. @return list<array{id:int,name:string,area:string,status:string}> */
    public static function options(): array
    {
        $rows = self::db()->fetchAll(
            'SELECT p.id, p.name, p.status, a.name AS area FROM partners p JOIN areas a ON a.id = p.area_id
             WHERE p.deleted_at IS NULL ORDER BY p.name'
        );

        return array_map(static fn(array $r): array => [
            'id' => (int) $r['id'],
            'name' => (string) $r['name'],
            'area' => (string) $r['area'],
            'status' => Format::status($r['status']),
        ], $rows);
    }

    /** @param array<string, mixed> $r */
    public static function present(array $r): array
    {
        return [
            'id' => (int) $r['id'],
            'name' => $r['name'],
            'number' => Phone::format($r['phone']),
            'phone' => $r['phone'],
            'tin' => $r['tin'] ?? '',
            'trade_license' => $r['trade_license'] ?? '',
            'nid' => $r['nid'] ?? '',
            'address' => $r['address'] ?? '',
            'area_id' => (int) $r['area_id'],
            'area' => $r['area_name'],
            'status' => Format::status($r['status']),
            'created_at' => substr((string) $r['created_at'], 0, 10),
            'counts' => [
                'companies' => (int) $r['companies_count'],
                'dealers' => (int) $r['dealers_count'],
                'salesmen' => (int) $r['salesmen_count'],
            ],
        ];
    }

    public static function findOrFail(int $id): array
    {
        $row = self::db()->fetch(self::SELECT . ' WHERE p.id = ? AND p.deleted_at IS NULL', [$id]);
        if ($row === null) {
            throw new HttpError('Partner not found.', 404);
        }

        return $row;
    }

    /** Partner that new records may be attached to. */
    public static function assertUsable(int $id, string $field = 'partner_id'): array
    {
        $row = self::db()->fetch('SELECT * FROM partners WHERE id = ? AND deleted_at IS NULL', [$id]);
        if ($row === null) {
            throw new HttpError('Selected partner is invalid.', 422, [$field => ['Selected partner is invalid.']]);
        }

        return $row;
    }

    /** @param array<string, mixed> $d validated data (phone normalized) */
    public static function create(array $d): array
    {
        Area::assertUsable((int) $d['area_id']);

        return self::db()->transaction(static function (Database $db) use ($d): array {
            $userId = User::createAccount($d['name'], $d['phone'], $d['password'], 'partner', $d['status']);
            $db->execute(
                'INSERT INTO partners (user_id, area_id, name, phone, tin, trade_license, nid, address, status)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                [$userId, $d['area_id'], $d['name'], $d['phone'], $d['tin'], $d['trade_license'], $d['nid'], $d['address'], $d['status']]
            );

            return self::findOrFail((int) $db->lastInsertId());
        });
    }

    /** @param array<string, mixed> $d */
    public static function update(int $id, array $d): array
    {
        $current = self::findOrFail($id);
        Area::assertUsable((int) $d['area_id'], (int) $current['area_id']);

        return self::db()->transaction(static function (Database $db) use ($id, $d, $current): array {
            User::syncAccount((int) $current['user_id'], $d['name'], $d['phone'], $d['status'], $d['password'] ?? null);
            $db->execute(
                'UPDATE partners SET area_id = ?, name = ?, phone = ?, tin = ?, trade_license = ?, nid = ?, address = ?, status = ?
                 WHERE id = ?',
                [$d['area_id'], $d['name'], $d['phone'], $d['tin'], $d['trade_license'], $d['nid'], $d['address'], $d['status'], $id]
            );

            return self::findOrFail($id);
        });
    }

    public static function setStatus(int $id, string $status): array
    {
        $current = self::findOrFail($id);

        return self::db()->transaction(static function (Database $db) use ($id, $status, $current): array {
            $db->execute('UPDATE partners SET status = ? WHERE id = ?', [$status, $id]);
            User::setStatus((int) $current['user_id'], $status);
            return self::findOrFail($id);
        });
    }

    public static function delete(int $id): array
    {
        $row = self::findOrFail($id);
        $dsr = (int) (self::db()->fetch('SELECT COUNT(*) AS t FROM delivery_men WHERE partner_id = ? AND status = \'active\'', [$id])['t'] ?? 0);
        $linked = array_filter([
            'dealers' => (int) $row['dealers_count'],
            'SRs' => (int) $row['salesmen_count'],
            'active DSRs' => $dsr,
        ]);
        if ($linked !== []) {
            $parts = array_map(static fn($k, $v) => "{$v} {$k}", array_keys($linked), $linked);
            throw new HttpError("Partner \"{$row['name']}\" still has " . implode(', ', $parts) . '. Remove or reassign them first, or deactivate the partner.', 409);
        }

        self::db()->transaction(static function (Database $db) use ($id, $row): void {
            $db->execute("UPDATE partners SET status = 'inactive', deleted_at = NOW() WHERE id = ?", [$id]);
            User::softDelete((int) $row['user_id']);
        });

        return $row;
    }
}
