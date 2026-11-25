<?php

declare(strict_types=1);

namespace App\Controllers\Partner;

use App\Models\Due;
use Core\Request;
use Core\Response;

/** Unpaid orders: approve / goods taken back, then collected / undo. */
final class DueController extends PartnerController
{
    public function index(): Response
    {
        $id = $this->partnerId();

        return $this->view('partner.dues', [
            'title' => 'বাকি',
            'activeNav' => 'dues',
            'dues' => Due::all($id),
            'settings' => Due::settings($id),
            'today' => Due::collectedToday($id),
        ]);
    }

    public function approve(int $id): Response
    {
        return $this->run('Approved', 'due approved', 'বাকি অনুমোদন হয়েছে।', fn(int $p, int $u): array => Due::approve($p, $id, $u));
    }

    public function collect(Request $request, int $id): Response
    {
        return $this->run('Updated', 'due collected', 'টাকা উত্তোলন সংরক্ষিত হয়েছে।', fn(int $p, int $u): array => Due::collect($p, $id, (float) $request->input('amount', 0), $u));
    }

    public function takeBack(Request $request, int $id): Response
    {
        return $this->run('Updated', 'goods taken back', 'মাল ফেরত নেওয়া হয়েছে, স্টকে যোগ হয়েছে।', fn(int $p, int $u): array => Due::takeBack($p, $id, (array) $request->input('items', []), $u));
    }

    public function undo(int $id): Response
    {
        return $this->run('Updated', 'due step undone', 'আগের অবস্থায় ফেরানো হয়েছে।', fn(int $p, int $u): array => Due::undo($p, $id));
    }

    public function settings(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $d = $this->check($request, ['limit' => 'required|numeric', 'days' => 'required|numeric']);
            Due::saveSettings($this->partnerId(), (float) $d['limit'], (int) $d['days']);
            return ['message' => 'ডিফল্ট সীমা সংরক্ষিত হয়েছে।'];
        });
    }

    public function shopLimit(Request $request, int $retailer): Response
    {
        return $this->action(function () use ($request, $retailer): array {
            $d = $this->check($request, ['limit' => 'nullable|numeric']);
            $v = $d['limit'] ?? null;
            Due::saveShopLimit($this->partnerId(), $retailer, $v === null || $v === '' ? null : (float) $v);
            return ['message' => 'দোকানের সীমা সংরক্ষিত হয়েছে।'];
        });
    }

    private function run(string $action, string $what, string $message, callable $task): Response
    {
        return $this->action(function () use ($action, $what, $message, $task): array {
            $row = $task($this->partnerId(), (int) $this->partner()['user_id']);
            $this->log($action, 'Due', "{$row['code']} ({$row['retailer']}): {$what}");
            return ['message' => $message];
        });
    }
}
