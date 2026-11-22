<?php

declare(strict_types=1);

use App\Controllers\PanelAuthController;
use App\Controllers\RetailerController;
use App\Middleware\CsrfMiddleware;
use App\Middleware\RetailerAuthMiddleware;
use Core\Router;

/** @var Router $router */

$router->group(['prefix' => 'retailer', 'middleware' => [CsrfMiddleware::class]], static function (Router $router): void {
    $router->get('/login', [PanelAuthController::class, 'showRetailer'])->name('retailer.login');
    $router->post('/login', [PanelAuthController::class, 'retailerLogin']);
    $router->post('/logout', [PanelAuthController::class, 'retailerLogout'])->name('retailer.logout');

    $router->group(['middleware' => [RetailerAuthMiddleware::class]], static function (Router $router): void {
        $router->get('/', [RetailerController::class, 'today'])->name('retailer.today');
        $router->get('/history', [RetailerController::class, 'history'])->name('retailer.history');
        $router->get('/invoice', [RetailerController::class, 'invoice'])->name('retailer.invoice');
        $router->get('/delivery-invoice', [RetailerController::class, 'deliveryInvoice'])->name('retailer.delivery-invoice');
        $router->get('/notifications', [RetailerController::class, 'notifications'])->name('retailer.notifications');
        $router->post('/notifications/seen', [RetailerController::class, 'markSeen']);
    });
});
