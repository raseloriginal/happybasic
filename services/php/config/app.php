<?php

declare(strict_types=1);

return [
    'name' => env('APP_NAME', 'HappyBasic'),
    'env' => env('APP_ENV', 'local'),
    'debug' => filter_var(env('APP_DEBUG', true), FILTER_VALIDATE_BOOL),
    'url' => rtrim((string) env('APP_URL', ''), '/'),
    'timezone' => env('APP_TIMEZONE', 'UTC'),
];
