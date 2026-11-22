<?php

declare(strict_types=1);

namespace Core;

final class Autoloader
{
    /** @var array<string, string> */
    private static array $prefixes = [];

    public static function register(string $basePath): void
    {
        self::$prefixes = [
            'Core\\' => rtrim($basePath, '/\\') . DIRECTORY_SEPARATOR . 'core' . DIRECTORY_SEPARATOR,
            'App\\'  => rtrim($basePath, '/\\') . DIRECTORY_SEPARATOR . 'app' . DIRECTORY_SEPARATOR,
        ];

        spl_autoload_register([self::class, 'load']);
    }

    public static function load(string $class): void
    {
        foreach (self::$prefixes as $prefix => $dir) {
            if (!str_starts_with($class, $prefix)) {
                continue;
            }

            $relative = substr($class, strlen($prefix));
            $file = $dir . str_replace('\\', DIRECTORY_SEPARATOR, $relative) . '.php';

            if (is_file($file)) {
                require_once $file;
                return;
            }
        }
    }
}
