<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\Format;
use App\Support\HttpError;
use App\Support\Phone;
use Core\Database;

/**
 * SRs are the bridge between partners and the global company catalog:
 * saving an SR creates/updates the partner_companies connection.
 */
final class Salesman
{
    private const SELECT = 'SELECT s.*, p.name AS partner_name, c.name AS company_name,
            pc.ownership, pc.dealer_id, pc.dealer_profit_share, pc.partner_profit_share, d.name AS dealer_name
        FROM salesmen s
        JOIN partners p ON p.id = s.partner_id
        JOIN companies c ON c.id = s.company_id
        LEFT JOIN partner_companies pc ON pc.partner_id = s.partner_id AND pc.company_id = s.company_id
        LEFT JOIN dealers d ON d.id = pc.dealer_id';

    private static function db(): Database
    {
        return Database::getInstance();
    }

    /** @return list<array<string, mixed>> */
    public static function all(): array
    {
        return array_map(
            [self::class, 'present'],
            self::db()->fetchAll(self::SELECT . ' WHERE s.deleted_at IS NULL ORDER BY s.id DESC')
        );
    }

    /** @param array<string, mixed> $r */
    public static function present(array $r): array
    {
        $isDealer = ($r['ownership'] ?? 'owned') === 'dealer';

        return [
            'id' => (int) $r['id'],
            'partner_id' => (int) $r['partner_id'],
            'partner_name' => $r['partner_name'],
            'name' => $r['name'],
            'number' => Phone::format($r['phone']),
            'company_id' => (int) $r['company_id'],
            'company' => $r['company_name'],
            'ownership' => $isDealer ? 'Dealer' : 'Owned',
            'dealer_id' => $isDealer ? (int) $r['dealer_id'] : null,
            'dealer' => $isDealer ? $r['dealer_name'] : null,
            'dealer_profit_share' => $isDealer && $r['dealer_profit_share'] !== null ? (float) $r['dealer_profit_share'] : null,
            'partner_profit_share' => $isDealer && $r['partner_profit_share'] !== null ? (float) $r['partner_profit_share'] : null,
            'status' => Format::status($r['status']),
            'daily_target' => (float) ($r['daily_target'] ?? 0),
            'monthly_target' => (float) ($r['monthly_target'] ?? 0),
            'code' => (string) ($r['code'] ?? ''),
        ];
    }

    public static function findOrFail(int $id): array
    {
        $row = self::db()->fetch(self::SELECT . ' WHERE s.id = ? AND s.deleted_at IS NULL', [$id]);
        if ($row === null) {
            throw new HttpError('Salesman not found.', 404);
        }

        return $row;
    }

    /**
     * Resolves partner (directly for Owned, via dealer for Dealer) and validates company.
     * @param array<string, mixed> $d
     * @return array<string, mixed> $d with partner_id filled
     */
    private static function resolve(array $d, ?array $current): array
    {
        if ($d['ownership'] === 'dealer') {
            $dealer = self::db()->fetch('SELECT * FROM dealers WHERE id = ? AND deleted_at IS NULL', [$d['dealer_id']]);
            $keepsDealer = $current !== null && (int) $current['dealer_id'] === (int) $d['dealer_id'];
            if ($dealer === null || ($dealer['status'] !== 'active' && !$keepsDealer)) {
                throw new HttpError('Selected dealer is invalid or inactive.', 422, ['dealer_id' => ['Selected dealer is invalid or inactive.']]);
            }
            $d['partner_id'] = (int) $dealer['partner_id'];
        }

        Partner::assertUsable((int) $d['partner_id']);

        if (!empty($d['code'])) {
            $taken = self::db()->fetch('SELECT id FROM salesmen WHERE code = ? AND deleted_at IS NULL AND id <> ?', [$d['code'], (int) ($current['id'] ?? 0)]);
            if ($taken !== null) {
                throw new HttpError('This SR ID is already used by another SR.', 422, ['code' => ['This SR ID is already used.']]);
            }
        }

        $company = self::db()->fetch('SELECT * FROM companies WHERE id = ? AND deleted_at IS NULL', [$d['company_id']]);
        $keepsCompany = $current !== null && (int) $current['company_id'] === (int) $d['company_id'];
        if ($company === null || ($company['status'] !== 'active' && !$keepsCompany)) {
            throw new HttpError('Selected company is invalid or inactive.', 422, ['company_id' => ['Selected company is invalid or inactive.']]);
        }

        if ($current !== null && (int) $current['partner_id'] !== (int) $d['partner_id']) {
            $id = (int) $current['id'];
            $deps = self::db()->fetch(
                'SELECT (SELECT COUNT(*) FROM orders WHERE sr_id = ?)
                      + (SELECT COUNT(*) FROM retailers WHERE created_by_sr_id = ?)
                      + (SELECT COUNT(*) FROM trip_srs WHERE sr_id = ?) AS t',
                [$id, $id, $id]
            );
            if ((int) ($deps['t'] ?? 0) > 0) {
                throw new HttpError('This SR already has orders, retailers or trips under the current partner, so the partner cannot be changed.', 409);
            }
        }

        return $d;
    }

