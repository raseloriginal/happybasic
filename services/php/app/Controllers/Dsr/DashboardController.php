<?php

declare(strict_types=1);

namespace App\Controllers\Dsr;

use App\Models\DsrDelivery;
use App\Models\TripSettlement;
use Core\Response;

final class DashboardController extends DsrController
{
    public function index(): Response
    {
        $trip = $this->trip();
        $stops = $trip ? DsrDelivery::stops($trip) : [];
        $byStatus = array_count_values(array_column($stops, 'status'));
        $van = $trip ? DsrDelivery::vanStock($trip['id']) : [];

        return $this->view('dsr.dashboard', [
            'title' => 'ড্যাশবোর্ড',
            'activeNav' => 'dashboard',
            'trip' => $trip,
            'stats' => [
                'stops' => count($stops),
                'delivered' => ($byStatus['Delivered'] ?? 0) + ($byStatus['Due'] ?? 0),
                'due' => $byStatus['Due'] ?? 0,
                'pending' => $byStatus['Pending'] ?? 0,
                'cancelled' => $byStatus['Cancelled'] ?? 0,
                'dispatched_pcs' => array_sum(array_column($van, 'dispatched_pcs')),
                'available_pcs' => array_sum(array_column($van, 'available_pcs')),
            ],
            'settlement' => $trip ? TripSettlement::compute($trip['id'])['summary'] : null,
        ]);
    }
}
