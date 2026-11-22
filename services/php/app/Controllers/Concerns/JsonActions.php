<?php

declare(strict_types=1);

namespace App\Controllers\Concerns;

use App\Support\HttpError;
use App\Support\Phone;
use Core\Request;
use Core\Response;
use Core\Validator;

/** JSON action + validation helpers shared by the admin, partner and SR controllers. */
trait JsonActions
{
    /** Runs a JSON action, converting business-rule failures into JSON errors. */
    protected function action(callable $fn): Response
    {
        try {
            return $this->json(['ok' => true] + $fn());
        } catch (HttpError $e) {
            return $this->json(['ok' => false, 'message' => $e->getMessage(), 'errors' => $e->errors()], $e->status());
        }
    }

    /**
     * @param array<string, string|list<string>> $rules
     * @param array<string, string> $messages
     * @return array<string, mixed>
     */
    protected function check(Request $request, array $rules, array $messages = []): array
    {
        $input = array_map(static fn($v) => is_string($v) ? trim($v) : $v, $request->all());
        $validator = Validator::make($input, $rules, $messages);
        if ($validator->fails()) {
            throw new HttpError($validator->first() ?? 'Invalid input.', 422, $validator->errors());
        }

        $data = $validator->validated();
        foreach (array_keys($rules) as $key) {
            $data[$key] ??= null;
        }

        return $data;
    }

    /** @param array<string, mixed> $data */
    protected function phone(array $data, string $field = 'number'): string
    {
        $phone = Phone::normalize((string) ($data[$field] ?? ''));
        if ($phone === null) {
            throw new HttpError('Enter a valid Bangladeshi mobile number (e.g. +880 1711-234567).', 422, [
                $field => ['Enter a valid Bangladeshi mobile number.'],
            ]);
        }

        return $phone;
    }

    /** Status sent by the UI ("Active") to the DB enum value ("active"). */
    protected function statusFrom(Request $request, array $allowed = ['active', 'inactive']): string
    {
        $status = strtolower(trim((string) $request->input('status', '')));
        if (!in_array($status, $allowed, true)) {
            throw new HttpError('Invalid status.', 422, ['status' => ['Invalid status.']]);
        }

        return $status;
    }

    /** @return list<string> */
    protected function passwordRule(bool $required): array
    {
        return [$required ? 'required' : 'nullable', 'string', 'min:6', 'max:72'];
    }
}
