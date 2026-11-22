<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Format;
use App\Support\HttpError;
use Core\Database;

final class Category
{
    private const SELECT = 'SELECT c.*, (SELECT COUNT(*) FROM products p WHERE p.category_id = c.id) AS products FROM categories c';

    private static function db(): Database
    {
        return Database::getInstance();
    }

    /** @return list<array<string, mixed>> */
    public static function all(): array
    {
        return array_map(
            [self::class, 'present'],
            self::db()->fetchAll(self::SELECT . ' WHERE c.deleted_at IS NULL ORDER BY c.name')
        );
    }

    /** @param array<string, mixed> $r */
    public static function present(array $r): array
    {
        return [
            'id' => (int) $r['id'],
            'name' => $r['name'],
            'slug' => $r['slug'],
            'products' => (int) ($r['products'] ?? 0),
            'status' => Format::status($r['status']),
        ];
    }

    public static function findOrFail(int $id): array
    {
        $row = self::db()->fetch(self::SELECT . ' WHERE c.id = ? AND c.deleted_at IS NULL', [$id]);
        if ($row === null) {
            throw new HttpError('Category not found.', 404);
        }

        return $row;
    }

    /** Creates a category, restoring a previously deleted one with the same slug. */
    public static function create(string $name, string $status): array
    {
        $slug = Format::slug($name);
        if ($slug === '') {
            throw new HttpError('Category name must contain letters or numbers.', 422, ['name' => ['Invalid category name.']]);
        }

        $existing = self::db()->fetch('SELECT * FROM categories WHERE slug = ?', [$slug]);
        if ($existing !== null && $existing['deleted_at'] === null) {
            throw new HttpError("Category \"{$existing['name']}\" already exists.", 422, ['name' => ['This category already exists.']]);
        }

        if ($existing !== null) {
            self::db()->execute('UPDATE categories SET name = ?, status = ?, deleted_at = NULL WHERE id = ?', [$name, $status, $existing['id']]);
            return self::findOrFail((int) $existing['id']);
        }

        self::db()->execute('INSERT INTO categories (name, slug, status) VALUES (?, ?, ?)', [$name, $slug, $status]);
        return self::findOrFail((int) self::db()->lastInsertId());
    }

    public static function setStatus(int $id, string $status): array
    {
        self::findOrFail($id);
        self::db()->execute('UPDATE categories SET status = ? WHERE id = ?', [$status, $id]);
        return self::findOrFail($id);
    }

    public static function delete(int $id): array
    {
        $row = self::findOrFail($id);
        self::db()->execute("UPDATE categories SET deleted_at = NOW(), status = 'inactive' WHERE id = ?", [$id]);
        return $row;
    }
}
