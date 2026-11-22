<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\HttpError;
use Core\Auth;
use Core\Database;
use Core\Model;

final class User extends Model
{
    protected static string $table = 'users';
    protected static string $primaryKey = 'id';
    protected static array $fillable = ['name', 'email', 'phone', 'password', 'role', 'status', 'deleted_at'];
    protected static array $hidden = ['password'];

    public static function register(string $name, string $email, string $plainPassword): int|string
    {
        return self::create([
            'name' => $name,
            'email' => strtolower(trim($email)),
            'password' => Auth::hashPassword($plainPassword),
        ]);
    }

    public static function assertPhoneAvailable(string $phone, ?int $ignoreUserId = null): void
    {
        $row = Database::getInstance()->fetch(
            'SELECT id FROM users WHERE phone = ? AND (? IS NULL OR id <> ?) LIMIT 1',
            [$phone, $ignoreUserId, $ignoreUserId]
        );

        if ($row !== null) {
            throw new HttpError('This phone number is already used by another account.', 422, [
                'number' => ['This phone number is already used by another account.'],
            ]);
        }
    }

    /** Creates a phone-login account for a partner / dealer / SR. */
    public static function createAccount(string $name, string $phone, string $password, string $role, string $status): int
    {
        self::assertPhoneAvailable($phone);

        return (int) self::create([
            'name' => $name,
            'phone' => $phone,
            'password' => Auth::hashPassword($password),
            'role' => $role,
            'status' => $status,
        ]);
    }

    public static function syncAccount(int $userId, string $name, string $phone, string $status, ?string $password = null): void
    {
        self::assertPhoneAvailable($phone, $userId);

        $data = ['name' => $name, 'phone' => $phone, 'status' => $status];
        if ($password !== null && $password !== '') {
            $data['password'] = Auth::hashPassword($password);
        }

        self::update($userId, $data);
        if ($status !== 'active') {
            UserSession::revokeAllForUser($userId);
        }
    }

    public static function setStatus(int $userId, string $status): void
    {
        self::update($userId, ['status' => $status]);
        if ($status !== 'active') {
            UserSession::revokeAllForUser($userId);
        }
    }

    /** Soft-deletes the login account and frees its phone number for reuse. */
    public static function softDelete(int $userId): void
    {
        Database::getInstance()->execute(
            "UPDATE users SET status = 'inactive', phone = NULL, deleted_at = NOW() WHERE id = ?",
            [$userId]
        );
        UserSession::revokeAllForUser($userId);
    }
}
