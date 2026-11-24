<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\HttpError;
use Core\Database;

/**
 * Partner-side monitoring of delivery men.
 *
 * Wage = daily wage x worked days (QR/manual attendance: present 1, half day 0.5).
 * Month result = wage + over(bonus) - advance - short - salary paid:
 *   positive = partner owes the DSR ("পাবে"), negative = the DSR owes the partner ("দেবে").
 *
 * Day status: a stored row (QR scan or the partner's manual choice) wins; otherwise Friday is a holiday,
 * a past day without a row is absent, today stays "pending" until the DSR scans, future days are not counted.
 */
final class DsrMonitor
{
    /** Weekly off day (PHP date('w'): 5 = Friday). */
    private const WEEKLY_OFF = 5;
    private const DAY_VALUE = ['present' => 1.0, 'half' => 0.5];
    public const DAY_STATUSES = ['present', 'half', 'absent', 'holiday'];

    private static function db(): Database
    {
        return Database::getInstance();
    }

    // ------------------------------------------------------------------ attendance settings (partner)

    /** @return array{token:?string, lat:?float, lng:?float, radius:int, duty_start:string} */
    public static function settings(int $partnerId): array
    {
        $p = self::db()->fetch(
            'SELECT attendance_token, office_lat, office_lng, office_radius_m, duty_start FROM partners WHERE id = ?',
            [$partnerId]
        ) ?? throw new HttpError('Partner not found.', 404);

        return [
            'token' => $p['attendance_token'] !== null ? (string) $p['attendance_token'] : null,
            'lat' => $p['office_lat'] !== null ? (float) $p['office_lat'] : null,
            'lng' => $p['office_lng'] !== null ? (float) $p['office_lng'] : null,
            'radius' => (int) $p['office_radius_m'],
            'duty_start' => substr((string) $p['duty_start'], 0, 5),
        ];
    }

    /** Creates the partner's QR token once (and again only when asked: the old QR then stops working). */
    public static function ensureToken(int $partnerId, bool $regenerate = false): string
    {
        $current = self::settings($partnerId)['token'];
        if ($current !== null && !$regenerate) {
            return $current;
        }
        $token = bin2hex(random_bytes(16));
        self::db()->execute('UPDATE partners SET attendance_token = ? WHERE id = ?', [$token, $partnerId]);

        return $token;
    }

    public static function saveOffice(int $partnerId, ?float $lat, ?float $lng, int $radius, string $dutyStart): void
    {
        if (($lat === null) !== ($lng === null)) {
            throw new HttpError('Set both latitude and longitude.', 422);
        }
        if ($lat !== null && ($lat < -90 || $lat > 90 || $lng < -180 || $lng > 180)) {
            throw new HttpError('Invalid location.', 422);
        }
        if ($radius < 30 || $radius > 5000) {
            throw new HttpError('দূরত্বের সীমা ৩০ থেকে ৫০০০ মিটারের মধ্যে দিন।', 422, ['radius' => ['Radius must be 30-5000 m.']]);
        }
        if (preg_match('/^([01]\d|2[0-3]):[0-5]\d$/', $dutyStart) !== 1) {
            throw new HttpError('ডিউটি শুরুর সময় সঠিক নয়।', 422, ['duty_start' => ['Invalid time.']]);
        }
        self::db()->execute(
            'UPDATE partners SET office_lat = ?, office_lng = ?, office_radius_m = ?, duty_start = ? WHERE id = ?',
            [$lat !== null ? round($lat, 7) : null, $lat !== null ? round($lng, 7) : null, $radius, $dutyStart . ':00', $partnerId]
        );
    }

    // ------------------------------------------------------------------ check-in (DSR)

    /** @return array<string, mixed>|null one day's attendance row of one DSR */
    public static function attendanceOn(int $dsrId, string $date): ?array
    {
        return self::db()->fetch('SELECT * FROM dsr_attendance WHERE dsr_id = ? AND work_date = ?', [$dsrId, $date]);
    }

