<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\HttpError;
use Core\Database;

/**
 * Partner <-> company account. Debit = amount owed to the company (lot purchases),
 * credit = paid / reduced (payments, damage claims). Balance = debit − credit (payable).
 */
final class CompanyLedger
{
    public const TYPES = ['lot_purchase' => 'Lot Purchase', 'damage_claim' => 'Damage Claim', 'payment' => 'Payment', 'adjustment' => 'Adjustment'];

    private static function db(): Database
    {
        return Database::getInstance();
    }

    /** @return list<array<string, mixed>> one row per connected company */
    public static function summary(int $partnerId): array
    {
        $rows = self::db()->fetchAll(
            "SELECT c.id, c.name,
                    COALESCE(SUM(CASE WHEN l.ref_type = 'lot_purchase' THEN l.debit END), 0) AS purchases,
                    COALESCE(SUM(CASE WHEN l.ref_type = 'payment' THEN l.credit END), 0) AS payments,
                    COALESCE(SUM(l.debit), 0) AS debit, COALESCE(SUM(l.credit), 0) AS credit,
                    MAX(l.entry_date) AS last_entry
             FROM partner_companies pc
             JOIN companies c ON c.id = pc.company_id AND c.deleted_at IS NULL
             LEFT JOIN company_ledger l ON l.partner_id = pc.partner_id AND l.company_id = c.id
             WHERE pc.partner_id = ?
             GROUP BY c.id, c.name ORDER BY c.name",
            [$partnerId]
        );

        return array_map(static fn(array $r): array => [
            'id' => (int) $r['id'],
            'name' => $r['name'],
            'purchases' => (float) $r['purchases'],
            'payments' => (float) $r['payments'],
            'balance' => round((float) $r['debit'] - (float) $r['credit'], 2),
            'last_entry' => $r['last_entry'],
        ], $rows);
    }

    /** @return array{opening:float, closing:float, debit:float, credit:float, entries:list<array<string, mixed>>} */
    public static function statement(int $partnerId, int $companyId, string $from, string $to): array
    {
        self::assertCompany($partnerId, $companyId);
        $open = self::db()->fetch(
            'SELECT COALESCE(SUM(debit - credit), 0) AS bal FROM company_ledger WHERE partner_id = ? AND company_id = ? AND entry_date < ?',
            [$partnerId, $companyId, $from]
        );
        $balance = round((float) $open['bal'], 2);
        $opening = $balance;

        $rows = self::db()->fetchAll(
            'SELECT l.*, lot.lot_code FROM company_ledger l
             LEFT JOIN lots lot ON l.ref_type = \'lot_purchase\' AND lot.id = l.ref_id
             WHERE l.partner_id = ? AND l.company_id = ? AND l.entry_date BETWEEN ? AND ?
             ORDER BY l.entry_date, l.id',
            [$partnerId, $companyId, $from, $to]
        );

        $entries = [];
        $debit = 0.0;
        $credit = 0.0;
        foreach ($rows as $r) {
            $balance = round($balance + (float) $r['debit'] - (float) $r['credit'], 2);
            $debit += (float) $r['debit'];
            $credit += (float) $r['credit'];
            $entries[] = [
                'id' => (int) $r['id'],
                'date' => $r['entry_date'],
                'type' => self::TYPES[$r['ref_type']] ?? $r['ref_type'],
                'type_key' => $r['ref_type'],
                'ref' => $r['lot_code'],
                'note' => $r['note'],
                'debit' => (float) $r['debit'],
                'credit' => (float) $r['credit'],
                'balance' => $balance,
                'manual' => in_array($r['ref_type'], ['payment', 'adjustment'], true),
            ];
        }

        return ['opening' => $opening, 'closing' => $balance, 'debit' => round($debit, 2), 'credit' => round($credit, 2), 'entries' => array_reverse($entries)];
    }

    /** @param array{company_id:int, type:string, side:string, amount:float, date:string, note:?string} $d */
    public static function addEntry(int $partnerId, array $d): void
    {
        self::assertCompany($partnerId, $d['company_id']);
        if ($d['amount'] <= 0) {
            throw new HttpError('Amount must be greater than 0.', 422, ['amount' => ['Amount must be greater than 0.']]);
        }
        $isDebit = $d['type'] === 'adjustment' && $d['side'] === 'debit';
        self::db()->execute(
            'INSERT INTO company_ledger (partner_id, company_id, ref_type, debit, credit, note, entry_date) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [$partnerId, $d['company_id'], $d['type'], $isDebit ? $d['amount'] : 0, $isDebit ? 0 : $d['amount'], $d['note'], $d['date']]
        );
    }

    /** Only manual entries (payments / adjustments) can be removed. */
    public static function deleteEntry(int $partnerId, int $id): void
    {
        $n = self::db()->execute(
            "DELETE FROM company_ledger WHERE id = ? AND partner_id = ? AND ref_type IN ('payment', 'adjustment')",
            [$id, $partnerId]
        );
        if ($n === 0) {
            throw new HttpError('Only payments and adjustments can be deleted.', 422);
        }
    }

    private static function assertCompany(int $partnerId, int $companyId): void
    {
        if (!in_array($companyId, array_column(Product::companyOptions($partnerId), 'id'), true)) {
            throw new HttpError('Company not found.', 404);
        }
    }
}
