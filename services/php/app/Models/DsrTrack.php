<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\HttpError;
use Core\Database;

/** DSR and SR GPS trail (an SR's id is negative on the live map, so the two lists never clash): recorded whenever the DSR app is open (the app shows a notice), read by the partner (live map, route of a day). */
final class DsrTrack
{
    private const KEEP_DAYS = 90;
    private const ONLINE_SEC = 150;
    private const STOP_RADIUS_M = 45;
    private const STOP_MIN_SEC = 300;

    private static function db(): Database
    {
        return Database::getInstance();
    }

    /**
     * Saves points sent by the phone (also late ones collected offline). Repeats are ignored.
     *
     * @param array<string, mixed> $dsr
     * @param list<mixed> $points
     */
    public static function store(array $dsr, array $points, string $who = 'dsr'): int
    {
        [$table, $col] = $who === 'sr' ? ['sr_locations', 'sr_id'] : ['dsr_locations', 'dsr_id'];
        $now = time();
        $saved = 0;
        foreach (array_slice($points, 0, 300) as $p) {
            if (!is_array($p) || !is_numeric($p['t'] ?? null) || !is_numeric($p['lat'] ?? null) || !is_numeric($p['lng'] ?? null)) {
                continue;
            }
            $t = (int) $p['t'];
            $lat = (float) $p['lat'];
            $lng = (float) $p['lng'];
            if ($t > $now + 120 || $t < $now - 3 * 86400 || abs($lat) > 90 || abs($lng) > 180 || ($lat === 0.0 && $lng === 0.0)) {
                continue;
            }
            $saved += self::db()->execute(
                "INSERT IGNORE INTO {$table} (partner_id, {$col}, recorded_at, lat, lng, accuracy_m, battery) VALUES (?, ?, ?, ?, ?, ?, ?)",
                [$dsr['partner_id'], $dsr['id'], date('Y-m-d H:i:s', min($t, $now)), round($lat, 7), round($lng, 7),
                    is_numeric($p['acc'] ?? null) ? max(0, min(65000, (int) $p['acc'])) : null,
                    is_numeric($p['bat'] ?? null) ? max(0, min(100, (int) $p['bat'])) : null]
            );
        }
        if (random_int(1, 300) === 1) {
            self::db()->execute("DELETE FROM {$table} WHERE recorded_at < (NOW() - INTERVAL " . self::KEEP_DAYS . ' DAY)');
        }

        return $saved;
    }

