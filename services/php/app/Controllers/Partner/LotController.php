<?php

declare(strict_types=1);

namespace App\Controllers\Partner;

use App\Models\Lot;
use App\Models\Product;
use App\Support\HttpError;
use Core\Request;
use Core\Response;

final class LotController extends PartnerController
{
    public function index(): Response
    {
        $pid = $this->partnerId();

        return $this->view('partner.lots', [
            'title' => 'লট ও স্টক',
            'activeNav' => 'lots',
            'companies' => Product::companyOptions($pid),
            'products' => Product::forPartner($pid, null, true),
            'lots' => Lot::forPartner($pid),
        ]);
    }

    public function store(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $data = $this->check($request, [
                'company_id' => 'required|integer',
                'notes' => 'nullable|string|max:255',
            ], ['company_id.required' => 'অনুগ্রহ করে একটি কোম্পানি নির্বাচন করুন।']);
            $date = $this->dateInput($request, 'lot_date');
            if ($date > date('Y-m-d')) {
                throw new HttpError('লটের তারিখ ভবিষ্যতের হতে পারবে না।', 422, ['lot_date' => ['ভবিষ্যতের তারিখ।']]);
            }

            $items = [];
            foreach ((array) $request->input('items', []) as $row) {
                if (!is_array($row)) {
                    continue;
                }
                $expire = (string) ($row['expire_date'] ?? '');
                $d = \DateTime::createFromFormat('!Y-m-d', $expire);
                if ($d === false || $d->format('Y-m-d') !== $expire) {
                    throw new HttpError('প্রতিটি সারিতে সঠিক মেয়াদ শেষের তারিখ দিন।', 422);
                }
                $items[] = [
                    'product_id' => (int) ($row['product_id'] ?? 0),
                    'pcs' => (int) ($row['pcs'] ?? 0),
                    'price_pc' => round((float) ($row['price_pc'] ?? 0), 4),
                    'expire_date' => $expire,
                ];
            }
            if ($items === []) {
                throw new HttpError('অন্তত একটি পণ্যের সারি যোগ করুন।', 422);
            }

            $lot = Lot::create($this->partnerId(), [
                'company_id' => (int) $data['company_id'],
                'received_date' => $date,
                'notes' => $data['notes'] ?: null,
                'items' => $items,
            ]);
            $this->log('Created', 'Lot', "Partner received lot {$lot['code']} ({$lot['company']})");

            return ['message' => 'লট ' . \App\Support\Bn::digits($lot['code']) . ' (' . \App\Support\Bn::num($lot['items_count']) . 'টি পণ্য) সংরক্ষিত হয়েছে।', 'lot' => $lot];
        });
    }

    public function destroy(int $id): Response
    {
        return $this->action(function () use ($id): array {
            $lot = Lot::delete($this->partnerId(), $id);
            $this->log('Deleted', 'Lot', "Partner deleted lot {$lot['code']}");
            return ['message' => 'লট ' . \App\Support\Bn::digits($lot['code']) . ' মুছে ফেলা হয়েছে এবং এর স্টক বাদ দেওয়া হয়েছে।'];
        });
    }
}
