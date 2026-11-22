<?php

declare(strict_types=1);

namespace Core;

use ReflectionFunction;
use ReflectionMethod;
use ReflectionNamedType;
use RuntimeException;

final class Router
{
    /**
     * @var list<array{
     *     methods: list<string>,
     *     pattern: string,
     *     regex: string,
     *     paramNames: list<string>,
     *     handler: callable|array{0: class-string, 1: string},
     *     middleware: list<class-string|callable>,
     *     name: ?string
     * }>
     */
    private array $routes = [];

    /** @var array<string, int> */
    private array $namedRoutes = [];

    /** @var list<array{prefix: string, middleware: list<class-string|callable>}> */
    private array $groupStack = [];

    private ?int $lastRouteIndex = null;

    /** @param callable|array{0: class-string, 1: string} $handler */
    public function get(string $path, callable|array $handler): self
    {
        return $this->addRoute(['GET', 'HEAD'], $path, $handler);
    }

    /** @param callable|array{0: class-string, 1: string} $handler */
    public function post(string $path, callable|array $handler): self
    {
        return $this->addRoute(['POST'], $path, $handler);
    }

    /** @param callable|array{0: class-string, 1: string} $handler */
    public function put(string $path, callable|array $handler): self
    {
        return $this->addRoute(['PUT'], $path, $handler);
    }

    /** @param callable|array{0: class-string, 1: string} $handler */
    public function patch(string $path, callable|array $handler): self
    {
        return $this->addRoute(['PATCH'], $path, $handler);
    }

    /** @param callable|array{0: class-string, 1: string} $handler */
    public function delete(string $path, callable|array $handler): self
    {
        return $this->addRoute(['DELETE'], $path, $handler);
    }

    /** @param callable|array{0: class-string, 1: string} $handler */
    public function any(string $path, callable|array $handler): self
    {
        return $this->addRoute(['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE'], $path, $handler);
    }

    /**
     * @param list<string> $methods
     * @param callable|array{0: class-string, 1: string} $handler
     */
    public function match(array $methods, string $path, callable|array $handler): self
    {
        return $this->addRoute(array_map('strtoupper', $methods), $path, $handler);
    }

    /** @param array{prefix?: string, middleware?: class-string|callable|list<class-string|callable>} $attributes */
    public function group(array $attributes, callable $callback): void
    {
        $middleware = $attributes['middleware'] ?? [];
        if (!is_array($middleware)) {
            $middleware = [$middleware];
        }

        $this->groupStack[] = [
            'prefix' => trim((string) ($attributes['prefix'] ?? ''), '/'),
            'middleware' => $middleware,
        ];

        $callback($this);
        array_pop($this->groupStack);
    }

    /** @param class-string|callable|list<class-string|callable> $middleware */
    public function middleware(string|callable|array $middleware): self
    {
        if ($this->lastRouteIndex === null) {
            throw new RuntimeException('No route registered to attach middleware.');
        }

        $items = is_array($middleware) ? $middleware : [$middleware];
        $this->routes[$this->lastRouteIndex]['middleware'] = array_merge(
            $this->routes[$this->lastRouteIndex]['middleware'],
            $items
        );

        return $this;
    }

    public function name(string $name): self
    {
        if ($this->lastRouteIndex === null) {
            throw new RuntimeException('No route registered to name.');
        }

        $this->routes[$this->lastRouteIndex]['name'] = $name;
        $this->namedRoutes[$name] = $this->lastRouteIndex;

        return $this;
    }

    /** @param array<string, scalar> $params */
    public function routeUrl(string $name, array $params = []): string
    {
        if (!isset($this->namedRoutes[$name])) {
            throw new RuntimeException("Named route not found: {$name}");
        }

        $pattern = $this->routes[$this->namedRoutes[$name]]['pattern'];
        $path = preg_replace_callback('/\{([a-zA-Z_][a-zA-Z0-9_]*)(?::[^}]+)?\}/', static function (array $m) use ($params): string {
            $key = $m[1];
            if (!array_key_exists($key, $params)) {
                throw new RuntimeException("Missing parameter '{$key}' for route.");
            }
            return rawurlencode((string) $params[$key]);
        }, $pattern);

        return url((string) $path);
    }