    /**
     * Records today's arrival after a QR scan. Safe to repeat: a second scan returns the first record.
     * A day the partner already marked by hand (no scan time yet) becomes a scanned "present" day.
     *
     * @param array<string, mixed> $dsr  (id, partner_id)
     * @return array{record: array<string, mixed>, already: bool}
     */
    public static function checkIn(array $dsr, string $token, ?float $lat, ?float $lng, ?float $accuracy): array
    {
        $partnerId = (int) $dsr['partner_id'];
        $dsrId = (int) $dsr['id'];
        $set = self::settings($partnerId);

        if ($set['token'] === null || !hash_equals($set['token'], $token)) {
            throw new HttpError('এই QR কোডটি সঠিক নয় বা আপনার পার্টনারের নয়। পার্টনারের কাছ থেকে নতুন QR নিন।', 422);
        }

        $today = date('Y-m-d');
        $existing = self::attendanceOn($dsrId, $today);
        if ($existing !== null && $existing['checked_in_at'] !== null) {
            return ['record' => $existing, 'already' => true];
        }

        $distance = null;
        if ($set['lat'] !== null && $set['lng'] !== null) {
            if ($lat === null || $lng === null) {
                throw new HttpError('হাজিরার জন্য ফোনের লোকেশন চালু করে অনুমতি দিন।', 422);
            }
            $distance = (int) round(self::meters($set['lat'], $set['lng'], $lat, $lng));
            $allowed = $set['radius'] + (int) min(max((float) $accuracy, 0.0), 100.0);
            if ($distance > $allowed) {
                throw new HttpError('আপনি গোডাউন থেকে প্রায় ' . $distance . ' মিটার দূরে আছেন। গোডাউনে পৌঁছে আবার স্ক্যান করুন।', 422);
            }
        }

        $now = time();
        $dutyTs = strtotime($today . ' ' . $set['duty_start'] . ':00');
        $late = $dutyTs !== false && $now > $dutyTs ? intdiv($now - $dutyTs, 60) : 0;
        $acc = $accuracy !== null ? (int) round($accuracy) : null;
        $at = date('Y-m-d H:i:s', $now);

        if ($existing !== null) {
            self::db()->execute(
                "UPDATE dsr_attendance SET status = 'present', source = 'qr', checked_in_at = ?, lat = ?, lng = ?, accuracy_m = ?, distance_m = ?, late_min = ?
                 WHERE id = ?",
                [$at, $lat, $lng, $acc, $distance, $late, $existing['id']]
            );
        } else {
            try {
                self::db()->execute(
                    "INSERT INTO dsr_attendance (partner_id, dsr_id, work_date, status, source, checked_in_at, lat, lng, accuracy_m, distance_m, late_min)
                     VALUES (?, ?, ?, 'present', 'qr', ?, ?, ?, ?, ?, ?)",
                    [$partnerId, $dsrId, $today, $at, $lat, $lng, $acc, $distance, $late]
                );
            } catch (\PDOException $e) {
                if ((string) $e->getCode() !== '23000') { // double tap: the unique (dsr, day) key already holds it
                    throw $e;
                }
            }
        }

        return ['record' => self::attendanceOn($dsrId, $today) ?? [], 'already' => false];
    }

    /** Great-circle distance in metres. */
    private static function meters(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $r = 6371000.0;
        $p1 = deg2rad($lat1);
        $p2 = deg2rad($lat2);
        $dp = $p2 - $p1;
        $dl = deg2rad($lng2 - $lng1);
        $a = sin($dp / 2) ** 2 + cos($p1) * cos($p2) * sin($dl / 2) ** 2;

        return 2 * $r * asin(min(1.0, sqrt($a)));
    }

    // ------------------------------------------------------------------ day statuses

    public static function validMonth(string $month): string
    {
        return preg_match('/^\d{4}-(0[1-9]|1[0-2])$/', $month) === 1 ? $month : date('Y-m');
    }

