<?php

declare(strict_types=1);

namespace App\Controllers\Partner;

use App\Models\DayClosing;
use Core\Request;
use Core\Response;

final class DayClosingController extends PartnerController
{
    public function index(Request $request): Response
    {
        $date = $this->dateQuery($request, 'date');

        return $this->view('partner.day-closing', [
            'title' => 'ডে ক্লোজিং',
            'activeNav' => 'day-closing',
            'date' => $date,
            'closing' => DayClosing::forDate($this->partnerId(), $date),
        ]);
    }
}
