<?php

declare(strict_types=1);

namespace App\Services;

use App\Models\UserSession;
use App\Support\Format;
use Core\Database;
use Throwable;

/** Live runtime diagnostics built only from measurable values. */
final class SystemHealth
{
    private const WARN_AT = 80;

    /** @return array<string, mixed> */
    public static function snapshot(): array
    {
        $db = Database::getInstance();
        $checks = [];

        // PHP runtime: memory vs memory_limit
        $limit = self::toBytes((string) ini_get('memory_limit'));
        $mem = memory_get_usage(true);
        $memPct = $limit > 0 ? (int) round($mem / $limit * 100) : 0;
        $checks[] = self::check('Application Server (PHP)', 'PHP ' . PHP_VERSION . ' · ' . Format::bytes($mem) . ' of ' . ($limit > 0 ? Format::bytes($limit) : 'unlimited'), $memPct);

        // Database: ping latency + connection usage
        $start = microtime(true);
        $dbOk = true;
        $latency = 0;
        $dbSize = 0.0;
        $connPct = 0;
        try {
            $db->fetch('SELECT 1');
            $latency = (int) max(1, round((microtime(true) - $start) * 1000));
            $dbSize = (float) ($db->fetch('SELECT COALESCE(SUM(data_length + index_length), 0) AS s FROM information_schema.tables WHERE table_schema = DATABASE()')['s'] ?? 0);
            $threads = (int) ($db->fetch("SHOW STATUS LIKE 'Threads_connected'")['Value'] ?? 0);
            $maxConn = (int) ($db->fetch("SHOW VARIABLES LIKE 'max_connections'")['Value'] ?? 0);
            $connPct = $maxConn > 0 ? (int) round($threads / $maxConn * 100) : 0;
            $checks[] = self::check('Primary SQL Database', "{$latency} ms ping · {$threads}/{$maxConn} connections", $connPct);
        } catch (Throwable) {
            $dbOk = false;
            $checks[] = ['name' => 'Primary SQL Database', 'status' => 'down', 'detail' => 'Connection failed', 'load' => 100];
        }

        // Sessions: share of users currently signed in
        $active = $dbOk ? UserSession::activeCount() : 0;
        $users = $dbOk ? (int) ($db->fetch('SELECT COUNT(*) AS t FROM users WHERE deleted_at IS NULL')['t'] ?? 0) : 0;
        $sessPct = $users > 0 ? (int) min(100, round($active / $users * 100)) : 0;
        $checks[] = [
            'name' => 'Session & Auth Store',
            'status' => is_writable((string) (session_save_path() ?: sys_get_temp_dir())) ? 'healthy' : 'warning',
            'detail' => "{$active} active session(s) · {$users} accounts",
            'load' => $sessPct,
        ];

        // Storage: disk usage of the storage partition + writability
        $storage = storage_path();
        $total = (float) (@disk_total_space($storage) ?: 0);
        $free = (float) (@disk_free_space($storage) ?: 0);
        $diskPct = $total > 0 ? (int) round(($total - $free) / $total * 100) : 0;
        $storageCheck = self::check('Storage & Uploads', $diskPct . '% disk used · ' . Format::bytes($free) . ' free', $diskPct);
        if (!is_writable($storage)) {
            $storageCheck['status'] = 'warning';
            $storageCheck['detail'] .= ' · not writable';
        }
        $checks[] = $storageCheck;

        $statuses = array_column($checks, 'status');
        $overall = in_array('down', $statuses, true) ? 'Down' : (in_array('warning', $statuses, true) ? 'Degraded' : 'Operational');

        return [
            'overall' => $overall,
            'db_size' => Format::bytes($dbSize),
            'latency' => $dbOk ? "{$latency} ms" : '—',
            'php_version' => PHP_VERSION,
            'memory_usage' => Format::bytes($mem),
            'checks' => $checks,
        ];
    }

    /** Cheap status for the top bar: DB ping + storage writable. */
    public static function quickStatus(): string
    {
        try {
            Database::getInstance()->fetch('SELECT 1');
        } catch (Throwable) {
            return 'Down';
        }

        return is_writable(storage_path()) ? 'Operational' : 'Degraded';
    }

    /** @return array{name:string,status:string,detail:string,load:int} */
    private static function check(string $name, string $detail, int $load): array
    {
        return ['name' => $name, 'status' => $load >= self::WARN_AT ? 'warning' : 'healthy', 'detail' => $detail, 'load' => min(100, $load)];
    }

    private static function toBytes(string $value): int
    {
        $value = trim($value);
        if ($value === '' || $value === '-1') {
            return 0;
        }
        $num = (int) $value;
        return match (strtolower(substr($value, -1))) {
            'g' => $num * 1024 ** 3,
            'm' => $num * 1024 ** 2,
            'k' => $num * 1024,
            default => $num,
        };
    }
}
