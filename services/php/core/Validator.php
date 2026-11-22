<?php

declare(strict_types=1);

namespace Core;

final class Validator
{
    /** @var array<string, mixed> */
    private array $data;
    /** @var array<string, string|list<string>> */
    private array $rules;
    /** @var array<string, string> */
    private array $messages;
    /** @var array<string, list<string>> */
    private array $errors = [];
    /** @var array<string, mixed> */
    private array $validated = [];
    private bool $hasRun = false;
    private bool $numericField = false;

    /**
     * @param array<string, mixed> $data
     * @param array<string, string|list<string>> $rules
     * @param array<string, string> $messages
     */
    public function __construct(array $data, array $rules, array $messages = [])
    {
        $this->data = $data;
        $this->rules = $rules;
        $this->messages = $messages;
    }

    /**
     * @param array<string, mixed> $data
     * @param array<string, string|list<string>> $rules
     * @param array<string, string> $messages
     */
    public static function make(array $data, array $rules, array $messages = []): self
    {
        $validator = new self($data, $rules, $messages);
        $validator->run();
        return $validator;
    }

    public function passes(): bool
    {
        if (!$this->hasRun) {
            $this->run();
        }
        return $this->errors === [];
    }

    public function fails(): bool
    {
        return !$this->passes();
    }

    /** @return array<string, list<string>> */
    public function errors(): array
    {
        if (!$this->hasRun) {
            $this->run();
        }
        return $this->errors;
    }

    public function first(?string $field = null): ?string
    {
        $errors = $this->errors();
        if ($field !== null) {
            return $errors[$field][0] ?? null;
        }

        foreach ($errors as $fieldErrors) {
            if (isset($fieldErrors[0])) {
                return $fieldErrors[0];
            }
        }
        return null;
    }

    /** @return array<string, mixed> */
    public function validated(): array
    {
        if (!$this->hasRun) {
            $this->run();
        }
        return $this->validated;
    }

    private function run(): void
    {
        $this->hasRun = true;
        $this->errors = [];
        $this->validated = [];

        foreach ($this->rules as $field => $ruleSet) {
            $rules = is_array($ruleSet) ? $ruleSet : explode('|', $ruleSet);
            $rules = array_values(array_filter(array_map('trim', $rules), static fn(string $r): bool => $r !== ''));

            $value = $this->data[$field] ?? null;
            $isNullable = in_array('nullable', $rules, true);
            $this->numericField = in_array('numeric', $rules, true) || in_array('integer', $rules, true);
            $isEmpty = $value === null || (is_string($value) && trim($value) === '') || $value === [];

            foreach ($rules as $rule) {
                if ($rule === 'nullable') {
                    continue;
                }

                if ($isEmpty && $rule !== 'required') {
                    if ($isNullable || !in_array('required', $rules, true)) {
                        continue;
                    }
                }

                [$name, $param] = array_pad(explode(':', $rule, 2), 2, null);
                $this->applyRule($field, $value, $name, $param);
            }

            if (!isset($this->errors[$field]) && array_key_exists($field, $this->data)) {
                $this->validated[$field] = $value;
            }
        }
    }

