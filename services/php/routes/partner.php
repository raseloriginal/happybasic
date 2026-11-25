<?php

declare(strict_types=1);

use App\Controllers\PanelAuthController;
use App\Controllers\Partner\AttendanceController;
use App\Controllers\Partner\CompanyLedgerController;
use App\Controllers\Partner\DashboardController;
use App\Controllers\Partner\DayClosingController;
use App\Controllers\Partner\DeliveryManController;
use App\Controllers\Partner\DsrMonitorController;
use App\Controllers\Partner\DueController;
use App\Controllers\Partner\LiveController;
use App\Controllers\Partner\LotController;
use App\Controllers\Partner\OrderController;
use App\Controllers\Partner\ProductController;
use App\Controllers\Partner\SettlementController;
use App\Controllers\Partner\TripController;
use App\Middleware\CsrfMiddleware;
use App\Middleware\PartnerAuthMiddleware;
use Core\Router;

/** @var Router $router */

$router->group(['prefix' => 'partner', 'middleware' => [CsrfMiddleware::class]], static function (Router $router): void {
    $router->get('/login', [PanelAuthController::class, 'showPartner'])->name('partner.login');
    $router->post('/login', [PanelAuthController::class, 'partnerLogin']);
    $router->post('/logout', [PanelAuthController::class, 'partnerLogout'])->name('partner.logout');

    $router->group(['middleware' => [PartnerAuthMiddleware::class]], static function (Router $router): void {
        $router->get('/', [DashboardController::class, 'index'])->name('partner.index');
        $router->get('/dashboard', [DashboardController::class, 'index'])->name('partner.dashboard');

        $router->get('/trips', [TripController::class, 'index'])->name('partner.trips');
        $router->get('/trips/planner', [TripController::class, 'planner']);
        $router->post('/trips', [TripController::class, 'store']);
        $router->get('/trips/{id:\d+}', [TripController::class, 'show']);
        $router->post('/trips/{id:\d+}/items', [TripController::class, 'addItem']);
        $router->patch('/trips/{id:\d+}/items/{product:\d+}', [TripController::class, 'updateItem']);
        $router->delete('/trips/{id:\d+}/items/{product:\d+}', [TripController::class, 'removeItem']);
        $router->delete('/trips/{id:\d+}/srs/{sr:\d+}', [TripController::class, 'removeSr']);
        $router->post('/trips/{id:\d+}/dispatch', [TripController::class, 'dispatch']);

        $router->get('/settlements', [SettlementController::class, 'index'])->name('partner.settlements');
        $router->post('/settlements/{id:\d+}/approve', [SettlementController::class, 'approve']);
        $router->post('/settlements/{id:\d+}/send-back', [SettlementController::class, 'sendBack']);

        $router->get('/day-closing', [DayClosingController::class, 'index'])->name('partner.day-closing');

        $router->get('/lots', [LotController::class, 'index'])->name('partner.lots');
        $router->post('/lots', [LotController::class, 'store']);
        $router->delete('/lots/{id:\d+}', [LotController::class, 'destroy']);

        $router->get('/products', [ProductController::class, 'index'])->name('partner.products');
        $router->post('/products', [ProductController::class, 'store']);
        $router->post('/products/{id:\d+}', [ProductController::class, 'update']);
        $router->delete('/products/{id:\d+}', [ProductController::class, 'destroy']);

        $router->get('/company-ledger', [CompanyLedgerController::class, 'index'])->name('partner.company-ledger');
        $router->post('/company-ledger', [CompanyLedgerController::class, 'store']);
        $router->delete('/company-ledger/{id:\d+}', [CompanyLedgerController::class, 'destroy']);

        $router->get('/orders', [OrderController::class, 'index'])->name('partner.orders');

        $router->get('/live', [LiveController::class, 'index'])->name('partner.live');
        $router->get('/live/channels', [LiveController::class, 'channels']);
        $router->get('/live/team', [LiveController::class, 'team']);
        $router->get('/live/{id:-?\d+}/route', [LiveController::class, 'route']);

        $router->get('/dues', [DueController::class, 'index'])->name('partner.dues');
        $router->post('/dues/settings', [DueController::class, 'settings']);
        $router->post('/dues/limits/{retailer:\d+}', [DueController::class, 'shopLimit']);
        $router->post('/dues/{id:\d+}/approve', [DueController::class, 'approve']);
        $router->post('/dues/{id:\d+}/collect', [DueController::class, 'collect']);
        $router->post('/dues/{id:\d+}/return', [DueController::class, 'takeBack']);
        $router->post('/dues/{id:\d+}/undo', [DueController::class, 'undo']);

        $router->get('/attendance', [AttendanceController::class, 'index'])->name('partner.attendance');
        $router->post('/attendance/settings', [AttendanceController::class, 'save']);
        $router->post('/attendance/regenerate', [AttendanceController::class, 'regenerate']);

        $router->get('/dsr-monitor', [DsrMonitorController::class, 'index'])->name('partner.dsr-monitor');
        $router->post('/dsr-monitor/{id:\d+}/entries', [DsrMonitorController::class, 'addEntry']);
        $router->post('/dsr-monitor/{id:\d+}/days', [DsrMonitorController::class, 'setDay']);
        $router->delete('/dsr-monitor/entries/{kind}/{entry:\d+}', [DsrMonitorController::class, 'destroyEntry']);

        $router->get('/delivery-men', [DeliveryManController::class, 'index'])->name('partner.delivery-men');
        $router->post('/delivery-men', [DeliveryManController::class, 'store']);
        $router->put('/delivery-men/{id:\d+}', [DeliveryManController::class, 'update']);
        $router->patch('/delivery-men/{id:\d+}/status', [DeliveryManController::class, 'status']);
        $router->post('/delivery-men/{id:\d+}/password', [DeliveryManController::class, 'resetPassword']);
        $router->post('/delivery-men/{id:\d+}/photo', [DeliveryManController::class, 'photo']);
        $router->delete('/delivery-men/{id:\d+}', [DeliveryManController::class, 'destroy']);
    });
});