    public function dispatch(Request $request): Response
    {
        $method = $request->method();
        $path = $request->path();
        $allowedMethods = [];

        foreach ($this->routes as $route) {
            if (!preg_match($route['regex'], $path, $matches)) {
                continue;
            }

            if (!in_array($method, $route['methods'], true)) {
                $allowedMethods = array_merge($allowedMethods, $route['methods']);
                continue;
            }

            $params = [];
            foreach ($route['paramNames'] as $name) {
                $params[$name] = rawurldecode((string) ($matches[$name] ?? ''));
            }
            $request->setRouteParams($params);

            $coreAction = fn(Request $req): Response => $this->invokeHandler($route['handler'], $req, $params);

            $pipeline = array_reduce(
                array_reverse($route['middleware']),
                fn(callable $next, string|callable $mw): callable => fn(Request $req): Response => $this->runMiddleware($mw, $req, $next),
                $coreAction
            );

            return $pipeline($request);
        }

        if ($allowedMethods !== []) {
            $allow = implode(', ', array_unique($allowedMethods));
            if ($request->expectsJson()) {
                return Response::json(['error' => 'Method Not Allowed'], 405, ['Allow' => $allow]);
            }
            return Response::text('405 Method Not Allowed', 405)->header('Allow', $allow);
        }

        if ($request->expectsJson()) {
            return Response::json(['error' => 'Not Found'], 404);
        }

        if (is_file(view_path('errors/404.php'))) {
            return Response::html(View::render('errors.404', ['path' => $path]), 404);
        }

        return Response::text('404 Not Found', 404);
    }

    /**
     * @param list<string> $methods
     * @param callable|array{0: class-string, 1: string} $handler
     */
    private function addRoute(array $methods, string $path, callable|array $handler): self
    {
        $prefixParts = [];
        $groupMiddleware = [];

        foreach ($this->groupStack as $group) {
            if ($group['prefix'] !== '') {
                $prefixParts[] = $group['prefix'];
            }
            $groupMiddleware = array_merge($groupMiddleware, $group['middleware']);
        }

        $trimmedPath = trim($path, '/');
        if ($trimmedPath !== '') {
            $prefixParts[] = $trimmedPath;
        }

        $fullPattern = '/' . implode('/', $prefixParts);
        [$regex, $paramNames] = $this->compilePattern($fullPattern);

        $this->routes[] = [
            'methods' => $methods,
            'pattern' => $fullPattern,
            'regex' => $regex,
            'paramNames' => $paramNames,
            'handler' => $handler,
            'middleware' => $groupMiddleware,
            'name' => null,
        ];

        $this->lastRouteIndex = array_key_last($this->routes);
        return $this;
    }

    /** @return array{0: string, 1: list<string>} */
    private function compilePattern(string $pattern): array
    {
        $paramNames = [];
        $regex = preg_replace_callback(
            '/\{([a-zA-Z_][a-zA-Z0-9_]*)(?::([^}]+))?\}/',
            static function (array $m) use (&$paramNames): string {
                $paramNames[] = $m[1];
                $constraint = $m[2] ?? '[^/]+';
                return '(?P<' . $m[1] . '>' . $constraint . ')';
            },
            $pattern
        );

        return ['#^' . $regex . '$#', $paramNames];
    }

    private function runMiddleware(string|callable $middleware, Request $request, callable $next): Response
    {
        if (is_string($middleware)) {
            $instance = new $middleware();
            $result = $instance->handle($request, $next);
        } else {
            $result = $middleware($request, $next);
        }

        return $this->normalizeResponse($result);
    }

    /**
     * @param callable|array{0: class-string, 1: string} $handler
     * @param array<string, string> $params
     */
    private function invokeHandler(callable|array $handler, Request $request, array $params): Response
    {
        if (is_array($handler)) {
            [$class, $method] = $handler;
            $controller = new $class();
            $reflection = new ReflectionMethod($controller, $method);
            $args = $this->resolveArguments($reflection->getParameters(), $request, $params);
            $result = $controller->$method(...$args);
        } else {
            $reflection = new ReflectionFunction($handler(...));
            $args = $this->resolveArguments($reflection->getParameters(), $request, $params);
            $result = $handler(...$args);
        }

        return $this->normalizeResponse($result);
    }

    /**
     * @param list<\ReflectionParameter> $parameters
     * @param array<string, string> $routeParams
     * @return list<mixed>
     */
    private function resolveArguments(array $parameters, Request $request, array $routeParams): array
    {
        $args = [];
        $remaining = array_values($routeParams);

        foreach ($parameters as $param) {
            $type = $param->getType();
            if ($type instanceof ReflectionNamedType && $type->getName() === Request::class) {
                $args[] = $request;
                continue;
            }

            $name = $param->getName();
            if (array_key_exists($name, $routeParams)) {
                $args[] = $this->castParam($routeParams[$name], $type);
                continue;
            }

            if ($remaining !== []) {
                $args[] = $this->castParam(array_shift($remaining), $type);
                continue;
            }

            if ($param->isDefaultValueAvailable()) {
                $args[] = $param->getDefaultValue();
            }
        }

        return $args;
    }

    private function castParam(string $value, ?\ReflectionType $type): mixed
    {
        if (!$type instanceof ReflectionNamedType || !$type->isBuiltin()) {
            return $value;
        }

        return match ($type->getName()) {
            'int' => (int) $value,
            'float' => (float) $value,
            'bool' => filter_var($value, FILTER_VALIDATE_BOOL),
            default => $value,
        };
    }

    private function normalizeResponse(mixed $result): Response
    {
        if ($result instanceof Response) {
            return $result;
        }

        if (is_array($result)) {
            return Response::json($result);
        }

        return Response::html((string) $result);
    }
}
