<?php

declare(strict_types=1);

namespace App\Controllers;

use Core\Auth;
use Core\Controller;
use Core\Request;
use Core\Response;

final class HomeController extends Controller
{
    public function index(): Response
    {
        return $this->view('home.index', [
            'title' => config('app.name', 'HappyBasic'),
        ]);
    }

    public function dashboard(): Response
    {
        return $this->view('home.dashboard', [
            'title' => 'Dashboard',
            'user' => Auth::user(),
        ]);
    }

    public function health(Request $request): Response
    {
        return $this->json([
            'status' => 'ok',
            'service' => 'php',
            'app' => config('app.name'),
            'method' => $request->method(),
            'path' => $request->path(),
        ]);
    }

    public function servicesHealth(): Response
    {
        $results = [];
        foreach (array_keys((array) config('services.endpoints', [])) as $name) {
            $res = service((string) $name)->get('/health');
            $results[$name] = [
                'ok' => $res['ok'],
                'status' => $res['status'],
                'data' => $res['data'],
                'error' => $res['error'],
            ];
        }

        return $this->json([
            'status' => 'ok',
            'services' => $results,
        ]);
    }
}
