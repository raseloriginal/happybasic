<?php

declare(strict_types=1);

namespace App\Controllers\Dsr;

use App\Models\TripSettlement;
use Core\Request;
use Core\Response;

final class SettlementController extends DsrController
{
    public function index(): Response
    {
        $trip = $this->trip();

        return $this->view('dsr.settlement', [
            'title' => 'সেটেলমেন্ট',
            'activeNav' => 'settlement',
            'trip' => $trip,
            'settlement' => $trip ? TripSettlement::compute($trip['id']) : null,
        ]);
    }

    public function submit(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $note = trim((string) $request->input('note', ''));
            $res = TripSettlement::submit(
                $this->dsr(),
                array_map('intval', (array) $request->input('notes', [])),
                $note !== '' ? $note : null
            );
            $this->log('Updated', 'DSR submitted settlement, counted ৳' . $res['counted'] . ' (diff ' . $res['diff'] . ')');
            $status = $res['diff'] < 0
                ? \App\Support\Bn::money(abs((float) $res['diff'])) . ' কম'
                : ($res['diff'] > 0 ? \App\Support\Bn::money((float) $res['diff']) . ' বেশি' : 'মিলেছে');

            return ['message' => "সেটেলমেন্ট পার্টনারের যাচাইয়ের জন্য জমা হয়েছে (ক্যাশ {$status})।"];
        });
    }
}
