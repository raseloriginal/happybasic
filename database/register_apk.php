<?php

/**
 * Registers APKs committed under releases/app/ as app releases (Admin → Mobile App).
 * File name: happybangladesh-<versionName>-<buildNumber>.apk  (optional notes: same name + .txt)
 * Safe to re-run: builds already in app_releases are skipped.
 */

declare(strict_types=1);

require_once dirname(__DIR__) . '/services/php/core/App.php';

Core\App::boot(dirname(__DIR__) . '/services/php', dirname(__DIR__));

$cfg = config('database');
$pdo = new PDO(
    sprintf('mysql:host=%s;port=%d;dbname=%s;charset=%s', $cfg['host'], $cfg['port'], $cfg['database'], $cfg['charset']),
    (string) $cfg['username'], (string) $cfg['password'], [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);

$dest = dirname(__DIR__) . '/services/php/public/uploads/app';
if (!is_dir($dest) && !mkdir($dest, 0775, true) && !is_dir($dest)) {
    fwrite(STDERR, "Cannot create {$dest}\n");
    exit(1);
}
$exists = $pdo->prepare('SELECT 1 FROM app_releases WHERE version_code = ?');
$insert = $pdo->prepare('INSERT INTO app_releases (version_name, version_code, apk_path, apk_size, sha256, notes) VALUES (?, ?, ?, ?, ?, ?)');

foreach (glob(__DIR__ . '/../releases/app/happybangladesh-*.apk') ?: [] as $file) {
    $name = basename($file);
    if (!preg_match('/^happybangladesh-([0-9A-Za-z.\-]+)-(\d+)\.apk$/', $name, $m)) {
        continue;
    }
    [, $version, $code] = $m;
    $exists->execute([(int) $code]);
    if ($exists->fetchColumn()) {
        continue;
    }
    if (!copy($file, "{$dest}/{$name}")) {
        fwrite(STDERR, "Cannot copy {$name}\n");
        exit(1);
    }
    $notes = is_file($file . '.txt') ? trim((string) file_get_contents($file . '.txt')) : '';
    $insert->execute([$version, (int) $code, "uploads/app/{$name}", (int) filesize($file), hash_file('sha256', $file), $notes !== '' ? mb_substr($notes, 0, 500) : null]);
    echo "app release registered: {$version} ({$code})\n";
}
