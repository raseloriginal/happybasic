<?php

declare(strict_types=1);

namespace App\Middleware;

use App\Support\PanelAuth;
use Core\Database;
use Core\Request;
use Core\Response;
use Core\View;

/** Retailer panel gate: signed-in retailer account that still owns at least one active shop record. */
final class RetailerAuthMiddleware
{
    /** @var array<string, mixed>|null */
    private static ?array $ctx = null;

    public function handle(Request $request, callable $next): Response
    {
        $user = PanelAuth::user('retailer', 'retailer');
        $shops = $user === null ? [] : Database::getInstance()->fetchAll(
            "SELECT r.id, r.name, r.address, r.phone FROM retailers r
             JOIN partners p ON p.id = r.partner_id AND p.status = 'active' AND p.deleted_at IS NULL
             WHERE r.phone = ? AND r.status = 'active' ORDER BY r.id DESC",
            [$user['phone']]
        );

        if ($shops === []) {
            PanelAuth::forget('retailer');
            if ($request->expectsJson()) {
                return Response::json(['ok' => false, 'message' => 'Your session has ended. Please sign in again.', 'redirect' => url('/retailer/login')], 401);
            }
            return Response::redirect('/retailer/login');
        }

        $seen = Database::getInstance()->fetch('SELECT notif_seen_at FROM users WHERE id = ?', [$user['id']]);
        self::$ctx = [
            'user_id' => (int) $user['id'],
            'ids' => array_map(static fn(array $s): int => (int) $s['id'], $shops),
            'name' => $shops[0]['name'],
            'address' => $shops[0]['address'],
            'phone' => $shops[0]['phone'],
            'seen_at' => $seen['notif_seen_at'] ?? null,
        ];
        View::share('currentRetailer', self::$ctx);

        return $next($request);
    }

    /** @return array<string, mixed> */
    public static function retailer(): array
    {
        return self::$ctx ?? throw new \LogicException('Retailer context is not resolved.');
    }
}
