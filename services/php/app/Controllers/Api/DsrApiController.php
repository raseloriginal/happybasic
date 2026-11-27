<?php

declare(strict_types=1);

namespace App\Controllers\Api;

use App\Controllers\Dsr\DsrController;
use App\Models\DsrDelivery;
use App\Models\DsrMonitor;
use App\Models\TripSettlement;
use App\Support\ApiUrl;
use Core\Request;
use Core\Response;

/**
 * DSR endpoints that the web panel renders as pages. Delivery state/stops, ready sales, damages, expenses
 * writes, GPS points, attendance scan and settlement submit are the web panel's own JSON actions,
 * mounted under /api/v1/dsr by routes/api.php.
 */
final class DsrApiController extends DsrController
{
    public function dashboard(Request $request): Response
    {
        return $this->action(function (): array {
            $trip = $this->viewTrip();
            $date = $this->viewDate($trip);
            $stops = $trip ? DsrDelivery::stops($trip) : [];
            $byStatus = array_count_values(array_column($stops, 'status'));
            $van = $trip ? DsrDelivery::vanStock($trip['id']) : [];

            return [
                'date' => $date,
                'today' => date('Y-m-d'),
                'dsr' => ['name' => $this->dsr()['name'], 'partner' => $this->dsr()['partner'], 'photo' => ApiUrl::abs($this->dsr()['photo_path'] ?? null)],
                'trip' => $trip,
                'attendance' => DsrMonitor::attendanceOn($this->dsr()['id'], $date),
                'stats' => [
                    'stops' => count($stops),
                    'delivered' => ($byStatus['Delivered'] ?? 0) + ($byStatus['Due'] ?? 0),
                    'due' => $byStatus['Due'] ?? 0,
                    'pending' => $byStatus['Pending'] ?? 0,
                    'cancelled' => $byStatus['Cancelled'] ?? 0,
                    'dispatched_pcs' => array_sum(array_column($van, 'dispatched_pcs')),
                    'available_pcs' => array_sum(array_column($van, 'available_pcs')),
                ],
                'settlement' => $trip ? TripSettlement::compute($trip['id'])['summary'] : null,
            ];
        });
    }

    /** Delivery screen in one call: trip, stops, van stock, damage products, cancel reasons and nearby shops. */
    public function delivery(Request $request): Response
    {
        return $this->action(function (): array {
            $trip = $this->viewTrip();
            $stops = $trip ? DsrDelivery::stops($trip) : [];

            return [
                'trip' => $trip,
                'selectedDate' => $this->viewDate($trip),
                'orders' => $stops,
                'vanStock' => $trip ? array_values(DsrDelivery::vanStock($trip['id'])) : [],
                'damageProducts' => $trip ? DsrDelivery::damageProducts($this->dsr()['partner_id'], $trip['sr_ids'] ?? []) : [],
                'cancelReasons' => DsrDelivery::CANCEL_REASONS,
                'server_time' => time(),
            ];
        });
    }

    public function vanStock(): Response
    {
        return $this->action(function (): array {
            $trip = $this->viewTrip();

            return ['trip' => $trip, 'selectedDate' => $this->viewDate($trip), 'products' => $trip ? array_values(DsrDelivery::vanStock($trip['id'])) : []];
        });
    }

    public function expenses(): Response
    {
        return $this->action(function (): array {
            $trip = $this->viewTrip();

            return [
                'trip' => $trip,
                'selectedDate' => $this->viewDate($trip),
                'expenses' => $trip ? DsrDelivery::expenses($trip['id']) : [],
                'categories' => DsrDelivery::EXPENSE_CATEGORIES,
            ];
        });
    }

    public function settlement(): Response
    {
        return $this->action(function (): array {
            $trip = $this->viewTrip();

            return ['trip' => $trip, 'selectedDate' => $this->viewDate($trip), 'settlement' => $trip ? TripSettlement::compute($trip['id']) : null];
        });
    }

    public function attendance(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $dsr = $this->dsr();
            $date = $this->pickedDate() ?? date('Y-m-d');
            $row = DsrMonitor::attendanceOn($dsr['id'], $date);
            $wage = null;
            foreach (DsrMonitor::overview($dsr['partner_id'], substr($date, 0, 7)) as $o) {
                if ($o['id'] === (int) $dsr['id']) {
                    $wage = [
                        'worked' => $o['totals']['worked'] ?? 0,
                        'daily_wage' => $o['daily_wage'],
                        'wage' => $o['wage'],
                        'over' => $o['over'],
                        'advance' => $o['advance'],
                        'short' => $o['short'],
                        'paid' => $o['paid'],
                        'net' => $o['net'],
                    ];
                }
            }

            return [
                'wage' => $wage,
                'selectedDate' => $date,
                'is_today' => $date === date('Y-m-d'),
                'today' => $row !== null && $row['checked_in_at'] !== null ? $row : null,
                'days' => DsrMonitor::historyFor($dsr['partner_id'], $dsr['id'], substr($date, 0, 7)),
            ];
        });
    }
}
