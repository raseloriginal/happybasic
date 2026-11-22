<?php

declare(strict_types=1);

use App\Controllers\PanelAuthController;
use App\Controllers\Sr\DashboardController;
use App\Controllers\Sr\HistoryController;
use App\Controllers\Sr\OrderController;
use App\Controllers\Sr\ProfileController;
use App\Middleware\CsrfMiddleware;
use App\Middleware\SrAuthMiddleware;
use Core\Router;

/** @var Router $router */

$router->group(['prefix' => 'sr', 'middleware' => [CsrfMiddleware::class]], static function (Router $router): void {
    $router->get('/login', [PanelAuthController::class, 'showSr'])->name('sr.login');
    $router->post('/login', [PanelAuthController::class, 'srLogin']);
    $router->post('/logout', [PanelAuthController::class, 'srLogout'])->name('sr.logout');

    $router->group(['middleware' => [SrAuthMiddleware::class]], static function (Router $router): void {
        $router->get('/', [OrderController::class, 'index'])->name('sr.index');
        $router->get('/order', [OrderController::class, 'index'])->name('sr.order');
        $router->get('/retailers', [OrderController::class, 'retailers']);
        $router->get('/orders/today', [OrderController::class, 'day']);
        $router->post('/retailers', [OrderController::class, 'storeRetailer']);
        $router->post('/orders', [OrderController::class, 'store']);
        $router->put('/orders/{id:\d+}', [OrderController::class, 'update']);
        $router->delete('/orders/{id:\d+}', [OrderController::class, 'destroy']);
        $router->post('/orders/complete', [OrderController::class, 'complete']);
        $router->post('/orders/reopen', [OrderController::class, 'reopen']);

        $router->get('/dashboard', [DashboardController::class, 'index'])->name('sr.dashboard');
        $router->get('/history', [HistoryController::class, 'index'])->name('sr.history');
        $router->get('/history/day', [HistoryController::class, 'day']);
        $router->get('/profile', [ProfileController::class, 'index'])->name('sr.profile');
        $router->get('/profile/day', [ProfileController::class, 'day']);
        $router->post('/profile/password', [ProfileController::class, 'password']);
        $router->post('/profile/photo', [ProfileController::class, 'photo']);
    });
});
