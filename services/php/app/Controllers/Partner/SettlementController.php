<?php

declare(strict_types=1);

namespace App\Controllers\Partner;

use App\Models\TripSettlement;
use App\Support\HttpError;
use Core\Request;
use Core\Response;

final class SettlementController extends PartnerController
{
    public function index(Request $request): Response
    {
        $to = $this->dateQuery($request, 'to');
        $from = $this->dateQuery($request, 'from', date('Y-m-d', strtotime($to . ' -6 days')));
        if ($to < $from) {
            [$from, $to] = [$to, $from];
        }

        return $this->view('partner.settlements', [
            'title' => 'ট্রিপ সেটেলমেন্ট',
            'activeNav' => 'settlements',
            'from' => $from,
            'to' => $to,
            'settlements' => TripSettlement::forPartner($this->partnerId(), $from, $to),
        ]);
    }

    public function approve(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $res = TripSettlement::approve($this->partnerId(), $id, (int) $this->partner()['user_id'], [
                'cash_received' => $request->input('cash_received'),
                'returns' => (array) $request->input('returns', []),
                'damage_amount' => $request->input('damage_amount'),
                'damage_note' => $request->input('damage_note'),
            ]);
            $this->log(
                'Approved',
                'Settlement',
                "Partner settled trip #{$id}: cash ৳{$res['cash_received']}, restocked {$res['restocked_pcs']} pcs, damage ৳{$res['damage_amount']}"
            );
            return ['message' => 'সেটেলমেন্ট কনফার্ম হয়েছে: ' . \App\Support\Bn::money($res['cash_received'], true) . ' ক্যাশ, ' . \App\Support\Bn::num($res['restocked_pcs']) . ' পিস স্টকে ফেরত।'];
        });
    }

    public function sendBack(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $note = trim((string) $request->input('note', ''));
            if ($note === '') {
                throw new HttpError('DM-কে কী ঠিক করতে হবে তা লিখুন।', 422, ['note' => ['প্রয়োজনীয়।']]);
            }
            TripSettlement::sendBack($this->partnerId(), $id, mb_substr($note, 0, 255));
            $this->log('Updated', 'Settlement', "Partner sent back settlement of trip #{$id}");
            return ['message' => 'সেটেলমেন্ট হিসাব DM-এর কাছে ফেরত পাঠানো হয়েছে।'];
        });
    }
}
