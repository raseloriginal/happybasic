<?php

declare(strict_types=1);

namespace App\Controllers\Sr;

use App\Controllers\Concerns\JsonActions;
use App\Middleware\SrAuthMiddleware;
use App\Models\ActivityLog;
use App\Models\SrStats;
use App\Models\UserSession;
use App\Support\HttpError;
use App\Support\PanelAuth;
use Core\Auth;
use Core\Controller;
use Core\Database;
use Core\Request;
use Core\Response;
use Core\Session;

final class ProfileController extends Controller
{
    use JsonActions;

    public function index(): Response
    {
        $sr = SrAuthMiddleware::sr();
        $today = date('Y-m-d');
        $last = Database::getInstance()->fetch('SELECT MAX(order_date) AS d FROM orders WHERE sr_id = ?', [$sr['id']]);
        $date = $last['d'] ?? $today;

        return $this->view('sr.profile', [
            'title' => 'আমি',
            'activeNav' => 'profile',
            'date' => $date,
            'today' => $today,
            'daySummary' => SrStats::daySummary($sr['id'], $date),
            'profile' => SrStats::profile($sr['id']),
            'month' => SrStats::range($sr['id'], date('Y-m-01'), $today),
            'monthLabel' => date('F Y'),
        ]);
    }

    /** Daily summary & product breakdown for one date (JSON). */
    public function day(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $raw = (string) $request->input('date', '');
            $d = \DateTime::createFromFormat('!Y-m-d', $raw);
            if ($d === false || $d->format('Y-m-d') !== $raw) {
                throw new HttpError('তারিখ সঠিক নয়।', 422);
            }
            return SrStats::daySummary(SrAuthMiddleware::sr()['id'], $raw);
        });
    }

    /** SR changes their own password; other devices are signed out. */
    public function password(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $sr = SrAuthMiddleware::sr();
            $data = $this->check($request, [
                'current_password' => 'required|string|max:255',
                'password' => $this->passwordRule(true),
                'password_confirmation' => 'required|string|max:255',
            ]);
            if ($data['password'] !== $data['password_confirmation']) {
                throw new HttpError('নতুন পাসওয়ার্ড দুটি মিলছে না।', 422, ['password_confirmation' => ['পাসওয়ার্ড মিলছে না।']]);
            }

            $db = Database::getInstance();
            $user = $db->fetch('SELECT password FROM users WHERE id = ?', [$sr['user_id']]);
            if ($user === null || !password_verify((string) $data['current_password'], (string) $user['password'])) {
                throw new HttpError('বর্তমান পাসওয়ার্ড ভুল।', 422, ['current_password' => ['ভুল পাসওয়ার্ড।']]);
            }

            $db->execute('UPDATE users SET password = ? WHERE id = ?', [Auth::hashPassword((string) $data['password']), $sr['user_id']]);
            $token = Session::get(PanelAuth::tokenKey('sr'));
            if (is_string($token)) {
                UserSession::revokeUserExcept($sr['user_id'], $token);
            }
            ActivityLog::record('Updated', 'Auth', 'SR changed own password', $sr['user_id']);

            return ['message' => 'পাসওয়ার্ড পরিবর্তন হয়েছে। অন্যান্য ডিভাইস থেকে লগ আউট করা হয়েছে।'];
        });
    }
}
