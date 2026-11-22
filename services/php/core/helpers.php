<?php

declare(strict_types=1);

use Core\App;
use Core\Auth;
use Core\Csrf;
use Core\Env;
use Core\Request;
use Core\Response;
use Core\ServiceClient;
use Core\Session;
use Core\View;

if (!function_exists('root_path')) {
    function root_path(string $path = ''): string
    {
        return App::rootPath($path);
    }
}

if (!function_exists('shared_path')) {
    function shared_path(string $path = ''): string
    {
        return root_path('shared' . ($path !== '' ? DIRECTORY_SEPARATOR . ltrim($path, '/\\') : ''));
    }
}

if (!function_exists('base_path')) {
    function base_path(string $path = ''): string
    {
        return App::basePath($path);
    }
}

if (!function_exists('app_path')) {
    function app_path(string $path = ''): string
    {
        return base_path('app' . ($path !== '' ? DIRECTORY_SEPARATOR . ltrim($path, '/\\') : ''));
    }
}

if (!function_exists('config_path')) {
    function config_path(string $path = ''): string
    {
        return base_path('config' . ($path !== '' ? DIRECTORY_SEPARATOR . ltrim($path, '/\\') : ''));
    }
}

if (!function_exists('view_path')) {
    function view_path(string $path = ''): string
    {
        return app_path('Views' . ($path !== '' ? DIRECTORY_SEPARATOR . ltrim($path, '/\\') : ''));
    }
}

if (!function_exists('storage_path')) {
    function storage_path(string $path = ''): string
    {
        return root_path('storage' . ($path !== '' ? DIRECTORY_SEPARATOR . ltrim($path, '/\\') : ''));
    }
}

if (!function_exists('service')) {
    function service(string $name): ServiceClient
    {
        return ServiceClient::for($name);
    }
}

if (!function_exists('env')) {
    function env(string $key, mixed $default = null): mixed
    {
        return Env::get($key, $default);
    }
}

if (!function_exists('config')) {
    function config(string $key, mixed $default = null): mixed
    {
        return App::config($key, $default);
    }
}

if (!function_exists('e')) {
    function e(mixed $value): string
    {
        return htmlspecialchars((string) ($value ?? ''), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }
}

if (!function_exists('url')) {
    function url(string $path = ''): string
    {
        $clean = '/' . ltrim($path, '/');
        $basePath = App::request()?->basePath() ?? '';

        if ($basePath !== '') {
            return $basePath . ($clean === '/' ? '/' : $clean);
        }

        $appUrl = rtrim((string) config('app.url', ''), '/');
        if ($appUrl !== '' && PHP_SAPI !== 'cli') {
            $parsedPath = rtrim((string) (parse_url($appUrl, PHP_URL_PATH) ?: ''), '/');
            if ($parsedPath !== '') {
                return $parsedPath . ($clean === '/' ? '/' : $clean);
            }
        }

        return $clean;
    }
}

if (!function_exists('asset')) {
    function asset(string $path): string
    {
        $rel = 'assets/' . ltrim($path, '/');
        $file = base_path('public/' . $rel);
        // Cache-bust with the file's modified time so edited JS/CSS is never served stale.
        $v = is_file($file) ? '?v=' . filemtime($file) : '';

        return url($rel) . $v;
    }
}

if (!function_exists('route')) {
    /** @param array<string, scalar> $params */
    function route(string $name, array $params = []): string
    {
        return App::router()->routeUrl($name, $params);
    }
}

if (!function_exists('request')) {
    function request(): Request
    {
        return App::request() ?? Request::capture();
    }
}

if (!function_exists('response')) {
    function response(string $body = '', int $status = 200, array $headers = []): Response
    {
        return Response::make($body, $status, $headers);
    }
}

if (!function_exists('view')) {
    /** @param array<string, mixed> $data */
    function view(string $template, array $data = [], int $status = 200): Response
    {
        return Response::html(View::render($template, $data), $status);
    }
}

if (!function_exists('redirect')) {
    function redirect(string $to, int $status = 302): Response
    {
        return Response::redirect($to, $status);
    }
}

if (!function_exists('back')) {
    function back(string $fallback = '/'): Response
    {
        return Response::back($fallback);
    }
}

if (!function_exists('session')) {
    function session(?string $key = null, mixed $default = null): mixed
    {
        if ($key === null) {
            return Session::class;
        }
        return Session::get($key, $default);
    }
}

if (!function_exists('flash')) {
    function flash(string $key, mixed $default = null): mixed
    {
        return Session::getFlash($key, $default);
    }
}

if (!function_exists('old')) {
    function old(string $key, mixed $default = ''): mixed
    {
        return Session::old($key, $default);
    }
}

if (!function_exists('errors')) {
    /** @return array<string, list<string>> */
    function errors(): array
    {
        return Session::errors();
    }
}

if (!function_exists('error')) {
    function error(string $field): ?string
    {
        $all = Session::errors();
        return $all[$field][0] ?? null;
    }
}

if (!function_exists('csrf_token')) {
    function csrf_token(): string
    {
        return Csrf::token();
    }
}

if (!function_exists('csrf_field')) {
    function csrf_field(): string
    {
        return Csrf::field();
    }
}

if (!function_exists('csrf_meta')) {
    function csrf_meta(): string
    {
        return Csrf::meta();
    }
}

if (!function_exists('method_field')) {
    function method_field(string $method): string
    {
        $method = htmlspecialchars(strtoupper($method), ENT_QUOTES, 'UTF-8');
        return '<input type="hidden" name="_method" value="' . $method . '">';
    }
}

if (!function_exists('auth')) {
    /** @return array<string, mixed>|null */
    function auth(): ?array
    {
        return Auth::user();
    }
}

if (!function_exists('dd')) {
    function dd(mixed ...$vars): never
    {
        if (PHP_SAPI !== 'cli' && !headers_sent()) {
            header('Content-Type: text/html; charset=UTF-8');
            echo '<pre style="background:#111;color:#eee;padding:16px;font:13px/1.5 monospace;overflow:auto;">';
        }
        foreach ($vars as $var) {
            var_dump($var);
        }
        if (PHP_SAPI !== 'cli') {
            echo '</pre>';
        }
        exit(1);
    }
}
