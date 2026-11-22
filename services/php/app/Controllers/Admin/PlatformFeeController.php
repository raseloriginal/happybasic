<?php

declare(strict_types=1);

namespace App\Controllers\Admin;

use App\Models\ActivityLog;
use App\Models\Partner;
use App\Models\PlatformFee;
use App\Support\HttpError;
use Core\Request;
use Core\Response;

final class PlatformFeeController extends AdminController
{
    public function index(Request $request): Response
    {
        $partners = Partner::options();
        $selected = (int) ($request->query('partner', 0) ?? 0);
        if (!in_array($selected, array_column($partners, 'id'), true)) {
            $selected = (int) ($partners[0]['id'] ?? 0);
        }

        return $this->view('admin.platform-fees', [
            'title' => 'Platform Fees',
            'activeNav' => 'platform-fees',
            'partners' => $partners,
            'links' => PlatformFee::links(),
            'selectedPartnerId' => $selected,
        ]);
    }

    public function update(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $input = $request->input('fees');
            if (!is_array($input) || $input === []) {
                throw new HttpError('Nothing to save.', 422);
            }

            $fees = [];
            $errors = [];
            foreach ($input as $companyId => $fee) {
                $fee = is_string($fee) ? trim($fee) : $fee;
                if (!ctype_digit((string) $companyId) || !is_numeric($fee) || (float) $fee < 0 || (float) $fee > 99999999) {
                    $errors["fees.{$companyId}"] = ['Enter a fee between 0 and 99,999,999.'];
                    continue;
                }
                $fees[(int) $companyId] = round((float) $fee, 2);
            }
            if ($errors) {
                throw new HttpError('Enter a valid fee (0 or more) for every company.', 422, $errors);
            }

            $partner = Partner::findOrFail($id);
            $changed = PlatformFee::save($id, $fees);
            if ($changed > 0) {
                ActivityLog::record('Updated', 'Platform Fee', "Changed platform fee for {$changed} company(ies) of partner \"{$partner['name']}\" (effective now)");
            }

            return [
                'message' => $changed > 0
                    ? "Platform fees saved for {$partner['name']}. New fees apply to sales from now; past sales keep their old fee."
                    : 'No fee changed.',
                'links' => PlatformFee::links(),
            ];
        });
    }

    public function history(int $id, int $company): Response
    {
        return $this->action(static fn(): array => ['history' => PlatformFee::history($id, $company)]);
    }
}
