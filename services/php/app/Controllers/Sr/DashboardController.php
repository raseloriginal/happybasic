<?php

declare(strict_types=1);

namespace App\Controllers\Sr;

use App\Middleware\SrAuthMiddleware;
use App\Models\Order;
use App\Models\SrStats;
use Core\Controller;
use Core\Response;

final class DashboardController extends Controller
{
    public function index(): Response
    {
        $sr = SrAuthMiddleware::sr();
        $today = date('Y-m-d');
        $profile = SrStats::profile($sr['id']);

        return $this->view('sr.dashboard', [
            'title' => 'ড্যাশবোর্ড',
            'activeNav' => 'dashboard',
            'dateLabel' => date('d M Y'),
            'profile' => $profile,
            'today' => SrStats::range($sr['id'], $today, $today),
            'month' => SrStats::range($sr['id'], date('Y-m-01'), $today),
            'dayCompleted' => Order::isDayCompleted($sr['id'], $today),
        ]);
    }
}
