<?php

declare(strict_types=1);

return [
    'token' => (string) env('INTERNAL_SERVICE_TOKEN', ''),
    'timeout' => (int) env('SERVICE_TIMEOUT', 5),
    'endpoints' => [
        'node' => rtrim((string) env('SERVICE_NODE_URL', 'http://127.0.0.1:3001'), '/'),
        'python' => rtrim((string) env('SERVICE_PYTHON_URL', 'http://127.0.0.1:8001'), '/'),
    ],
];
