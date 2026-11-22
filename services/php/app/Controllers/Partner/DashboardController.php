<?php

declare(strict_types=1);

namespace App\Controllers\Partner;

use App\Models\PartnerDashboard;
use Core\Request;
use Core\Response;

final class DashboardController extends PartnerController
{
    public function index(Request $request): Response
    {
        $from = $this->dateQuery($request, 'from');
        $to = $this->dateQuery($request, 'to', $from);
        if ($to < $from) {
            [$from, $to] = [$to, $from];
        }

        return $this->view('partner.dashboard', [
            'title' => 'ড্যাশবোর্ড',
            'activeNav' => 'dashboard',
            'from' => $from,
            'to' => $to,
            'stats' => PartnerDashboard::stats($this->partnerId(), $from, $to),
        ]);
    }
}
