<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Controllers\Concerns\JsonActions;
use App\Models\ActivityLog;
use App\Support\PanelAuth;
use Core\Controller;
use Core\Csrf;
use Core\Request;
use Core\Response;

/** Phone + password sign-in pages for the partner (/partner/login) and SR (/sr/login) panels. */
final class PanelAuthController extends Controller
{
    use JsonActions;

    private const PANELS = [
        'partner' => ['role' => 'partner', 'title' => 'পার্টনার প্যানেল', 'home' => '/partner/dashboard'],
        'sr' => ['role' => 'sr', 'title' => 'SR অ্যাপ', 'home' => '/sr/order'],
        'dsr' => ['role' => 'dsr', 'title' => 'DSR ডেলিভারি', 'home' => '/dsr/dashboard'],
    ];

    public function showPartner(): Response
    {
        return $this->show('partner');
    }

    public function showSr(): Response
    {
        return $this->show('sr');
    }

    public function showDsr(): Response
    {
        return $this->show('dsr');
    }

    public function dsrLogin(Request $request): Response
    {
        return $this->login($request, 'dsr');
    }

    public function dsrLogout(): Response
    {
        return $this->logout('dsr');
    }

    public function partnerLogin(Request $request): Response
    {
        return $this->login($request, 'partner');
    }

    public function srLogin(Request $request): Response
    {
        return $this->login($request, 'sr');
    }

    public function partnerLogout(): Response
    {
        return $this->logout('partner');
    }

    public function srLogout(): Response
    {
        return $this->logout('sr');
    }

    private function show(string $panel): Response
    {
        $cfg = self::PANELS[$panel];
        if (PanelAuth::user($panel, $cfg['role']) !== null) {
            return $this->redirect($cfg['home']);
        }

        return $this->view('auth.panel-login', [
            'panelTitle' => $cfg['title'],
            'action' => url("/{$panel}/login"),
            'home' => url($cfg['home']),
            'isBn' => in_array($panel, ['partner', 'sr', 'dsr'], true),
        ]);
    }

    private function login(Request $request, string $panel): Response
    {
        return $this->action(function () use ($request, $panel): array {
            $data = $this->check($request, [
                'phone' => 'required|string|max:30',
                'password' => 'required|string|max:255',
            ]);
            PanelAuth::attempt(
                $request,
                $panel,
                self::PANELS[$panel]['role'],
                (string) $data['phone'],
                (string) $data['password'],
                (bool) $request->input('remember', false)
            );

            return ['message' => 'Signed in.', 'redirect' => url(self::PANELS[$panel]['home']), 'csrf' => Csrf::token()];
        });
    }

    private function logout(string $panel): Response
    {
        $user = PanelAuth::user($panel, self::PANELS[$panel]['role']);
        if ($user !== null) {
            ActivityLog::record('Logout', 'Auth', "Signed out of {$panel} panel", (int) $user['id']);
        }
        PanelAuth::logout($panel);

        return $this->redirect("/{$panel}/login");
    }
}
