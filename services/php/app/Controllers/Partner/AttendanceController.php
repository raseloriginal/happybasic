<?php

declare(strict_types=1);

namespace App\Controllers\Partner;

use App\Models\DsrMonitor;
use Core\Request;
use Core\Response;

/** QR attendance setup for the partner: one QR for the godown, office location, duty start. */
final class AttendanceController extends PartnerController
{
    public function index(): Response
    {
        $partnerId = $this->partnerId();
        $settings = DsrMonitor::settings($partnerId);
        if ($settings['token'] === null) {
            $settings['token'] = DsrMonitor::ensureToken($partnerId);
        }

        return $this->view('partner.attendance', [
            'title' => 'হাজিরা ও QR',
            'activeNav' => 'attendance',
            'settings' => $settings,
            'scanPath' => url('/dsr/attendance?t=' . $settings['token']),
            'roll' => DsrMonitor::todayRoll($partnerId),
        ]);
    }

    public function save(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $data = $this->check($request, [
                'lat' => 'nullable|numeric',
                'lng' => 'nullable|numeric',
                'radius' => 'required|numeric',
                'duty_start' => 'required|string|max:5',
            ]);
            $lat = $data['lat'] !== null && $data['lat'] !== '' ? (float) $data['lat'] : null;
            $lng = $data['lng'] !== null && $data['lng'] !== '' ? (float) $data['lng'] : null;
            DsrMonitor::saveOffice($this->partnerId(), $lat, $lng, (int) $data['radius'], (string) $data['duty_start']);
            $this->log('Updated', 'Attendance', 'Partner updated attendance location/time settings');

            return ['message' => 'হাজিরার সেটিংস সংরক্ষিত হয়েছে।'];
        });
    }

    public function regenerate(): Response
    {
        return $this->action(function (): array {
            DsrMonitor::ensureToken($this->partnerId(), true);
            $this->log('Updated', 'Attendance', 'Partner regenerated the attendance QR');

            return ['message' => 'নতুন QR তৈরি হয়েছে। আগের ছাপানো QR আর কাজ করবে না।'];
        });
    }
}
