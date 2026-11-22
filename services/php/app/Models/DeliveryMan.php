<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Format;
use App\Support\HttpError;
use App\Support\Phone;
use Core\Database;

/** Partner-owned delivery men (DSR). Each has a phone-login account with role "dsr". */
final class DeliveryMan
{
    private const SELECT = 'SELECT dm.*,
            (SELECT COUNT(*) FROM trips t WHERE t.dsr_id = dm.id) AS trips,
            (SELECT COUNT(*) FROM trips t WHERE t.dsr_id = dm.id AND t.status IN (\'pending\', \'dispatched\', \'in_review\')) AS open_trips
        FROM delivery_men dm';

    private static function db(): Database
    {
        return Database::getInstance();
    }

    /** @return list<array<string, mixed>> */
    public static function forPartner(int $partnerId): array
    {
        return array_map([self::class, 'present'], self::db()->fetchAll(
            self::SELECT . ' WHERE dm.partner_id = ? AND dm.deleted_at IS NULL ORDER BY dm.name',
            [$partnerId]
        ));
    }

    /** @param array<string, mixed> $r */
    public static function present(array $r): array
    {
        return [
            'id' => (int) $r['id'],
            'name' => $r['name'],
            'phone' => $r['phone'],
            'number' => Phone::format($r['phone']),
            'salary' => (float) $r['salary'],
            'photo' => !empty($r['photo_path']) ? url((string) $r['photo_path']) : null,
            'status' => Format::status($r['status']),
            'trips' => (int) ($r['trips'] ?? 0),
            'open_trips' => (int) ($r['open_trips'] ?? 0),
        ];
    }

    /** @return array<string, mixed> */
    public static function findOrFail(int $partnerId, int $id): array
    {
        $row = self::db()->fetch(self::SELECT . ' WHERE dm.id = ? AND dm.partner_id = ? AND dm.deleted_at IS NULL', [$id, $partnerId]);
        if ($row === null) {
            throw new HttpError('Delivery man not found.', 404);
        }

        return $row;
    }

    /** @param array{name:string, phone:string, salary:float, password:string, status:string} $d */
    public static function create(int $partnerId, array $d): array
    {
        return self::db()->transaction(static function (Database $db) use ($partnerId, $d): array {
            $userId = User::createAccount($d['name'], $d['phone'], $d['password'], 'dsr', $d['status']);
            $db->execute(
                'INSERT INTO delivery_men (partner_id, user_id, name, phone, salary, status) VALUES (?, ?, ?, ?, ?, ?)',
                [$partnerId, $userId, $d['name'], $d['phone'], $d['salary'], $d['status']]
            );

            return self::findOrFail($partnerId, (int) $db->lastInsertId());
        });
    }

    /** @param array{name:string, phone:string, salary:float, password:?string, status:string} $d */
    public static function update(int $partnerId, int $id, array $d): array
    {
        $current = self::findOrFail($partnerId, $id);

        return self::db()->transaction(static function (Database $db) use ($partnerId, $id, $d, $current): array {
            User::syncAccount((int) $current['user_id'], $d['name'], $d['phone'], $d['status'], $d['password'] ?? null);
            $db->execute(
                'UPDATE delivery_men SET name = ?, phone = ?, salary = ?, status = ? WHERE id = ?',
                [$d['name'], $d['phone'], $d['salary'], $d['status'], $id]
            );

            return self::findOrFail($partnerId, $id);
        });
    }

    public static function setPhoto(int $partnerId, int $id, string $path): array
    {
        self::findOrFail($partnerId, $id);
        self::db()->execute('UPDATE delivery_men SET photo_path = ? WHERE id = ?', [$path, $id]);

        return self::findOrFail($partnerId, $id);
    }

    public static function setStatus(int $partnerId, int $id, string $status): array
    {
        $current = self::findOrFail($partnerId, $id);

        return self::db()->transaction(static function (Database $db) use ($partnerId, $id, $status, $current): array {
            User::setStatus((int) $current['user_id'], $status);
            $db->execute('UPDATE delivery_men SET status = ? WHERE id = ?', [$status, $id]);

            return self::findOrFail($partnerId, $id);
        });
    }

    public static function resetPassword(int $partnerId, int $id, string $password): array
    {
        $current = self::findOrFail($partnerId, $id);
        User::syncAccount((int) $current['user_id'], $current['name'], $current['phone'], $current['status'], $password);
        UserSession::revokeAllForUser((int) $current['user_id']);

        return $current;
    }

    /** Soft delete; blocked while the DSR still has an unsettled trip. */
    public static function delete(int $partnerId, int $id): array
    {
        $row = self::findOrFail($partnerId, $id);
        if ((int) $row['open_trips'] > 0) {
            throw new HttpError("\"{$row['name']}\" has unsettled trips. Settle them or deactivate the DSR instead.", 422);
        }

        self::db()->transaction(static function (Database $db) use ($row): void {
            User::softDelete((int) $row['user_id']);
            $db->execute("UPDATE delivery_men SET status = 'inactive', deleted_at = NOW() WHERE id = ?", [$row['id']]);
        });

        return $row;
    }
}
