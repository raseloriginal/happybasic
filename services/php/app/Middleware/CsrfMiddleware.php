<?php

declare(strict_types=1);

namespace App\Middleware;

use Core\Csrf;
use Core\Request;
use Core\Response;

final class CsrfMiddleware
{
    private const SAFE_METHODS = ['GET', 'HEAD', 'OPTIONS'];

    public function handle(Request $request, callable $next): Response
    {
        if (in_array($request->method(), self::SAFE_METHODS, true)) {
            return $next($request);
        }

        if (!Csrf::verifyRequest($request)) {
            if ($request->expectsJson()) {
                return Response::json(['error' => 'Invalid CSRF token'], 419);
            }

            return Response::back('/')
                ->with('error', 'Session expired or invalid CSRF token. Please try again.');
        }

        return $next($request);
    }
}
