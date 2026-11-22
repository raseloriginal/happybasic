<?php

declare(strict_types=1);

namespace Core;

use InvalidArgumentException;

final class ServiceClient
{
    private string $baseUrl;
    private string $token;
    private int $timeout;

    public function __construct(string $baseUrl, string $token = '', int $timeout = 5)
    {
        $this->baseUrl = rtrim($baseUrl, '/');
        $this->token = $token;
        $this->timeout = max(1, $timeout);
    }

    public static function for(string $service): self
    {
        $endpoints = (array) config('services.endpoints', []);
        if (!isset($endpoints[$service]) || !is_string($endpoints[$service]) || $endpoints[$service] === '') {
            throw new InvalidArgumentException("Unknown service endpoint: {$service}");
        }

        return new self(
            $endpoints[$service],
            (string) config('services.token', ''),
            (int) config('services.timeout', 5)
        );
    }

    /** @param array<string, scalar> $query @param array<string, string> $headers @return array{ok: bool, status: int, data: mixed, raw: string, error: ?string} */
    public function get(string $path, array $query = [], array $headers = []): array
    {
        if ($query !== []) {
            $path .= (str_contains($path, '?') ? '&' : '?') . http_build_query($query);
        }
        return $this->send('GET', $path, null, $headers);
    }

    /** @param array<string, mixed> $payload @param array<string, string> $headers @return array{ok: bool, status: int, data: mixed, raw: string, error: ?string} */
    public function post(string $path, array $payload = [], array $headers = []): array
    {
        return $this->send('POST', $path, $payload, $headers);
    }

    /** @param array<string, mixed> $payload @param array<string, string> $headers @return array{ok: bool, status: int, data: mixed, raw: string, error: ?string} */
    public function put(string $path, array $payload = [], array $headers = []): array
    {
        return $this->send('PUT', $path, $payload, $headers);
    }

    /** @param array<string, string> $headers @return array{ok: bool, status: int, data: mixed, raw: string, error: ?string} */
    public function delete(string $path, array $headers = []): array
    {
        return $this->send('DELETE', $path, null, $headers);
    }

    /**
     * @param array<string, mixed>|null $payload
     * @param array<string, string> $headers
     * @return array{ok: bool, status: int, data: mixed, raw: string, error: ?string}
     */
    public function send(string $method, string $path, ?array $payload = null, array $headers = []): array
    {
        $url = $this->baseUrl . '/' . ltrim($path, '/');
        $method = strtoupper($method);
        $body = $payload !== null ? json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) : null;

        $headerLines = ['Accept: application/json'];
        if ($body !== null) {
            $headerLines[] = 'Content-Type: application/json';
        }
        if ($this->token !== '') {
            $headerLines[] = 'X-Service-Token: ' . $this->token;
        }
        foreach ($headers as $name => $value) {
            $headerLines[] = "{$name}: {$value}";
        }

        if (function_exists('curl_init')) {
            return $this->sendWithCurl($method, $url, $body, $headerLines);
        }

        return $this->sendWithStream($method, $url, $body, $headerLines);
    }

    /** @param list<string> $headers @return array{ok: bool, status: int, data: mixed, raw: string, error: ?string} */
    private function sendWithCurl(string $method, string $url, ?string $body, array $headers): array
    {
        $ch = curl_init($url);
        if ($ch === false) {
            return ['ok' => false, 'status' => 0, 'data' => null, 'raw' => '', 'error' => 'Failed to initialize cURL'];
        }

        curl_setopt_array($ch, [
            CURLOPT_CUSTOMREQUEST => $method,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_TIMEOUT => $this->timeout,
            CURLOPT_CONNECTTIMEOUT => min(3, $this->timeout),
        ]);

        if ($body !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
        }

        $raw = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $error = $raw === false ? curl_error($ch) : null;
        curl_close($ch);

        $rawStr = is_string($raw) ? $raw : '';
        $decoded = $rawStr !== '' ? json_decode($rawStr, true) : null;

        return [
            'ok' => $error === null && $status >= 200 && $status < 300,
            'status' => $status,
            'data' => json_last_error() === JSON_ERROR_NONE ? $decoded : null,
            'raw' => $rawStr,
            'error' => $error,
        ];
    }

    /** @param list<string> $headers @return array{ok: bool, status: int, data: mixed, raw: string, error: ?string} */
    private function sendWithStream(string $method, string $url, ?string $body, array $headers): array
    {
        $context = stream_context_create([
            'http' => [
                'method' => $method,
                'header' => implode("\r\n", $headers),
                'content' => $body ?? '',
                'timeout' => $this->timeout,
                'ignore_errors' => true,
            ],
        ]);

        $raw = @file_get_contents($url, false, $context);
        $responseHeaders = $http_response_header ?? [];
        $status = 0;

        if (isset($responseHeaders[0]) && preg_match('/\s(\d{3})\s/', $responseHeaders[0], $m)) {
            $status = (int) $m[1];
        }

        if ($raw === false) {
            return ['ok' => false, 'status' => $status, 'data' => null, 'raw' => '', 'error' => 'Service unreachable'];
        }

        $decoded = $raw !== '' ? json_decode($raw, true) : null;

        return [
            'ok' => $status >= 200 && $status < 300,
            'status' => $status,
            'data' => json_last_error() === JSON_ERROR_NONE ? $decoded : null,
            'raw' => $raw,
            'error' => null,
        ];
    }
}
