<?php

declare(strict_types=1);

namespace App\Controllers\Partner;

use App\Models\DsrTrack;
use Core\Request;
use Core\Response;

/** Live map of the DSRs and the route of any past day. */
final class LiveController extends PartnerController
{
    public function index(Request $request): Response
    {
        $date = min($this->dateQuery($request, 'date'), date('Y-m-d'));

        return $this->view('partner.live', [
            'title' => 'লাইভ লোকেশন',
            'activeNav' => 'live',
            'date' => $date,
            'team' => DsrTrack::team($this->partnerId(), $date),
        ]);
    }

    public function team(Request $request): Response
    {
        return $this->action(fn(): array => ['team' => DsrTrack::team($this->partnerId(), $this->dateInput($request, 'date')), 'now' => time()]);
    }

    public function route(Request $request, int $id): Response
    {
        return $this->action(fn(): array => ['route' => DsrTrack::route($this->partnerId(), $id, $this->dateInput($request, 'date'))]);
    }
}
