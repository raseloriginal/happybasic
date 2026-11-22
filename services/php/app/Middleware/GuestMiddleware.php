<?php

declare(strict_types=1);

namespace App\Middleware;

use Core\Auth;
use Core\Request;
use Core\Response;

final class GuestMiddleware
{
    public function handle(Request $request, callable $next): Response
    {
        if (Auth::check()) {
            return Response::redirect('/dashboard');
        }

        return $next($request);
    }
}
