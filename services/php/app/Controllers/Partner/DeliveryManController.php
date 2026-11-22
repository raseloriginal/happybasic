<?php

declare(strict_types=1);

namespace App\Controllers\Partner;

use App\Models\DeliveryMan;
use App\Support\HttpError;
use Core\Request;
use Core\Response;

final class DeliveryManController extends PartnerController
{
    public function index(): Response
    {
        return $this->view('partner.delivery-men', [
            'title' => 'ডেলিভারিম্যান (DSR)',
            'activeNav' => 'delivery-men',
            'deliveryMen' => DeliveryMan::forPartner($this->partnerId()),
        ]);
    }

    public function store(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $dsr = DeliveryMan::present(DeliveryMan::create($this->partnerId(), $this->payload($request, true)));
            $this->log('Created', 'DSR', "Partner added DSR \"{$dsr['name']}\"");
            return ['message' => "DSR \"{$dsr['name']}\" যোগ করা হয়েছে।", 'dsr' => $dsr];
        });
    }

    public function update(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $dsr = DeliveryMan::present(DeliveryMan::update($this->partnerId(), $id, $this->payload($request, false)));
            $this->log('Updated', 'DSR', "Partner updated DSR \"{$dsr['name']}\"");
            return ['message' => "DSR \"{$dsr['name']}\" হালনাগাদ করা হয়েছে।", 'dsr' => $dsr];
        });
    }

    public function status(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $dsr = DeliveryMan::present(DeliveryMan::setStatus($this->partnerId(), $id, $this->statusFrom($request)));
            return ['message' => "DSR \"{$dsr['name']}\"-কে " . \App\Support\Bn::status($dsr['status']) . ' করা হয়েছে।', 'dsr' => $dsr];
        });
    }

    public function resetPassword(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $data = $this->check($request, ['password' => $this->passwordRule(true)]);
            $row = DeliveryMan::resetPassword($this->partnerId(), $id, (string) $data['password']);
            $this->log('Updated', 'DSR', "Partner reset password of DSR \"{$row['name']}\"");
            return ['message' => "\"{$row['name']}\"-এর পাসওয়ার্ড রিসেট হয়েছে। নতুন পাসওয়ার্ডটি DSR-কে দিন।"];
        });
    }

    public function destroy(int $id): Response
    {
        return $this->action(function () use ($id): array {
            $row = DeliveryMan::delete($this->partnerId(), $id);
            $this->log('Deleted', 'DSR', "Partner deleted DSR \"{$row['name']}\"");
            return ['message' => "DSR \"{$row['name']}\"-কে মুছে ফেলা হয়েছে।"];
        });
    }

    /** @return array<string, mixed> */
    private function payload(Request $request, bool $creating): array
    {
        $rules = [
            'name' => 'required|string|max:120',
            'number' => 'required|string|max:30',
            'salary' => 'required|numeric',
        ];
        if ($creating) {
            $rules['password'] = $this->passwordRule(true);
        }
        $data = $this->check($request, $rules);

        $salary = (float) $data['salary'];
        if ($salary < 0 || $salary > 9999999) {
            throw new HttpError('বেতন ০ থেকে ৯৯,৯৯,৯৯৯-এর মধ্যে হতে হবে।', 422, ['salary' => ['সঠিক বেতন দিন।']]);
        }

        return [
            'name' => (string) $data['name'],
            'phone' => $this->phone($data),
            'salary' => round($salary, 2),
            'password' => $creating ? (string) $data['password'] : null,
            'status' => $creating ? 'active' : $this->statusFrom($request),
        ];
    }
}
