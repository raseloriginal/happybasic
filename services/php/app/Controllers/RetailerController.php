<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Controllers\Concerns\JsonActions;
use App\Middleware\RetailerAuthMiddleware;
use App\Models\RetailerPortal;
use App\Support\Bn;
use Core\Controller;
use Core\Database;
use Core\Request;
use Core\Response;

/** Retailer (দোকান) mobile panel: today's goods, invoices, history, notifications. */
final class RetailerController extends Controller
{
    use JsonActions;

    public function today(): Response
    {
        $r = RetailerAuthMiddleware::retailer();
        $day = RetailerPortal::day($r['ids'], date('Y-m-d'));
        $unread = count(array_filter(RetailerPortal::notifications($r['ids'], $r['seen_at']), static fn(array $e): bool => $e['unread']));

        return $this->view('retailer.today', ['title' => 'আজ', 'activeNav' => 'today', 'day' => $day, 'unread' => $unread, 'date' => date('Y-m-d')]);
    }

    public function history(): Response
    {
        $r = RetailerAuthMiddleware::retailer();

        return $this->view('retailer.history', [
            'title' => 'হিস্ট্রি', 'activeNav' => 'history', 'rows' => RetailerPortal::history($r['ids']), 'week' => RetailerPortal::weekSummary($r['ids']),
        ]);
    }

    public function invoice(Request $request): Response
    {
        return $this->invoicePage($request, 'retailer.invoice', 'today');
    }

    public function deliveryInvoice(Request $request): Response
    {
        return $this->invoicePage($request, 'retailer.delivery-invoice', 'history');
    }

    public function notifications(): Response
    {
        $r = RetailerAuthMiddleware::retailer();
        $events = RetailerPortal::notifications($r['ids'], $r['seen_at']);
        $orders = array_values(array_filter($events, static fn(array $e): bool => $e['kind'] === 'order'));
        $dms = array_values(array_filter($events, static fn(array $e): bool => $e['kind'] !== 'order'));
        $unread = static fn(array $list): int => count(array_filter($list, static fn(array $e): bool => $e['unread']));

        return $this->view('retailer.notifications', [
            'title' => 'নোটিফিকেশন', 'activeNav' => 'today', 'orders' => $orders, 'dms' => $dms,
            'unread' => $unread($events), 'unreadOrders' => $unread($orders), 'unreadDms' => $unread($dms),
        ]);
    }

    public function markSeen(): Response
    {
        return $this->action(function (): array {
            Database::getInstance()->execute('UPDATE users SET notif_seen_at = NOW() WHERE id = ?', [RetailerAuthMiddleware::retailer()['user_id']]);

            return [];
        });
    }

    private function invoicePage(Request $request, string $template, string $nav): Response
    {
        $r = RetailerAuthMiddleware::retailer();
        $date = (string) $request->query('date', date('Y-m-d'));
        if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $date) !== 1 || strtotime($date) === false) {
            $date = date('Y-m-d');
        }
        $day = RetailerPortal::day($r['ids'], $date);

        return $this->view($template, [
            'title' => 'ইনভয়েস', 'activeNav' => $nav, 'mode' => $template === 'retailer.invoice' ? 'order' : 'delivery',
            'date' => $date, 'dateLabel' => RetailerPortal::dateLabel($date),
            'orders' => $day['orders'], 'selected' => (int) $request->query('order', 0),
            'backUrl' => $nav === 'today' && $date === date('Y-m-d') ? url('/retailer') : url('/retailer/history'),
            'invoiceJson' => json_encode(['orders' => $day['orders'], 'selected' => (int) $request->query('order', 0), 'date' => $date, 'dateLabel' => RetailerPortal::dateLabel($date)],
                JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT),
        ]);
    }
}
