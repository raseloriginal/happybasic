<?php

declare(strict_types=1);

namespace App\Support;

final class Format
{
    public static function status(?string $status): string
    {
        return ucfirst((string) $status);
    }

    public static function timeAgo(?string $datetime): string
    {
        if ($datetime === null || $datetime === '') {
            return '—';
        }

        $diff = time() - strtotime($datetime);
        if ($diff < 60) {
            return 'Just now';
        }

        foreach ([86400 * 30 => 'month', 86400 => 'day', 3600 => 'hour', 60 => 'min'] as $secs => $unit) {
            if ($diff >= $secs) {
                $n = intdiv($diff, $secs);
                return $n . ' ' . $unit . ($n > 1 ? 's' : '') . ' ago';
            }
        }

        return 'Just now';
    }

    public static function bytes(float $bytes): string
    {
        $units = ['B', 'KB', 'MB', 'GB', 'TB'];
        $i = 0;
        while ($bytes >= 1024 && $i < count($units) - 1) {
            $bytes /= 1024;
            $i++;
        }

        return round($bytes, 1) . ' ' . $units[$i];
    }

    public static function slug(string $text): string
    {
        return trim((string) preg_replace('/[^a-z0-9]+/', '-', strtolower($text)), '-');
    }
}
