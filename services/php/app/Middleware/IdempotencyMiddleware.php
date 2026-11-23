<?php

declare(strict_types=1);

namespace App\Middleware;

use Core\Database;
use Core\Request;
use Core\Response;

/**
 * Makes app writes safe to retry. A write sent with an `X-Op-Id` header runs at most once per user:
 * the result is stored, and any repeat of the same op (offline queue retry, lost response, double tap)
 * gets the stored result back without touching the data again.
 *
 * Must run after the panel auth middleware (needs the signed-in user).
 */
final class IdempotencyMiddleware
{
    private const SAFE_METHODS = ['GET', 'HEAD', 'OPTIONS'];
    /** Not stored: the op never really ran, so it may run on the next try (session, CSRF, rate limit, server error). */
    private const RETRYABLE = [401, 419, 429];

    public function handle(Request $request, callable $next): Response
    {
        $opId = trim((string) $request->header('X-Op-Id', ''));
        if ($opId === '' || in_array($request->method(), self::SAFE_METHODS, true)) {
            return $next($request);
        }
        if (preg_match('/^[A-Za-z0-9_-]{8,64}$/', $opId) !== 1) {
            return Response::json(['ok' => false, 'message' => 'Invalid operation id.'], 422);
        }

        $userId = self::userId();
        $db = Database::getInstance();
        $lock = 'hb_op_' . $opId;
        // Serialise concurrent copies of the same op (e.g. a retry while the first try is still running).
        $db->fetch('SELECT GET_LOCK(?, 20) AS l', [$lock]);
        try {
            $done = $db->fetch('SELECT status_code, response FROM offline_ops WHERE op_id = ? AND user_id = ?', [$opId, $userId]);
            if ($done !== null) {
                return Response::make((string) $done['response'], (int) $done['status_code'], [
                    'Content-Type' => 'application/json; charset=UTF-8',
                    'X-Op-Replayed' => '1',
                ]);
            }

            $response = $next($request);
            $status = $response->getStatus();
            if ($status < 500 && !in_array($status, self::RETRYABLE, true)) {
                $db->execute(
                    'INSERT IGNORE INTO offline_ops (op_id, user_id, path, status_code, response) VALUES (?, ?, ?, ?, ?)',
                    [$opId, $userId, mb_substr($request->method() . ' ' . $request->path(), 0, 190), $status, $response->getBody()]
                );
                if (random_int(1, 200) === 1) {
                    $db->execute('DELETE FROM offline_ops WHERE created_at < (NOW() - INTERVAL 60 DAY)');
                }
            }

            return $response;
        } finally {
            $db->fetch('SELECT RELEASE_LOCK(?) AS l', [$lock]);
        }
    }

    private static function userId(): int
    {
        return (int) DsrAuthMiddleware::dsr()['user_id'];
    }
}
