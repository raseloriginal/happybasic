<?php

declare(strict_types=1);

namespace App\Middleware;

use App\Models\UserSession;
use App\Support\PanelAuth;
use Core\Database;
use Core\Request;
use Core\Response;

/** Role-agnostic bearer gate for the app's shared endpoints (me, logout, password, device). */
final class ApiAuthMiddleware
{
    /** @var array<string, mixed>|null */
    private static ?array $user = null;

    public function handle(Request $request, callable $next): Response
    {
        $token = PanelAuth::bearer();
        $row = $token === null ? null : UserSession::findValid($token);
        $user = $row === null ? null : Database::getInstance()->fetch(
            "SELECT id, name, phone, role, status FROM users WHERE id = ? AND role IN ('sr', 'dsr', 'retailer') AND status = 'active' AND deleted_at IS NULL",
            [$row['user_id']]
        );
        if ($user === null) {
            return Response::json(['ok' => false, 'code' => 'unauthenticated', 'message' => 'সেশন শেষ হয়েছে। আবার লগইন করুন।'], 401);
        }

        UserSession::touch($row, true);
        $user['id'] = (int) $user['id'];
        self::$user = $user;

        return $next($request);
    }

    /** @return array<string, mixed> */
    public static function user(): array
    {
        return self::$user ?? throw new \LogicException('API user is not resolved.');
    }
}
