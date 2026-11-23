<?php

declare(strict_types=1);

namespace App\Controllers\Dsr;

use App\Models\DsrDelivery;
use App\Support\HttpError;
use Core\Request;
use Core\Response;

final class DeliveryController extends DsrController
{
    /** Map fallback when the browser gives no location (Dhaka). */
    private const DEFAULT_LOCATION = ['lat' => 23.8103, 'lng' => 90.4125];

    public function index(?Request $request = null): Response
    {
        $reqDate = trim((string) ($request?->query('date', '') ?? ($_GET['date'] ?? '')));
        $hasValidDate = preg_match('/^\d{4}-\d{2}-\d{2}$/', $reqDate) === 1;
        $trip = $hasValidDate ? DsrDelivery::tripForDate($this->dsr()['id'], $reqDate) : $this->trip();
        $selectedDate = $hasValidDate ? $reqDate : ($trip['date'] ?? date('Y-m-d'));

        $stops = $trip ? DsrDelivery::stops($trip) : [];
        $first = $stops[0] ?? null;
        $loc = $first && ($first['lat'] || $first['lng']) ? ['lat' => $first['lat'], 'lng' => $first['lng']] : self::DEFAULT_LOCATION;

        return $this->view('dsr.delivery', [
            'title' => 'ডেলিভারি',
            'activeNav' => 'delivery',
            'trip' => $trip,
            'selectedDate' => $selectedDate,
            'dsrLocation' => $loc,
            'cancelReasons' => DsrDelivery::CANCEL_REASONS,
            'orders' => $stops,
            'vanStock' => $trip ? array_values(DsrDelivery::vanStock($trip['id'])) : [],
            'retailers' => DsrDelivery::retailers($this->dsr()['partner_id'], $trip['sr_ids'] ?? [], $loc['lat'], $loc['lng'], 80),
            'damageProducts' => $trip ? DsrDelivery::damageProducts($this->dsr()['partner_id'], $trip['sr_ids'] ?? []) : [],
        ]);
    }

    /** Full active retailer directory loaded asynchronously for Banglish search inside Ready Sale. */
    public function retailers(): Response
    {
        return $this->action(fn(): array => [
            'retailers' => DsrDelivery::retailers($this->dsr()['partner_id']),
        ]);
    }

    /** Current CSRF token: the offline sync asks for it when the queued page's token has gone stale. */
    public function csrf(): Response
    {
        return $this->action(fn(): array => ['token' => csrf_token()]);
    }

    /** Fresh stops + van stock (optionally filtered by trip_date=YYYY-MM-DD). */
    public function state(?Request $request = null): Response
    {
        return $this->action(function () use ($request): array {
            $reqDate = trim((string) ($request?->query('date', '') ?? ''));
            $date = preg_match('/^\d{4}-\d{2}-\d{2}$/', $reqDate) === 1 ? $reqDate : null;

            return $this->stateData(false, $date);
        });
    }

    public function saveStop(Request $request, int $retailer): Response
    {
        return $this->action(function () use ($request, $retailer): array {
            $orders = [];
            foreach ((array) $request->input('orders', []) as $o) {
                if (!is_array($o)) {
                    continue;
                }
                $orders[] = [
                    'id' => (int) ($o['id'] ?? 0),
                    'cancelled' => (bool) ($o['cancelled'] ?? false),
                    'items' => array_map(static fn($it): array => [
                        'product_id' => (int) ($it['product_id'] ?? 0),
                        'pcs' => (int) ($it['pcs'] ?? 0),
                    ], array_filter((array) ($o['items'] ?? []), 'is_array')),
                ];
            }
            $damages = array_map(static fn($d): array => [
                'order_id' => (int) ($d['order_id'] ?? 0),
                'product_id' => (int) ($d['product_id'] ?? 0),
                'pcs' => (int) ($d['pcs'] ?? 0),
            ], array_filter((array) $request->input('damages', []), 'is_array'));

            $reason = trim((string) $request->input('cancel_reason', ''));
            if ($reason !== '' && !in_array(explode(' (', $reason)[0], DsrDelivery::CANCEL_REASONS, true)) {
                throw new HttpError('তালিকা থেকে বাতিলের কারণ নির্বাচন করুন।', 422);
            }

            DsrDelivery::saveStop($this->dsr(), $retailer, [
                'orders' => $orders,
                'damages' => array_values($damages),
                'paid' => (float) $request->input('paid', 0),
                'cancel_reason' => mb_substr($reason, 0, 240),
            ]);
            $this->log('Updated', "DSR saved delivery for retailer #{$retailer}");

            return ['message' => 'ডেলিভারি সংরক্ষিত হয়েছে।'] + $this->stateData();
        });
    }

