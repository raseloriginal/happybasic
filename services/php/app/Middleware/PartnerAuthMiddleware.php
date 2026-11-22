<?php

declare(strict_types=1);

namespace App\Middleware;

use App\Support\PanelAuth;
use Core\Database;
use Core\Request;
use Core\Response;
use Core\View;

/** Partner panel gate: signed-in partner user whose partner record is active. */
final class PartnerAuthMiddleware
{
    /** @var array<string, mixed>|null */
    private static ?array $partner = null;

    public function handle(Request $request, callable $next): Response
    {
        $user = PanelAuth::user('partner', 'partner');
        $partner = $user === null ? null : Database::getInstance()->fetch(
            "SELECT p.id, p.name, p.phone, p.area_id, a.name AS area FROM partners p
             JOIN areas a ON a.id = p.area_id
             WHERE p.user_id = ? AND p.status = 'active' AND p.deleted_at IS NULL",
            [$user['id']]
        );

        if ($partner === null) {
            PanelAuth::forget('partner');
            if ($request->expectsJson()) {
                return Response::json(['ok' => false, 'message' => 'Your session has ended. Please sign in again.', 'redirect' => url('/partner/login')], 401);
            }
            return Response::redirect('/partner/login');
        }

        $partner['id'] = (int) $partner['id'];
        $partner['user_id'] = (int) $user['id'];
        self::$partner = $partner;
        View::share('currentPartner', $partner);

        return $next($request);
    }

    /** @return array<string, mixed> */
    public static function partner(): array
    {
        return self::$partner ?? throw new \LogicException('Partner context is not resolved.');
    }
}
