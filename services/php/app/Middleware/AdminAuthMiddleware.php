<?php

declare(strict_types=1);

namespace App\Middleware;

use App\Models\UserSession;
use App\Services\SystemHealth;
use Core\Auth;
use Core\Request;
use Core\Response;
use Core\Session;
use Core\View;

/** Admin-only gate: valid PHP session (or remember cookie) + live, unrevoked tracked session. */
final class AdminAuthMiddleware
{
    public const TOKEN_KEY = 'admin_session_token';
    public const REMEMBER_KEY = 'admin_remember';
    public const REMEMBER_COOKIE = 'hb_admin_remember';

    public function handle(Request $request, callable $next): Response
    {
        $token = Session::get(self::TOKEN_KEY);
        $row = is_string($token) && Auth::check() ? UserSession::findValid($token) : null;

        if ($row === null && is_string($_COOKIE[self::REMEMBER_COOKIE] ?? null)) {
            $token = (string) $_COOKIE[self::REMEMBER_COOKIE];
            $row = UserSession::findValid($token);
            if ($row !== null) {
                Auth::login((int) $row['user_id']);
                Session::set(self::TOKEN_KEY, $token);
                Session::set(self::REMEMBER_KEY, true);
            }
        }

        $user = $row !== null ? Auth::user() : null;
        $valid = $user !== null
            && (int) $user['id'] === (int) $row['user_id']
            && $user['role'] === 'admin'
            && $user['status'] === 'active'
            && $user['deleted_at'] === null;

        if (!$valid) {
            self::forget();
            if ($request->expectsJson()) {
                return Response::json(['ok' => false, 'message' => 'Your session has ended. Please sign in again.', 'redirect' => url('/admin/login')], 401);
            }
            return Response::redirect('/admin/login');
        }

        UserSession::touch($row, (bool) Session::get(self::REMEMBER_KEY, false));
        View::share('adminUser', $user);
        View::share('systemStatus', SystemHealth::quickStatus());

        return $next($request);
    }

    public static function forget(): void
    {
        Auth::logout();
        Session::remove(self::TOKEN_KEY);
        Session::remove(self::REMEMBER_KEY);
        if (isset($_COOKIE[self::REMEMBER_COOKIE])) {
            setcookie(self::REMEMBER_COOKIE, '', ['expires' => time() - 3600, 'path' => '/', 'httponly' => true, 'samesite' => 'Lax']);
        }
    }
}
