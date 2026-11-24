<?php

declare(strict_types=1);

namespace App\Controllers\Partner;

use App\Models\DsrMonitor;
use Core\Request;
use Core\Response;

/** One page for every DSR: attendance calendar, daily wage, advances, short/over and the month result. */
final class DsrMonitorController extends PartnerController
{
    public function index(Request $request): Response
    {
        $partnerId = $this->partnerId();
        $month = DsrMonitor::validMonth((string) $request->query('month', date('Y-m')));
        $rows = DsrMonitor::overview($partnerId, $month);

        $selected = null;
        $wanted = (int) $request->query('dsr', 0);
        foreach ($rows as $r) {
            if ($r['id'] === $wanted) {
                $selected = $r;
            }
        }
        $selected ??= $rows[0] ?? null;

        $active = array_values(array_filter($rows, static fn(array $r): bool => $r['active']));

        return $this->view('partner.dsr-monitor', [
            'title' => 'ডেলিভারি ম্যান',
            'activeNav' => 'dsr-monitor',
            'month' => $month,
            'rows' => $rows,
            'sel' => $selected,
            'ledger' => $selected ? DsrMonitor::ledger($partnerId, $selected, $month) : [],
            'settlementCash' => $selected ? DsrMonitor::settlementCash($partnerId, $selected['id'], $month) : null,
            'kpi' => [
                'dsrs' => count($active),
                'in_today' => count(array_filter($active, static fn(array $r): bool => $r['in_today'])),
                'wage' => array_sum(array_column($rows, 'wage')),
                'elapsed' => $rows ? max(array_map(static fn(array $r): int => $r['totals']['elapsed'], $rows)) : 0,
                'advance' => array_sum(array_column($rows, 'advance')),
                'short' => array_sum(array_column($rows, 'short')),
                'short_people' => count(array_filter($rows, static fn(array $r): bool => $r['short'] > 0)),
            ],
        ]);
    }

    public function addEntry(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $data = $this->check($request, [
                'type' => 'required|string|max:10',
                'amount' => 'required|numeric',
                'note' => 'nullable|string|max:255',
            ]);
            DsrMonitor::addEntry($this->partnerId(), $id, (string) $data['type'], (float) $data['amount'], $this->dateInput($request, 'date'), (string) ($data['note'] ?? ''), (int) $this->partner()['user_id']);
            $this->log('Created', 'DSR', "Partner added {$data['type']} ৳{$data['amount']} for DSR #{$id}");

            return ['message' => 'সংরক্ষিত হয়েছে।'];
        });
    }

    public function setDay(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $data = $this->check($request, ['status' => 'required|string|max:10']);
            $date = $this->dateInput($request, 'date');
            DsrMonitor::setDay($this->partnerId(), $id, $date, (string) $data['status']);
            $this->log('Updated', 'DSR', "Partner set attendance of DSR #{$id} on {$date} to {$data['status']}");

            return ['message' => 'হাজিরা হালনাগাদ হয়েছে।'];
        });
    }

    public function destroyEntry(string $kind, int $entry): Response
    {
        return $this->action(function () use ($kind, $entry): array {
            DsrMonitor::deleteEntry($this->partnerId(), $kind, $entry);
            $this->log('Deleted', 'DSR', "Partner removed a DSR {$kind} entry #{$entry}");

            return ['message' => 'এন্ট্রি মুছে ফেলা হয়েছে।'];
        });
    }
}
