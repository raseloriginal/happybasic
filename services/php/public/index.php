<?php

declare(strict_types=1);

use Core\App;

require_once dirname(__DIR__) . '/core/App.php';

App::boot(
    servicePath: dirname(__DIR__),
    rootPath: dirname(__DIR__, 3)
);

$router = App::router();
require base_path('routes/web.php');

App::run();
