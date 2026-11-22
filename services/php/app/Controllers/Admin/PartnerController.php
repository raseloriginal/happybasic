<?php

declare(strict_types=1);

namespace App\Controllers\Admin;

use App\Models\ActivityLog;
use App\Models\Area;
use App\Models\Partner;
use Core\Request;
use Core\Response;

final class PartnerController extends AdminController
{
    public function index(): Response
    {
        return $this->view('admin.partners', [
            'title' => 'Partners',
            'activeNav' => 'partners',
            'partners' => Partner::all(),
            'areas' => Area::all(),
        ]);
    }

    public function store(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $data = $this->payload($request, true);
            $p = Partner::present(Partner::create($data));
            ActivityLog::record('Created', 'Partner', "Added partner \"{$p['name']}\" ({$p['area']})");
            return ['message' => "Partner \"{$p['name']}\" added.", 'partner' => $p];
        });
    }

    public function update(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $data = $this->payload($request, false);
            $p = Partner::present(Partner::update($id, $data));
            ActivityLog::record('Updated', 'Partner', "Updated partner \"{$p['name']}\"" . ($data['password'] ? ' (password reset)' : ''));
            return ['message' => "Partner \"{$p['name']}\" updated.", 'partner' => $p];
        });
    }

    public function status(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $p = Partner::present(Partner::setStatus($id, $this->statusFrom($request, ['active', 'pending', 'inactive'])));
            ActivityLog::record('Updated', 'Partner', "Changed status of partner \"{$p['name']}\" to {$p['status']}");
            return ['message' => "Partner \"{$p['name']}\" marked {$p['status']}.", 'partner' => $p];
        });
    }

    public function destroy(int $id): Response
    {
        return $this->action(function () use ($id): array {
            $row = Partner::delete($id);
            ActivityLog::record('Deleted', 'Partner', "Deleted partner \"{$row['name']}\"");
            return ['message' => "Partner \"{$row['name']}\" deleted."];
        });
    }

    /** @return array<string, mixed> */
    private function payload(Request $request, bool $creating): array
    {
        $data = $this->check($request, [
            'name' => 'required|string|max:150',
            'number' => 'required|string|max:30',
            'area_id' => 'required|integer',
            'tin' => ['required', 'regex:/^\d{12}$/'],
            'trade_license' => 'required|string|max:100',
            'nid' => ['required', 'regex:/^(\d{10}|\d{13}|\d{17})$/'],
            'address' => 'required|string|max:255',
            'password' => $this->passwordRule($creating),
        ], [
            'area_id.required' => 'Please select an area.',
            'tin.regex' => 'TIN must be exactly 12 digits.',
            'nid.regex' => 'NID must be 10, 13 or 17 digits.',
        ]);

        $data['phone'] = $this->phone($data);
        $data['area_id'] = (int) $data['area_id'];
        $data['status'] = $this->statusFrom($request, ['active', 'pending', 'inactive']);

        return $data;
    }
}
