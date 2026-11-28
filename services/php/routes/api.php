<?php

declare(strict_types=1);

use App\Controllers\Api\AppReleaseController;
use App\Controllers\Api\AuthController;
use App\Controllers\Api\DsrApiController;
use App\Controllers\Api\RetailerApiController;
use App\Controllers\Api\SrController;
use App\Controllers\Dsr\AttendanceController as DsrAttendance;
use App\Controllers\Dsr\DeliveryController as DsrDelivery;
use App\Controllers\Dsr\ExpenseController as DsrExpense;
use App\Controllers\Dsr\SettlementController as DsrSettlement;
use App\Controllers\Dsr\TrackController as DsrTrack;
use App\Controllers\Sr\OrderController as SrOrder;
use App\Controllers\Sr\ProfileController as SrProfile;
use App\Middleware\ApiAuthMiddleware;
use App\Middleware\ApiMiddleware;
use App\Middleware\DsrAuthMiddleware;
use App\Middleware\IdempotencyMiddleware;
use App\Middleware\RetailerAuthMiddleware;
use App\Middleware\SrAuthMiddleware;
use Core\Router;

/**
 * Mobile app API — /api/v1. Bearer-token auth (no cookies, no CSRF).
 * Writes accept an `X-Op-Id` header: a retried / offline-queued write runs at most once.
 * Business rules are the web panels' own (same models), so app and web can never disagree.
 *
 * @var Router $router
 */
$router->group(['prefix' => 'api/v1', 'middleware' => [ApiMiddleware::class]], static function (Router $router): void {
    // Public
    $router->get('/ping', static fn() => \Core\Response::json(['ok' => true, 'time' => time()]));
    $router->get('/app/version', [AppReleaseController::class, 'latest']);
    $router->post('/auth/login', [AuthController::class, 'login']);

    // Any signed-in role
    $router->group(['middleware' => [ApiAuthMiddleware::class]], static function (Router $router): void {
        $router->get('/auth/me', [AuthController::class, 'me']);
        $router->post('/auth/logout', [AuthController::class, 'logout']);
        $router->post('/auth/password', [AuthController::class, 'password']);
        $router->post('/device', [AuthController::class, 'device']);
        $router->get('/auth/channels', [AuthController::class, 'channels']);
    });

    // SR
    $router->group(['prefix' => 'sr', 'middleware' => [SrAuthMiddleware::class, IdempotencyMiddleware::class]], static function (Router $router): void {
        $router->get('/bootstrap', [SrController::class, 'bootstrap']);
        $router->get('/dashboard', [SrController::class, 'dashboard']);
        $router->get('/history', [SrController::class, 'history']);
        $router->get('/profile', [SrController::class, 'profile']);
        $router->get('/report', [SrController::class, 'report']);
        $router->get('/notifications', [SrController::class, 'notifications']);
        $router->post('/notifications/seen', [SrController::class, 'markSeen']);
        $router->post('/profile/photo', [SrProfile::class, 'photo']);
        $router->post('/track', [SrController::class, 'track']);

        $router->get('/retailers', [SrOrder::class, 'retailers']);
        $router->post('/retailers', [SrOrder::class, 'storeRetailer']);
        $router->get('/orders/today', [SrOrder::class, 'day']);
        $router->post('/orders', [SrOrder::class, 'store']);
        $router->put('/orders/{id:\d+}', [SrOrder::class, 'update']);
        $router->delete('/orders/{id:\d+}', [SrOrder::class, 'destroy']);
        $router->post('/orders/complete', [SrOrder::class, 'complete']);
        $router->post('/orders/reopen', [SrOrder::class, 'reopen']);
    });

    // DSR
    $router->group(['prefix' => 'dsr', 'middleware' => [DsrAuthMiddleware::class, IdempotencyMiddleware::class]], static function (Router $router): void {
        $router->get('/dashboard', [DsrApiController::class, 'dashboard']);
        $router->get('/delivery', [DsrApiController::class, 'delivery']);
        $router->get('/van-stock', [DsrApiController::class, 'vanStock']);
        $router->get('/expenses', [DsrApiController::class, 'expenses']);
        $router->get('/settlement', [DsrApiController::class, 'settlement']);
        $router->get('/attendance', [DsrApiController::class, 'attendance']);

        $router->get('/delivery/state', [DsrDelivery::class, 'state']);
        $router->get('/retailers', [DsrDelivery::class, 'retailers']);
        $router->post('/stops/{retailer:\d+}', [DsrDelivery::class, 'saveStop']);
        $router->post('/stops/{retailer:\d+}/reset', [DsrDelivery::class, 'resetStop']);
        $router->post('/damages', [DsrDelivery::class, 'saveDamages']);
        $router->post('/ready-sales', [DsrDelivery::class, 'readySale']);
        $router->delete('/ready-sales/{id:\d+}', [DsrDelivery::class, 'deleteReadySale']);

        $router->post('/attendance', [DsrAttendance::class, 'checkIn']);
        $router->post('/track', [DsrTrack::class, 'store']);
        $router->post('/expenses', [DsrExpense::class, 'store']);
        $router->delete('/expenses/{id:\d+}', [DsrExpense::class, 'destroy']);
        $router->post('/settlement', [DsrSettlement::class, 'submit']);
    });

    // Retailer (shop)
    $router->group(['prefix' => 'retailer', 'middleware' => [RetailerAuthMiddleware::class]], static function (Router $router): void {
        $router->get('/today', [RetailerApiController::class, 'today']);
        $router->get('/history', [RetailerApiController::class, 'history']);
        $router->get('/day', [RetailerApiController::class, 'day']);
        $router->get('/notifications', [RetailerApiController::class, 'notifications']);
        $router->post('/notifications/seen', [RetailerApiController::class, 'markSeen']);
    });
});
