# API Logging

## Overview

All API requests and responses are logged via the `LogApiRequests` middleware (`app/Http/Middleware/LogApiRequests.php`), registered globally on the `api` middleware group in `bootstrap/app.php`.

Each log entry is structured JSON, modeled after what Sentry captures: request context, user identity, performance metrics, and error details.

## What Gets Logged

Every API request produces two log entries sharing the same `request_id`:

### Request Entry (`api.request`)

| Field | Description |
|---|---|
| `request_id` | UUID v4, unique per request. Also set as `X-Request-ID` response header. |
| `http.method` | HTTP method (GET, POST, etc.) |
| `http.url` | Full URL including query string |
| `http.route` | Route pattern (e.g. `api/v1/users/{user}/roles`) |
| `http.route_name` | Named route, if defined |
| `http.query_string` | Parsed query parameters |
| `client.ip` | Client IP address |
| `client.user_agent` | User-Agent header |
| `client.referer` | Referer header |
| `headers` | All request headers (sensitive ones redacted) |
| `body` | Request payload (sensitive fields redacted) |
| `user` | Authenticated user `id` and `email`, or `null` |

### Response Entry (`api.response`)

| Field | Description |
|---|---|
| `request_id` | Same UUID as the corresponding request entry |
| `http.status_code` | HTTP response status |
| `performance.duration_ms` | Request duration in milliseconds |
| `performance.memory_bytes` | Memory consumed during the request |
| `performance.memory_mb` | Same value in megabytes |
| `response_body` | Included only for 4xx/5xx responses (truncated to 2KB) |
| `user` | Authenticated user `id` and `email`, or `null` |

### Log Levels

| Status Code | Level |
|---|---|
| 2xx, 3xx | `info` |
| 4xx | `warning` |
| 5xx | `error` |

## Sensitive Data Redaction

The middleware automatically redacts sensitive data before logging.

**Redacted headers** (value replaced with `[REDACTED]`):
- `authorization`
- `cookie`
- `x-csrf-token`
- `x-xsrf-token`

**Redacted body fields** (value replaced with `[REDACTED]`, applied recursively):
- `password`, `password_confirmation`
- `token`, `secret`
- `credit_card`, `card_number`, `cvv`
- `ssn`

To add more fields, update the `$sensitiveHeaders` or `$sensitiveFields` arrays in `LogApiRequests`.

## Configuration

### Environment Variables

| Variable | Local | Production (Fargate) | Description |
|---|---|---|---|
| `LOG_CHANNEL` | `stack` | `stderr` | Log channel driver |
| `LOG_STACK` | `single` | - | Channels used by the `stack` driver |
| `LOG_LEVEL` | `debug` | `warning` or `info` | Minimum log level |
| `TELESCOPE_ENABLED` | `true` | `false` | Telescope is disabled in production |

### Log Channels

Configured in `config/logging.php`:

- **`stack`** (local default) -- Writes to `storage/logs/laravel.log` via the `single` channel.
- **`stderr`** (production default) -- Writes JSON-formatted log lines to `php://stderr` using Monolog's `JsonFormatter`. On Fargate, stderr is automatically captured by the awslogs driver and shipped to CloudWatch Logs.

## Accessing Logs

### Local Development

Logs write to `storage/logs/laravel.log` by default (`LOG_CHANNEL=stack`).

```bash
# Tail the log file
tail -f storage/logs/laravel.log

# Use Laravel Pail for real-time formatted output
php artisan pail

# Filter Pail output
php artisan pail --filter="api.response"
php artisan pail --level=error
```

Laravel Telescope is also available locally at `/telescope` when `TELESCOPE_ENABLED=true`. It provides a web UI for inspecting requests, queries, exceptions, and more.

### Production (AWS Fargate / CloudWatch)

On Fargate, set `LOG_CHANNEL=stderr` in your task definition environment variables. The awslogs log driver captures stderr and ships it to a CloudWatch Log Group (typically `/ecs/<service-name>`).

#### Viewing Logs in the AWS Console

1. Go to **CloudWatch > Log groups**
2. Select the log group for your ECS service
3. Browse log streams (one per Fargate task)

#### Querying with CloudWatch Logs Insights

Navigate to **CloudWatch > Logs Insights**, select your log group, and run queries:

```
# All 5xx errors in the last hour
fields @timestamp, context.request_id, context.http.method, context.http.url, context.http.status_code
| filter message = "api.response" and context.http.status_code >= 500
| sort @timestamp desc
| limit 50
```

```
# Trace a single request end-to-end by request ID
fields @timestamp, message, context.http.status_code, context.performance.duration_ms
| filter context.request_id = "your-uuid-here"
| sort @timestamp asc
```

```
# All requests by a specific user
fields @timestamp, context.http.method, context.http.url, context.http.status_code
| filter context.user.email = "john@example.com"
| sort @timestamp desc
```

```
# Slow requests (over 1 second)
fields @timestamp, context.http.method, context.http.url, context.performance.duration_ms
| filter message = "api.response" and context.performance.duration_ms > 1000
| sort context.performance.duration_ms desc
```

```
# Failed login attempts
fields @timestamp, context.client.ip, context.http.status_code
| filter context.http.url like /login/ and context.http.status_code = 401
| sort @timestamp desc
```

```
# Request volume by endpoint
fields context.http.route
| filter message = "api.response"
| stats count(*) as requests by context.http.route
| sort requests desc
```

#### Using the AWS CLI

```bash
# Tail logs in real time
aws logs tail /ecs/your-service-name --follow

# Tail only errors
aws logs tail /ecs/your-service-name --follow --filter-pattern '{ $.level_name = "ERROR" }'
```

## Request Tracing

Every request gets a UUID (`request_id`) set as the `X-Request-ID` response header. This allows you to:

1. Grab the ID from a client-side error report or API response header
2. Search CloudWatch for that exact ID to find both the request and response log entries
3. See the full context: who made the request, what they sent, what the server returned, and how long it took

If your frontend or API consumers forward error details, include the `X-Request-ID` header value to enable instant log correlation.
