<?php

declare(strict_types=1);

namespace App\Controllers\Sr;

use App\Controllers\Concerns\JsonActions;
use App\Middleware\SrAuthMiddleware;
use App\Models\Order;
use App\Support\HttpError;
use Core\Controller;
use Core\Database;
use Core\Request;
use Core\Response;

final class HistoryController extends Controller
{
    use JsonActions;

    public function index(Request $request): Response
    {
        $sr = SrAuthMiddleware::sr();
        $date = $this->validDate((string) $request->input('date', ''));
        if ($date === null) {
            // Open on the latest day that has orders (today when nothing yet)
            $last = Database::getInstance()->fetch('SELECT MAX(order_date) AS d FROM orders WHERE sr_id = ?', [$sr['id']]);
            $date = $last['d'] ?? date('Y-m-d');
        }

        return $this->view('sr.history', [
            'title' => 'ইতিহাস',
            'activeNav' => 'history',
            'date' => $date,
            'today' => date('Y-m-d'),
            'orders' => Order::srHistory($sr, $date),
        ]);
    }

    /** Orders of one date (JSON) for the < date > navigator. */
    public function day(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $date = $this->validDate((string) $request->input('date', '')) ?? throw new HttpError('তারিখ সঠিক নয়।', 422);
            return ['date' => $date, 'orders' => Order::srHistory(SrAuthMiddleware::sr(), $date)];
        });
    }

    private function validDate(string $value): ?string
    {
        $d = \DateTime::createFromFormat('!Y-m-d', $value);
        return $d !== false && $d->format('Y-m-d') === $value ? $value : null;
    }
}
