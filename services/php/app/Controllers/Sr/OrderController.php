<?php

declare(strict_types=1);

namespace App\Controllers\Sr;

use App\Controllers\Concerns\JsonActions;
use App\Middleware\SrAuthMiddleware;
use App\Models\ActivityLog;
use App\Models\Order;
use App\Models\Product;
use App\Models\Retailer;
use App\Support\HttpError;
use Core\Controller;
use Core\Database;
use Core\Request;
use Core\Response;

/** SR order flow: retailers on the map, product cart, place / edit / cancel orders, complete the day. */
final class OrderController extends Controller
{
    use JsonActions;

    /** Map fallback when the browser gives no location yet (Dhaka). */
    private const DEFAULT_LOCATION = ['lat' => 23.8103, 'lng' => 90.4125];

    public function index(): Response
    {
        $sr = SrAuthMiddleware::sr();
        $loc = $this->lastLocation($sr) ?? self::DEFAULT_LOCATION;
        // Pass nearest ~80 retailers for instant first paint; full directory loads async via /sr/retailers with loader
        $retailers = Retailer::forSrMap($sr['partner_id'], $loc['lat'], $loc['lng'], 80);

        return $this->view('sr.order', [
            'title' => 'অর্ডার',
            'activeNav' => 'order',
            'srLocation' => $loc,
            // ids as strings: the order page compares them with DOM data-* values
            'retailers' => array_map(static fn(array $r): array => ['id' => (string) $r['id']] + $r, $retailers),
            'products' => $this->catalog($sr),
            'day' => Order::srDay($sr, date('Y-m-d')),
        ]);
    }

    public function retailers(): Response
    {
        return $this->action(function (): array {
            $sr = SrAuthMiddleware::sr();
            $rows = Retailer::forSrMap($sr['partner_id']);

            return [
                'retailers' => array_map(static fn(array $r): array => ['id' => (string) $r['id']] + $r, $rows),
            ];
        });
    }

    public function day(): Response
    {
        return $this->action(fn(): array => ['day' => Order::srDay(SrAuthMiddleware::sr(), date('Y-m-d'))]);
    }

    public function storeRetailer(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $sr = SrAuthMiddleware::sr();
            $data = $this->check($request, [
                'name' => 'required|string|max:150',
                'phone' => 'nullable|string|max:30',
                'address' => 'required|string|max:255',
                'lat' => 'required|numeric',
                'lng' => 'required|numeric',
            ]);
            $phone = null;
            if (!empty($data['phone'])) {
                $phone = $this->phone($data, 'phone');
            }
            $r = Retailer::create($sr['partner_id'], $sr['id'], [
                'name' => (string) $data['name'],
                'phone' => $phone,
                'address' => (string) $data['address'],
                'lat' => round((float) $data['lat'], 7),
                'lng' => round((float) $data['lng'], 7),
            ]);
            ActivityLog::record('Created', 'Retailer', "SR {$sr['name']} added retailer \"{$r['name']}\"", $sr['user_id']);

            return ['message' => "\"{$r['name']}\" দোকানটি যোগ হয়েছে।", 'retailer' => ['id' => (string) $r['id']] + $r];
        });
    }

    public function store(Request $request): Response
    {
        return $this->save($request, null);
    }

    public function update(Request $request, int $id): Response
    {
        return $this->save($request, $id);
    }

    public function destroy(int $id): Response
    {
        return $this->action(function () use ($id): array {
            $sr = SrAuthMiddleware::sr();
            $order = Order::cancel($sr, $id);
            return ['message' => "{$order['retailer_name_snapshot']}-এর অর্ডার বাতিল হয়েছে।", 'day' => Order::srDay($sr, date('Y-m-d'))];
        });
    }

    public function complete(): Response
    {
        return $this->action(function (): array {
            $sr = SrAuthMiddleware::sr();
            Order::completeDay($sr, date('Y-m-d'));
            ActivityLog::record('Updated', 'Order', "SR {$sr['name']} completed orders of " . date('Y-m-d'), $sr['user_id']);
            return ['message' => 'আজকের অর্ডার সম্পন্ন হয়েছে এবং ডেলিভারি ট্রিপের জন্য প্রস্তুত।', 'day' => Order::srDay($sr, date('Y-m-d'))];
        });
    }

    public function reopen(): Response
    {
        return $this->action(function (): array {
            $sr = SrAuthMiddleware::sr();
            Order::reopenDay($sr, date('Y-m-d'));
            return ['message' => 'আজকের দিন পুনরায় খোলা হয়েছে। এখন অর্ডার যোগ বা পরিবর্তন করতে পারবেন।', 'day' => Order::srDay($sr, date('Y-m-d'))];
        });
    }

    private function save(Request $request, ?int $orderId): Response
    {
        return $this->action(function () use ($request, $orderId): array {
            $sr = SrAuthMiddleware::sr();
            $retailerId = (int) $request->input('retailer_id', 0);
            $items = [];
            foreach ((array) $request->input('items', []) as $it) {
                if (!is_array($it)) {
                    continue;
                }
                $items[] = [
                    'product_id' => (int) ($it['product_id'] ?? 0),
                    'pcs' => (int) ($it['pcs'] ?? 0),
                    'total' => (float) ($it['total'] ?? -1),
                ];
            }
            if ($retailerId < 1) {
                throw new HttpError('একটি দোকান নির্বাচন করুন।', 422);
            }

            $res = Order::save($sr, $retailerId, $items, $orderId);
            ActivityLog::record($orderId ? 'Updated' : 'Created', 'Order', ($orderId ? 'Updated' : 'Placed') . " order {$res['order']['code']} for {$res['order']['retailer']}", $sr['user_id']);

            return [
                'message' => 'অর্ডার সংরক্ষিত হয়েছে।',
                'order' => $res['order'],
                'warnings' => $res['warnings'],
                'day' => Order::srDay($sr, date('Y-m-d')),
            ];
        });
    }

    /** @return list<array<string, mixed>> SR's company products that have a price (received through a lot) */
    private function catalog(array $sr): array
    {
        $out = [];
        foreach (Product::forPartner($sr['partner_id'], $sr['company_id'], true) as $p) {
            if (!$p['priced']) {
                continue;
            }
            $out[] = [
                'id' => (string) $p['id'],
                'name' => $p['name'],
                'unit_type' => $p['unit_type'],
                'qty_per_unit' => $p['qty_per_unit'],
                'unit_price' => $p['dealer_price_unit'],
                'pc_price' => $p['dealer_price_pc'],
                'available_pcs' => $p['available_pcs'],
                'image' => $p['image'],
                'tint' => $p['tint'],
                'code' => $p['code'],
            ];
        }

        return $out;
    }

    /** @return array{lat:float, lng:float}|null location of the SR's latest retailer, as a map start point */
    private function lastLocation(array $sr): ?array
    {
        $r = Database::getInstance()->fetch(
            'SELECT r.lat, r.lng FROM orders o JOIN retailers r ON r.id = o.retailer_id
             WHERE o.sr_id = ? ORDER BY o.id DESC LIMIT 1',
            [$sr['id']]
        ) ?? Database::getInstance()->fetch(
            'SELECT lat, lng FROM retailers WHERE partner_id = ? ORDER BY id DESC LIMIT 1',
            [$sr['partner_id']]
        );

        return $r !== null ? ['lat' => (float) $r['lat'], 'lng' => (float) $r['lng']] : null;
    }
}
