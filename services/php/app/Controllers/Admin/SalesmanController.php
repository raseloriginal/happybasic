<?php

declare(strict_types=1);

namespace App\Controllers\Admin;

use App\Models\ActivityLog;
use App\Models\Company;
use App\Models\Dealer;
use App\Models\Partner;
use App\Models\Salesman;
use Core\Request;
use Core\Response;

final class SalesmanController extends AdminController
{
    public function index(Request $request): Response
    {
        $selectedPartnerId = (int) ($request->query('partner', 0) ?? 0);

        return $this->view('admin.salesmen', [
            'title' => 'Salesmen (SR)',
            'activeNav' => 'salesmen',
            'partners' => Partner::options(),
            'companies' => Company::options(),
            'dealers' => Dealer::options(),
            'salesmen' => Salesman::all(),
            'selectedPartnerId' => $selectedPartnerId > 0 ? $selectedPartnerId : null,
        ]);
    }

    public function store(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $s = Salesman::present(Salesman::create($this->payload($request, true)));
            ActivityLog::record('Created', 'SR', "Added SR \"{$s['name']}\" to {$s['company']} ({$s['partner_name']})");
            return ['message' => "SR \"{$s['name']}\" added for {$s['partner_name']}.", 'sr' => $s];
        });
    }

    public function update(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $data = $this->payload($request, false);
            $s = Salesman::present(Salesman::update($id, $data));
            ActivityLog::record('Updated', 'SR', "Updated SR \"{$s['name']}\"" . ($data['password'] ? ' (password reset)' : ''));
            return ['message' => "SR \"{$s['name']}\" updated.", 'sr' => $s];
        });
    }

    public function status(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $s = Salesman::present(Salesman::setStatus($id, $this->statusFrom($request)));
            ActivityLog::record('Updated', 'SR', "Changed status of SR \"{$s['name']}\" to {$s['status']}");
            return ['message' => "SR \"{$s['name']}\" marked {$s['status']}.", 'sr' => $s];
        });
    }

    public function destroy(int $id): Response
    {
        return $this->action(function () use ($id): array {
            $row = Salesman::delete($id);
            ActivityLog::record('Deleted', 'SR', "Deleted SR \"{$row['name']}\"");
            return ['message' => "SR \"{$row['name']}\" deleted."];
        });
    }

    /** @return array<string, mixed> */
    private function payload(Request $request, bool $creating): array
    {
        $isDealer = strtolower((string) $request->input('ownership')) === 'dealer';
        $data = $this->check($request, [
            'ownership' => 'required|in:Owned,Dealer',
            'partner_id' => $isDealer ? 'nullable' : 'required|integer',
            'dealer_id' => $isDealer ? 'required|integer' : 'nullable',
            'dealer_profit_share' => $isDealer ? 'required|numeric|min:0|max:100' : 'nullable',
            'name' => 'required|string|max:120',
            'number' => 'required|string|max:30',
            'company_id' => 'required|integer',
            'password' => $this->passwordRule($creating),
        ], [
            'partner_id.required' => 'Please select a partner.',
            'company_id.required' => 'Please select a company.',
            'dealer_id.required' => 'Please select a dealer.',
            'dealer_profit_share.required' => 'Enter the dealer profit share.',
        ]);

        $data['phone'] = $this->phone($data);
        $data['ownership'] = $isDealer ? 'dealer' : 'owned';
        $data['partner_id'] = $isDealer ? 0 : (int) $data['partner_id'];
        $data['dealer_id'] = $isDealer ? (int) $data['dealer_id'] : null;
        $data['company_id'] = (int) $data['company_id'];
        $data['status'] = $this->statusFrom($request);

        return $data;
    }
}
