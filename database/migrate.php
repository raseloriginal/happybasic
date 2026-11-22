<?php

/**
 * Applies pending SQL files from database/migrations/ (sorted by name), each exactly once.
 *
 *   php database/migrate.php                 apply pending (backs up the DB first)
 *   php database/migrate.php --status        list applied / pending, change nothing
 *   php database/migrate.php --baseline[=NNN] mark files <= NNN as applied WITHOUT running them
 *                                            (default NNN = database/BASELINE; for DBs built from schema.sql)
 *   php database/migrate.php --no-backup     skip the mysqldump safety copy
 *
 * MySQL DDL cannot be rolled back: a failing file stops the run, is NOT recorded, and may be
 * partly applied. Fix it (or write the next file so it is safe to re-run) and run again.
 */

declare(strict_types=1);

require_once dirname(__DIR__) . '/services/php/core/App.php';

Core\App::boot(dirname(__DIR__) . '/services/php', dirname(__DIR__));

$opts = getopt('', ['baseline::', 'status', 'no-backup']);
$cfg = config('database');
$dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=%s', $cfg['host'], $cfg['port'], $cfg['database'], $cfg['charset']);
$pdo = new PDO($dsn, (string) $cfg['username'], (string) $cfg['password'], [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);

$pdo->exec('CREATE TABLE IF NOT EXISTS `schema_migrations` (
    `filename` VARCHAR(190) NOT NULL PRIMARY KEY,
    `checksum` CHAR(64) NOT NULL,
    `applied_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');

if (!$pdo->query("SELECT GET_LOCK('happybasic_migrate', 30)")->fetchColumn()) {
    fwrite(STDERR, "Another migration is running.\n");
    exit(1);
}

$files = glob(__DIR__ . '/migrations/*.sql') ?: [];
sort($files);
$applied = $pdo->query('SELECT filename, checksum FROM schema_migrations')->fetchAll(PDO::FETCH_KEY_PAIR);

if (array_key_exists('baseline', $opts)) {
    $limit = is_string($opts['baseline']) && $opts['baseline'] !== ''
        ? $opts['baseline']
        : trim((string) @file_get_contents(__DIR__ . '/BASELINE'));
    $ins = $pdo->prepare('INSERT IGNORE INTO schema_migrations (filename, checksum) VALUES (?, ?)');
    foreach ($files as $f) {
        $name = basename($f);
        if (strnatcmp(substr($name, 0, strlen($limit)), $limit) <= 0) {
            $ins->execute([$name, hash_file('sha256', $f)]);
            echo "baseline: {$name}\n";
        }
    }
    exit(0);
}

$pending = [];
foreach ($files as $f) {
    $name = basename($f);
    if (!isset($applied[$name])) {
        $pending[] = $f;
    } elseif ($applied[$name] !== hash_file('sha256', $f)) {
        echo "warning: {$name} changed after it was applied (ignored; add a new migration instead)\n";
    }
}

if (isset($opts['status'])) {
    foreach ($files as $f) {
        echo (isset($applied[basename($f)]) ? '[x] ' : '[ ] ') . basename($f) . "\n";
    }
    exit(0);
}

if (!$pending) {
    echo "Nothing to migrate.\n";
    exit(0);
}

if (!isset($opts['no-backup'])) {
    $dir = dirname(__DIR__) . '/storage/backups';
    is_dir($dir) || mkdir($dir, 0770, true);
    $out = $dir . '/pre-' . date('Ymd-His') . '.sql';
    $cmd = [
        'mysqldump', '--single-transaction', '--routines',
        '-h' . $cfg['host'], '-P' . $cfg['port'], '-u' . $cfg['username'],
        '--result-file=' . $out, $cfg['database'],
    ];
    $proc = proc_open($cmd, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, null, ['MYSQL_PWD' => (string) $cfg['password']] + getenv());
    $err = '';
    if (is_resource($proc)) {
        stream_get_contents($pipes[1]);
        $err = stream_get_contents($pipes[2]);
        $code = proc_close($proc);
    } else {
        $code = 1;
    }
    if ($code !== 0 || !is_file($out) || filesize($out) === 0) {
        fwrite(STDERR, "Backup failed, migrations NOT applied: {$err}\n(use --no-backup to skip)\n");
        @unlink($out);
        exit(1);
    }
    echo 'backup: ' . basename($out) . "\n";
    $old = glob($dir . '/pre-*.sql') ?: [];
    rsort($old);
    foreach (array_slice($old, 10) as $o) {
        @unlink($o);
    }
}

$ins = $pdo->prepare('INSERT INTO schema_migrations (filename, checksum) VALUES (?, ?)');
foreach ($pending as $f) {
    $name = basename($f);
    $sql = (string) file_get_contents($f);
    $sql = preg_replace('/^\s*--.*$/m', '', $sql) ?? $sql;
    try {
        foreach (array_filter(array_map('trim', explode(';', $sql))) as $statement) {
            if (stripos($statement, 'USE ') === 0) {
                continue; // connection is already on the right database
            }
            $pdo->exec($statement);
        }
    } catch (Throwable $e) {
        fwrite(STDERR, "FAILED {$name}: {$e->getMessage()}\nStopped; later migrations not run.\n");
        exit(1);
    }
    $ins->execute([$name, hash_file('sha256', $f)]);
    echo "applied: {$name}\n";
}
echo "Done.\n";