    /** @return array{0:string,1:string} first and last day of a Y-m month */
    private static function range(string $month): array
    {
        return [$month . '-01', date('Y-m-t', strtotime($month . '-01') ?: time())];
    }

    /**
     * Every day of the month with its status and worth.
     *
     * @param array<string, array<string, mixed>> $rows attendance rows of this DSR by date
     * @return list<array<string, mixed>>
     */
    private static function buildDays(string $month, string $joined, array $rows): array
    {
        [$from, $to] = self::range($month);
        $today = date('Y-m-d');
        $days = [];
        for ($t = strtotime($from); $t !== false && $t <= strtotime($to); $t = strtotime('+1 day', $t)) {
            $date = date('Y-m-d', $t);
            $row = $rows[$date] ?? null;
            if ($date > $today) {
                $status = 'future';
            } elseif ($date < $joined && $row === null) {
                $status = 'none';
            } elseif ($row !== null) {
                $status = (string) $row['status'];
            } elseif ((int) date('w', $t) === self::WEEKLY_OFF) {
                $status = 'holiday';
            } elseif ($date === $today) {
                $status = 'pending';
            } else {
                $status = 'absent';
            }
            $days[] = [
                'date' => $date,
                'day' => (int) date('j', $t),
                'weekday' => (int) date('w', $t),
                'status' => $status,
                'value' => self::DAY_VALUE[$status] ?? 0.0,
                'manual' => $row !== null && $row['source'] === 'manual',
                'time' => $row['checked_in_at'] ?? null,
                'late_min' => (int) ($row['late_min'] ?? 0),
                'distance' => $row['distance_m'] ?? null,
            ];
        }

        return $days;
    }

    /**
     * @param list<array<string, mixed>> $days
     * @return array{present:int, half:int, absent:int, holiday:int, worked:float, workdays:int, elapsed:int}
     */
    private static function dayTotals(array $days): array
    {
        $c = ['present' => 0, 'half' => 0, 'absent' => 0, 'holiday' => 0];
        $elapsed = 0;
        foreach ($days as $d) {
            if (isset($c[$d['status']])) {
                $c[$d['status']]++;
            }
            if (!in_array($d['status'], ['future', 'none'], true)) {
                $elapsed++;
            }
        }
        $workdays = $elapsed - $c['holiday'] - count(array_filter($days, static fn(array $d): bool => $d['status'] === 'pending'));

        return $c + [
            'worked' => $c['present'] + 0.5 * $c['half'],
            'workdays' => max(0, $workdays),
            'elapsed' => $elapsed,
        ];
    }

    /** Month days of one DSR for the DSR's own history page (past days and today, newest first). @return list<array<string, mixed>> */
    public static function historyFor(int $partnerId, int $dsrId, string $month): array
    {
        $dsr = self::dsrRow($partnerId, $dsrId);
        $days = self::buildDays($month, substr((string) $dsr['created_at'], 0, 10), self::attendanceRows($dsrId, $month));

        return array_reverse(array_values(array_filter($days, static fn(array $d): bool => !in_array($d['status'], ['future', 'none'], true))));
    }

    /** @return array<string, mixed> */
    private static function dsrRow(int $partnerId, int $dsrId): array
    {
        return self::db()->fetch(
            'SELECT id, name, phone, photo_path, zone, vehicle_no, salary, daily_wage, status, created_at
             FROM delivery_men WHERE id = ? AND partner_id = ? AND deleted_at IS NULL',
            [$dsrId, $partnerId]
        ) ?? throw new HttpError('DSR not found.', 404);
    }

    /** @return array<string, array<string, mixed>> */
    private static function attendanceRows(int $dsrId, string $month): array
    {
        [$from, $to] = self::range($month);
        $out = [];
        foreach (self::db()->fetchAll('SELECT * FROM dsr_attendance WHERE dsr_id = ? AND work_date BETWEEN ? AND ?', [$dsrId, $from, $to]) as $a) {
            $out[(string) $a['work_date']] = $a;
        }

        return $out;
    }