    /** Every DSR of the partner with the last known place on that day. @return list<array<string, mixed>> */
    public static function team(int $partnerId, string $date): array
    {
        $db = self::db();
        $next = date('Y-m-d', strtotime($date . ' +1 day'));
        $rows = $db->fetchAll(
            "SELECT dm.id, dm.name, dm.phone, dm.photo_path, dm.status, l.lat, l.lng, l.accuracy_m, l.battery, l.recorded_at,
                    a.checked_in_at
             FROM delivery_men dm
             LEFT JOIN dsr_locations l ON l.id = (SELECT x.id FROM dsr_locations x WHERE x.dsr_id = dm.id AND x.recorded_at >= ? AND x.recorded_at < ?
                                                  ORDER BY x.recorded_at DESC LIMIT 1)
             LEFT JOIN dsr_attendance a ON a.dsr_id = dm.id AND a.work_date = ?
             WHERE dm.partner_id = ? AND dm.deleted_at IS NULL AND (dm.status = 'active' OR l.id IS NOT NULL)
             ORDER BY l.recorded_at IS NULL, dm.name",
            [$date, $next, $date, $partnerId]
        );
        $trips = [];
        foreach ($db->fetchAll(
            "SELECT t.dsr_id, COUNT(DISTINCT o.retailer_id) AS shops,
                    COUNT(DISTINCT CASE WHEN o.status NOT IN ('assigned', 'pending') THEN o.retailer_id END) AS done
             FROM trips t LEFT JOIN orders o ON o.trip_id = t.id
             WHERE t.partner_id = ? AND t.trip_date = ? AND t.status IN ('dispatched', 'in_review', 'settled') GROUP BY t.dsr_id",
            [$partnerId, $date]
        ) as $t) {
            $trips[(int) $t['dsr_id']] = $t;
        }

        $today = $date === date('Y-m-d');

        $dsrs = array_map(static function (array $r) use ($today, $trips): array {
            $id = (int) $r['id'];
            $age = $r['recorded_at'] !== null ? max(0, time() - strtotime((string) $r['recorded_at'])) : null;

            return [
                'id' => $id,
                'role' => 'dsr',
                'name' => $r['name'],
                'phone' => $r['phone'],
                'photo' => !empty($r['photo_path']) ? url((string) $r['photo_path']) : null,
                'lat' => $r['lat'] !== null ? (float) $r['lat'] : null,
                'lng' => $r['lng'] !== null ? (float) $r['lng'] : null,
                'accuracy' => $r['accuracy_m'] !== null ? (int) $r['accuracy_m'] : null,
                'battery' => $r['battery'] !== null ? (int) $r['battery'] : null,
                't' => $r['recorded_at'] !== null ? strtotime((string) $r['recorded_at']) : null,
                'online' => $today && $age !== null && $age <= self::ONLINE_SEC,
                'checked_in' => $r['checked_in_at'] !== null ? strtotime((string) $r['checked_in_at']) : null,
                'shops' => (int) ($trips[$id]['shops'] ?? 0),
                'done' => (int) ($trips[$id]['done'] ?? 0),
            ];
        }, $rows);

        return array_merge($dsrs, self::srTeam($partnerId, $date));
    }

    /** The partner's SRs that sent a location that day, same shape as the DSR list. @return list<array<string, mixed>> */
    private static function srTeam(int $partnerId, string $date): array
    {
        $today = $date === date('Y-m-d');
        $rows = self::db()->fetchAll(
            "SELECT s.id, s.name, s.phone, s.photo_path, l.lat, l.lng, l.accuracy_m, l.battery, l.recorded_at
             FROM salesmen s
             JOIN sr_locations l ON l.id = (SELECT x.id FROM sr_locations x WHERE x.sr_id = s.id AND x.recorded_at >= ? AND x.recorded_at < ?
                                            ORDER BY x.recorded_at DESC LIMIT 1)
             WHERE s.partner_id = ? AND s.deleted_at IS NULL ORDER BY s.name",
            [$date, date('Y-m-d', strtotime($date . ' +1 day')), $partnerId]
        );

        return array_map(static function (array $r) use ($today): array {
            $t = strtotime((string) $r['recorded_at']);

            return [
                'id' => -(int) $r['id'],
                'role' => 'sr',
                'name' => $r['name'] . ' (SR)',
                'phone' => $r['phone'],
                'photo' => !empty($r['photo_path']) ? url((string) $r['photo_path']) : null,
                'lat' => (float) $r['lat'],
                'lng' => (float) $r['lng'],
                'accuracy' => $r['accuracy_m'] !== null ? (int) $r['accuracy_m'] : null,
                'battery' => $r['battery'] !== null ? (int) $r['battery'] : null,
                't' => $t,
                'online' => $today && max(0, time() - $t) <= self::ONLINE_SEC,
                'checked_in' => null,
                'shops' => 0,
                'done' => 0,
            ];
        }, $rows);
    }

