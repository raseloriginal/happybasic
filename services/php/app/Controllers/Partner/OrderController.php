<?php

declare(strict_types=1);

namespace App\Controllers\Partner;

use App\Models\Order;
use App\Models\Product;
use Core\Database;
use Core\Request;
use Core\Response;

final class OrderController extends PartnerController
{
    private const STATUSES = ['pending', 'assigned', 'delivered', 'due', 'partial', 'cancelled'];

    public function index(Request $request): Response
    {
        $pid = $this->partnerId();
        $from = $this->dateQuery($request, 'from');
        $to = $this->dateQuery($request, 'to', $from);
        if ($to < $from) {
            [$from, $to] = [$to, $from];
        }
        $status = (string) $request->input('status', '');
        $filters = [
            'from' => $from,
            'to' => $to,
            'sr_id' => $this->intInput($request, 'sr'),
            'company_id' => $this->intInput($request, 'company'),
            'status' => in_array($status, self::STATUSES, true) ? $status : null,
        ];
        $orders = Order::forPartner($pid, $filters);
        $active = array_filter($orders, static fn(array $o): bool => $o['status_key'] !== 'cancelled');

        return $this->view('partner.orders', [
            'title' => 'অর্ডার',
            'activeNav' => 'orders',
            'filters' => $filters,
            'statuses' => self::STATUSES,
            'orders' => $orders,
            'totals' => [
                'count' => count($active),
                'value' => array_sum(array_column($active, 'sr_total')),
                'oc' => array_sum(array_column($active, 'oc')),
            ],
            'srs' => Database::getInstance()->fetchAll(
                'SELECT id, name FROM salesmen WHERE partner_id = ? AND deleted_at IS NULL ORDER BY name',
                [$pid]
            ),
            'companies' => Product::companyOptions($pid),
        ]);
    }
}
