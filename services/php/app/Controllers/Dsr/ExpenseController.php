<?php

declare(strict_types=1);

namespace App\Controllers\Dsr;

use App\Models\DsrDelivery;
use Core\Request;
use Core\Response;

final class ExpenseController extends DsrController
{
    public function index(): Response
    {
        $trip = $this->viewTrip();

        return $this->view('dsr.expense', [
            'title' => 'খরচ',
            'activeNav' => 'expense',
            'trip' => $trip,
            'selectedDate' => $this->viewDate($trip),
            'expenses' => $trip ? DsrDelivery::expenses($trip['id']) : [],
            'categories' => DsrDelivery::EXPENSE_CATEGORIES,
        ]);
    }

    public function store(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $data = $this->check($request, [
                'title' => 'required|string|max:150',
                'category' => 'required|string|max:50',
                'amount' => 'required|numeric',
                'note' => 'nullable|string|max:255',
            ]);
            DsrDelivery::addExpense($this->dsr(), [
                'title' => (string) $data['title'],
                'category' => (string) $data['category'],
                'amount' => (float) $data['amount'],
                'note' => $data['note'] ?: null,
            ]);
            $this->log('Created', "DSR expense {$data['title']} ৳{$data['amount']}");

            return ['message' => "খরচ যোগ হয়েছে: {$data['title']}", 'expenses' => DsrDelivery::expenses((int) $this->trip()['id'])];
        });
    }

    public function destroy(int $id): Response
    {
        return $this->action(function () use ($id): array {
            DsrDelivery::deleteExpense($this->dsr(), $id);
            return ['message' => 'খরচ মুছে ফেলা হয়েছে।', 'expenses' => DsrDelivery::expenses((int) $this->trip()['id'])];
        });
    }
}
