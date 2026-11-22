<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Format;
use App\Support\HttpError;
use App\Support\Phone;
use Core\Database;

final class Dealer
{
    private const SELECT = 'SELECT d.*, p.name AS partner_name,
            (SELECT COUNT(*) FROM partner_companies pc JOIN companies c ON c.id = pc.company_id WHERE pc.dealer_id = d.id AND c.deleted_at IS NULL) AS companies_count,
            (SELECT COUNT(*) FROM partner_companies pc JOIN salesmen s ON s.partner_id = pc.partner_id AND s.company_id = pc.company_id
               WHERE pc.dealer_id = d.id AND s.deleted_at IS NULL) AS srs_count
        FROM dealers d JOIN partners p ON p.id = d.partner_id';

    private static function db(): Database
    {
        return Database::getInstance();
    }

    /** @return list<array<string, mixed>> */
    public static function all(): array
    {
        return array_map(
            [self::class, 'present'],
            self::db()->fetchAll(self::SELECT . ' WHERE d.deleted_at IS NULL ORDER BY d.id DESC')
        );
    }

    /** @return list<array{id:int,partner_id:int,name:string,partner_name:string,status:string}> */
    public static function options(): array
    {
        return array_map(static fn(array $r): array => [
            'id' => (int) $r['id'],
            'partner_id' => (int) $r['partner_id'],
            'name' => (string) $r['name'],
            'partner_name' => (string) $r['partner_name'],
            'status' => Format::status($r['status']),
        ], self::db()->fetchAll(
            'SELECT d.id, d.partner_id, d.name, d.status, p.name AS partner_name FROM dealers d
             JOIN partners p ON p.id = d.partner_id WHERE d.deleted_at IS NULL ORDER BY d.name'
        ));
    }

    /** @param array<string, mixed> $r */
    public static function present(array $r): array
    {
        return [
            'id' => (int) $r['id'],
            'partner_id' => (int) $r['partner_id'],
            'partner_name' => $r['partner_name'],
            'name' => $r['name'],
            'number' => Phone::format($r['phone']),
            'trade_license' => $r['trade_license'] ?? '',
            'nid' => $r['nid'] ?? '',
            'tin' => $r['tin'] ?? '',
            'address' => $r['address'] ?? '',
            'companies' => (int) $r['companies_count'],
            'status' => Format::status($r['status']),
        ];
    }

    public static function findOrFail(int $id): array
    {
        $row = self::db()->fetch(self::SELECT . ' WHERE d.id = ? AND d.deleted_at IS NULL', [$id]);
        if ($row === null) {
            throw new HttpError('Dealer not found.', 404);
        }

        return $row;
    }

    /** @param array<string, mixed> $d */
    public static function create(array $d): array
    {
        Partner::assertUsable((int) $d['partner_id']);

        return self::db()->transaction(static function (Database $db) use ($d): array {
            $userId = User::createAccount($d['name'], $d['phone'], $d['password'], 'dealer', $d['status']);
            $db->execute(
                'INSERT INTO dealers (partner_id, user_id, name, phone, tin, trade_license, nid, address, status)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                [$d['partner_id'], $userId, $d['name'], $d['phone'], $d['tin'], $d['trade_license'], $d['nid'], $d['address'], $d['status']]
            );

            return self::findOrFail((int) $db->lastInsertId());
        });
    }

    /** @param array<string, mixed> $d */
    public static function update(int $id, array $d): array
    {
        $current = self::findOrFail($id);
        if ((int) $d['partner_id'] !== (int) $current['partner_id']) {
            Partner::assertUsable((int) $d['partner_id']);
            if ((int) $current['srs_count'] > 0) {
                throw new HttpError("Dealer has {$current['srs_count']} active SR(s) under the current partner. Move or delete the SRs of those companies before changing partner.", 409);
            }
        }

        return self::db()->transaction(static function (Database $db) use ($id, $d, $current): array {
            if ((int) $d['partner_id'] !== (int) $current['partner_id']) {
                // Old partner connections through this dealer have no active SRs (checked above).
                $db->execute('DELETE FROM partner_companies WHERE dealer_id = ?', [$id]);
            }
            User::syncAccount((int) $current['user_id'], $d['name'], $d['phone'], $d['status'], $d['password'] ?? null);
            $db->execute(
                'UPDATE dealers SET partner_id = ?, name = ?, phone = ?, tin = ?, trade_license = ?, nid = ?, address = ?, status = ?
                 WHERE id = ?',
                [$d['partner_id'], $d['name'], $d['phone'], $d['tin'], $d['trade_license'], $d['nid'], $d['address'], $d['status'], $id]
            );

            return self::findOrFail($id);
        });
    }

    public static function setStatus(int $id, string $status): array
    {
        $current = self::findOrFail($id);

        return self::db()->transaction(static function (Database $db) use ($id, $status, $current): array {
            $db->execute('UPDATE dealers SET status = ? WHERE id = ?', [$status, $id]);
            User::setStatus((int) $current['user_id'], $status);
            return self::findOrFail($id);
        });
    }

    public static function delete(int $id): array
    {
        $row = self::findOrFail($id);
        if ((int) $row['srs_count'] > 0) {
            throw new HttpError("Dealer \"{$row['name']}\" still has {$row['srs_count']} active SR(s). Move or delete the SRs using this dealer first, or deactivate the dealer.", 409);
        }

        self::db()->transaction(static function (Database $db) use ($id, $row): void {
            $db->execute("UPDATE dealers SET status = 'inactive', deleted_at = NOW() WHERE id = ?", [$id]);
            User::softDelete((int) $row['user_id']);
        });

        return $row;
    }
}
