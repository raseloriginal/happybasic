<?php

declare(strict_types=1);

namespace App\Controllers\Dsr;

use App\Controllers\Concerns\JsonActions;
use App\Middleware\DsrAuthMiddleware;
use App\Models\ActivityLog;
use App\Models\DsrDelivery;
use Core\Controller;

/** Base for DSR panel controllers: the signed-in DSR and their open trip. */
abstract class DsrController extends Controller
{
    use JsonActions;

    /** @return array<string, mixed> */
    protected function dsr(): array
    {
        return DsrAuthMiddleware::dsr();
    }

    /** @return array<string, mixed>|null */
    protected function trip(): ?array
    {
        return DsrDelivery::activeTrip($this->dsr()['id']);
    }

    /** Date picked in the page's date bar (?date=YYYY-MM-DD), or null for "current". */
    protected function pickedDate(): ?string
    {
        $d = trim((string) ($_GET['date'] ?? ''));

        return preg_match('/^\d{4}-\d{2}-\d{2}$/', $d) === 1 && strtotime($d) !== false ? $d : null;
    }

    /** Trip shown on a page: the one on the picked date, else the open trip. @return array<string, mixed>|null */
    protected function viewTrip(): ?array
    {
        $date = $this->pickedDate();

        return $date !== null ? DsrDelivery::tripForDate($this->dsr()['id'], $date) : $this->trip();
    }

    /** Date the page is showing. @param array<string, mixed>|null $trip */
    protected function viewDate(?array $trip): string
    {
        return $this->pickedDate() ?? ($trip['date'] ?? date('Y-m-d'));
    }

    protected function log(string $action, string $detail): void
    {
        ActivityLog::record($action, 'Delivery', $detail, (int) $this->dsr()['user_id']);
    }
}
