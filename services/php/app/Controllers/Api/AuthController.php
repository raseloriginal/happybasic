<?php

declare(strict_types=1);

namespace App\Controllers\Api;

use App\Controllers\Concerns\JsonActions;
use App\Middleware\ApiAuthMiddleware;
use App\Models\ActivityLog;
use App\Models\UserSession;
use App\Support\ApiUrl;
use App\Support\HttpError;
use App\Support\PanelAuth;
use Core\App;
use Core\Auth;
use Core\Controller;
use Core\Database;
use Core\Request;
use Core\Response;

/** App sign-in (one screen for every role), profile, password and push-device registration. */
final class AuthController extends Controller
{
    use JsonActions;

    public function login(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $data = $this->check($request, [
                'phone' => 'required|string|max:30',
                'password' => 'required|string|max:255',
            ]);
            $res = PanelAuth::attemptApp($request, (string) $data['phone'], (string) $data['password']);

            return ['token' => $res['token'], 'role' => $res['user']['role'], 'profile' => self::profile($res['user'])];
        });
    }

    public function me(): Response
    {
        return $this->action(fn(): array => ['role' => ApiAuthMiddleware::user()['role'], 'profile' => self::profile(ApiAuthMiddleware::user())]);
    }

    public function logout(): Response
    {
        return $this->action(function (): array {
            $user = ApiAuthMiddleware::user();
            // Stop pushes to this phone for this account.
            $fcm = App::request()?->input('fcm_token');
            if (is_string($fcm) && $fcm !== '') {
                Database::getInstance()->execute('DELETE FROM device_tokens WHERE fcm_token = ? AND user_id = ?', [$fcm, $user['id']]);
            }
            PanelAuth::revokeBearer();
            ActivityLog::record('Logout', 'Auth', 'Signed out of the mobile app', $user['id']);

            return ['message' => 'লগআউট হয়েছে।'];
        });
    }

    /** Change own password (SR / DSR). Other devices are signed out. */
    public function password(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $user = ApiAuthMiddleware::user();
            if ($user['role'] === 'retailer') {
                throw new HttpError('দোকানের পাসওয়ার্ড বদলানো যায় না — মোবাইল নম্বরই পাসওয়ার্ড।', 403);
            }
            $data = $this->check($request, [
                'current_password' => 'required|string|max:255',
                'password' => $this->passwordRule(true),
                'password_confirmation' => 'required|string|max:255',
            ]);
            if ($data['password'] !== $data['password_confirmation']) {
                throw new HttpError('নতুন পাসওয়ার্ড দুটি মিলছে না।', 422, ['password_confirmation' => ['পাসওয়ার্ড মিলছে না।']]);
            }

            $db = Database::getInstance();
            $row = $db->fetch('SELECT password FROM users WHERE id = ?', [$user['id']]);
            if ($row === null || !password_verify((string) $data['current_password'], (string) $row['password'])) {
                throw new HttpError('বর্তমান পাসওয়ার্ড ভুল।', 422, ['current_password' => ['ভুল পাসওয়ার্ড।']]);
            }
            $db->execute('UPDATE users SET password = ? WHERE id = ?', [Auth::hashPassword((string) $data['password']), $user['id']]);
            $token = PanelAuth::bearer();
            if ($token !== null) {
                UserSession::revokeUserExcept($user['id'], $token);
            }
            ActivityLog::record('Updated', 'Auth', 'Changed own password from the app', $user['id']);

            return ['message' => 'পাসওয়ার্ড পরিবর্তন হয়েছে। অন্যান্য ডিভাইস থেকে লগ আউট করা হয়েছে।'];
        });
    }

    /** Realtime channels this token may listen to (asked by the Node realtime service, see services/node). */
    public function channels(): Response
    {
        return $this->action(fn(): array => ['channels' => ['user:' . ApiAuthMiddleware::user()['id']]]);
    }

    /** Saves the phone's FCM token so the server can push to it. Idempotent. */
    public function device(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $data = $this->check($request, [
                'fcm_token' => 'required|string|max:255',
                'platform' => 'nullable|string|max:20',
                'app_version' => 'nullable|string|max:20',
            ]);
            // A phone token belongs to whoever signed in last on that phone.
            Database::getInstance()->execute(
                'INSERT INTO device_tokens (user_id, fcm_token, platform, app_version) VALUES (?, ?, ?, ?)
                 ON DUPLICATE KEY UPDATE user_id = VALUES(user_id), platform = VALUES(platform), app_version = VALUES(app_version)',
                [ApiAuthMiddleware::user()['id'], (string) $data['fcm_token'], (string) ($data['platform'] ?: 'android'), $data['app_version']]
            );

            return [];
        });
    }

    /** @param array<string, mixed> $user @return array<string, mixed> */
    public static function profile(array $user): array
    {
        $db = Database::getInstance();
        $base = ['user_id' => (int) $user['id'], 'name' => $user['name'], 'phone' => $user['phone'], 'role' => $user['role']];

        if ($user['role'] === 'sr') {
            $r = $db->fetch(
                'SELECT s.id, s.code, s.area, s.photo_path, s.daily_target, c.name AS company, p.name AS partner
                 FROM salesmen s JOIN companies c ON c.id = s.company_id JOIN partners p ON p.id = s.partner_id
                 WHERE s.user_id = ? AND s.deleted_at IS NULL',
                [$user['id']]
            );

            return $base + ($r === null ? [] : [
                'sr_id' => (int) $r['id'], 'code' => $r['code'] ?: 'SR-' . str_pad((string) $r['id'], 4, '0', STR_PAD_LEFT), 'area' => $r['area'], 'company' => $r['company'], 'partner' => $r['partner'],
                'photo' => ApiUrl::abs($r['photo_path']), 'daily_target' => (float) $r['daily_target'],
            ]);
        }
        if ($user['role'] === 'dsr') {
            $r = $db->fetch(
                'SELECT dm.id, dm.code, dm.photo_path, p.name AS partner
                 FROM delivery_men dm JOIN partners p ON p.id = dm.partner_id
                 WHERE dm.user_id = ? AND dm.deleted_at IS NULL',
                [$user['id']]
            );

            return $base + ($r === null ? [] : [
                'dsr_id' => (int) $r['id'], 'code' => $r['code'], 'partner' => $r['partner'], 'photo' => ApiUrl::abs($r['photo_path']),
            ]);
        }

        $shops = $db->fetchAll("SELECT id, name, address FROM retailers WHERE phone = ? AND status = 'active' ORDER BY id DESC", [$user['phone']]);

        return $base + ['shops' => array_map(static fn(array $s): array => ['id' => (int) $s['id'], 'name' => $s['name'], 'address' => $s['address']], $shops)];
    }
}