    /** Everyone's arrival today (active DSRs only). @return list<array<string, mixed>> */
    public static function todayRoll(int $partnerId): array
    {
        return self::db()->fetchAll(
            'SELECT dm.id, dm.name, dm.photo_path, a.checked_in_at, a.late_min, a.distance_m, a.status
             FROM delivery_men dm
             LEFT JOIN dsr_attendance a ON a.dsr_id = dm.id AND a.work_date = ?
             WHERE dm.partner_id = ? AND dm.status = \'active\' AND dm.deleted_at IS NULL
             ORDER BY a.checked_in_at IS NULL, a.checked_in_at, dm.name',
            [date('Y-m-d'), $partnerId]
        );
    }

    // ------------------------------------------------------------------ month overview

    /**
     * One row per DSR: days, wage and the money result of the month.
     *
     * @return list<array<string, mixed>>
     */
    public static function overview(int $partnerId, string $month): array
    {
        [$from, $to] = self::range($month);
        $db = self::db();

        $dsrs = $db->fetchAll(
            'SELECT id, name, phone, photo_path, zone, vehicle_no, salary, daily_wage, status, created_at FROM delivery_men
             WHERE partner_id = ? AND deleted_at IS NULL ORDER BY status = \'active\' DESC, name',
            [$partnerId]
        );

        $att = [];
        foreach ($db->fetchAll('SELECT * FROM dsr_attendance WHERE partner_id = ? AND work_date BETWEEN ? AND ?', [$partnerId, $from, $to]) as $a) {
            $att[(int) $a['dsr_id']][(string) $a['work_date']] = $a;
        }
        $sum = static fn(string $table, string $dateCol, string $extra = ''): array => self::byDsr($db->fetchAll(
            "SELECT dsr_id, SUM(amount) AS total FROM {$table} WHERE partner_id = ? AND {$dateCol} BETWEEN ? AND ? {$extra} GROUP BY dsr_id",
            [$partnerId, $from, $to]
        ));
        $adv = $sum('dsr_advances', 'given_on');
        $paid = $sum('dsr_salary_payments', 'paid_on');
        $short = $sum('dsr_adjustments', 'adj_date', "AND kind = 'short'");
        $over = $sum('dsr_adjustments', 'adj_date', "AND kind = 'over'");

        $today = date('Y-m-d');
        $out = [];
        foreach ($dsrs as $d) {
            $id = (int) $d['id'];
            $days = self::buildDays($month, substr((string) $d['created_at'], 0, 10), $att[$id] ?? []);
            $t = self::dayTotals($days);
            $wageRate = (float) $d['daily_wage'];
            $wage = round($t['worked'] * $wageRate, 2);
            $advance = (float) ($adv[$id]['total'] ?? 0);
            $shortAmt = (float) ($short[$id]['total'] ?? 0);
            $overAmt = (float) ($over[$id]['total'] ?? 0);
            $paidAmt = (float) ($paid[$id]['total'] ?? 0);
            $todayRow = $att[$id][$today] ?? null;

            $out[] = [
                'id' => $id,
                'name' => $d['name'],
                'phone' => $d['phone'],
                'photo' => !empty($d['photo_path']) ? url((string) $d['photo_path']) : null,
                'active' => $d['status'] === 'active',
                'zone' => $d['zone'],
                'vehicle' => $d['vehicle_no'],
                'joined' => substr((string) $d['created_at'], 0, 10),
                'salary' => (float) $d['salary'],
                'daily_wage' => $wageRate,
                'days' => $days,
                'totals' => $t,
                'wage' => $wage,
                'over' => $overAmt,
                'advance' => $advance,
                'short' => $shortAmt,
                'paid' => $paidAmt,
                'net' => round($wage + $overAmt - $advance - $shortAmt - $paidAmt, 2),
                'in_today' => $todayRow !== null && in_array($todayRow['status'], ['present', 'half'], true),
            ];
        }

        return $out;
    }

