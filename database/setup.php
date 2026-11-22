<?php

/**
 * Creates the database (if missing) and applies schema.sql.
 * Usage: php database/setup.php
 */

declare(strict_types=1);

require_once dirname(__DIR__) . '/services/php/core/App.php';

Core\App::boot(dirname(__DIR__) . '/services/php', dirname(__DIR__));

$cfg = config('database');
$dsn = sprintf('mysql:host=%s;port=%d;charset=%s', $cfg['host'], $cfg['port'], $cfg['charset']);
$pdo = new PDO($dsn, (string) $cfg['username'], (string) $cfg['password'], [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);

$sql = (string) file_get_contents(__DIR__ . '/schema.sql');
$db = (string) $cfg['database'];
if ($db !== 'happybasic') {
    $sql = str_replace('`happybasic`', '`' . str_replace('`', '', $db) . '`', $sql);
}

// Strip line comments, then run statement by statement.
$sql = preg_replace('/^\s*--.*$/m', '', $sql) ?? $sql;
foreach (array_filter(array_map('trim', explode(';', $sql))) as $statement) {
    $pdo->exec($statement);
}

echo "Database `{$db}` is ready.\n";

// schema.sql already contains every migration up to database/BASELINE; later ones run via migrate.php.
passthru(escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(__DIR__ . '/migrate.php') . ' --baseline');