    private function applyRule(string $field, mixed $value, string $rule, ?string $param): void
    {
        $label = ucfirst(str_replace('_', ' ', $field));

        switch ($rule) {
            case 'required':
                if ($value === null || (is_string($value) && trim($value) === '') || $value === []) {
                    $this->addError($field, $rule, "{$label} is required.");
                }
                break;

            case 'string':
                if (!is_string($value)) {
                    $this->addError($field, $rule, "{$label} must be a string.");
                }
                break;

            case 'numeric':
                if (!is_numeric($value)) {
                    $this->addError($field, $rule, "{$label} must be a number.");
                }
                break;

            case 'integer':
                if (filter_var($value, FILTER_VALIDATE_INT) === false) {
                    $this->addError($field, $rule, "{$label} must be an integer.");
                }
                break;

            case 'email':
                if (!is_string($value) || filter_var($value, FILTER_VALIDATE_EMAIL) === false) {
                    $this->addError($field, $rule, "{$label} must be a valid email address.");
                }
                break;

            case 'url':
                if (!is_string($value) || filter_var($value, FILTER_VALIDATE_URL) === false) {
                    $this->addError($field, $rule, "{$label} must be a valid URL.");
                }
                break;

            case 'min':
                $min = (float) $param;
                if (is_numeric($value) && ($this->numericField || !is_string($value))) {
                    if ((float) $value < $min) {
                        $this->addError($field, $rule, "{$label} must be at least {$param}.");
                    }
                } elseif (mb_strlen((string) $value) < (int) $param) {
                    $this->addError($field, $rule, "{$label} must be at least {$param} characters.");
                }
                break;

            case 'max':
                $max = (float) $param;
                if (is_numeric($value) && ($this->numericField || !is_string($value))) {
                    if ((float) $value > $max) {
                        $this->addError($field, $rule, "{$label} may not be greater than {$param}.");
                    }
                } elseif (mb_strlen((string) $value) > (int) $param) {
                    $this->addError($field, $rule, "{$label} may not exceed {$param} characters.");
                }
                break;

            case 'between':
                [$min, $max] = array_pad(explode(',', (string) $param, 2), 2, '0');
                $len = mb_strlen((string) $value);
                if ($len < (int) $min || $len > (int) $max) {
                    $this->addError($field, $rule, "{$label} must be between {$min} and {$max} characters.");
                }
                break;

            case 'in':
                $allowed = array_map('trim', explode(',', (string) $param));
                if (!in_array((string) $value, $allowed, true)) {
                    $this->addError($field, $rule, "{$label} must be one of: " . implode(', ', $allowed) . '.');
                }
                break;

            case 'confirmed':
                $confirmation = $this->data["{$field}_confirmation"] ?? null;
                if ($value !== $confirmation) {
                    $this->addError($field, $rule, "{$label} confirmation does not match.");
                }
                break;

            case 'regex':
                if (!is_string($value) || $param === null || preg_match($param, $value) !== 1) {
                    $this->addError($field, $rule, "{$label} format is invalid.");
                }
                break;

            case 'unique':
                if ($this->recordExists($param, $field, $value, true)) {
                    $this->addError($field, $rule, "{$label} has already been taken.");
                }
                break;

            case 'exists':
                if (!$this->recordExists($param, $field, $value, false)) {
                    $this->addError($field, $rule, "Selected {$label} is invalid.");
                }
                break;
        }
    }

    private function recordExists(?string $param, string $defaultColumn, mixed $value, bool $allowIgnore): bool
    {
        if ($param === null || $param === '') {
            return false;
        }

        $parts = array_map('trim', explode(',', $param));
        $table = $parts[0] ?? '';
        $column = $parts[1] ?? $defaultColumn;
        $ignoreId = $allowIgnore ? ($parts[2] ?? null) : null;

        if (!preg_match('/^[a-zA-Z_][a-zA-Z0-9_]*$/', $table) || !preg_match('/^[a-zA-Z_][a-zA-Z0-9_]*$/', $column)) {
            return false;
        }

        $sql = "SELECT COUNT(*) AS total FROM `{$table}` WHERE `{$column}` = ?";
        $bindings = [$value];

        if ($ignoreId !== null && $ignoreId !== '') {
            $sql .= ' AND `id` != ?';
            $bindings[] = $ignoreId;
        }

        $row = Database::getInstance()->fetch($sql, $bindings);
        return (int) ($row['total'] ?? 0) > 0;
    }

    private function addError(string $field, string $rule, string $defaultMessage): void
    {
        $message = $this->messages["{$field}.{$rule}"]
            ?? $this->messages[$field]
            ?? $defaultMessage;

        $this->errors[$field][] = $message;
    }
}
