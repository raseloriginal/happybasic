<?php

declare(strict_types=1);

namespace App\Controllers\Partner;

use App\Models\Product;
use App\Models\Trip;
use App\Support\HttpError;
use Core\Request;
use Core\Response;

final class TripController extends PartnerController
{
    public function index(Request $request): Response
    {
        $pid = $this->partnerId();
        $date = $this->dateQuery($request, 'date');

        return $this->view('partner.trips', [
            'title' => 'ট্রিপ',
            'activeNav' => 'trips',
            'date' => $date,
            'trips' => Trip::forPartner($pid, $date),
            'products' => array_values(array_filter(Product::forPartner($pid, null, true), static fn(array $p): bool => $p['priced'])),
        ]);
    }

    /** SRs with orders on an order date + DSRs for a delivery date (New Trip modal). */
    public function planner(Request $request): Response
    {
        return $this->action(fn(): array => Trip::planner(
            $this->partnerId(),
            $this->dateInput($request, 'order_date'),
            $this->dateInput($request, 'delivery_date')
        ));
    }

    public function store(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $srIds = array_values(array_unique(array_filter(array_map('intval', (array) $request->input('sr_ids', [])))));
            $dsrId = $this->intInput($request, 'dsr_id');
            if ($srIds === [] || $dsrId === null) {
                throw new HttpError('অন্তত একজন SR এবং একজন DSR নির্বাচন করুন।', 422);
            }
            $trip = Trip::assign(
                $this->partnerId(),
                $this->dateInput($request, 'order_date'),
                $this->dateInput($request, 'delivery_date'),
                $dsrId,
                $srIds
            );
            $this->log('Updated', 'Trip', "Partner assigned " . count($srIds) . " SR(s) to {$trip['code']} ({$trip['dsr']})");

            return ['message' => \App\Support\Bn::num(count($srIds)) . " জন SR-এর অর্ডার {$trip['dsr']} (" . \App\Support\Bn::digits($trip['code']) . ")-কে দেওয়া হয়েছে।", 'trip' => $trip];
        });
    }

    public function show(int $id): Response
    {
        return $this->action(fn(): array => ['trip' => Trip::detail($this->partnerId(), $id)]);
    }

    public function updateItem(Request $request, int $id, int $product): Response
    {
        return $this->action(function () use ($request, $id, $product): array {
            $loaded = $request->input('loaded_pcs');
            $checked = $request->input('checked');
            $trip = Trip::updateItem(
                $this->partnerId(),
                $id,
                $product,
                is_numeric($loaded) ? (int) $loaded : null,
                $checked === null ? null : filter_var($checked, FILTER_VALIDATE_BOOL)
            );

            return ['trip' => $trip];
        });
    }

    public function addItem(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $trip = Trip::addItem($this->partnerId(), $id, (int) $request->input('product_id', 0), (int) $request->input('pcs', 0));
            return ['message' => 'অতিরিক্ত পণ্য ভ্যানে যোগ করা হয়েছে।', 'trip' => $trip];
        });
    }

    public function removeItem(int $id, int $product): Response
    {
        return $this->action(fn(): array => ['message' => 'অতিরিক্ত পণ্য সরানো হয়েছে।', 'trip' => Trip::removeItem($this->partnerId(), $id, $product)]);
    }

    public function removeSr(int $id, int $sr): Response
    {
        return $this->action(function () use ($id, $sr): array {
            $trip = Trip::unassignSr($this->partnerId(), $id, $sr);
            return ['message' => $trip === null ? 'SR সরানো হয়েছে। ট্রিপটি খালি থাকায় মুছে দেওয়া হয়েছে।' : 'SR ও তাঁর অর্ডারগুলো ট্রিপ থেকে সরানো হয়েছে।', 'trip' => $trip];
        });
    }

    public function dispatch(int $id): Response
    {
        return $this->action(function () use ($id): array {
            $trip = Trip::dispatch($this->partnerId(), $id);
            $this->log('Updated', 'Trip', "Partner dispatched {$trip['code']} ({$trip['dsr']})");
            return ['message' => "{$trip['dsr']} (" . \App\Support\Bn::digits($trip['code']) . ") ডিসপ্যাচ করা হয়েছে। FIFO নিয়মে স্টক বাদ দেওয়া হয়েছে।", 'trip' => $trip];
        });
    }
}
