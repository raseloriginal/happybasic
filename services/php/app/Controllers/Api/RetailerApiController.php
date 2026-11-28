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

    /** R3: ?range=7|30|month (&month=YYYY-MM for a past month). Without range: the old 60-day list + 7-day summary. */
    public function history(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $ids = RetailerAuthMiddleware::retailer()['ids'];
            $range = (string) $request->query('range', '');
            if ($range === '') {
                return ['rows' => RetailerPortal::history($ids), 'week' => RetailerPortal::weekSummary($ids)];
            }
            $month = (string) $request->query('month', '');
            if ($range === 'month') {
                $m = $month !== '' ? \DateTime::createFromFormat('!Y-m', $month) : new \DateTime('first day of this month');
                if ($m === false) {
                    throw new HttpError('মাস সঠিক নয়।', 422);
                }
                $from = $m->format('Y-m-01');
                $to = min($m->format('Y-m-t'), date('Y-m-d'));
            } else {
                $days = $range === '30' ? 30 : 7;
                $from = date('Y-m-d', strtotime('-' . ($days - 1) . ' days'));
                $to = date('Y-m-d');
            }

            return RetailerPortal::period($ids, $from, $to) + ['range' => $range, 'month' => substr($from, 0, 7), 'months' => RetailerPortal::months($ids)];
        });
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
