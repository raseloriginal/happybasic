<?php

/**
 * Creates (or resets the password of) an admin account.
 * Usage: php database/create-admin.php --email=admin@example.com --name="Super Admin"
 *        The password is read from STDIN (prompted) or --password=...
 */

declare(strict_types=1);

require_once dirname(__DIR__) . '/services/php/core/App.php';

Core\App::boot(dirname(__DIR__) . '/services/php', dirname(__DIR__));

$opts = getopt('', ['email:', 'name::', 'password::']);
$email = strtolower(trim((string) ($opts['email'] ?? '')));
$name = trim((string) ($opts['name'] ?? 'Super Admin'));
$password = (string) ($opts['password'] ?? '');

if (filter_var($email, FILTER_VALIDATE_EMAIL) === false) {
    fwrite(STDERR, "A valid --email is required.\n");
    exit(1);
}

if ($password === '') {
    echo 'Password (min 8 chars): ';
    $password = trim((string) fgets(STDIN));
}

if (mb_strlen($password) < 8) {
    fwrite(STDERR, "Password must be at least 8 characters.\n");
    exit(1);
}

$db = Core\Database::getInstance();
$hash = password_hash($password, PASSWORD_DEFAULT);
$existing = $db->fetch('SELECT id FROM users WHERE email = ? LIMIT 1', [$email]);

if ($existing !== null) {
    $db->execute(
        "UPDATE users SET name = ?, password = ?, role = 'admin', status = 'active', deleted_at = NULL WHERE id = ?",
        [$name, $hash, $existing['id']]
    );
    echo "Admin {$email} updated.\n";
    exit(0);
}

$db->execute(
    "INSERT INTO users (name, email, password, role, status) VALUES (?, ?, ?, 'admin', 'active')",
    [$name, $email, $hash]
);
echo "Admin {$email} created.\n";
