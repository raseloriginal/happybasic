<?php

declare(strict_types=1);

namespace App\Middleware;

use App\Support\PanelAuth;
use Core\Database;
use Core\Request;
use Core\Response;
use Core\View;

/** DSR panel gate: signed-in delivery man whose record and partner are active. */
final class DsrAuthMiddleware
{
    /** @var array<string, mixed>|null */
    private static ?array $dsr = null;

    public function handle(Request $request, callable $next): Response
    {
        $user = PanelAuth::user('dsr', 'dsr');
        $dsr = $user === null ? null : Database::getInstance()->fetch(
            "SELECT dm.id, dm.partner_id, dm.code, dm.name, dm.phone, p.name AS partner
             FROM delivery_men dm
             JOIN partners p ON p.id = dm.partner_id AND p.status = 'active' AND p.deleted_at IS NULL
             WHERE dm.user_id = ? AND dm.status = 'active' AND dm.deleted_at IS NULL",
            [$user['id']]
        );

        if ($dsr === null) {
            PanelAuth::forget('dsr');
            if ($request->expectsJson()) {
                return Response::json(['ok' => false, 'message' => 'Your session has ended. Please sign in again.', 'redirect' => url('/dsr/login')], 401);
            }
            return Response::redirect('/dsr/login');
        }

        $dsr['id'] = (int) $dsr['id'];
        $dsr['partner_id'] = (int) $dsr['partner_id'];
        $dsr['user_id'] = (int) $user['id'];
        self::$dsr = $dsr;
        View::share('currentDsr', $dsr);

        return $next($request);
    }

    /** @return array<string, mixed> */
    public static function dsr(): array
    {
        return self::$dsr ?? throw new \LogicException('DSR context is not resolved.');
    }
}
