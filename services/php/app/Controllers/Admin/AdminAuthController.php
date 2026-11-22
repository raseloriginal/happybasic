<?php

declare(strict_types=1);

namespace App\Controllers\Admin;

use App\Middleware\AdminAuthMiddleware;
use App\Models\ActivityLog;
use App\Models\UserSession;
use App\Support\HttpError;
use Core\Auth;
use Core\Csrf;
use Core\Database;
use Core\Request;
use Core\Response;
use Core\Session;

final class AdminAuthController extends AdminController
{
    private const MAX_FAILED = 5;
    private const LOCK_MINUTES = 15;

    public function showLogin(): Response
    {
        $token = Session::get(AdminAuthMiddleware::TOKEN_KEY);
        if (is_string($token) && Auth::check() && UserSession::findValid($token) !== null && (Auth::user()['role'] ?? '') === 'admin') {
            return $this->redirect('/admin/dashboard');
        }

        return $this->view('admin.auth.login', ['title' => 'Admin Sign In']);
    }

    public function login(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $ip = $request->ip();
            if (ActivityLog::recentFailedLogins($ip, self::LOCK_MINUTES) >= self::MAX_FAILED) {
                throw new HttpError('Too many failed attempts. Please try again in ' . self::LOCK_MINUTES . ' minutes.', 429);
            }

            $data = $this->check($request, [
                'email' => 'required|email|max:191',
                'password' => 'required|string|max:255',
            ], ['email.email' => 'Enter a valid email address.']);

            $user = Database::getInstance()->fetch(
                "SELECT * FROM users WHERE email = ? AND role = 'admin' AND deleted_at IS NULL LIMIT 1",
                [strtolower((string) $data['email'])]
            );

            if ($user === null || !password_verify((string) $data['password'], (string) $user['password'])) {
                ActivityLog::record('Failed', 'Auth', 'Failed admin sign-in for ' . mb_substr((string) $data['email'], 0, 120), $user !== null ? (int) $user['id'] : null);
                throw new HttpError('Invalid email or password.', 422);
            }

            if ($user['status'] !== 'active') {
                throw new HttpError('This admin account is not active.', 403);
            }

            $remember = (bool) $request->input('remember', false);
            Auth::login($user);
            $token = UserSession::start((int) $user['id'], $remember, $request->ip(), (string) $request->header('User-Agent', ''));
            Session::set(AdminAuthMiddleware::TOKEN_KEY, $token);
            Session::set(AdminAuthMiddleware::REMEMBER_KEY, $remember);

            if ($remember) {
                setcookie(AdminAuthMiddleware::REMEMBER_COOKIE, $token, [
                    'expires' => time() + UserSession::REMEMBER_DAYS * 86400,
                    'path' => '/',
                    'secure' => $request->header('X-Forwarded-Proto') === 'https' || !empty($_SERVER['HTTPS']),
                    'httponly' => true,
                    'samesite' => 'Lax',
                ]);
            }

            ActivityLog::record('Login', 'Auth', 'Signed in to admin console', (int) $user['id']);

            return ['message' => 'Signed in.', 'redirect' => url('/admin/dashboard'), 'csrf' => Csrf::token()];
        });
    }

    public function logout(): Response
    {
        $token = Session::get(AdminAuthMiddleware::TOKEN_KEY);
        if (is_string($token)) {
            UserSession::revokeToken($token);
        }
        if (Auth::id() !== null) {
            ActivityLog::record('Logout', 'Auth', 'Signed out of admin console');
        }
        AdminAuthMiddleware::forget();

        return $this->redirect('/admin/login');
    }
}
