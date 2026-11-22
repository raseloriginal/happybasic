<?php

declare(strict_types=1);

namespace Core;

final class Csrf
{
    public const SESSION_KEY = '_csrf_token';
    public const FIELD_NAME = '_token';

    public static function token(): string
    {
        $token = Session::get(self::SESSION_KEY);
        if (!is_string($token) || $token === '') {
            $token = bin2hex(random_bytes(32));
            Session::set(self::SESSION_KEY, $token);
        }

        return $token;
    }

    public static function regenerate(): string
    {
        $token = bin2hex(random_bytes(32));
        Session::set(self::SESSION_KEY, $token);
        return $token;
    }

    public static function verify(?string $token): bool
    {
        $stored = Session::get(self::SESSION_KEY);
        if (!is_string($stored) || $stored === '' || !is_string($token) || $token === '') {
            return false;
        }

        return hash_equals($stored, $token);
    }

    public static function verifyRequest(Request $request): bool
    {
        $token = $request->input(self::FIELD_NAME)
            ?? $request->header('X-CSRF-TOKEN')
            ?? $request->header('X-XSRF-TOKEN');

        return self::verify(is_string($token) ? $token : null);
    }

    public static function field(): string
    {
        $token = htmlspecialchars(self::token(), ENT_QUOTES, 'UTF-8');
        return '<input type="hidden" name="' . self::FIELD_NAME . '" value="' . $token . '">';
    }

    public static function meta(): string
    {
        $token = htmlspecialchars(self::token(), ENT_QUOTES, 'UTF-8');
        return '<meta name="csrf-token" content="' . $token . '">';
    }
}
