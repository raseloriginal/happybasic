<?php

declare(strict_types=1);

use App\Controllers\AuthController;
use App\Controllers\HomeController;
use App\Middleware\CsrfMiddleware;
use App\Middleware\GuestMiddleware;
use Core\Router;

/** @var Router $router */

// Public pages
$router->get('/', [HomeController::class, 'index'])->name('home');

// Health & Service endpoints
$router->get('/api/health', [HomeController::class, 'health'])->name('api.health');
$router->get('/api/services/health', [HomeController::class, 'servicesHealth'])->name('api.services.health');

// User Auth pages (ready for backend phase)
$router->group(['middleware' => [GuestMiddleware::class, CsrfMiddleware::class]], static function (Router $router): void {
    $router->get('/login', [AuthController::class, 'showLogin'])->name('login');
    $router->post('/login', [AuthController::class, 'login']);
    $router->get('/register', [AuthController::class, 'showRegister'])->name('register');
    $router->post('/register', [AuthController::class, 'register']);
});

$router->post('/logout', [AuthController::class, 'logout'])
    ->middleware(CsrfMiddleware::class)
    ->name('logout');

// Admin routes (/admin/*)
require __DIR__ . '/admin.php';

// Partner routes (/partner/*)
require __DIR__ . '/partner.php';

// SR routes (/sr/*)
require __DIR__ . '/sr.php';

// DSR routes (/dsr/*)
require __DIR__ . '/dsr.php';
