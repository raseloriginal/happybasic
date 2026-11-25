<?php

declare(strict_types=1);

use App\Controllers\Admin\AdminAuthController;
use App\Controllers\Admin\AppController;
use App\Controllers\Admin\CompanyController;
use App\Controllers\Admin\DashboardController;
use App\Controllers\Admin\DealerController;
use App\Controllers\Admin\PartnerController;
use App\Controllers\Admin\PlatformFeeController;
use App\Controllers\Admin\SalesmanController;
use App\Controllers\Admin\SettingController;
use App\Middleware\AdminAuthMiddleware;
use App\Middleware\CsrfMiddleware;
use Core\Router;

/** @var Router $router */

$router->group(['prefix' => 'admin', 'middleware' => [CsrfMiddleware::class]], static function (Router $router): void {
    $router->get('/login', [AdminAuthController::class, 'showLogin'])->name('admin.login');
    $router->post('/login', [AdminAuthController::class, 'login']);
    $router->post('/logout', [AdminAuthController::class, 'logout'])->name('admin.logout');

    $router->group(['middleware' => [AdminAuthMiddleware::class]], static function (Router $router): void {
        $router->get('/', [DashboardController::class, 'index'])->name('admin.index');
        $router->get('/dashboard', [DashboardController::class, 'index'])->name('admin.dashboard');
        $router->get('/health', [DashboardController::class, 'health'])->name('admin.health');

        $resources = [
            'partners' => PartnerController::class,
            'companies' => CompanyController::class,
            'dealers' => DealerController::class,
            'salesmen' => SalesmanController::class,
        ];
        foreach ($resources as $path => $controller) {
            $router->get("/{$path}", [$controller, 'index'])->name("admin.{$path}");
            $router->post("/{$path}", [$controller, 'store']);
            $router->put("/{$path}/{id:\\d+}", [$controller, 'update']);
            $router->patch("/{$path}/{id:\\d+}/status", [$controller, 'status']);
            $router->delete("/{$path}/{id:\\d+}", [$controller, 'destroy']);
        }

        $router->get('/platform-fees', [PlatformFeeController::class, 'index'])->name('admin.platform-fees');
        $router->put('/platform-fees/{id:\d+}', [PlatformFeeController::class, 'update']);
        $router->get('/platform-fees/{id:\d+}/history/{company:\d+}', [PlatformFeeController::class, 'history']);

        $router->get('/app', [AppController::class, 'index'])->name('admin.app');
        $router->post('/app', [AppController::class, 'store']);
        $router->patch('/app/{id:\d+}/status', [AppController::class, 'status']);
        $router->delete('/app/{id:\d+}', [AppController::class, 'destroy']);

        $router->get('/settings', [SettingController::class, 'index'])->name('admin.settings');
        $router->post('/settings/categories', [SettingController::class, 'storeCategory']);
        $router->patch('/settings/categories/{id:\d+}/status', [SettingController::class, 'categoryStatus']);
        $router->delete('/settings/categories/{id:\d+}', [SettingController::class, 'destroyCategory']);
        $router->post('/settings/areas', [SettingController::class, 'storeArea']);
        $router->patch('/settings/areas/{id:\d+}/status', [SettingController::class, 'areaStatus']);
        $router->delete('/settings/areas/{id:\d+}', [SettingController::class, 'destroyArea']);
        $router->delete('/settings/sessions/{id:\d+}', [SettingController::class, 'revokeSession']);
        $router->post('/settings/sessions/revoke-others', [SettingController::class, 'revokeOthers']);
    });
});
