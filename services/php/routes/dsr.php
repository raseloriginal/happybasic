<?php

declare(strict_types=1);

use App\Controllers\Dsr\AttendanceController;
use App\Controllers\Dsr\DashboardController;
use App\Controllers\Dsr\DeliveryController;
use App\Controllers\Dsr\ExpenseController;
use App\Controllers\Dsr\SettlementController;
use App\Controllers\Dsr\VanStockController;
use App\Controllers\PanelAuthController;
use App\Middleware\CsrfMiddleware;
use App\Middleware\DsrAuthMiddleware;
use App\Middleware\IdempotencyMiddleware;
use Core\Router;

/** @var Router $router */

$router->group(['prefix' => 'dsr', 'middleware' => [CsrfMiddleware::class]], static function (Router $router): void {
    $router->get('/login', [PanelAuthController::class, 'showDsr'])->name('dsr.login');
    $router->post('/login', [PanelAuthController::class, 'dsrLogin']);
    $router->post('/logout', [PanelAuthController::class, 'dsrLogout'])->name('dsr.logout');

    $router->group(['middleware' => [DsrAuthMiddleware::class, IdempotencyMiddleware::class]], static function (Router $router): void {
        $router->get('/', [DashboardController::class, 'index'])->name('dsr.index');
        $router->get('/dashboard', [DashboardController::class, 'index'])->name('dsr.dashboard');

        $router->get('/delivery', [DeliveryController::class, 'index'])->name('dsr.delivery');
        $router->get('/delivery/state', [DeliveryController::class, 'state']);
        $router->get('/csrf', [DeliveryController::class, 'csrf']);
        $router->get('/retailers', [DeliveryController::class, 'retailers']);
        $router->post('/stops/{retailer:\d+}', [DeliveryController::class, 'saveStop']);
        $router->post('/stops/{retailer:\d+}/reset', [DeliveryController::class, 'resetStop']);
        $router->post('/damages', [DeliveryController::class, 'saveDamages']);
        $router->post('/ready-sales', [DeliveryController::class, 'readySale']);
        $router->delete('/ready-sales/{id:\d+}', [DeliveryController::class, 'deleteReadySale']);

        $router->get('/attendance', [AttendanceController::class, 'index'])->name('dsr.attendance');
        $router->post('/attendance', [AttendanceController::class, 'checkIn']);

        $router->get('/van-stock', [VanStockController::class, 'index'])->name('dsr.van_stock');

        $router->get('/settlement', [SettlementController::class, 'index'])->name('dsr.settlement');
        $router->post('/settlement', [SettlementController::class, 'submit']);

        $router->get('/expense', [ExpenseController::class, 'index'])->name('dsr.expense');
        $router->post('/expenses', [ExpenseController::class, 'store']);
        $router->delete('/expenses/{id:\d+}', [ExpenseController::class, 'destroy']);
    });
});
