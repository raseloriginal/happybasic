<?php

declare(strict_types=1);

namespace App\Services;

use Core\Database;
use Throwable;

/**
 * Push notifications to the mobile app through Firebase Cloud Messaging (HTTP v1).
 *
 * Set FCM_SERVICE_ACCOUNT in .env to the path (relative to the project root, or absolute) of the Firebase
 * service-account JSON. Without it every call is a silent no-op, so the web panels never depend on push.
 * Sending never throws: a failed push must not roll back a business action.
 */
final class Push
{
    /** @var list<array{users:list<int>, title:string, body:string, data:array<string, scalar>}> */
    private static array $queue = [];
    /** @var list<array{channels:list<string>, event:string, data:array<string, mixed>}> */
    private static array $events = [];
    private static bool $hooked = false;

    /** Queues a notification; it is sent after the response, so the user never waits for it. @param list<int> $userIds @param array<string, scalar> $data */
    public static function toUsers(array $userIds, string $title, string $body, array $data = []): void
    {
        $userIds = array_values(array_unique(array_filter(array_map('intval', $userIds))));
        if ($userIds === []) {
            return;
        }
        // The same id travels by push and by realtime, so the app can show it only once.
        $data['nid'] = bin2hex(random_bytes(8));
        self::$queue[] = ['users' => $userIds, 'title' => $title, 'body' => $body, 'data' => $data];
        self::publish(array_map(static fn(int $id): string => "user:{$id}", $userIds), 'notify', ['title' => $title, 'body' => $body] + $data);
    }

    /** Sends a realtime event to connected apps / browsers (after the response). @param list<string> $channels @param array<string, mixed> $data */
    public static function publish(array $channels, string $event, array $data = []): void
    {
        if ($channels === []) {
            return;
        }
        self::$events[] = ['channels' => $channels, 'event' => $event, 'data' => $data];
        if (!self::$hooked) {
            self::$hooked = true;
            register_shutdown_function([self::class, 'flush']);
        }
    }

    public static function flush(): void
    {
        if (function_exists('fastcgi_finish_request')) {
            fastcgi_finish_request();
        }
        try {
            if (self::$events !== []) {
                self::postAll([[
                    'url' => rtrim((string) config('services.endpoints.node'), '/') . '/publish',
                    'body' => (string) json_encode(['events' => self::$events], JSON_UNESCAPED_UNICODE),
                    'headers' => ['Content-Type: application/json', 'X-Service-Token: ' . config('services.token')],
                ]], 2);
            }
            foreach (self::$queue as $n) {
                self::deliver($n['users'], $n['title'], $n['body'], $n['data']);
            }
        } catch (Throwable $e) {
            error_log('[push] ' . $e->getMessage());
        }
        self::$events = self::$queue = [];
    }

    /** @param list<int> $userIds @param array<string, scalar> $data */
    private static function deliver(array $userIds, string $title, string $body, array $data): void
    {
        $account = self::account();
        if ($account === null) {
            return;
        }
        $in = implode(',', array_fill(0, count($userIds), '?'));
        $rows = Database::getInstance()->fetchAll("SELECT fcm_token FROM device_tokens WHERE user_id IN ({$in})", $userIds);
        $access = $rows === [] ? null : self::accessToken($account);
        if ($access === null) {
            return;
        }
        foreach (array_chunk(array_column($rows, 'fcm_token'), 50) as $tokens) {
            $res = self::postAll(array_map(static fn(string $t): array => [
                'url' => "https://fcm.googleapis.com/v1/projects/{$account['project_id']}/messages:send",
                'body' => (string) json_encode(['message' => [
                    'token' => $t,
                    'notification' => ['title' => $title, 'body' => $body],
                    'data' => array_map('strval', $data),
                    'android' => ['priority' => 'HIGH', 'notification' => ['channel_id' => 'hb_default', 'sound' => 'default']],
                ]], JSON_UNESCAPED_UNICODE),
                'headers' => ['Content-Type: application/json', 'Authorization: Bearer ' . $access],
            ], $tokens), 8);
            foreach ($res as $i => [$status, $text]) {
                if ($status === 404 || str_contains($text, 'UNREGISTERED')) { // app uninstalled
                    Database::getInstance()->execute('DELETE FROM device_tokens WHERE fcm_token = ?', [$tokens[$i]]);
                } elseif ($status >= 400) {
                    error_log("[push] FCM {$status}: {$text}");
                }
            }
        }
    }

    /** Login users of the shops with this id's phone. @return list<int> */
    public static function retailerUsers(int $retailerId): array
    {
        return array_map('intval', array_column(Database::getInstance()->fetchAll(
            "SELECT u.id FROM retailers r JOIN users u ON u.phone = r.phone AND u.role = 'retailer' AND u.status = 'active' AND u.deleted_at IS NULL WHERE r.id = ?",
            [$retailerId]
        ), 'id'));
    }