    /**
     * Ledger of one DSR for the month: wage first, then advances / short / over / payments with a running balance.
     *
     * @param array<string, mixed> $row one overview() row
     * @return list<array<string, mixed>>
     */
    public static function ledger(int $partnerId, array $row, string $month): array
    {
        [$from, $to] = self::range($month);
        $dsrId = (int) $row['id'];
        $db = self::db();
        $entries = [];
        foreach ($db->fetchAll('SELECT id, amount, given_on AS d, note FROM dsr_advances WHERE dsr_id = ? AND partner_id = ? AND given_on BETWEEN ? AND ?', [$dsrId, $partnerId, $from, $to]) as $r) {
            $entries[] = $r + ['type' => 'advance', 'sign' => -1, 'kind' => 'advance'];
        }
        foreach ($db->fetchAll('SELECT id, amount, adj_date AS d, note, kind AS type FROM dsr_adjustments WHERE dsr_id = ? AND partner_id = ? AND adj_date BETWEEN ? AND ?', [$dsrId, $partnerId, $from, $to]) as $r) {
            $entries[] = $r + ['sign' => $r['type'] === 'over' ? 1 : -1, 'kind' => 'adjustment'];
        }
        foreach ($db->fetchAll('SELECT id, amount, paid_on AS d, note FROM dsr_salary_payments WHERE dsr_id = ? AND partner_id = ? AND paid_on BETWEEN ? AND ?', [$dsrId, $partnerId, $from, $to]) as $r) {
            $entries[] = $r + ['type' => 'payment', 'sign' => -1, 'kind' => 'payment'];
        }
        usort($entries, static fn(array $a, array $b): int => [$a['d'], $a['kind'], (int) $a['id']] <=> [$b['d'], $b['kind'], (int) $b['id']]);

        $balance = (float) $row['wage'];
        $last = array_values(array_filter($row['days'], static fn(array $d): bool => !in_array($d['status'], ['future', 'none'], true)));
        $out = [[
            'type' => 'wage',
            'from' => $last[0]['date'] ?? $from,
            'to' => $last !== [] ? $last[count($last) - 1]['date'] : $from,
            'worked' => $row['totals']['worked'],
            'amount' => $balance,
            'balance' => $balance,
            'id' => null,
            'kind' => null,
            'note' => null,
        ]];
        foreach ($entries as $e) {
            $amount = (float) $e['amount'] * $e['sign'];
            $balance = round($balance + $amount, 2);
            $out[] = ['type' => $e['type'], 'date' => $e['d'], 'amount' => $amount, 'balance' => $balance, 'id' => (int) $e['id'], 'kind' => $e['kind'], 'note' => $e['note']];
        }

        return $out;
    }

    /**
     * Cash short/over that the DSR's own trip settlements recorded (information only — the short/over that
     * counts in the wage result is what the partner enters).
     *
     * @return array{short:float, over:float, trips:int}
     */
    public static function settlementCash(int $partnerId, int $dsrId, string $month): array
    {
        [$from, $to] = self::range($month);
        $r = self::db()->fetch(
            "SELECT COUNT(DISTINCT t.id) AS trips,
                    COALESCE(SUM(LEAST(COALESCE(ts.partner_cash_diff, ts.cash_diff), 0)), 0) AS short_total,
                    COALESCE(SUM(GREATEST(COALESCE(ts.partner_cash_diff, ts.cash_diff), 0)), 0) AS over_total
             FROM trips t
             LEFT JOIN trip_settlements ts ON ts.trip_id = t.id AND ts.status IN ('submitted', 'approved')
             WHERE t.partner_id = ? AND t.dsr_id = ? AND t.trip_date BETWEEN ? AND ? AND t.status IN ('dispatched', 'in_review', 'settled')",
            [$partnerId, $dsrId, $from, $to]
        );

        return ['short' => abs((float) ($r['short_total'] ?? 0)), 'over' => (float) ($r['over_total'] ?? 0), 'trips' => (int) ($r['trips'] ?? 0)];
    }

    // ------------------------------------------------------------------ writes (partner)

