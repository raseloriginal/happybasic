<?php

declare(strict_types=1);

namespace App\Controllers\Partner;

use App\Controllers\Concerns\JsonActions;
use App\Middleware\PartnerAuthMiddleware;
use App\Models\ActivityLog;
use App\Support\HttpError;
use Core\Controller;
use Core\Request;

/** Base for partner panel controllers: JSON helpers + the signed-in partner. */
abstract class PartnerController extends Controller
{
    use JsonActions;

    /** @return array<string, mixed> */
    protected function partner(): array
    {
        return PartnerAuthMiddleware::partner();
    }

    protected function partnerId(): int
    {
        return (int) $this->partner()['id'];
    }

    /** Activity log entry attributed to the partner's user account. */
    protected function log(string $action, string $module, string $detail): void
    {
        ActivityLog::record($action, $module, $detail, (int) $this->partner()['user_id']);
    }

    /** A Y-m-d date from input (query or body), or the default; invalid input raises 422. */
    protected function dateInput(Request $request, string $key, ?string $default = null): string
    {
        $value = trim((string) $request->input($key, ''));
        if ($value === '') {
            return $default ?? date('Y-m-d');
        }
        $d = \DateTime::createFromFormat('!Y-m-d', $value);
        if ($d === false || $d->format('Y-m-d') !== $value) {
            throw new HttpError('Invalid date.', 422, [$key => ['Invalid date.']]);
        }

        return $value;
    }

    /** Like dateInput() for GET pages: falls back to the default instead of failing. */
    protected function dateQuery(Request $request, string $key, ?string $default = null): string
    {
        try {
            return $this->dateInput($request, $key, $default);
        } catch (HttpError) {
            return $default ?? date('Y-m-d');
        }
    }

    protected function intInput(Request $request, string $key): ?int
    {
        $v = $request->input($key);
        return is_numeric($v) && (int) $v > 0 ? (int) $v : null;
    }
}
