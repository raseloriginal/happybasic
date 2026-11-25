<?php

declare(strict_types=1);

namespace App\Support;

use Core\App;

/** Absolute URLs for the mobile app (the web helpers return site-relative paths). */
final class ApiUrl
{
    public static function abs(?string $path): ?string
    {
        if ($path === null || $path === '') {
            return null;
        }
        if (preg_match('#^https?://#i', $path) === 1) {
            return $path;
        }
        $req = App::request();
        $https = $req?->header('X-Forwarded-Proto') === 'https' || (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');
        $host = (string) ($req?->header('Host') ?? $_SERVER['HTTP_HOST'] ?? 'localhost');

        return ($https ? 'https://' : 'http://') . $host . url($path);
    }
}
