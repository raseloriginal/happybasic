<?php

declare(strict_types=1);

namespace App\Controllers\Dsr;

use App\Models\DsrDelivery;
use Core\Response;

final class VanStockController extends DsrController
{
    public function index(): Response
    {
        $trip = $this->trip();

        return $this->view('dsr.van_stock', [
            'title' => 'ভ্যান স্টক',
            'activeNav' => 'van_stock',
            'trip' => $trip,
            'products' => $trip ? array_values(DsrDelivery::vanStock($trip['id'])) : [],
        ]);
    }
}
