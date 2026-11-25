<?php

declare(strict_types=1);

namespace App\Controllers\Dsr;

use App\Models\DsrMonitor;
use App\Support\Bn;
use Core\Request;
use Core\Response;

/** DSR arrival attendance: scan the partner's QR, location is checked against the godown. */
final class AttendanceController extends DsrController
{
    public function index(Request $request): Response
    {
        $dsr = $this->dsr();
        $token = (string) $request->query('t', '');
        $date = $this->pickedDate() ?? date('Y-m-d');
        $row = DsrMonitor::attendanceOn($dsr['id'], $date);

        return $this->view('dsr.attendance', [
            'title' => 'হাজিরা',
            'activeNav' => 'dashboard',
            'selectedDate' => $date,
            'isToday' => $date === date('Y-m-d'),
            'today' => $row !== null && $row['checked_in_at'] !== null ? $row : null, // a day only marked by the partner can still be scanned
            'token' => preg_match('/^[a-f0-9]{16,64}$/', $token) === 1 ? $token : '',
            'days' => DsrMonitor::historyFor($dsr['partner_id'], $dsr['id'], substr($date, 0, 7)),
        ]);
    }

    public function checkIn(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $data = $this->check($request, [
                'token' => 'required|string|max:64',
                'lat' => 'nullable|numeric',
                'lng' => 'nullable|numeric',
                'accuracy' => 'nullable|numeric',
            ]);
            $num = static fn($v): ?float => $v !== null && $v !== '' ? (float) $v : null;
            $res = DsrMonitor::checkIn($this->dsr(), (string) $data['token'], $num($data['lat']), $num($data['lng']), $num($data['accuracy']));
            $at = (string) ($res['record']['checked_in_at'] ?? '');
            $late = (int) ($res['record']['late_min'] ?? 0);
            if (!$res['already']) {
                $this->log('Created', 'DSR attendance ' . date('Y-m-d') . ' ' . $at);
            }

            return [
                'message' => $res['already']
                    ? 'আজকের হাজিরা আগেই নেওয়া হয়েছে — ' . Bn::time($at)
                    : 'হাজিরা সম্পন্ন — ' . Bn::time($at) . ($late > 0 ? ' (' . Bn::digits($late) . ' মিনিট দেরি)' : ''),
                'time' => Bn::time($at),
                'late_min' => $late,
                'already' => $res['already'],
            ];
        });
    }
}