    /** Creates the partner<->company connection, or checks it matches the existing one. */
    private static function syncLink(Database $db, array $d, int $srId = 0): void
    {
        $isDealer = $d['ownership'] === 'dealer';
        $link = $db->fetch(
            'SELECT pc.*, d.name AS dealer_name FROM partner_companies pc LEFT JOIN dealers d ON d.id = pc.dealer_id
             WHERE pc.partner_id = ? AND pc.company_id = ?',
            [$d['partner_id'], $d['company_id']]
        );

        $dealerShare = $isDealer ? (float) $d['dealer_profit_share'] : null;
        $partnerShare = $isDealer ? round(100 - $dealerShare, 2) : null;

        if ($link === null) {
            $db->execute(
                'INSERT INTO partner_companies (partner_id, company_id, ownership, dealer_id, dealer_profit_share, partner_profit_share)
                 VALUES (?, ?, ?, ?, ?, ?)',
                [$d['partner_id'], $d['company_id'], $d['ownership'], $isDealer ? $d['dealer_id'] : null, $dealerShare, $partnerShare]
            );
            return;
        }

        $sameDealer = (int) $link['dealer_id'] === (int) ($isDealer ? $d['dealer_id'] : 0);
        $otherSrs = (int) ($db->fetch(
            'SELECT COUNT(*) AS t FROM salesmen WHERE partner_id = ? AND company_id = ? AND deleted_at IS NULL AND id <> ?',
            [$d['partner_id'], $d['company_id'], $srId]
        )['t'] ?? 0);
        if (($link['ownership'] !== $d['ownership'] || ($isDealer && !$sameDealer)) && $otherSrs === 0) {
            // Nobody else uses this connection, so it can be re-pointed.
            $db->execute(
                'UPDATE partner_companies SET ownership = ?, dealer_id = ?, dealer_profit_share = ?, partner_profit_share = ? WHERE id = ?',
                [$d['ownership'], $isDealer ? $d['dealer_id'] : null, $dealerShare, $partnerShare, $link['id']]
            );
            return;
        }
        if ($link['ownership'] !== $d['ownership'] || ($isDealer && !$sameDealer)) {
            $existing = $link['ownership'] === 'dealer' ? "via dealer \"{$link['dealer_name']}\"" : 'as Owned';
            throw new HttpError("This partner is already connected to this company {$existing}. Use the same ownership/dealer for its SRs.", 422, ['ownership' => ["Partner already connected {$existing}."]]);
        }

        if ($isDealer) {
            $db->execute(
                'UPDATE partner_companies SET dealer_profit_share = ?, partner_profit_share = ? WHERE id = ?',
                [$dealerShare, $partnerShare, $link['id']]
            );
        }
    }

    /** @param array<string, mixed> $d */
    public static function create(array $d): array
    {
        $d = self::resolve($d, null);

        return self::db()->transaction(static function (Database $db) use ($d): array {
            self::syncLink($db, $d);
            $userId = User::createAccount($d['name'], $d['phone'], $d['password'], 'sr', $d['status']);
            $db->execute(
                'INSERT INTO salesmen (partner_id, company_id, user_id, name, phone, joining_date, status, daily_target, monthly_target, code) VALUES (?, ?, ?, ?, ?, CURDATE(), ?, ?, ?, ?)',
                [$d['partner_id'], $d['company_id'], $userId, $d['name'], $d['phone'], $d['status'], $d['daily_target'], $d['monthly_target'], $d['code']]
            );

            return self::findOrFail((int) $db->lastInsertId());
        });
    }

    /** @param array<string, mixed> $d */
    public static function update(int $id, array $d): array
    {
        $current = self::findOrFail($id);
        $d = self::resolve($d, $current);

        return self::db()->transaction(static function (Database $db) use ($id, $d, $current): array {
            self::syncLink($db, $d, $id);
            User::syncAccount((int) $current['user_id'], $d['name'], $d['phone'], $d['status'], $d['password'] ?? null);
            $db->execute(
                'UPDATE salesmen SET partner_id = ?, company_id = ?, name = ?, phone = ?, status = ?, daily_target = ?, monthly_target = ?, code = ? WHERE id = ?',
                [$d['partner_id'], $d['company_id'], $d['name'], $d['phone'], $d['status'], $d['daily_target'], $d['monthly_target'], $d['code'], $id]
            );

            return self::findOrFail($id);
        });
    }

    public static function setStatus(int $id, string $status): array
    {
        $current = self::findOrFail($id);

        return self::db()->transaction(static function (Database $db) use ($id, $status, $current): array {
            $db->execute('UPDATE salesmen SET status = ? WHERE id = ?', [$status, $id]);
            User::setStatus((int) $current['user_id'], $status);
            return self::findOrFail($id);
        });
    }

    public static function delete(int $id): array
    {
        $row = self::findOrFail($id);

        self::db()->transaction(static function (Database $db) use ($id, $row): void {
            $db->execute("UPDATE salesmen SET status = 'inactive', deleted_at = NOW() WHERE id = ?", [$id]);
            User::softDelete((int) $row['user_id']);
        });

        return $row;
    }
}
