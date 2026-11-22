<?php

declare(strict_types=1);

namespace App\Support;

/** Bangladeshi mobile numbers: stored as 01XXXXXXXXX, displayed as +880 1XXX-XXXXXX. */
final class Phone
{
    public static function normalize(string $input): ?string
    {
        $digits = preg_replace('/\D+/', '', $input) ?? '';
        if (str_starts_with($digits, '880')) {
            $digits = '0' . substr($digits, 3);
        } elseif (strlen($digits) === 10 && str_starts_with($digits, '1')) {
            $digits = '0' . $digits;
        }

        return preg_match('/^01[3-9]\d{8}$/', $digits) === 1 ? $digits : null;
    }

    public static function format(?string $stored): string
    {
        if ($stored === null || preg_match('/^0(1\d{3})(\d{6})$/', $stored, $m) !== 1) {
            return (string) $stored;
        }

        return "+880 {$m[1]}-{$m[2]}";
    }
}
