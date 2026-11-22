<?php

declare(strict_types=1);

namespace App\Controllers\Admin;

use App\Middleware\AdminAuthMiddleware;
use App\Controllers\Concerns\JsonActions;
use Core\Controller;
use Core\Session;

abstract class AdminController extends Controller
{
    use JsonActions;

    protected function currentSessionToken(): ?string
    {
        $token = Session::get(AdminAuthMiddleware::TOKEN_KEY);
        return is_string($token) ? $token : null;
    }
}