    /** Partner sets one day by hand ('auto' goes back to the QR / automatic result). */
    public static function setDay(int $partnerId, int $dsrId, string $date, string $status): void
    {
        self::dsrRow($partnerId, $dsrId);
        if ($date > date('Y-m-d')) {
            throw new HttpError('ভবিষ্যতের তারিখের হাজিরা দেওয়া যায় না।', 422);
        }
        if ($status !== 'auto' && !in_array($status, self::DAY_STATUSES, true)) {
            throw new HttpError('Invalid status.', 422);
        }
        $row = self::attendanceOn($dsrId, $date);

        if ($status === 'auto') {
            if ($row === null) {
                return;
            }
            if ($row['checked_in_at'] !== null) {
                self::db()->execute("UPDATE dsr_attendance SET status = 'present', source = 'qr' WHERE id = ?", [$row['id']]);
            } else {
                self::db()->execute('DELETE FROM dsr_attendance WHERE id = ?', [$row['id']]);
            }

            return;
        }
        if ($row !== null) {
            self::db()->execute(
                'UPDATE dsr_attendance SET status = ?, source = ? WHERE id = ?',
                [$status, $row['checked_in_at'] !== null ? 'qr' : 'manual', $row['id']]
            );

            return;
        }
        self::db()->execute(
            "INSERT INTO dsr_attendance (partner_id, dsr_id, work_date, status, source, checked_in_at, late_min) VALUES (?, ?, ?, ?, 'manual', NULL, 0)",
            [$partnerId, $dsrId, $date, $status]
        );
    }

    /** @param 'advance'|'short'|'over'|'payment' $type */
    public static function addEntry(int $partnerId, int $dsrId, string $type, float $amount, string $date, string $note, int $userId): void
    {
        self::dsrRow($partnerId, $dsrId);
        if ($amount <= 0) {
            throw new HttpError('টাকার পরিমাণ ০-এর বেশি হতে হবে।', 422, ['amount' => ['Amount must be positive.']]);
        }
        $amount = round($amount, 2);
        $note = $note !== '' ? mb_substr($note, 0, 255) : null;
        $db = self::db();
        match ($type) {
            'advance' => $db->execute(
                'INSERT INTO dsr_advances (partner_id, dsr_id, amount, given_on, note, created_by) VALUES (?, ?, ?, ?, ?, ?)',
                [$partnerId, $dsrId, $amount, $date, $note, $userId]
            ),
            'payment' => $db->execute(
                'INSERT INTO dsr_salary_payments (partner_id, dsr_id, pay_month, amount, paid_on, note, created_by) VALUES (?, ?, ?, ?, ?, ?, ?)',
                [$partnerId, $dsrId, substr($date, 0, 7), $amount, $date, $note, $userId]
            ),
            'short', 'over' => $db->execute(
                'INSERT INTO dsr_adjustments (partner_id, dsr_id, kind, amount, adj_date, note, created_by) VALUES (?, ?, ?, ?, ?, ?, ?)',
                [$partnerId, $dsrId, $type, $amount, $date, $note, $userId]
            ),
            default => throw new HttpError('Invalid entry type.', 422),
        };
    }

    /** @param 'advance'|'payment'|'adjustment' $kind */
    public static function deleteEntry(int $partnerId, string $kind, int $id): void
    {
        $table = match ($kind) {
            'advance' => 'dsr_advances',
            'payment' => 'dsr_salary_payments',
            'adjustment' => 'dsr_adjustments',
            default => throw new HttpError('Not found.', 404),
        };
        if (self::db()->execute("DELETE FROM {$table} WHERE id = ? AND partner_id = ?", [$id, $partnerId]) < 1) {
            throw new HttpError('Entry not found.', 404);
        }
    }

    /**
     * @param list<array<string, mixed>> $rows
     * @return array<int, array<string, mixed>>
     */
    private static function byDsr(array $rows): array
    {
        $out = [];
        foreach ($rows as $r) {
            $out[(int) $r['dsr_id']] = $r;
        }

        return $out;
    }
}
