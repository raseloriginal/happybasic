<?php

declare(strict_types=1);

namespace Core;

use InvalidArgumentException;

abstract class Model
{
    protected static string $table = '';
    protected static string $primaryKey = 'id';
    /** @var list<string> */
    protected static array $fillable = [];
    /** @var list<string> */
    protected static array $hidden = [];

    protected static function db(): Database
    {
        return Database::getInstance();
    }

    public static function table(): string
    {
        if (static::$table === '') {
            throw new InvalidArgumentException(static::class . ' must define protected static string $table.');
        }

        return self::quoteIdentifier(static::$table);
    }

    /** @return list<array<string, mixed>> */
    public static function all(?string $orderBy = null, string $direction = 'ASC'): array
    {
        $sql = 'SELECT * FROM ' . static::table();

        if ($orderBy !== null) {
            $dir = strtoupper($direction) === 'DESC' ? 'DESC' : 'ASC';
            $sql .= ' ORDER BY ' . self::quoteIdentifier($orderBy) . " {$dir}";
        }

        return array_map([static::class, 'hideAttributes'], static::db()->fetchAll($sql));
    }

    /** @return array<string, mixed>|null */
    public static function find(int|string $id, bool $withHidden = false): ?array
    {
        $pk = self::quoteIdentifier(static::$primaryKey);
        $row = static::db()->fetch(
            'SELECT * FROM ' . static::table() . " WHERE {$pk} = ? LIMIT 1",
            [$id]
        );

        return ($row === null || $withHidden) ? $row : static::hideAttributes($row);
    }

    /** @return array<string, mixed>|null */
    public static function findBy(string $column, mixed $value, bool $withHidden = false): ?array
    {
        $col = self::quoteIdentifier($column);
        $row = static::db()->fetch(
            'SELECT * FROM ' . static::table() . " WHERE {$col} = ? LIMIT 1",
            [$value]
        );

        return ($row === null || $withHidden) ? $row : static::hideAttributes($row);
    }

    /** @return list<array<string, mixed>> */
    public static function where(string $column, mixed $value, string $operator = '='): array
    {
        $allowed = ['=', '!=', '<>', '<', '<=', '>', '>=', 'LIKE'];
        $op = strtoupper(trim($operator));
        if (!in_array($op, $allowed, true)) {
            throw new InvalidArgumentException("Unsupported SQL operator: {$operator}");
        }

        $col = self::quoteIdentifier($column);
        $rows = static::db()->fetchAll(
            'SELECT * FROM ' . static::table() . " WHERE {$col} {$op} ?",
            [$value]
        );

        return array_map([static::class, 'hideAttributes'], $rows);
    }

    /** @param array<string, mixed> $data */
    public static function create(array $data): int|string
    {
        $filtered = static::filterFillable($data);
        if ($filtered === []) {
            throw new InvalidArgumentException('No fillable attributes provided for insert.');
        }

        $columns = array_map([self::class, 'quoteIdentifier'], array_keys($filtered));
        $placeholders = implode(', ', array_fill(0, count($filtered), '?'));

        $sql = 'INSERT INTO ' . static::table()
            . ' (' . implode(', ', $columns) . ')'
            . " VALUES ({$placeholders})";

        static::db()->execute($sql, array_values($filtered));
        $id = static::db()->lastInsertId();

        return ctype_digit($id) ? (int) $id : $id;
    }

    /** @param array<string, mixed> $data */
    public static function update(int|string $id, array $data): bool
    {
        $filtered = static::filterFillable($data);
        if ($filtered === []) {
            return false;
        }

        $sets = [];
        foreach (array_keys($filtered) as $column) {
            $sets[] = self::quoteIdentifier($column) . ' = ?';
        }

        $pk = self::quoteIdentifier(static::$primaryKey);
        $sql = 'UPDATE ' . static::table() . ' SET ' . implode(', ', $sets) . " WHERE {$pk} = ?";

        $params = array_values($filtered);
        $params[] = $id;

        return static::db()->execute($sql, $params) > 0;
    }

    public static function delete(int|string $id): bool
    {
        $pk = self::quoteIdentifier(static::$primaryKey);
        $sql = 'DELETE FROM ' . static::table() . " WHERE {$pk} = ?";
        return static::db()->execute($sql, [$id]) > 0;
    }

    public static function count(?string $column = null, mixed $value = null): int
    {
        if ($column === null) {
            $row = static::db()->fetch('SELECT COUNT(*) AS total FROM ' . static::table());
            return (int) ($row['total'] ?? 0);
        }

        $col = self::quoteIdentifier($column);
        $row = static::db()->fetch(
            'SELECT COUNT(*) AS total FROM ' . static::table() . " WHERE {$col} = ?",
            [$value]
        );
        return (int) ($row['total'] ?? 0);
    }

    /** @return array{data: list<array<string, mixed>>, total: int, per_page: int, current_page: int, last_page: int} */
    public static function paginate(int $perPage = 15, int $page = 1, ?string $orderBy = null, string $direction = 'DESC'): array
    {
        $perPage = max(1, $perPage);
        $page = max(1, $page);
        $total = static::count();
        $offset = ($page - 1) * $perPage;

        $orderCol = self::quoteIdentifier($orderBy ?? static::$primaryKey);
        $dir = strtoupper($direction) === 'ASC' ? 'ASC' : 'DESC';

        $rows = static::db()->fetchAll(
            'SELECT * FROM ' . static::table() . " ORDER BY {$orderCol} {$dir} LIMIT {$perPage} OFFSET {$offset}"
        );

        return [
            'data' => array_map([static::class, 'hideAttributes'], $rows),
            'total' => $total,
            'per_page' => $perPage,
            'current_page' => $page,
            'last_page' => max(1, (int) ceil($total / $perPage)),
        ];
    }

    /** @param array<string, mixed> $data @return array<string, mixed> */
    protected static function filterFillable(array $data): array
    {
        if (static::$fillable === []) {
            return $data;
        }

        return array_intersect_key($data, array_flip(static::$fillable));
    }

    /** @param array<string, mixed> $row @return array<string, mixed> */
    protected static function hideAttributes(array $row): array
    {
        if (static::$hidden === []) {
            return $row;
        }

        return array_diff_key($row, array_flip(static::$hidden));
    }

    protected static function quoteIdentifier(string $identifier): string
    {
        if (!preg_match('/^[a-zA-Z_][a-zA-Z0-9_]*$/', $identifier)) {
            throw new InvalidArgumentException("Invalid SQL identifier: {$identifier}");
        }

        return "`{$identifier}`";
    }
}
