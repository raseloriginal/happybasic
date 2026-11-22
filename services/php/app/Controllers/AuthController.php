<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Models\User;
use Core\Auth;
use Core\Controller;
use Core\Request;
use Core\Response;

final class AuthController extends Controller
{
    public function showLogin(): Response
    {
        return $this->view('auth.login', ['title' => 'Login']);
    }

    public function login(Request $request): Response
    {
        $validator = $this->validate($request, [
            'email' => 'required|email',
            'password' => 'required|min:6',
        ]);

        if ($validator->fails()) {
            return $this->redirect('/login')
                ->withErrors($validator->errors())
                ->withInput();
        }

        $data = $validator->validated();
        if (!Auth::attempt((string) $data['email'], (string) $data['password'])) {
            return $this->redirect('/login')
                ->withErrors(['email' => ['Invalid email or password.']])
                ->withInput();
        }

        return $this->redirect('/dashboard')
            ->with('success', 'Welcome back!');
    }

    public function showRegister(): Response
    {
        return $this->view('auth.register', ['title' => 'Register']);
    }

    public function register(Request $request): Response
    {
        $validator = $this->validate($request, [
            'name' => 'required|string|min:2|max:100',
            'email' => 'required|email|unique:users,email',
            'password' => 'required|string|min:6|confirmed',
        ]);

        if ($validator->fails()) {
            return $this->redirect('/register')
                ->withErrors($validator->errors())
                ->withInput();
        }

        $data = $validator->validated();
        $id = User::register(
            (string) $data['name'],
            (string) $data['email'],
            (string) $data['password']
        );

        Auth::login($id);

        return $this->redirect('/dashboard')
            ->with('success', 'Account created successfully.');
    }

    public function logout(): Response
    {
        Auth::logout();

        return $this->redirect('/login')
            ->with('success', 'You have been logged out.');
    }
}
