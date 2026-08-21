<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

class LogApiRequests
{
    /**
     * Headers that should never be logged.
     *
     * @var array<int, string>
     */
    protected array $sensitiveHeaders = [
        'authorization',
        'cookie',
        'x-csrf-token',
        'x-xsrf-token',
    ];

    /**
     * Request body fields that should be redacted.
     *
     * @var array<int, string>
     */
    protected array $sensitiveFields = [
        'password',
        'password_confirmation',
        'token',
        'secret',
        'credit_card',
        'card_number',
        'cvv',
        'ssn',
    ];

    /**
     * Handle an incoming request.
     *
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $requestId = (string) Str::uuid();
        $startTime = microtime(true);
        $startMemory = memory_get_usage(true);

        $request->headers->set('X-Request-ID', $requestId);

        $this->logRequest($request, $requestId);

        $response = $next($request);

        $duration = round((microtime(true) - $startTime) * 1000, 2);
        $memoryUsed = memory_get_usage(true) - $startMemory;

        $response->headers->set('X-Request-ID', $requestId);

        $this->logResponse($request, $response, $requestId, $duration, $memoryUsed);

        return $response;
    }

    /**
     * Log the incoming request with Sentry-style context.
     */
    protected function logRequest(Request $request, string $requestId): void
    {
        Log::channel('stderr')->info('api.request', [
            'request_id' => $requestId,
            'timestamp' => now()->toIso8601String(),
            'http' => [
                'method' => $request->method(),
                'url' => $request->fullUrl(),
                'route' => $request->route()?->uri() ?? $request->path(),
                'route_name' => $request->route()?->getName(),
                'query_string' => $request->query() ?: null,
            ],
            'client' => [
                'ip' => $request->ip(),
                'user_agent' => $request->userAgent(),
                'referer' => $request->header('referer'),
            ],
            'headers' => $this->filterHeaders($request),
            'body' => $this->filterBody($request),
            'user' => $this->resolveUser($request),
        ]);
    }

    /**
     * Log the outgoing response with performance metrics.
     */
    protected function logResponse(
        Request $request,
        Response $response,
        string $requestId,
        float $durationMs,
        int $memoryUsed,
    ): void {
        $statusCode = $response->getStatusCode();
        $level = $this->resolveLogLevel($statusCode);

        $context = [
            'request_id' => $requestId,
            'timestamp' => now()->toIso8601String(),
            'http' => [
                'method' => $request->method(),
                'url' => $request->fullUrl(),
                'route' => $request->route()?->uri() ?? $request->path(),
                'route_name' => $request->route()?->getName(),
                'status_code' => $statusCode,
            ],
            'performance' => [
                'duration_ms' => $durationMs,
                'memory_bytes' => $memoryUsed,
                'memory_mb' => round($memoryUsed / 1024 / 1024, 2),
            ],
            'user' => $this->resolveUser($request),
        ];

        if ($statusCode >= 400) {
            $context['response_body'] = $this->truncateResponseBody($response);
        }

        Log::channel('stderr')->{$level}('api.response', $context);
    }

    /**
     * Filter request headers, redacting sensitive values.
     *
     * @return array<string, mixed>
     */
    protected function filterHeaders(Request $request): array
    {
        $headers = collect($request->headers->all())
            ->map(fn (array $values): string => implode(', ', $values))
            ->toArray();

        foreach ($this->sensitiveHeaders as $header) {
            if (isset($headers[$header])) {
                $headers[$header] = '[REDACTED]';
            }
        }

        return $headers;
    }

    /**
     * Filter request body, redacting sensitive fields.
     *
     * @return array<string, mixed>|null
     */
    protected function filterBody(Request $request): ?array
    {
        $input = $request->all();

        if (empty($input)) {
            return null;
        }

        return $this->redactSensitiveFields($input);
    }

    /**
     * Recursively redact sensitive fields from the given data.
     *
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>
     */
    protected function redactSensitiveFields(array $data): array
    {
        foreach ($data as $key => $value) {
            if (in_array(strtolower((string) $key), $this->sensitiveFields, true)) {
                $data[$key] = '[REDACTED]';
            } elseif (is_array($value)) {
                $data[$key] = $this->redactSensitiveFields($value);
            }
        }

        return $data;
    }

    /**
     * Resolve the authenticated user context.
     *
     * @return array<string, mixed>|null
     */
    protected function resolveUser(Request $request): ?array
    {
        $user = $request->user();

        if (! $user) {
            return null;
        }

        return [
            'id' => $user->id,
            'email' => $user->email,
        ];
    }

    /**
     * Determine the log level based on HTTP status code.
     */
    protected function resolveLogLevel(int $statusCode): string
    {
        return match (true) {
            $statusCode >= 500 => 'error',
            $statusCode >= 400 => 'warning',
            default => 'info',
        };
    }

    /**
     * Truncate the response body for logging.
     */
    protected function truncateResponseBody(Response $response): mixed
    {
        if ($response instanceof JsonResponse) {
            $data = $response->getData(true);

            return Str::limit(json_encode($data), 2048);
        }

        return Str::limit((string) $response->getContent(), 2048);
    }
}
