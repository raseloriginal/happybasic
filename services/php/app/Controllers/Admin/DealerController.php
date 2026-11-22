<?php

declare(strict_types=1);

namespace App\Controllers\Admin;

use App\Models\ActivityLog;
use App\Models\Dealer;
use App\Models\Partner;
use Core\Request;
use Core\Response;

final class DealerController extends AdminController
{
    public function index(Request $request): Response
    {
        $selectedPartnerId = (int) ($request->query('partner', 0) ?? 0);

        return $this->view('admin.dealers', [
            'title' => 'Dealers',
            'activeNav' => 'dealers',
            'partners' => Partner::options(),
            'dealers' => Dealer::all(),
            'selectedPartnerId' => $selectedPartnerId > 0 ? $selectedPartnerId : null,
        ]);
    }

    public function store(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $d = Dealer::present(Dealer::create($this->payload($request, true)));
            ActivityLog::record('Created', 'Dealer', "Added dealer \"{$d['name']}\" for {$d['partner_name']}");
            return ['message' => "Dealer \"{$d['name']}\" added for {$d['partner_name']}.", 'dealer' => $d];
        });
    }

    public function update(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $data = $this->payload($request, false);
            $d = Dealer::present(Dealer::update($id, $data));
            ActivityLog::record('Updated', 'Dealer', "Updated dealer \"{$d['name']}\"" . ($data['password'] ? ' (password reset)' : ''));
            return ['message' => "Dealer \"{$d['name']}\" updated.", 'dealer' => $d];
        });
    }

    public function status(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $d = Dealer::present(Dealer::setStatus($id, $this->statusFrom($request)));
            ActivityLog::record('Updated', 'Dealer', "Changed status of dealer \"{$d['name']}\" to {$d['status']}");
            return ['message' => "Dealer \"{$d['name']}\" marked {$d['status']}.", 'dealer' => $d];
        });
    }

    public function destroy(int $id): Response
    {
        return $this->action(function () use ($id): array {
            $row = Dealer::delete($id);
            ActivityLog::record('Deleted', 'Dealer', "Deleted dealer \"{$row['name']}\"");
            return ['message' => "Dealer \"{$row['name']}\" deleted."];
        });
    }

    /** @return array<string, mixed> */
    private function payload(Request $request, bool $creating): array
    {
        $data = $this->check($request, [
            'partner_id' => 'required|integer',
            'name' => 'required|string|max:150',
            'number' => 'required|string|max:30',
            'trade_license' => 'required|string|max:100',
            'nid' => ['required', 'regex:/^(\d{10}|\d{13}|\d{17})$/'],
            'tin' => ['required', 'regex:/^\d{12}$/'],
            'address' => 'required|string|max:255',
            'password' => $this->passwordRule($creating),
        ], [
            'partner_id.required' => 'Please select a partner.',
            'tin.regex' => 'TIN must be exactly 12 digits.',
            'nid.regex' => 'NID must be 10, 13 or 17 digits.',
        ]);

        $data['phone'] = $this->phone($data);
        $data['partner_id'] = (int) $data['partner_id'];
        $data['status'] = $this->statusFrom($request);

        return $data;
    }
}
