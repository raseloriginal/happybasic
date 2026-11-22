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

    protected function log(string $action, string $detail): void
    {
        ActivityLog::record($action, 'Delivery', $detail, (int) $this->dsr()['user_id']);
    }
}
