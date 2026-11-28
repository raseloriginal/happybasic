<?php

declare(strict_types=1);

namespace App\Controllers\Api;

use App\Controllers\Concerns\JsonActions;
use App\Controllers\Sr\OrderController;
use App\Middleware\SrAuthMiddleware;
use App\Models\Order;
use App\Models\Retailer;
use App\Models\SrStats;
use App\Support\ApiUrl;
use App\Support\HttpError;
use Core\Controller;
use Core\Database;
use Core\Request;
use Core\Response;

/**
 * SR endpoints that the web panel renders as pages. The order writes (retailers, orders, complete, reopen, photo)
 * are the web panel's own JSON actions, mounted under /api/v1/sr by routes/api.php.
 */
final class SrController extends Controller
{
    use JsonActions;

    /** Everything the order screen needs in one call: catalog, today's orders and the nearest shops. */
    public function bootstrap(): Response
    {
        return $this->action(function (): array {
            $sr = SrAuthMiddleware::sr();
            $today = date('Y-m-d');

            return [
                'server_time' => time(),
                'products' => (new OrderController())->catalog($sr),
                'retailers' => $this->retailers($sr),
                'day' => Order::srDay($sr, $today),
                'day_completed' => Order::isDayCompleted($sr['id'], $today),
            ];
        });
    }

    public function dashboard(): Response
    {
        return $this->action(function (): array {
            $sr = SrAuthMiddleware::sr();
            $today = date('Y-m-d');

            return [
                'date' => $today,
                'profile' => SrStats::profile($sr['id']),
                'today' => SrStats::range($sr['id'], $today, $today),
                'month' => SrStats::range($sr['id'], date('Y-m-01'), $today),
                'day_completed' => Order::isDayCompleted($sr['id'], $today),
                'no_order' => \App\Models\SrReport::noOrder((int) $sr['id'], $today),
                'notif_unread' => count(array_filter(\App\Models\SrReport::notifications($sr, Database::getInstance()->fetch('SELECT notif_seen_at FROM users WHERE id = ?', [$sr['user_id']])['notif_seen_at'] ?? null), static fn(array $e): bool => $e['unread'])),
                'duty' => \App\Models\SrReport::duty((int) $sr['id'], $today),
            ];
        });
    }

    public function history(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $sr = SrAuthMiddleware::sr();
            $date = $this->date((string) $request->query('date', ''));
            if ($date === null) {
                $last = Database::getInstance()->fetch('SELECT MAX(order_date) AS d FROM orders WHERE sr_id = ?', [$sr['id']]);
                $date = $last['d'] ?? date('Y-m-d');
            }

            return ['date' => $date, 'today' => date('Y-m-d'), 'orders' => Order::srHistory($sr, $date), 'no_order' => \App\Models\SrReport::noOrder((int) $sr['id'], $date)];
        });
    }

    public function profile(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $sr = SrAuthMiddleware::sr();
            $today = date('Y-m-d');
            $date = $this->date((string) $request->query('date', ''));
            if ($date === null) {
                $last = Database::getInstance()->fetch('SELECT MAX(order_date) AS d FROM orders WHERE sr_id = ?', [$sr['id']]);
                $date = $last['d'] ?? $today;
            }
            $profile = SrStats::profile($sr['id']);
            $profile['photo'] = ApiUrl::abs($sr['photo_path']);

            return [
                'date' => $date,
                'today' => $today,
                'day_summary' => SrStats::daySummary($sr['id'], $date),
                'profile' => $profile,
                'month' => SrStats::range($sr['id'], date('Y-m-01'), $today),
                'month_label' => date('F Y'),
                'no_order' => \App\Models\SrReport::noOrder((int) $sr['id'], $date),
                'month_goal' => \App\Models\SrReport::monthGoal($sr),
            ];
        });
    }

    /** SR day report (SRReport): duty, target, visits, order → delivery, shops, reasons, products, 7 days. */
    public function report(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $sr = SrAuthMiddleware::sr();

            return \App\Models\SrReport::build($sr, $this->date((string) $request->query('date', '')) ?? date('Y-m-d'));
        });
    }

    /** What happened to the SR's orders (delivered, short, cancelled) and new shops, newest first. */
    public function notifications(): Response
    {
        return $this->action(function (): array {
            $sr = SrAuthMiddleware::sr();
            $seen = Database::getInstance()->fetch('SELECT notif_seen_at FROM users WHERE id = ?', [$sr['user_id']])['notif_seen_at'] ?? null;
            $items = \App\Models\SrReport::notifications($sr, $seen);

            return ['items' => $items, 'unread' => count(array_filter($items, static fn(array $e): bool => $e['unread']))];
        });
    }

    public function markSeen(): Response
    {
        return $this->action(function (): array {
            $sr = SrAuthMiddleware::sr();
            Database::getInstance()->execute('UPDATE users SET notif_seen_at = NOW() WHERE id = ?', [$sr['user_id']]);

            return ['ok' => true];
        });
    }

    /** GPS points from the SR's phone while on duty. */
    public function track(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $sr = SrAuthMiddleware::sr();
            $saved = \App\Models\DsrTrack::store($sr, array_values((array) $request->input('points', [])), 'sr');
            if ($saved > 0) {
                \App\Services\Push::publish(["partner:{$sr['partner_id']}"], 'location');
            }

            return ['saved' => $saved, 'tracking' => true];
        });
    }

    /** @return list<array<string, mixed>> */
    private function retailers(array $sr): array
    {
        $rows = Retailer::forSrMap($sr['partner_id']);

        return array_map(static fn(array $r): array => ['id' => (string) $r['id']] + $r, $rows);
    }

    private function date(string $value): ?string
    {
        if ($value === '') {
            return null;
        }
        $d = \DateTime::createFromFormat('!Y-m-d', $value);
        if ($d === false || $d->format('Y-m-d') !== $value) {
            throw new HttpError('তারিখ সঠিক নয়।', 422);
        }

        return $value;
    }
}
