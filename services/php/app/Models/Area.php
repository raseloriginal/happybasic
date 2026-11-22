<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Format;
use App\Support\HttpError;
use Core\Database;

final class Area
{
    private static function db(): Database
    {
        return Database::getInstance();
    }

    /** @return list<array<string, mixed>> */
    public static function all(bool $activeOnly = false): array
    {
        $rows = self::db()->fetchAll(
            'SELECT a.*, (SELECT COUNT(*) FROM partners p WHERE p.area_id = a.id AND p.deleted_at IS NULL) AS partners
             FROM areas a WHERE a.deleted_at IS NULL' . ($activeOnly ? " AND a.status = 'active'" : '') . '
             ORDER BY a.name'
        );

        return array_map([self::class, 'present'], $rows);
    }

    /** @param array<string, mixed> $r */
    public static function present(array $r): array
    {
        return [
            'id' => (int) $r['id'],
            'name' => $r['name'],
            'partners' => (int) ($r['partners'] ?? 0),
            'status' => Format::status($r['status']),
        ];
    }

    /** @return array<string, mixed> */
    public static function findOrFail(int $id): array
    {
        $row = self::db()->fetch(
            'SELECT a.*, (SELECT COUNT(*) FROM partners p WHERE p.area_id = a.id AND p.deleted_at IS NULL) AS partners
             FROM areas a WHERE a.id = ? AND a.deleted_at IS NULL',
            [$id]
        );
        if ($row === null) {
            throw new HttpError('Area not found.', 404);
        }

        return $row;
    }

    /** Creates an area, restoring a previously deleted one with the same name. */
    public static function create(string $name, string $status): array
    {
        $existing = self::db()->fetch('SELECT * FROM areas WHERE name = ?', [$name]);
        if ($existing !== null && $existing['deleted_at'] === null) {
            throw new HttpError("Area \"{$name}\" already exists.", 422, ['name' => ['This area already exists.']]);
        }

        if ($existing !== null) {
            self::db()->execute('UPDATE areas SET status = ?, deleted_at = NULL WHERE id = ?', [$status, $existing['id']]);
            return self::findOrFail((int) $existing['id']);
        }

        self::db()->execute('INSERT INTO areas (name, status) VALUES (?, ?)', [$name, $status]);
        return self::findOrFail((int) self::db()->lastInsertId());
    }

    public static function setStatus(int $id, string $status): array
    {
        self::findOrFail($id);
        self::db()->execute('UPDATE areas SET status = ? WHERE id = ?', [$status, $id]);
        return self::findOrFail($id);
    }

    public static function delete(int $id): array
    {
        $row = self::findOrFail($id);
        if ((int) $row['partners'] > 0) {
            throw new HttpError("Area \"{$row['name']}\" is used by {$row['partners']} partner(s). Move them to another area or deactivate it instead.", 409);
        }

        self::db()->execute('UPDATE areas SET deleted_at = NOW() WHERE id = ?', [$id]);
        return $row;
    }

    public static function assertUsable(int $id, ?int $currentAreaId = null): void
    {
        $row = self::db()->fetch('SELECT status FROM areas WHERE id = ? AND deleted_at IS NULL', [$id]);
        if ($row === null || ($row['status'] !== 'active' && $id !== $currentAreaId)) {
            throw new HttpError('Selected area is invalid or inactive.', 422, ['area_id' => ['Selected area is invalid or inactive.']]);
        }
    }
}
