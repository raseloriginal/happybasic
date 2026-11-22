<?php

declare(strict_types=1);

namespace App\Controllers\Partner;

use App\Models\CompanyLedger;
use App\Support\HttpError;
use Core\Request;
use Core\Response;

final class CompanyLedgerController extends PartnerController
{
    public function index(Request $request): Response
    {
        $pid = $this->partnerId();
        $summary = CompanyLedger::summary($pid);
        $companyId = $this->intInput($request, 'company') ?? ($summary[0]['id'] ?? null);
        $to = $this->dateQuery($request, 'to');
        $from = $this->dateQuery($request, 'from', date('Y-m-01', strtotime($to)));
        if ($to < $from) {
            [$from, $to] = [$to, $from];
        }

        $statement = null;
        if ($companyId !== null && in_array($companyId, array_column($summary, 'id'), true)) {
            $statement = CompanyLedger::statement($pid, $companyId, $from, $to);
        }

        return $this->view('partner.company-ledger', [
            'title' => 'কোম্পানি খাতা',
            'activeNav' => 'company-ledger',
            'summary' => $summary,
            'companyId' => $statement !== null ? $companyId : null,
            'from' => $from,
            'to' => $to,
            'statement' => $statement,
        ]);
    }

    public function store(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $data = $this->check($request, [
                'company_id' => 'required|integer',
                'type' => 'required|in:payment,adjustment',
                'side' => 'nullable|in:debit,credit',
                'amount' => 'required|numeric',
                'note' => 'nullable|string|max:255',
            ]);
            $date = $this->dateInput($request, 'date');
            if ($date > date('Y-m-d')) {
                throw new HttpError('তারিখ ভবিষ্যতের হতে পারবে না।', 422, ['date' => ['ভবিষ্যতের তারিখ।']]);
            }
            CompanyLedger::addEntry($this->partnerId(), [
                'company_id' => (int) $data['company_id'],
                'type' => (string) $data['type'],
                'side' => (string) ($data['side'] ?? 'credit'),
                'amount' => round((float) $data['amount'], 2),
                'date' => $date,
                'note' => $data['note'] ?: null,
            ]);
            $this->log('Created', 'Company Ledger', "Partner recorded a {$data['type']} of ৳{$data['amount']}");

            return ['message' => \App\Support\Bn::status((string) $data['type']) . ' সংরক্ষিত হয়েছে।'];
        });
    }

    public function destroy(int $id): Response
    {
        return $this->action(function () use ($id): array {
            CompanyLedger::deleteEntry($this->partnerId(), $id);
            return ['message' => 'এন্ট্রি মুছে ফেলা হয়েছে।'];
        });
    }
}
