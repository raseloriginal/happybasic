<?php

declare(strict_types=1);

namespace Core;

use PDO;
use PDOStatement;
use RuntimeException;
use Throwable;

final class Database
{
    private static ?self $instance = null;
    private PDO $pdo;

    /** @param array<string, mixed> $config */
    private function __construct(array $config)
    {
        $driver = (string) ($config['driver'] ?? 'mysql');

        if ($driver === 'sqlite') {
            $database = (string) ($config['database'] ?? ':memory:');
            $dsn = "sqlite:{$database}";
            $this->pdo = new PDO($dsn, null, null, $this->defaultOptions());
            $this->pdo->exec('PRAGMA foreign_keys = ON');
            return;
        }

        $host = (string) ($config['host'] ?? '127.0.0.1');
        $port = (int) ($config['port'] ?? 3306);
        $database = (string) ($config['database'] ?? '');
        $charset = (string) ($config['charset'] ?? 'utf8mb4');
        $username = (string) ($config['username'] ?? 'root');
        $password = (string) ($config['password'] ?? '');

        $dsn = "{$driver}:host={$host};port={$port};dbname={$database};charset={$charset}";
        $this->pdo = new PDO($dsn, $username, $password, $this->defaultOptions());
        // Use the app's timezone (APP_TIMEZONE) in MySQL too, whatever the DB server's own clock zone is:
        // NOW()/CURDATE()/CURRENT_TIMESTAMP and TIMESTAMP columns then match PHP's date().
        $this->pdo->exec("SET time_zone = '" . date('P') . "'");
    }

    private function __clone(): void
    {
    }

    public function __wakeup(): void
    {
        throw new RuntimeException('Cannot unserialize Database singleton.');
    }

    /** @param array<string, mixed>|null $config */
    public static function getInstance(?array $config = null): self
    {
        if (self::$instance === null) {
            self::$instance = new self($config ?? (array) config('database', []));
        }

        return self::$instance;
    }

    public static function pdo(): PDO
    {
        return self::getInstance()->pdo;
    }

    public static function reset(): void
    {
        self::$instance = null;
    }

    public function connection(): PDO
    {
        return $this->pdo;
    }

    /** @param array<int|string, mixed> $params */
    public function query(string $sql, array $params = []): PDOStatement
    {
        $stmt = $this->pdo->prepare($sql);
        $stmt->execute($params);
        return $stmt;
    }

    /** @param array<int|string, mixed> $params @return array<string, mixed>|null */
    public function fetch(string $sql, array $params = []): ?array
    {
        $row = $this->query($sql, $params)->fetch();
        return $row === false ? null : $row;
    }

    /** @param array<int|string, mixed> $params @return list<array<string, mixed>> */
    public function fetchAll(string $sql, array $params = []): array
    {
        return $this->query($sql, $params)->fetchAll();
    }

    /** @param array<int|string, mixed> $params */
    public function execute(string $sql, array $params = []): int
    {
        return $this->query($sql, $params)->rowCount();
    }

    public function lastInsertId(): string
    {
        return $this->pdo->lastInsertId();
    }

    public function beginTransaction(): bool
    {
        return $this->pdo->beginTransaction();
    }

    public function commit(): bool
    {
        return $this->pdo->commit();
    }

    public function rollBack(): bool
    {
        return $this->pdo->rollBack();
    }

    /** @template T @param callable(self): T $callback @return T */
    public function transaction(callable $callback): mixed
    {
        $this->beginTransaction();
        try {
            $result = $callback($this);
            $this->commit();
            return $result;
        } catch (Throwable $e) {
            if ($this->pdo->inTransaction()) {
                $this->rollBack();
            }
            throw $e;
        }
    }

    /** @return array<int, mixed> */
    private function defaultOptions(): array
    {
        return [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ];
    }
}
