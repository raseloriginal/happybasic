<?php

declare(strict_types=1);

namespace App\Controllers\Admin;

use App\Models\ActivityLog;
use App\Support\ApiUrl;
use App\Support\HttpError;
use Core\Database;
use Core\Request;
use Core\Response;

/** Admin → App: upload Android builds (APK) and share the download link. */
final class AppController extends AdminController
{
    public function index(): Response
    {
        $rows = Database::getInstance()->fetchAll('SELECT * FROM app_releases ORDER BY version_code DESC');

        return $this->view('admin.app', [
            'title' => 'Mobile App',
            'activeNav' => 'app',
            'releases' => $rows,
            'shareUrl' => ApiUrl::abs('/app'),
            'minCode' => (int) env('APP_MIN_VERSION_CODE', 0),
        ]);
    }

    public function store(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $data = $this->check($request, [
                'version_name' => 'required|string|max:20',
                'version_code' => 'required|integer',
                'notes' => 'nullable|string|max:500',
            ]);
            $code = (int) $data['version_code'];
            if ($code < 1) {
                throw new HttpError('Build number must be 1 or more.', 422, ['version_code' => ['Build number must be 1 or more.']]);
            }
            $file = $request->file('apk');
            if ($file === null || ($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK || !is_uploaded_file($file['tmp_name'])) {
                throw new HttpError('APK upload failed. Check the file size limit (upload_max_filesize / post_max_size) and try again.', 422, ['apk' => ['APK upload failed.']]);
            }
            if (strtolower(pathinfo((string) $file['name'], PATHINFO_EXTENSION)) !== 'apk') {
                throw new HttpError('Choose an .apk file.', 422, ['apk' => ['Choose an .apk file.']]);
            }
            // An APK is a ZIP archive.
            $fh = fopen($file['tmp_name'], 'rb');
            $magic = $fh ? fread($fh, 2) : '';
            if ($fh) {
                fclose($fh);
            }
            if ($magic !== 'PK') {
                throw new HttpError('This is not a valid APK file.', 422, ['apk' => ['This is not a valid APK file.']]);
            }

            $db = Database::getInstance();
            if ($db->fetch('SELECT id FROM app_releases WHERE version_code = ?', [$code]) !== null) {
                throw new HttpError("Build {$code} already exists. Use a higher build number.", 422, ['version_code' => ['This build number already exists.']]);
            }

            $dir = base_path('public/uploads/app');
            if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
                throw new HttpError('Could not create the upload folder.', 500);
            }
            $name = 'happybangladesh-' . preg_replace('/[^0-9A-Za-z.\-]/', '', (string) $data['version_name']) . '-' . $code . '.apk';
            if (!move_uploaded_file($file['tmp_name'], "{$dir}/{$name}")) {
                throw new HttpError('Could not save the APK.', 500);
            }
            $db->execute(
                'INSERT INTO app_releases (version_name, version_code, apk_path, apk_size, sha256, notes, force_update) VALUES (?, ?, ?, ?, ?, ?, ?)',
                [(string) $data['version_name'], $code, "uploads/app/{$name}", (int) filesize("{$dir}/{$name}"), hash_file('sha256', "{$dir}/{$name}"),
                    $data['notes'] ?: null, $request->input('force_update') ? 1 : 0]
            );
            ActivityLog::record('Created', 'App', "Uploaded app build {$data['version_name']} ({$code})");

            return ['message' => "Build {$data['version_name']} uploaded.", 'reload' => true];
        });
    }

    public function status(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $status = $this->statusFrom($request);
            Database::getInstance()->execute('UPDATE app_releases SET status = ? WHERE id = ?', [$status, $id]);
            ActivityLog::record('Updated', 'App', "Set app release #{$id} to {$status}");

            return ['message' => 'Release updated.', 'reload' => true];
        });
    }

    public function destroy(int $id): Response
    {
        return $this->action(function () use ($id): array {
            $db = Database::getInstance();
            $row = $db->fetch('SELECT * FROM app_releases WHERE id = ?', [$id]);
            if ($row === null) {
                throw new HttpError('Release not found.', 404);
            }
            $db->execute('DELETE FROM app_releases WHERE id = ?', [$id]);
            $file = base_path('public/' . $row['apk_path']);
            if (str_starts_with((string) $row['apk_path'], 'uploads/app/') && is_file($file)) {
                @unlink($file);
            }
            ActivityLog::record('Deleted', 'App', "Deleted app build {$row['version_name']} ({$row['version_code']})");

            return ['message' => 'Release deleted.', 'reload' => true];
        });
    }
}
