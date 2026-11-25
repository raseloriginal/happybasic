<?php

declare(strict_types=1);

namespace App\Controllers\Api;

use App\Support\ApiUrl;
use Core\Controller;
use Core\Database;
use Core\Request;
use Core\Response;

/** Public: which app build is the latest, and where to download it. */
final class AppReleaseController extends Controller
{
    /** The app calls this on start with its own build number. */
    public function latest(Request $request): Response
    {
        $have = (int) $request->query('code', 0);
        $row = Database::getInstance()->fetch("SELECT * FROM app_releases WHERE status = 'active' ORDER BY version_code DESC LIMIT 1");
        if ($row === null) {
            return $this->json(['ok' => true, 'update' => false]);
        }
        $min = (int) env('APP_MIN_VERSION_CODE', 0);
        $newer = (int) $row['version_code'] > $have;

        return $this->json([
            'ok' => true,
            'update' => $newer,
            'force' => $newer && ((bool) $row['force_update'] || ($min > 0 && $have < $min)),
            'version_name' => $row['version_name'],
            'version_code' => (int) $row['version_code'],
            'notes' => $row['notes'],
            'size' => (int) $row['apk_size'],
            'sha256' => $row['sha256'],
            'url' => ApiUrl::abs('/app/download'),
        ]);
    }

    /** Public link for the latest APK: redirects to the static file (Apache serves it with range support). */
    public function download(): Response
    {
        $row = Database::getInstance()->fetch("SELECT * FROM app_releases WHERE status = 'active' ORDER BY version_code DESC LIMIT 1");
        if ($row === null || !is_file(base_path('public/' . $row['apk_path']))) {
            return Response::text('অ্যাপ এখনো আপলোড করা হয়নি।', 404);
        }

        return Response::redirect('/' . $row['apk_path']);
    }

    /** Small public page with the download button (link to share). */
    public function page(): Response
    {
        $row = Database::getInstance()->fetch("SELECT * FROM app_releases WHERE status = 'active' ORDER BY version_code DESC LIMIT 1");

        return $this->view('app.download', ['release' => $row, 'title' => 'অ্যাপ ডাউনলোড']);
    }
}
