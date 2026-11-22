<?php

declare(strict_types=1);

namespace App\Controllers\Admin;

use App\Models\ActivityLog;
use App\Models\Company;
use App\Models\Partner;
use Core\Request;
use Core\Response;

final class CompanyController extends AdminController
{
    public function index(Request $request): Response
    {
        $selectedPartnerId = (int) ($request->query('partner', 0) ?? 0);

        return $this->view('admin.companies', [
            'title' => 'Companies',
            'activeNav' => 'companies',
            'partners' => Partner::options(),
            'companies' => Company::all(),
            'selectedPartnerId' => $selectedPartnerId > 0 ? $selectedPartnerId : null,
        ]);
    }

    public function store(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $c = Company::present(Company::create($this->payload($request)));
            ActivityLog::record('Created', 'Company', "Added company \"{$c['name']}\"");
            return ['message' => "Company \"{$c['name']}\" added.", 'company' => $c];
        });
    }

    public function update(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $c = Company::present(Company::update($id, $this->payload($request)));
            ActivityLog::record('Updated', 'Company', "Updated company \"{$c['name']}\"");
            return ['message' => "Company \"{$c['name']}\" updated.", 'company' => $c];
        });
    }

    public function status(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $c = Company::present(Company::setStatus($id, $this->statusFrom($request)));
            ActivityLog::record('Updated', 'Company', "Changed status of company \"{$c['name']}\" to {$c['status']}");
            return ['message' => "Company \"{$c['name']}\" marked {$c['status']}.", 'company' => $c];
        });
    }

    public function destroy(int $id): Response
    {
        return $this->action(function () use ($id): array {
            $row = Company::delete($id);
            ActivityLog::record('Deleted', 'Company', "Deleted company \"{$row['name']}\"");
            return ['message' => "Company \"{$row['name']}\" deleted."];
        });
    }

    /** @return array<string, mixed> */
    private function payload(Request $request): array
    {
        $data = $this->check($request, [
            'name' => 'required|string|max:150',
        ]);
        $data['status'] = $this->statusFrom($request);

        return $data;
    }
}
