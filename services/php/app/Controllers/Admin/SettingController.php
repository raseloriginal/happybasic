<?php

declare(strict_types=1);

namespace App\Controllers\Admin;

use App\Models\ActivityLog;
use App\Models\Area;
use App\Models\Category;
use App\Models\UserSession;
use App\Support\HttpError;
use Core\Request;
use Core\Response;

final class SettingController extends AdminController
{
    private const LOG_LIMIT = 500;

    public function index(): Response
    {
        return $this->view('admin.settings', [
            'title' => 'Settings',
            'activeNav' => 'settings',
            'sessions' => UserSession::active($this->currentSessionToken()),
            'categories' => Category::all(),
            'areas' => Area::all(),
            'logs' => ActivityLog::latest(self::LOG_LIMIT),
            'logModules' => ActivityLog::modules(),
            'logLimit' => self::LOG_LIMIT,
        ]);
    }

    // ---- Categories -------------------------------------------------------

    public function storeCategory(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $data = $this->check($request, ['name' => 'required|string|max:120']);
            $c = Category::present(Category::create((string) $data['name'], $this->statusFrom($request)));
            ActivityLog::record('Created', 'Category', "Added category \"{$c['name']}\"");
            return ['message' => "Category \"{$c['name']}\" added.", 'category' => $c];
        });
    }

    public function categoryStatus(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $c = Category::present(Category::setStatus($id, $this->statusFrom($request)));
            ActivityLog::record('Updated', 'Category', "Changed status of \"{$c['name']}\" to {$c['status']}");
            return ['message' => "Category marked {$c['status']}.", 'category' => $c];
        });
    }

    public function destroyCategory(int $id): Response
    {
        return $this->action(function () use ($id): array {
            $row = Category::delete($id);
            ActivityLog::record('Deleted', 'Category', "Deleted category \"{$row['name']}\"");
            return ['message' => "Category \"{$row['name']}\" removed."];
        });
    }

    // ---- Areas ------------------------------------------------------------

    public function storeArea(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $data = $this->check($request, ['name' => 'required|string|max:100']);
            $a = Area::present(Area::create((string) $data['name'], $this->statusFrom($request)));
            ActivityLog::record('Created', 'Area', "Added area \"{$a['name']}\"");
            return ['message' => "Area \"{$a['name']}\" added.", 'area' => $a];
        });
    }

    public function areaStatus(Request $request, int $id): Response
    {
        return $this->action(function () use ($request, $id): array {
            $a = Area::present(Area::setStatus($id, $this->statusFrom($request)));
            ActivityLog::record('Updated', 'Area', "Changed status of \"{$a['name']}\" to {$a['status']}");
            return ['message' => "Area marked {$a['status']}.", 'area' => $a];
        });
    }

    public function destroyArea(int $id): Response
    {
        return $this->action(function () use ($id): array {
            $row = Area::delete($id);
            ActivityLog::record('Deleted', 'Area', "Deleted area \"{$row['name']}\"");
            return ['message' => "Area \"{$row['name']}\" removed."];
        });
    }

    // ---- Sessions ---------------------------------------------------------

    public function revokeSession(int $id): Response
    {
        return $this->action(function () use ($id): array {
            $current = $this->currentSessionToken();
            $mine = $current !== null ? UserSession::findValid($current) : null;
            if ($mine !== null && (int) $mine['id'] === $id) {
                throw new HttpError('You cannot revoke your current session. Use Sign out instead.', 422);
            }

            $row = UserSession::revokeById($id);
            if ($row === null) {
                throw new HttpError('Session not found or already revoked.', 404);
            }

            ActivityLog::record('Revoked', 'Session', "Revoked session #{$id} of {$row['name']}");
            return ['message' => 'User session revoked.'];
        });
    }

    public function revokeOthers(): Response
    {
        return $this->action(function (): array {
            $count = UserSession::revokeAllExcept((string) $this->currentSessionToken());
            if ($count > 0) {
                ActivityLog::record('Revoked', 'Session', "Revoked {$count} other session(s)");
            }
            return ['message' => $count > 0 ? "Revoked {$count} other session(s)." : 'No other active sessions.', 'revoked' => $count];
        });
    }
}
