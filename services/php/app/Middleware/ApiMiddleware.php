<?php

declare(strict_types=1);

namespace App\Middleware;

use Core\Request;
use Core\Response;

/**
 * Wraps every /api/v1 call: JSON-only answers, `no-store`, and the minimum app version gate.
 * The app sends `X-App-Version: <build number>`; builds below APP_MIN_VERSION_CODE get 426 and must update.
 */
final class ApiMiddleware
{
    public function handle(Request $request, callable $next): Response
    {
        $min = (int) env('APP_MIN_VERSION_CODE', 0);
        $have = (int) $request->header('X-App-Version', '0');
        if ($min > 0 && $have > 0 && $have < $min) {
            return Response::json(['ok' => false, 'code' => 'update_required', 'message' => 'অ্যাপের নতুন সংস্করণ এসেছে। চালিয়ে যেতে অ্যাপ আপডেট করুন।'], 426);
        }

        return $next($request)->header('Cache-Control', 'no-store')->header('X-Content-Type-Options', 'nosniff');
    }
}
