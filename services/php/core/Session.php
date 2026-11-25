<?php

declare(strict_types=1);

namespace Core;

final class Session
{
    private const FLASH_KEY = '_flash';
    private const FLASH_OLD_KEY = '_flash_old';

    public static function start(): void
    {
        if (session_status() === PHP_SESSION_ACTIVE) {
            return;
        }

        // Mobile app API: token auth only, no PHP session file / cookie per request.
        if (App::isApi()) {
            $_SESSION ??= [];
            return;
        }

        if (PHP_SAPI !== 'cli' && !headers_sent()) {
            $isSecure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
                || ((int) ($_SERVER['SERVER_PORT'] ?? 80) === 443);

            session_set_cookie_params([
                'lifetime' => 0,
                'path' => '/',
                'secure' => $isSecure,
                'httponly' => true,
                'samesite' => 'Lax',
            ]);
            session_start();
        } elseif (!isset($_SESSION)) {
            $_SESSION = [];
        }

        self::ageFlashData();
    }

    public static function get(string $key, mixed $default = null): mixed
    {
        self::start();
        return $_SESSION[$key] ?? $default;
    }

    public static function set(string $key, mixed $value): void
    {
        self::start();
        $_SESSION[$key] = $value;
    }

    public static function has(string $key): bool
    {
        self::start();
        return array_key_exists($key, $_SESSION);
    }

    public static function remove(string $key): void
    {
        self::start();
        unset($_SESSION[$key]);
    }

    public static function pull(string $key, mixed $default = null): mixed
    {
        $value = self::get($key, $default);
        self::remove($key);
        return $value;
    }

    public static function flash(string $key, mixed $value): void
    {
        self::start();
        $_SESSION[self::FLASH_KEY][$key] = $value;
    }

    public static function getFlash(string $key, mixed $default = null): mixed
    {
        self::start();
        return $_SESSION[self::FLASH_OLD_KEY][$key]
            ?? $_SESSION[self::FLASH_KEY][$key]
            ?? $default;
    }

    public static function hasFlash(string $key): bool
    {
        self::start();
        return array_key_exists($key, $_SESSION[self::FLASH_OLD_KEY] ?? [])
            || array_key_exists($key, $_SESSION[self::FLASH_KEY] ?? []);
    }

    public static function flashInput(array $input): void
    {
        unset($input['password'], $input['password_confirmation'], $input['_token']);
        self::flash('_old_input', $input);
    }

    public static function old(string $key, mixed $default = ''): mixed
    {
        $old = self::getFlash('_old_input', []);
        return is_array($old) && array_key_exists($key, $old) ? $old[$key] : $default;
    }

    public static function flashErrors(array $errors): void
    {
        self::flash('_errors', $errors);
    }

    /** @return array<string, list<string>> */
    public static function errors(): array
    {
        $errors = self::getFlash('_errors', []);
        return is_array($errors) ? $errors : [];
    }

    public static function regenerate(): void
    {
        self::start();
        if (session_status() === PHP_SESSION_ACTIVE && !headers_sent()) {
            session_regenerate_id(true);
        }
    }

    public static function destroy(): void
    {
        self::start();
        $_SESSION = [];

        if (session_status() === PHP_SESSION_ACTIVE) {
            if (ini_get('session.use_cookies') && !headers_sent()) {
                $params = session_get_cookie_params();
                setcookie(
                    session_name(),
                    '',
                    time() - 42000,
                    $params['path'],
                    $params['domain'],
                    $params['secure'],
                    $params['httponly']
                );
            }
            session_destroy();
        }
    }

    public static function ageFlashData(): void
    {
        $_SESSION[self::FLASH_OLD_KEY] = $_SESSION[self::FLASH_KEY] ?? [];
        $_SESSION[self::FLASH_KEY] = [];
    }
}