    /** @return list<int> SR login users whose orders of this shop are on the trip */
    public static function srUsersOfStop(int $tripId, int $retailerId): array
    {
        return array_map('intval', array_column(Database::getInstance()->fetchAll(
            'SELECT DISTINCT s.user_id AS id FROM orders o JOIN salesmen s ON s.id = o.sr_id WHERE o.trip_id = ? AND o.retailer_id = ? AND o.is_ready_sale = 0',
            [$tripId, $retailerId]
        ), 'id'));
    }

    /** @return list<int> the DSR's login user of a trip */
    public static function tripDsrUser(int $tripId): array
    {
        $r = Database::getInstance()->fetch('SELECT dm.user_id FROM trips t JOIN delivery_men dm ON dm.id = t.dsr_id WHERE t.id = ?', [$tripId]);

        return $r === null ? [] : [(int) $r['user_id']];
    }

    /** Users of the retailer role whose shop phone belongs to any retailer of the given trip's orders. @return list<int> */
    public static function retailerUsersOfTrip(int $tripId): array
    {
        $rows = Database::getInstance()->fetchAll(
            "SELECT DISTINCT u.id FROM orders o JOIN retailers r ON r.id = o.retailer_id
             JOIN users u ON u.phone = r.phone AND u.role = 'retailer' AND u.status = 'active'
             WHERE o.trip_id = ?",
            [$tripId]
        );

        return array_map(static fn(array $r): int => (int) $r['id'], $rows);
    }

    /** @return array<string, mixed>|null */
    private static function account(): ?array
    {
        $path = (string) env('FCM_SERVICE_ACCOUNT', '');
        if ($path === '') {
            return null;
        }
        if (!preg_match('#^([A-Za-z]:)?[\\\\/]#', $path)) {
            $path = root_path($path);
        }
        $json = is_file($path) ? json_decode((string) file_get_contents($path), true) : null;

        return is_array($json) && isset($json['project_id'], $json['client_email'], $json['private_key']) ? $json : null;
    }

    /** @param array<string, mixed> $account */
    private static function accessToken(array $account): ?string
    {
        $cache = storage_path('cache/fcm-token.json');
        $hit = is_file($cache) ? json_decode((string) file_get_contents($cache), true) : null;
        if (is_array($hit) && ($hit['exp'] ?? 0) > time() + 60 && ($hit['for'] ?? '') === $account['client_email']) {
            return (string) $hit['token'];
        }

        $b64 = static fn(string $s): string => rtrim(strtr(base64_encode($s), '+/', '-_'), '=');
        $now = time();
        $unsigned = $b64((string) json_encode(['alg' => 'RS256', 'typ' => 'JWT'])) . '.' . $b64((string) json_encode([
            'iss' => $account['client_email'],
            'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
            'aud' => 'https://oauth2.googleapis.com/token',
            'iat' => $now,
            'exp' => $now + 3600,
        ]));
        if (!openssl_sign($unsigned, $sig, (string) $account['private_key'], OPENSSL_ALGO_SHA256)) {
            return null;
        }
        [[$status, $res]] = self::postAll([[
            'url' => 'https://oauth2.googleapis.com/token',
            'body' => http_build_query(['grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer', 'assertion' => $unsigned . '.' . $b64($sig)]),
            'headers' => ['Content-Type: application/x-www-form-urlencoded'],
        ]], 8);
        $data = json_decode($res, true);
        if ($status !== 200 || !is_array($data) || empty($data['access_token'])) {
            error_log('[push] token request failed: ' . $res);
            return null;
        }

        $dir = dirname($cache);
        if (!is_dir($dir)) {
            @mkdir($dir, 0775, true);
        }
        @file_put_contents($cache, json_encode(['token' => $data['access_token'], 'exp' => $now + (int) ($data['expires_in'] ?? 3000), 'for' => $account['client_email']]));

        return (string) $data['access_token'];
    }

    /** Posts in parallel. @param list<array{url:string, body:string, headers:list<string>}> $reqs @return list<array{0:int, 1:string}> */
    private static function postAll(array $reqs, int $timeout): array
    {
        $mh = curl_multi_init();
        $hs = [];
        foreach ($reqs as $r) {
            $ch = curl_init($r['url']);
            curl_setopt_array($ch, [
                CURLOPT_POST => true, CURLOPT_POSTFIELDS => $r['body'], CURLOPT_HTTPHEADER => $r['headers'],
                CURLOPT_RETURNTRANSFER => true, CURLOPT_CONNECTTIMEOUT => min(3, $timeout), CURLOPT_TIMEOUT => $timeout,
            ]);
            curl_multi_add_handle($mh, $ch);
            $hs[] = $ch;
        }
        do {
            curl_multi_exec($mh, $running);
            if ($running) {
                curl_multi_select($mh, 0.2);
            }
        } while ($running);
        $out = [];
        foreach ($hs as $ch) {
            $out[] = [(int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE), (string) curl_multi_getcontent($ch)];
            curl_multi_remove_handle($mh, $ch);
        }
        curl_multi_close($mh);

        return $out;
    }
}
