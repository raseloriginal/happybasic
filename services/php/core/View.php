<?php

declare(strict_types=1);

namespace Core;

use RuntimeException;

final class View
{
    /** @var array<string, mixed> */
    private static array $shared = [];

    private ?string $layout = null;
    /** @var array<string, string> */
    private array $sections = [];
    /** @var list<string> */
    private array $sectionStack = [];
    /** @var array<string, mixed> */
    private array $data = [];

    public static function share(string $key, mixed $value): void
    {
        self::$shared[$key] = $value;
    }

    /** @param array<string, mixed> $data */
    public static function render(string $template, array $data = []): string
    {
        $view = new self();
        return $view->renderTemplate($template, $data);
    }

    /** @param array<string, mixed> $data */
    private function renderTemplate(string $template, array $data): string
    {
        $this->data = array_merge(self::$shared, $data);
        $content = $this->evaluate($this->resolvePath($template), $this->data);

        if ($this->layout !== null) {
            if (!array_key_exists('content', $this->sections)) {
                $this->sections['content'] = $content;
            }
            $layout = $this->layout;
            $this->layout = null;
            return $this->evaluate($this->resolvePath($layout), $this->data);
        }

        return $content;
    }

    protected function extend(string $layout): void
    {
        $this->layout = $layout;
    }

    protected function section(string $name, ?string $value = null): void
    {
        if ($value !== null) {
            $this->sections[$name] = $value;
            return;
        }

        $this->sectionStack[] = $name;
        ob_start();
    }

    protected function endSection(): void
    {
        if ($this->sectionStack === []) {
            throw new RuntimeException('Cannot call endSection() without a matching section().');
        }

        $name = array_pop($this->sectionStack);
        $this->sections[$name] = (string) ob_get_clean();
    }

    protected function yield(string $name, string $default = ''): string
    {
        return $this->sections[$name] ?? $default;
    }

    /** @param array<string, mixed> $data */
    protected function include(string $partial, array $data = []): void
    {
        echo $this->evaluate($this->resolvePath($partial), array_merge($this->data, $data));
    }

    protected function e(mixed $value): string
    {
        return htmlspecialchars((string) ($value ?? ''), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }

    /** @param array<string, mixed> $data */
    private function evaluate(string $file, array $data): string
    {
        extract($data, EXTR_SKIP);

        ob_start();
        try {
            include $file;
        } catch (\Throwable $e) {
            ob_end_clean();
            throw $e;
        }

        return (string) ob_get_clean();
    }

    private function resolvePath(string $template): string
    {
        $relative = str_replace('.', DIRECTORY_SEPARATOR, trim($template, './\\'));
        $file = view_path($relative . '.php');

        if (!is_file($file)) {
            throw new RuntimeException("View not found: {$template} ({$file})");
        }

        return $file;
    }
}
