<?php

declare(strict_types=1);

namespace Core;

final class Request
{
    private string $method;
    private string $path;
    private string $basePath;
    /** @var array<string, mixed> */
    private array $query;
    /** @var array<string, mixed> */
    private array $post;
    /** @var array<string, mixed> */
    private array $json;
    /** @var array<string, mixed> */
    private array $files;
    /** @var array<string, string> */
    private array $headers;
    /** @var array<string, mixed> */
    private array $server;
    /** @var array<string, string> */
    private array $routeParams = [];

    public function __construct(
        string $method = 'GET',
        string $uri = '/',
        array $query = [],
        array $post = [],
        array $files = [],
        array $headers = [],
        array $server = [],
        ?string $rawBody = null
    ) {
        $this->server = $server;
        $this->headers = self::normalizeHeaders($headers);
        $this->query = $query;
        $this->post = $post;
        $this->files = $files;
        $this->json = self::parseJsonBody($rawBody, $this->headers);
        $this->method = $this->resolveMethod($method);
        $this->basePath = $this->detectBasePath($uri);
        $this->path = $this->normalizePath($uri, $this->basePath);
    }

    public static function capture(): self
    {
        $headers = [];
        foreach ($_SERVER as $key => $value) {
            if (str_starts_with($key, 'HTTP_')) {
                $name = str_replace('_', '-', substr($key, 5));
                $headers[$name] = (string) $value;
            } elseif (in_array($key, ['CONTENT_TYPE', 'CONTENT_LENGTH'], true)) {
                $headers[str_replace('_', '-', $key)] = (string) $value;
            }
        }

        $rawBody = file_get_contents('php://input');

        return new self(
            $_SERVER['REQUEST_METHOD'] ?? 'GET',
            $_SERVER['REQUEST_URI'] ?? '/',
            $_GET,
            $_POST,
            $_FILES,
            $headers,
            $_SERVER,
            $rawBody === false ? null : $rawBody
        );
    }

    public function method(): string
    {
        return $this->method;
    }

    public function isMethod(string $method): bool
    {
        return $this->method === strtoupper($method);
    }

    public function path(): string
    {
        return $this->path;
    }

    public function basePath(): string
    {
        return $this->basePath;
    }

    public function fullUrl(): string
    {
        $scheme = (!empty($this->server['HTTPS']) && $this->server['HTTPS'] !== 'off') ? 'https' : 'http';
        $host = $this->server['HTTP_HOST'] ?? 'localhost';
        $uri = $this->server['REQUEST_URI'] ?? $this->path;
        return "{$scheme}://{$host}{$uri}";
    }

    public function query(?string $key = null, mixed $default = null): mixed
    {
        if ($key === null) {
            return $this->query;
        }
        return $this->query[$key] ?? $default;
    }

    public function post(?string $key = null, mixed $default = null): mixed
    {
        if ($key === null) {
            return $this->post;
        }
        return $this->post[$key] ?? $default;
    }

    public function json(?string $key = null, mixed $default = null): mixed
    {
        if ($key === null) {
            return $this->json;
        }
        return $this->json[$key] ?? $default;
    }

    /** @return array<string, mixed> */
    public function all(): array
    {
        return array_merge($this->query, $this->post, $this->json);
    }

    public function input(string $key, mixed $default = null): mixed
    {
        $all = $this->all();
        return $all[$key] ?? $default;
    }

    public function has(string $key): bool
    {
        return array_key_exists($key, $this->all());
    }

    /** @param list<string> $keys @return array<string, mixed> */
    public function only(array $keys): array
    {
        $all = $this->all();
        $result = [];
        foreach ($keys as $key) {
            if (array_key_exists($key, $all)) {
                $result[$key] = $all[$key];
            }
        }
        return $result;
    }

    /** @param list<string> $keys @return array<string, mixed> */
    public function except(array $keys): array
    {
        return array_diff_key($this->all(), array_flip($keys));
    }

    public function file(string $key): ?array
    {
        return isset($this->files[$key]) && is_array($this->files[$key]) ? $this->files[$key] : null;
    }

    public function header(string $name, ?string $default = null): ?string
    {
        return $this->headers[strtolower($name)] ?? $default;
    }

    /** @return array<string, string> */
    public function headers(): array
    {
        return $this->headers;
    }

    public function ip(): string
    {
        return (string) ($this->server['REMOTE_ADDR'] ?? '127.0.0.1');
    }

    public function referer(string $default = '/'): string
    {
        return $this->header('referer') ?? $default;
    }

    public function isAjax(): bool
    {
        return strtolower((string) $this->header('X-Requested-With')) === 'xmlhttprequest';
    }

    public function expectsJson(): bool
    {
        $accept = strtolower((string) $this->header('Accept'));
        $contentType = strtolower((string) $this->header('Content-Type'));
        return str_contains($accept, 'application/json')
            || str_contains($contentType, 'application/json')
            || $this->isAjax();
    }

    /** @param array<string, string> $params */
    public function setRouteParams(array $params): void
    {
        $this->routeParams = $params;
    }

    public function param(string $key, mixed $default = null): mixed
    {
        return $this->routeParams[$key] ?? $default;
    }

    /** @return array<string, string> */
    public function params(): array
    {
        return $this->routeParams;
    }

    private function resolveMethod(string $method): string
    {
        $method = strtoupper($method);
        if ($method === 'POST') {
            $override = $this->post['_method'] ?? $this->header('X-HTTP-Method-Override');
            if (is_string($override)) {
                $upper = strtoupper($override);
                if (in_array($upper, ['PUT', 'PATCH', 'DELETE'], true)) {
                    return $upper;
                }
            }
        }
        return $method;
    }

    private function detectBasePath(string $uri): string
    {
        $scriptName = str_replace('\\', '/', (string) ($this->server['SCRIPT_NAME'] ?? ''));
        if ($scriptName === '') {
            return '';
        }

        $candidate = rtrim(dirname($scriptName), '/');
        $rawPath = (string) (parse_url($uri, PHP_URL_PATH) ?: '/');

        while ($candidate !== '' && $candidate !== '.' && $candidate !== '/') {
            if ($rawPath === $candidate || str_starts_with($rawPath, $candidate . '/')) {
                return $candidate;
            }
            $parent = rtrim(dirname($candidate), '/');
            if ($parent === $candidate) {
                break;
            }
            $candidate = $parent;
        }

        return '';
    }

    private function normalizePath(string $uri, string $basePath): string
    {
        $path = (string) (parse_url($uri, PHP_URL_PATH) ?: '/');
        if ($basePath !== '' && str_starts_with($path, $basePath)) {
            $path = substr($path, strlen($basePath)) ?: '/';
        }

        $path = '/' . trim($path, '/');
        return $path === '' ? '/' : $path;
    }

    /** @param array<string, string> $headers @return array<string, string> */
    private static function normalizeHeaders(array $headers): array
    {
        $normalized = [];
        foreach ($headers as $key => $value) {
            $normalized[strtolower($key)] = (string) $value;
        }
        return $normalized;
    }

    /** @param array<string, string> $headers @return array<string, mixed> */
    private static function parseJsonBody(?string $rawBody, array $headers): array
    {
        if ($rawBody === null || trim($rawBody) === '') {
            return [];
        }

        $contentType = strtolower($headers['content-type'] ?? '');
        if (!str_contains($contentType, 'application/json')) {
            return [];
        }

        $decoded = json_decode($rawBody, true);
        return is_array($decoded) ? $decoded : [];
    }
}
