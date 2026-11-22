<?php

declare(strict_types=1);

namespace App\Support;

use App\Models\ActivityLog;
use App\Models\UserSession;
use Core\Database;
use Core\Request;
use Core\Session;

/**
 * Phone + password sign-in for the partner and SR panels.
 *
 * Each panel keeps its own tracked session token (independent of Core\Auth and of
 * the admin console), so an admin, a partner and an SR can be signed in side by side.
 */
final class PanelAuth
{
    private const MAX_FAILED = 5;
    private const LOCK_MINUTES = 15;

    /** @var array<string, array<string, mixed>> resolved user per panel for this request */
    private static array $users = [];

    public static function tokenKey(string $panel): string
    {
        return "panel_{$panel}_token";
    }

    private static function rememberKey(string $panel): string
    {
        return "panel_{$panel}_remember";
    }

    private static function cookie(string $panel): string
    {
        return "hb_{$panel}_remember";
    }

    /**
     * Verifies phone + password for a role and starts the panel session.
     *
     * @return array<string, mixed> the user row
     */
    public static function attempt(Request $request, string $panel, string $role, string $phoneInput, string $password, bool $remember): array
    {
        $ip = $request->ip();
        if (ActivityLog::recentFailedLogins($ip, self::LOCK_MINUTES) >= self::MAX_FAILED) {
            throw new HttpError('Too many failed attempts. Please try again in ' . self::LOCK_MINUTES . ' minutes.', 429);
        }

        $phone = Phone::normalize($phoneInput);
        if ($role === 'retailer') {
            // Retailers sign in with their shop phone (any format) and the same number as password;
            // the account is created on first sign-in.
            $phone = \App\Models\Retailer::loginPhone($phoneInput);
            $password = \App\Models\Retailer::phoneKey($password);
            if ($phone !== null) {
                \App\Models\Retailer::ensureAccount($phone);
            }
        }
        $user = $phone === null ? null : Database::getInstance()->fetch(
            'SELECT * FROM users WHERE phone = ? AND role = ? AND deleted_at IS NULL LIMIT 1',
            [$phone, $role]
        );

        if ($user === null || !password_verify($password, (string) $user['password'])) {
            ActivityLog::record('Failed', 'Auth', "Failed {$panel} sign-in for " . mb_substr($phoneInput, 0, 40), $user !== null ? (int) $user['id'] : null);
            throw new HttpError('Invalid phone number or password.', 422);
        }
        if ($user['status'] !== 'active') {
            throw new HttpError('This account is not active. Please contact your administrator.', 403);
        }

        Session::regenerate();
        $token = UserSession::start((int) $user['id'], $remember, $ip, (string) $request->header('User-Agent', ''));
        Session::set(self::tokenKey($panel), $token);
        Session::set(self::rememberKey($panel), $remember);

        if ($remember) {
            setcookie(self::cookie($panel), $token, [
                'expires' => time() + UserSession::REMEMBER_DAYS * 86400,
                'path' => '/',
                'secure' => $request->header('X-Forwarded-Proto') === 'https' || !empty($_SERVER['HTTPS']),
                'httponly' => true,
                'samesite' => 'Lax',
            ]);
        }

        ActivityLog::record('Login', 'Auth', "Signed in to {$panel} panel", (int) $user['id']);
        unset($user['password']);

        return $user;
    }

    /** @return array<string, mixed>|null active user of the given role signed in to this panel */
    public static function user(string $panel, string $role): ?array
    {
        if (isset(self::$users[$panel])) {
            return self::$users[$panel];
        }

        $remember = (bool) Session::get(self::rememberKey($panel), false);
        $token = Session::get(self::tokenKey($panel));
        $row = is_string($token) ? UserSession::findValid($token) : null;

        if ($row === null && is_string($_COOKIE[self::cookie($panel)] ?? null)) {
            $token = (string) $_COOKIE[self::cookie($panel)];
            $row = UserSession::findValid($token);
            if ($row !== null) {
                Session::set(self::tokenKey($panel), $token);
                Session::set(self::rememberKey($panel), true);
                $remember = true;
            }
        }
        if ($row === null) {
            return null;
        }

        $user = Database::getInstance()->fetch(
            "SELECT id, name, phone, role, status FROM users WHERE id = ? AND role = ? AND status = 'active' AND deleted_at IS NULL",
            [$row['user_id'], $role]
        );
        if ($user === null) {
            return null;
        }

        UserSession::touch($row, $remember);
        return self::$users[$panel] = $user;
    }

    public static function logout(string $panel): void
    {
        $token = Session::get(self::tokenKey($panel));
        if (is_string($token)) {
            UserSession::revokeToken($token);
        }
        self::forget($panel);
    }

    public static function forget(string $panel): void
    {
        unset(self::$users[$panel]);
        Session::remove(self::tokenKey($panel));
        Session::remove(self::rememberKey($panel));
        if (isset($_COOKIE[self::cookie($panel)])) {
            setcookie(self::cookie($panel), '', ['expires' => time() - 3600, 'path' => '/', 'httponly' => true, 'samesite' => 'Lax']);
        }
    }
}
