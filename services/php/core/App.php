<?php

declare(strict_types=1);

namespace Core;

use Throwable;

final class App
{
    private static string $basePath = '';
    private static string $rootPath = '';
    /** @var array<string, mixed> */
    private static array $config = [];
    private static ?Router $router = null;
    private static ?Request $request = null;

    public static function boot(string $servicePath, ?string $rootPath = null): void
    {
        self::$basePath = rtrim($servicePath, '/\\');
        self::$rootPath = rtrim($rootPath ?? $servicePath, '/\\');

        require_once self::$basePath . '/core/Autoloader.php';
        Autoloader::register(self::$basePath);

        require_once self::$basePath . '/core/helpers.php';

        Env::load(self::$rootPath . '/.env');
        if (self::$basePath !== self::$rootPath) {
            Env::load(self::$basePath . '/.env');
        }

        self::loadConfigs();

        date_default_timezone_set((string) self::config('app.timezone', 'UTC'));

        Session::start();
        self::$router = new Router();
    }

    public static function basePath(string $path = ''): string
    {
        return $path === ''
            ? self::$basePath
            : self::$basePath . DIRECTORY_SEPARATOR . ltrim($path, '/\\');
    }

    public static function rootPath(string $path = ''): string
    {
        return $path === ''
            ? self::$rootPath
            : self::$rootPath . DIRECTORY_SEPARATOR . ltrim($path, '/\\');
    }

    public static function config(string $key, mixed $default = null): mixed
    {
        $segments = explode('.', $key);
        $value = self::$config;

        foreach ($segments as $segment) {
            if (!is_array($value) || !array_key_exists($segment, $value)) {
                return $default;
            }
            $value = $value[$segment];
        }

        return $value;
    }

    public static function router(): Router
    {
        if (self::$router === null) {
            self::$router = new Router();
        }
        return self::$router;
    }

    /** True for the mobile app API (/api/v1/...): token auth, no session, no cookies. Looks at the path only, never the query. */
    public static function isApi(): bool
    {
        $path = (string) (parse_url((string) ($_SERVER['REQUEST_URI'] ?? ''), PHP_URL_PATH) ?: '');
        $base = rtrim(str_replace('\\', '/', dirname((string) ($_SERVER['SCRIPT_NAME'] ?? ''))), '/');
        $base = preg_replace('#/services/php/public$#', '', $base) ?? '';

        return str_starts_with($path, $base . '/api/v1/');
    }

    public static function request(): ?Request
    {
        return self::$request;
    }

    public static function run(?Request $request = null): void
    {
        $response = self::handle($request ?? Request::capture());
        $response->send();
    }

    public static function handle(Request $request): Response
    {
        self::$request = $request;

        try {
            return self::router()->dispatch($request);
        } catch (Throwable $e) {
            return self::handleException($e, $request);
        }
    }

    private static function loadConfigs(): void
    {
        self::$config = [];
        $configDir = self::$basePath . DIRECTORY_SEPARATOR . 'config';
        if (!is_dir($configDir)) {
            return;
        }

        foreach (glob($configDir . DIRECTORY_SEPARATOR . '*.php') ?: [] as $file) {
            $name = basename($file, '.php');
            self::$config[$name] = require $file;
        }
    }

    private static function handleException(Throwable $e, Request $request): Response
    {
        $debug = (bool) self::config('app.debug', false);
        self::logError($e);

        if ($request->expectsJson()) {
            $payload = ['error' => $debug ? $e->getMessage() : 'Internal Server Error'];
            if ($debug) {
                $payload['exception'] = $e::class;
                $payload['file'] = $e->getFile() . ':' . $e->getLine();
            }
            return Response::json($payload, 500);
        }

        if (is_file(view_path('errors/500.php'))) {
            return Response::html(View::render('errors.500', [
                'exception' => $debug ? $e : null,
            ]), 500);
        }

        $body = $debug
            ? $e::class . ': ' . $e->getMessage() . "\n" . $e->getTraceAsString()
            : '500 Internal Server Error';

        return Response::text($body, 500);
    }

    private static function logError(Throwable $e): void
    {
        $logDir = storage_path('logs');
        if (!is_dir($logDir)) {
            @mkdir($logDir, 0775, true);
        }

        $entry = sprintf(
            "[%s] %s: %s in %s:%d\n%s\n\n",
            date('Y-m-d H:i:s'),
            $e::class,
            $e->getMessage(),
            $e->getFile(),
            $e->getLine(),
            $e->getTraceAsString()
        );

        @file_put_contents($logDir . DIRECTORY_SEPARATOR . 'app.log', $entry, FILE_APPEND);
    }
}