    public function resetStop(int $retailer): Response
    {
        return $this->action(function () use ($retailer): array {
            DsrDelivery::resetStop($this->dsr(), $retailer);
            $this->log('Updated', "DSR reset delivery for retailer #{$retailer}");
            return ['message' => 'ডেলিভারি পূর্বাবস্থায় নেওয়া হয়েছে। দোকানটি আবার অপেক্ষমান তালিকায় আছে।'] + $this->stateData();
        });
    }

    public function readySale(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $new = null;
            if ((string) $request->input('mode', 'existing') === 'new') {
                $data = $this->check($request, [
                    'name' => 'required|string|max:150',
                    'phone' => 'nullable|string|max:30',
                    'address' => 'nullable|string|max:255',
                    'lat' => 'required|numeric',
                    'lng' => 'required|numeric',
                ]);
                $addr = trim((string) ($data['address'] ?? ''));
                $new = [
                    'name' => (string) $data['name'],
                    'phone' => !empty($data['phone']) ? $this->phone($data, 'phone') : null,
                    'address' => $addr !== '' ? $addr : 'স্পট লোকেশন',
                    'lat' => round((float) $data['lat'], 7),
                    'lng' => round((float) $data['lng'], 7),
                ];
            }

            $items = [];
            foreach ((array) $request->input('items', []) as $it) {
                if (!is_array($it)) {
                    continue;
                }
                $items[] = [
                    'product_id' => (int) ($it['product_id'] ?? 0),
                    'pcs' => (int) ($it['pcs'] ?? 0),
                ];
            }

            $res = DsrDelivery::readySale($this->dsr(), [
                'retailer_id' => $new === null ? (int) $request->input('retailer_id', 0) : null,
                'new_retailer' => $new,
                'items' => $items,
                'product_id' => (int) $request->input('product_id', 0),
                'pcs' => (int) $request->input('pcs', 0),
            ]);
            $this->log('Created', "DSR ready sale to {$res['retailer']} ৳{$res['total']}");

            $payload = [
                'message' => "{$res['retailer']}-এ রেডি সেল: " . \App\Support\Bn::money((float) $res['total']),
                'receipt' => [
                    'retailer' => $res['retailer'],
                    'total' => $res['total'],
                    'codes' => $res['codes'],
                    'items' => $res['items'],
                ],
            ] + $this->stateData(false);

            if ($res['new_retailer'] !== null) {
                $payload['newRetailer'] = $res['new_retailer'];
            }

            return $payload;
        });
    }

    public function deleteReadySale(int $id): Response
    {
        return $this->action(function () use ($id): array {
            DsrDelivery::deleteReadySale($this->dsr(), $id);
            return ['message' => 'রেডি সেল মুছে ফেলা হয়েছে।'] + $this->stateData();
        });
    }

    public function saveDamages(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $retailerId = (int) $request->input('retailer_id', 0);
            if ($retailerId < 1) {
                throw new HttpError('একটি দোকান নির্বাচন করুন।', 422);
            }
            $items = [];
            foreach ((array) $request->input('items', []) as $it) {
                if (!is_array($it)) {
                    continue;
                }
                $items[] = [
                    'product_id' => (int) ($it['product_id'] ?? 0),
                    'pcs' => (int) ($it['pcs'] ?? 0),
                ];
            }

            $res = DsrDelivery::saveDamages($this->dsr(), $retailerId, $items);
            $this->log('Updated', "DSR submitted {$res['count']} damage item(s) for {$res['retailer']} ৳{$res['total']}");

            $msg = $res['count'] > 0
                ? "{$res['retailer']}-এ ড্যামেজ সাবমিট হয়েছে (" . \App\Support\Bn::digits($res['count']) . "টি পণ্য · " . \App\Support\Bn::money($res['total']) . ")"
                : "{$res['retailer']}-এর ড্যামেজ তালিকা পরিষ্কার করা হয়েছে।";

            return ['message' => $msg, 'damageResult' => $res] + $this->stateData();
        });
    }

    /** @return array<string, mixed> */
    private function stateData(bool $withRetailers = false, ?string $date = null): array
    {
        $trip = $date !== null ? DsrDelivery::tripForDate($this->dsr()['id'], $date) : $this->trip();
        $data = [
            'trip' => $trip,
            'selectedDate' => $date ?? ($trip['date'] ?? date('Y-m-d')),
            'orders' => $trip ? DsrDelivery::stops($trip) : [],
            'vanStock' => $trip ? array_values(DsrDelivery::vanStock($trip['id'])) : [],
            'damageProducts' => $trip ? DsrDelivery::damageProducts($this->dsr()['partner_id'], $trip['sr_ids'] ?? []) : [],
        ];
        if ($withRetailers) {
            $data['retailers'] = DsrDelivery::retailers($this->dsr()['partner_id']);
        }

        return $data;
    }
}
