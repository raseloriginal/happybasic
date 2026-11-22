<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\HttpError;
use App\Support\Phone;
use Core\Database;

/** Retail shops, shared by every SR of the same partner. */
final class Retailer
{
    private static function db(): Database
    {
        return Database::getInstance();
    }

    /** @return list<array<string, mixed>> */
    public static function forPartner(int $partnerId): array
    {
        $rows = self::db()->fetchAll(
            "SELECT r.*,
                (SELECT CONCAT(o.order_sr_total, '|', o.order_date) FROM orders o
                 WHERE o.retailer_id = r.id AND o.status <> 'cancelled' ORDER BY o.order_date DESC, o.id DESC LIMIT 1) AS last_order
             FROM retailers r WHERE r.partner_id = ? AND r.status = 'active' ORDER BY r.name",
            [$partnerId]
        );

        return array_map([self::class, 'present'], $rows);
    }

    /** Lightweight list for SR map & Banglish search (optionally nearest N around GPS). @return list<array<string, mixed>> */
    public static function forSrMap(int $partnerId, ?float $lat = null, ?float $lng = null, ?int $limit = null): array
    {
        if ($lat !== null && $lng !== null && $limit !== null && $limit > 0) {
            $rows = self::db()->fetchAll(
                "SELECT id, partner_id, created_by_sr_id, name, phone, address, lat, lng, due_balance
                 FROM retailers
                 WHERE partner_id = ? AND status = 'active'
                 ORDER BY ((lat - ?) * (lat - ?) + (lng - ?) * (lng - ?)) ASC, id DESC
                 LIMIT {$limit}",
                [$partnerId, $lat, $lat, $lng, $lng]
            );
        } else {
            $rows = self::db()->fetchAll(
                "SELECT id, partner_id, created_by_sr_id, name, phone, address, lat, lng, due_balance
                 FROM retailers
                 WHERE partner_id = ? AND status = 'active'
                 ORDER BY id DESC",
                [$partnerId]
            );
        }

        return array_map(static fn(array $r): array => [
            'id' => (int) $r['id'],
            'name' => $r['name'],
            'phone' => $r['phone'] ? Phone::format($r['phone']) : '',
            'address' => $r['address'],
            'lat' => (float) $r['lat'],
            'lng' => (float) $r['lng'],
            'sr_id' => isset($r['created_by_sr_id']) ? (int) $r['created_by_sr_id'] : null,
            'due' => (float) $r['due_balance'],
        ], $rows);
    }

    /** @param array<string, mixed> $r */
    public static function present(array $r): array
    {
        $last = 'No orders yet';
        if (!empty($r['last_order'])) {
            [$amount, $date] = explode('|', (string) $r['last_order']);
            $days = (int) floor((strtotime(date('Y-m-d')) - strtotime($date)) / 86400);
            $when = match (true) {
                $days <= 0 => 'Today',
                $days === 1 => 'Yesterday',
                default => "{$days}d ago",
            };
            $last = '৳ ' . number_format((float) $amount) . ' · ' . $when;
        }

        return [
            'id' => (int) $r['id'],
            'name' => $r['name'],
            'phone' => $r['phone'] ? Phone::format($r['phone']) : '',
            'address' => $r['address'],
            'lat' => (float) $r['lat'],
            'lng' => (float) $r['lng'],
            'sr_id' => isset($r['created_by_sr_id']) ? (int) $r['created_by_sr_id'] : null,
            'due' => (float) $r['due_balance'],
            'last_order' => $last,
        ];
    }

    /** @return array<string, mixed> */
    public static function findForPartner(int $partnerId, int $id): array
    {
        $row = self::db()->fetch("SELECT * FROM retailers WHERE id = ? AND partner_id = ? AND status = 'active'", [$id, $partnerId]);
        if ($row === null) {
            throw new HttpError('Retailer not found.', 404);
        }

        return $row;
    }

    /**
     * Retailer panel login = phone + password (the phone itself). Creates the account the first time an active
     * shop with this phone signs in; does nothing when the phone belongs to no shop or already has an account.
     */
    /** Comparable form of a phone typed in any format: valid BD numbers → 01XXXXXXXXX, otherwise digits only. */
    public static function phoneKey(string $input): string
    {
        return Phone::normalize($input) ?? (preg_replace('/\D+/', '', $input) ?? '');
    }

    /** The phone exactly as stored on an active shop that matches what the retailer typed (any format), or null. */
    public static function loginPhone(string $input): ?string
    {
        $key = self::phoneKey($input);
        if (strlen($key) < 5) {
            return null;
        }
        foreach (self::db()->fetchAll("SELECT DISTINCT phone FROM retailers WHERE phone LIKE ? AND status = 'active'", ['%' . substr($key, -5) . '%']) as $r) {
            if (self::phoneKey((string) $r['phone']) === $key) {
                return (string) $r['phone'];
            }
        }

        return null;
    }

    public static function ensureAccount(string $phone): void
    {
        $shop = self::db()->fetch("SELECT name FROM retailers WHERE phone = ? AND status = 'active' ORDER BY id DESC LIMIT 1", [$phone]);
        $exists = self::db()->fetch('SELECT id FROM users WHERE phone = ? LIMIT 1', [$phone]);
        if ($shop !== null && $exists === null) {
            User::createAccount((string) $shop['name'], $phone, self::phoneKey($phone), 'retailer', 'active');
        }
    }

    /** @param array{name:string, phone:?string, address:string, lat:float, lng:float} $d */
    public static function create(int $partnerId, int $srId, array $d): array
    {
        if (abs($d['lat']) > 90 || abs($d['lng']) > 180 || ($d['lat'] == 0.0 && $d['lng'] == 0.0)) {
            throw new HttpError('Retailer location is missing. Allow location access or place a pin on the map.', 422);
        }
        $dup = self::db()->fetch(
            "SELECT id FROM retailers WHERE partner_id = ? AND name = ? AND status = 'active'
               AND ABS(lat - ?) < 0.0003 AND ABS(lng - ?) < 0.0003",
            [$partnerId, $d['name'], $d['lat'], $d['lng']]
        );
        if ($dup !== null) {
            throw new HttpError("\"{$d['name']}\" is already registered at this location.", 422);
        }

        self::db()->execute(
            'INSERT INTO retailers (partner_id, created_by_sr_id, name, phone, address, lat, lng) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [$partnerId, $srId, $d['name'], $d['phone'], $d['address'], $d['lat'], $d['lng']]
        );

        return self::present(self::findForPartner($partnerId, (int) self::db()->lastInsertId()));
    }
}
