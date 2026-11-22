<?php

declare(strict_types=1);

namespace App\Middleware;

use Core\Auth;
use Core\Request;
use Core\Response;

final class AuthMiddleware
{
    public function handle(Request $request, callable $next): Response
    {
        if (Auth::guest()) {
            if ($request->expectsJson()) {
                return Response::json(['error' => 'Unauthenticated'], 401);
            }

            return Response::redirect('/login')
                ->with('error', 'Please sign in to continue.');
        }

        return $next($request);
    }
}
