<?php

declare(strict_types=1);

namespace App\Controllers\Api;

use App\Controllers\Concerns\JsonActions;
use App\Middleware\RetailerAuthMiddleware;
use App\Models\RetailerPortal;
use App\Support\HttpError;
use Core\Controller;
use Core\Database;
use Core\Request;
use Core\Response;

/** Retailer (shop) app screens: today's goods, history, invoices and notifications. Read-only. */
final class RetailerApiController extends Controller
{
    use JsonActions;

    public function today(): Response
    {
        return $this->action(function (): array {
            $r = RetailerAuthMiddleware::retailer();
            $events = RetailerPortal::notifications($r['ids'], $r['seen_at']);

            return [
                'date' => date('Y-m-d'),
                'shop' => ['name' => $r['name'], 'address' => $r['address'], 'phone' => $r['phone']],
                'day' => RetailerPortal::day($r['ids'], date('Y-m-d')),
                'unread' => count(array_filter($events, static fn(array $e): bool => $e['unread'])),
            ];
        });
    }

    public function history(): Response
    {
        return $this->action(fn(): array => ['rows' => RetailerPortal::history(RetailerAuthMiddleware::retailer()['ids'])]);
    }

    /** Orders (with invoice lines and totals) of one date. */
    public function day(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $r = RetailerAuthMiddleware::retailer();
            $date = (string) $request->query('date', date('Y-m-d'));
            $d = \DateTime::createFromFormat('!Y-m-d', $date);
            if ($d === false || $d->format('Y-m-d') !== $date) {
                throw new HttpError('তারিখ সঠিক নয়।', 422);
            }

            return ['date' => $date, 'date_label' => RetailerPortal::dateLabel($date)] + RetailerPortal::day($r['ids'], $date);
        });
    }

    public function notifications(): Response
    {
        return $this->action(function (): array {
            $r = RetailerAuthMiddleware::retailer();
            $events = RetailerPortal::notifications($r['ids'], $r['seen_at']);

            return ['events' => $events, 'unread' => count(array_filter($events, static fn(array $e): bool => $e['unread']))];
        });
    }

    public function markSeen(): Response
    {
        return $this->action(function (): array {
            Database::getInstance()->execute('UPDATE users SET notif_seen_at = NOW() WHERE id = ?', [RetailerAuthMiddleware::retailer()['user_id']]);

            return [];
        });
    }
}
