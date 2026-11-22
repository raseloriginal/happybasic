<?php

declare(strict_types=1);

namespace App\Support;

use RuntimeException;

/** Business-rule failure that should be returned to the client as a JSON error. */
final class HttpError extends RuntimeException
{
    /** @param array<string, list<string>> $errors */
    public function __construct(string $message, private readonly int $status = 422, private readonly array $errors = [])
    {
        parent::__construct($message);
    }

    public function status(): int
    {
        return $this->status;
    }

    /** @return array<string, list<string>> */
    public function errors(): array
    {
        return $this->errors;
    }
}