    /** Route of one DSR on one day: points [t, lat, lng], stops, deliveries and totals. @return array<string, mixed> */
    public static function route(int $partnerId, int $dsrId, string $date): array
    {
        $db = self::db();
        $isSr = $dsrId < 0;
        $dsrId = abs($dsrId);
        [$people, $table, $col] = $isSr ? ['salesmen', 'sr_locations', 'sr_id'] : ['delivery_men', 'dsr_locations', 'dsr_id'];
        if ($db->fetch("SELECT id FROM {$people} WHERE id = ? AND partner_id = ?", [$dsrId, $partnerId]) === null) {
            throw new HttpError(($isSr ? 'SR' : 'DSR') . ' পাওয়া যায়নি।', 404);
        }
        $next = date('Y-m-d', strtotime($date . ' +1 day'));
        $points = [];
        $distance = 0.0;
        $moving = 0;
        $prev = null;
        foreach ($db->fetchAll(
            "SELECT recorded_at, lat, lng FROM {$table} WHERE {$col} = ? AND partner_id = ? AND recorded_at >= ? AND recorded_at < ?
             AND (accuracy_m IS NULL OR accuracy_m <= 100) ORDER BY recorded_at",
            [$dsrId, $partnerId, $date, $next]
        ) as $r) {
            $p = [(int) strtotime((string) $r['recorded_at']), (float) $r['lat'], (float) $r['lng']];
            if ($prev !== null) {
                $d = self::meters($prev, $p);
                $dt = max(1, $p[0] - $prev[0]);
                if ($d / $dt > 42) { // faster than 150 km/h: a wrong fix
                    continue;
                }
                $distance += $d;
                if ($d / $dt > 0.5 && $dt < 300) {
                    $moving += $dt;
                }
            }
            $points[] = $prev = $p;
        }

        $events = [];
        foreach ($isSr ? [] : $db->fetchAll(
            "SELECT o.retailer_id, MIN(o.retailer_name_snapshot) AS name, MIN(o.delivered_at) AS at, SUM(o.delivered_sr_total) AS total,
                    SUM(o.status <> 'cancelled') AS ok, MIN(r.lat) AS lat, MIN(r.lng) AS lng
             FROM orders o JOIN trips t ON t.id = o.trip_id LEFT JOIN retailers r ON r.id = o.retailer_id
             WHERE t.dsr_id = ? AND t.partner_id = ? AND o.delivered_at >= ? AND o.delivered_at < ?
             GROUP BY o.trip_id, o.retailer_id ORDER BY at",
            [$dsrId, $partnerId, $date, $next]
        ) as $e) {
            $events[] = [
                'type' => (int) $e['ok'] > 0 ? 'delivery' : 'cancel', 't' => strtotime((string) $e['at']), 'name' => $e['name'], 'total' => (float) $e['total'],
                'lat' => $e['lat'] !== null ? (float) $e['lat'] : null, 'lng' => $e['lng'] !== null ? (float) $e['lng'] : null,
            ];
        }

        return [
            'points' => $points,
            'stops' => self::stops($points),
            'events' => $events,
            'distance' => (int) round($distance),
            'moving' => $moving,
            'start' => $points[0][0] ?? null,
            'end' => $points !== [] ? $points[count($points) - 1][0] : null,
        ];
    }

    /** Places where the DSR stayed at least 5 minutes. @param list<array{0:int,1:float,2:float}> $points @return list<array<string, mixed>> */
    private static function stops(array $points): array
    {
        $out = [];
        $n = count($points);
        for ($i = 0; $i < $n; $i = $j) {
            $j = $i + 1;
            while ($j < $n && self::meters($points[$i], $points[$j]) <= self::STOP_RADIUS_M) {
                $j++;
            }
            $sec = $points[$j - 1][0] - $points[$i][0];
            if ($sec >= self::STOP_MIN_SEC) {
                $out[] = ['type' => 'stop', 't' => $points[$i][0], 'sec' => $sec, 'lat' => $points[$i][1], 'lng' => $points[$i][2]];
            }
        }

        return $out;
    }

    private static function meters(array $a, array $b): float
    {
        $y = ($b[1] - $a[1]) * 111320;
        $x = ($b[2] - $a[2]) * 111320 * cos(deg2rad($a[1]));

        return sqrt($x * $x + $y * $y);
    }
}
