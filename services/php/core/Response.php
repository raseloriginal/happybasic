<?php

declare(strict_types=1);

namespace Core;

final class Response
{
    private string $body;
    private int $status;
    /** @var array<string, string> */
    private array $headers;

    /** @param array<string, string> $headers */
    public function __construct(string $body = '', int $status = 200, array $headers = [])
    {
        $this->body = $body;
        $this->status = $status;
        $this->headers = $headers;
    }

    public static function make(string $body = '', int $status = 200, array $headers = []): self
    {
        return new self($body, $status, $headers);
    }

    public static function html(string $html, int $status = 200, array $headers = []): self
    {
        return new self($html, $status, array_merge(['Content-Type' => 'text/html; charset=UTF-8'], $headers));
    }

    public static function json(mixed $data, int $status = 200, array $headers = []): self
    {
        $payload = json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
        return new self($payload, $status, array_merge(['Content-Type' => 'application/json; charset=UTF-8'], $headers));
    }

    public static function redirect(string $to, int $status = 302): self
    {
        if (!preg_match('#^https?://#i', $to) && str_starts_with($to, '/')) {
            $to = url($to);
        }

        return new self('', $status, ['Location' => $to]);
    }

    public static function back(string $fallback = '/'): self
    {
        $referer = App::request()?->referer($fallback) ?? $fallback;
        return self::redirect($referer);
    }

    public static function text(string $text, int $status = 200): self
    {
        return new self($text, $status, ['Content-Type' => 'text/plain; charset=UTF-8']);
    }

    public function status(int $status): self
    {
        $clone = clone $this;
        $clone->status = $status;
        return $clone;
    }

    public function header(string $name, string $value): self
    {
        $clone = clone $this;
        $clone->headers[$name] = $value;
        return $clone;
    }

    public function with(string $key, mixed $value): self
    {
        Session::flash($key, $value);
        return $this;
    }

    public function withErrors(array $errors): self
    {
        Session::flashErrors($errors);
        return $this;
    }

    public function withInput(?array $input = null): self
    {
        Session::flashInput($input ?? (App::request()?->all() ?? []));
        return $this;
    }

    public function getBody(): string
    {
        return $this->body;
    }

    public function getStatus(): int
    {
        return $this->status;
    }

    /** @return array<string, string> */
    public function getHeaders(): array
    {
        return $this->headers;
    }

    public function send(): void
    {
        if (!headers_sent()) {
            // Apache turns status codes it has no reason phrase for (e.g. 419) into 500, so send the phrase explicitly.
            if ($this->status === 419) {
                header(($_SERVER['SERVER_PROTOCOL'] ?? 'HTTP/1.1') . ' 419 Page Expired', true, 419);
            } else {
                http_response_code($this->status);
            }
            foreach ($this->headers as $name => $value) {
                header("{$name}: {$value}");
            }
        }

        echo $this->body;
    }
}
