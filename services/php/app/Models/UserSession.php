<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Format;
use Core\Database;

/** Tracked login sessions (tokens are stored hashed). */
final class UserSession
{
    public const REMEMBER_DAYS = 30;

    private static function db(): Database
    {
        return Database::getInstance();
    }

    private static function idleSeconds(): int
    {
        return max(300, (int) ini_get('session.gc_maxlifetime'));
    }

    public static function start(int $userId, bool $remember, string $ip, string $userAgent): string
    {
        $token = bin2hex(random_bytes(32));
        $ttl = $remember ? self::REMEMBER_DAYS * 86400 : self::idleSeconds();

        self::db()->execute(
            'INSERT INTO user_sessions (user_id, session_token, device, ip_address, user_agent, expires_at)
             VALUES (?, ?, ?, ?, ?, NOW() + INTERVAL ? SECOND)',
            [$userId, hash('sha256', $token), self::describeDevice($userAgent), $ip, mb_substr($userAgent, 0, 255), $ttl]
        );

        return $token;
    }

    /** @return array<string, mixed>|null Valid (not revoked / expired) session row. */
    public static function findValid(string $token): ?array
    {
        return self::db()->fetch(
            'SELECT * FROM user_sessions
             WHERE session_token = ? AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > NOW())
             LIMIT 1',
            [hash('sha256', $token)]
        );
    }

    /** Refreshes activity at most once a minute; sliding expiry for non-remembered sessions. */
    public static function touch(array $row, bool $remember): void
    {
        if (strtotime((string) $row['last_active_at']) > time() - 60) {
            return;
        }

        $ttl = $remember ? self::REMEMBER_DAYS * 86400 : self::idleSeconds();
        self::db()->execute(
            'UPDATE user_sessions SET last_active_at = NOW(), expires_at = NOW() + INTERVAL ? SECOND WHERE id = ?',
            [$ttl, $row['id']]
        );
    }

    public static function revokeToken(string $token): void
    {
        self::db()->execute(
            'UPDATE user_sessions SET revoked_at = NOW() WHERE session_token = ? AND revoked_at IS NULL',
            [hash('sha256', $token)]
        );
    }

    public static function revokeById(int $id): ?array
    {
        $row = self::db()->fetch(
            'SELECT s.id, u.name FROM user_sessions s JOIN users u ON u.id = s.user_id WHERE s.id = ? AND s.revoked_at IS NULL',
            [$id]
        );
        if ($row !== null) {
            self::db()->execute('UPDATE user_sessions SET revoked_at = NOW() WHERE id = ?', [$id]);
        }

        return $row;
    }

    public static function revokeAllExcept(string $currentToken): int
    {
        return self::db()->execute(
            'UPDATE user_sessions SET revoked_at = NOW() WHERE revoked_at IS NULL AND session_token <> ?',
            [hash('sha256', $currentToken)]
        );
    }

    /** Signs one user out of every other device, keeping the current session. */
    public static function revokeUserExcept(int $userId, string $currentToken): void
    {
        self::db()->execute(
            'UPDATE user_sessions SET revoked_at = NOW() WHERE user_id = ? AND revoked_at IS NULL AND session_token <> ?',
            [$userId, hash('sha256', $currentToken)]
        );
    }

    public static function revokeAllForUser(int $userId): void
    {
        self::db()->execute('UPDATE user_sessions SET revoked_at = NOW() WHERE user_id = ? AND revoked_at IS NULL', [$userId]);
    }

    public static function activeCount(): int
    {
        $row = self::db()->fetch(
            'SELECT COUNT(*) AS total FROM user_sessions WHERE revoked_at IS NULL AND (expires_at IS NULL OR expires_at > NOW())'
        );

        return (int) ($row['total'] ?? 0);
    }

    /** @return list<array<string, mixed>> */
    public static function active(?string $currentToken): array
    {
        $currentHash = $currentToken !== null ? hash('sha256', $currentToken) : '';
        $rows = self::db()->fetchAll(
            'SELECT s.*, u.name, u.email, u.phone, u.role FROM user_sessions s
             JOIN users u ON u.id = s.user_id
             WHERE s.revoked_at IS NULL AND (s.expires_at IS NULL OR s.expires_at > NOW()) AND u.deleted_at IS NULL
             ORDER BY s.last_active_at DESC'
        );

        return array_map(static fn(array $r): array => [
            'id' => (int) $r['id'],
            'user' => $r['name'],
            'email' => $r['email'] ?? \App\Support\Phone::format($r['phone']),
            'role' => in_array($r['role'], ['sr', 'dsr'], true) ? strtoupper((string) $r['role']) : ucfirst((string) $r['role']),
            'device' => $r['device'] ?? 'Unknown device',
            'ip' => $r['ip_address'] ?? '—',
            'location' => $r['location'] ?? '',
            'last_active' => Format::timeAgo((string) $r['last_active_at']),
            'current' => hash_equals((string) $r['session_token'], $currentHash),
        ], $rows);
    }

    private static function describeDevice(string $ua): string
    {
        // The mobile app sends "HappyBangladesh/1.0.0 (Samsung SM-A15; Android 14)".
        if (preg_match('/^HappyBangladesh\/[\d.]+ \(([^)]*)\)/', $ua, $m) === 1) {
            return 'অ্যাপ · ' . mb_substr($m[1], 0, 60);
        }
        $browser = match (true) {
            str_contains($ua, 'Edg/') => 'Edge',
            str_contains($ua, 'OPR/') => 'Opera',
            str_contains($ua, 'Chrome/') => 'Chrome',
            str_contains($ua, 'Firefox/') => 'Firefox',
            str_contains($ua, 'Safari/') => 'Safari',
            default => 'Browser',
        };
        $os = match (true) {
            str_contains($ua, 'Windows NT 10') => 'Windows 10/11',
            str_contains($ua, 'Windows') => 'Windows',
            str_contains($ua, 'Android') => 'Android',
            str_contains($ua, 'iPhone') => 'iPhone',
            str_contains($ua, 'iPad') => 'iPad',
            str_contains($ua, 'Mac OS X') => 'macOS',
            str_contains($ua, 'Linux') => 'Linux',
            default => 'Unknown OS',
        };

        return "{$browser} · {$os}";
    }
}
