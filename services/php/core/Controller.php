<?php

declare(strict_types=1);

namespace Core;

abstract class Controller
{
    /** @param array<string, mixed> $data */
    protected function view(string $template, array $data = [], int $status = 200): Response
    {
        return Response::html(View::render($template, $data), $status);
    }

    protected function json(mixed $data, int $status = 200): Response
    {
        return Response::json($data, $status);
    }

    protected function redirect(string $to, int $status = 302): Response
    {
        return Response::redirect($to, $status);
    }

    protected function back(string $fallback = '/'): Response
    {
        return Response::back($fallback);
    }

    /**
     * @param array<string, string|list<string>> $rules
     * @param array<string, string> $messages
     */
    protected function validate(Request $request, array $rules, array $messages = []): Validator
    {
        return Validator::make($request->all(), $rules, $messages);
    }
}
