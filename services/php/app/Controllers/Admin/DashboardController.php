<?php

declare(strict_types=1);

namespace App\Controllers\Admin;

use App\Models\ActivityLog;
use App\Services\SystemHealth;
use Core\Database;
use Core\Response;

final class DashboardController extends AdminController
{
    public function index(): Response
    {
        $db = Database::getInstance();
        $count = static fn(string $sql): int => (int) ($db->fetch($sql)['t'] ?? 0);

        $partners = $count('SELECT COUNT(*) AS t FROM partners WHERE deleted_at IS NULL');
        $partnersThisMonth = $count("SELECT COUNT(*) AS t FROM partners WHERE deleted_at IS NULL AND created_at >= DATE_FORMAT(CURDATE(), '%Y-%m-01')");
        $companies = $count('SELECT COUNT(*) AS t FROM companies WHERE deleted_at IS NULL');
        $activeCompanies = $count("SELECT COUNT(*) AS t FROM companies WHERE deleted_at IS NULL AND status = 'active'");
        $sr = $count('SELECT COUNT(*) AS t FROM salesmen WHERE deleted_at IS NULL');
        $srThisMonth = $count("SELECT COUNT(*) AS t FROM salesmen WHERE deleted_at IS NULL AND created_at >= DATE_FORMAT(CURDATE(), '%Y-%m-01')");
        $dsr = $count("SELECT COUNT(*) AS t FROM delivery_men WHERE status = 'active'");
        $dsrToday = $count('SELECT COUNT(DISTINCT dsr_id) AS t FROM trips WHERE trip_date = CURDATE()');
        $products = $count('SELECT COUNT(*) AS t FROM products');
        $categories = $count("SELECT COUNT(*) AS t FROM categories WHERE deleted_at IS NULL AND status = 'active'");

        $metrics = [
            'partners' => ['label' => 'Total Partners', 'value' => $partners, 'delta' => "+{$partnersThisMonth} this month"],
            'companies' => ['label' => 'Total Companies', 'value' => $companies, 'delta' => "{$activeCompanies} active"],
            'sr' => ['label' => 'Total SR', 'value' => $sr, 'delta' => "+{$srThisMonth} onboarded"],
            'dsr' => ['label' => 'Total DSR', 'value' => $dsr, 'delta' => ($dsr > 0 ? (int) round($dsrToday / $dsr * 100) : 0) . '% active today'],
            'products' => ['label' => 'Total Products', 'value' => $products, 'delta' => "{$categories} global categories"],
        ];

        // Cumulative partner count at the end of each of the last 6 months.
        $growth = [];
        for ($i = 5; $i >= 0; $i--) {
            $monthEnd = date('Y-m-t 23:59:59', strtotime("first day of -{$i} month"));
            $growth[] = [
                'label' => date('M', strtotime($monthEnd)),
                'value' => (int) ($db->fetch(
                    'SELECT COUNT(*) AS t FROM partners WHERE created_at <= ? AND (deleted_at IS NULL OR deleted_at > ?)',
                    [$monthEnd, $monthEnd]
                )['t'] ?? 0),
            ];
        }
        $growthMax = max(1, ...array_column($growth, 'value'));

        $areaRows = $db->fetchAll(
            "SELECT a.name AS area, COUNT(p.id) AS partners FROM areas a
             LEFT JOIN partners p ON p.area_id = a.id AND p.deleted_at IS NULL
             WHERE a.deleted_at IS NULL GROUP BY a.id, a.name ORDER BY partners DESC, a.name"
        );
        $areaMax = max(1, ...array_map(static fn($r) => (int) $r['partners'], $areaRows ?: [['partners' => 0]]));
        $areaBreakdown = array_map(static fn(array $r): array => [
            'area' => $r['area'],
            'partners' => (int) $r['partners'],
            'pct' => $partners > 0 ? (int) round($r['partners'] / $partners * 100) : 0,
            'bar' => (int) round($r['partners'] / $areaMax * 100),
        ], $areaRows);
        $activeZones = count(array_filter($areaBreakdown, static fn($r) => $r['partners'] > 0));

        $recentEvents = array_map(static fn(array $l): array => [
            'title' => $l['detail'],
            'meta' => "{$l['actor']} · {$l['module']} · {$l['action']}",
            'time' => $l['ago'],
        ], ActivityLog::latest(5));

        return $this->view('admin.dashboard', [
            'title' => 'Dashboard',
            'activeNav' => 'dashboard',
            'metrics' => $metrics,
            'growth' => $growth,
            'growthMax' => $growthMax,
            'activeZones' => $activeZones,
            'health' => SystemHealth::snapshot(),
            'areaBreakdown' => $areaBreakdown,
            'recentEvents' => $recentEvents,
        ]);
    }

    public function health(): Response
    {
        return $this->json(['ok' => true, 'health' => SystemHealth::snapshot()]);
    }
}
