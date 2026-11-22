<?php

declare(strict_types=1);

namespace Core;

use App\Models\User;

final class Auth
{
    private const SESSION_KEY = '_auth_user_id';

    /** @var class-string<Model> */
    private static string $userModel = User::class;
    /** @var array<string, mixed>|null */
    private static ?array $cachedUser = null;

    /** @param class-string<Model> $model */
    public static function setUserModel(string $model): void
    {
        self::$userModel = $model;
        self::$cachedUser = null;
    }

    public static function attempt(string $email, string $password): bool
    {
        $user = (self::$userModel)::findBy('email', $email, true);
        if ($user === null || !isset($user['password']) || !is_string($user['password'])) {
            return false;
        }

        if (!password_verify($password, $user['password'])) {
            return false;
        }

        self::login($user);
        return true;
    }

    /** @param array<string, mixed>|int|string $user */
    public static function login(array|int|string $user): void
    {
        Session::regenerate();

        if (is_array($user)) {
            $id = $user['id'] ?? null;
            Session::set(self::SESSION_KEY, $id);
            unset($user['password']);
            self::$cachedUser = $user;
            return;
        }

        Session::set(self::SESSION_KEY, $user);
        self::$cachedUser = null;
    }

    public static function logout(): void
    {
        self::$cachedUser = null;
        Session::remove(self::SESSION_KEY);
        Session::regenerate();
        Csrf::regenerate();
    }

    public static function id(): int|string|null
    {
        $id = Session::get(self::SESSION_KEY);
        return (is_int($id) || is_string($id)) ? $id : null;
    }

    public static function check(): bool
    {
        return self::id() !== null && self::user() !== null;
    }

    public static function guest(): bool
    {
        return !self::check();
    }

    /** @return array<string, mixed>|null */
    public static function user(): ?array
    {
        $id = self::id();
        if ($id === null) {
            return null;
        }

        if (self::$cachedUser !== null && (self::$cachedUser['id'] ?? null) == $id) {
            return self::$cachedUser;
        }

        self::$cachedUser = (self::$userModel)::find($id);
        return self::$cachedUser;
    }

    public static function hashPassword(string $password): string
    {
        return password_hash($password, PASSWORD_DEFAULT);
    }

    public static function flushCache(): void
    {
        self::$cachedUser = null;
    }
}
