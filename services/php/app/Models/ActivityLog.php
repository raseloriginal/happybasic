<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Format;
use Core\App;
use Core\Auth;
use Core\Database;

final class ActivityLog
{
    public static function record(string $action, string $module, string $detail, ?int $userId = null): void
    {
        $userId ??= Auth::id() !== null ? (int) Auth::id() : null;

        Database::getInstance()->execute(
            'INSERT INTO activity_logs (user_id, action, module, detail, ip_address) VALUES (?, ?, ?, ?, ?)',
            [$userId, $action, $module, mb_substr($detail, 0, 255), App::request()?->ip()]
        );
    }

    /** @return list<array<string, mixed>> */
    public static function latest(int $limit = 500): array
    {
        $limit = max(1, $limit);
        $rows = Database::getInstance()->fetchAll(
            "SELECT l.*, u.name AS actor FROM activity_logs l
             LEFT JOIN users u ON u.id = l.user_id
             ORDER BY l.id DESC LIMIT {$limit}"
        );

        return array_map(static fn(array $r): array => [
            'id' => (int) $r['id'],
            'time' => date('Y-m-d H:i', strtotime((string) $r['created_at'])),
            'ago' => Format::timeAgo((string) $r['created_at']),
            'actor' => $r['actor'] ?? 'System',
            'action' => $r['action'],
            'module' => $r['module'],
            'detail' => $r['detail'],
            'ip' => $r['ip_address'] ?? '—',
        ], $rows);
    }

    /** @return list<string> */
    public static function modules(): array
    {
        return array_column(
            Database::getInstance()->fetchAll('SELECT DISTINCT module FROM activity_logs ORDER BY module'),
            'module'
        );
    }

    public static function recentFailedLogins(string $ip, int $minutes): int
    {
        $row = Database::getInstance()->fetch(
            "SELECT COUNT(*) AS total FROM activity_logs
             WHERE module = 'Auth' AND action = 'Failed' AND ip_address = ?
               AND created_at >= (NOW() - INTERVAL ? MINUTE)",
            [$ip, $minutes]
        );

        return (int) ($row['total'] ?? 0);
    }
}
