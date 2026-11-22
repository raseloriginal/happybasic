<?php

declare(strict_types=1);

namespace App\Middleware;

use App\Support\PanelAuth;
use Core\Database;
use Core\Request;
use Core\Response;
use Core\View;

/** SR panel gate: signed-in SR whose salesman record, partner and company are active. */
final class SrAuthMiddleware
{
    /** @var array<string, mixed>|null */
    private static ?array $sr = null;

    public function handle(Request $request, callable $next): Response
    {
        $user = PanelAuth::user('sr', 'sr');
        $sr = $user === null ? null : Database::getInstance()->fetch(
            "SELECT s.id, s.partner_id, s.company_id, s.code, s.name, s.phone, s.area, c.name AS company, p.name AS partner
             FROM salesmen s
             JOIN partners p ON p.id = s.partner_id AND p.status = 'active' AND p.deleted_at IS NULL
             JOIN companies c ON c.id = s.company_id AND c.status = 'active' AND c.deleted_at IS NULL
             WHERE s.user_id = ? AND s.status = 'active' AND s.deleted_at IS NULL",
            [$user['id']]
        );

        if ($sr === null) {
            PanelAuth::forget('sr');
            if ($request->expectsJson()) {
                return Response::json(['ok' => false, 'message' => 'Your session has ended. Please sign in again.', 'redirect' => url('/sr/login')], 401);
            }
            return Response::redirect('/sr/login');
        }

        foreach (['id', 'partner_id', 'company_id'] as $k) {
            $sr[$k] = (int) $sr[$k];
        }
        $sr['user_id'] = (int) $user['id'];
        self::$sr = $sr;
        View::share('currentSr', $sr);

        return $next($request);
    }

    /** @return array<string, mixed> */
    public static function sr(): array
    {
        return self::$sr ?? throw new \LogicException('SR context is not resolved.');
    }
}
