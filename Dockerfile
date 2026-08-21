# syntax=docker/dockerfile:1
# Required for heredoc (COPY <<'EOF') support.

# =============================================================================
# Stage 0: Base — PHP extensions compiled once, shared by every later stage
# =============================================================================
FROM php:8.5-fpm-alpine AS base

# Runtime libs are kept; build deps are added and removed in the SAME layer so
# they never get baked into the image. $PHPIZE_DEPS is provided by the official
# PHP image (autoconf, gcc, g++, make, libc-dev, pkgconf, re2c, ...).
#
# NOTE: no `docker-php-ext-configure pgsql --with-pgsql=...` here. Alpine's
# libpq-dev exposes pg_config, so pdo_pgsql/pgsql autodetect their paths.
RUN apk add --no-cache \
    libpq \
    icu-libs \
    libzip \
    && apk add --no-cache --virtual .build-deps \
    $PHPIZE_DEPS \
    libpq-dev \
    icu-dev \
    libzip-dev \
    && docker-php-ext-install -j"$(nproc)" \
    pdo_pgsql \
    pgsql \
    intl \
    bcmath \
    zip \
    opcache \
    && apk del --no-network .build-deps \
    && rm -rf /var/cache/apk/*

# =============================================================================
# Stage 1: Vendor — Composer dependencies only (cached on composer.lock)
# =============================================================================
FROM base AS vendor

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Only the manifests are copied so this layer is reused until deps change.
COPY composer.json composer.lock ./

RUN --mount=type=cache,target=/tmp/composer-cache \
    COMPOSER_CACHE_DIR=/tmp/composer-cache \
    composer install \
    --no-dev \
    --no-scripts \
    --no-interaction \
    --prefer-dist \
    --optimize-autoloader

# =============================================================================
# Stage 2: Production
# =============================================================================
FROM base AS production

RUN apk add --no-cache nginx supervisor

# -----------------------------------------------------------------------------
# PHP-FPM
# -----------------------------------------------------------------------------
RUN sed -i 's/^listen = .*/listen = 127.0.0.1:9000/' /usr/local/etc/php-fpm.d/www.conf

# -----------------------------------------------------------------------------
# PHP runtime settings (upload limits kept in sync with nginx client_max_body_size)
# -----------------------------------------------------------------------------
COPY <<'PHPINI' /usr/local/etc/php/conf.d/zz-app.ini
memory_limit = 256M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 60
expose_php = Off

opcache.enable = 1
opcache.enable_cli = 0
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 20000
opcache.validate_timestamps = 0
opcache.save_comments = 1
PHPINI

# -----------------------------------------------------------------------------
# Nginx
# -----------------------------------------------------------------------------
RUN rm -f /etc/nginx/http.d/default.conf

COPY <<'NGINX' /etc/nginx/http.d/default.conf
server {
    listen 80;
    server_name _;
    root /app/public;
    index index.php;

    charset utf-8;
    client_max_body_size 64M;

    server_tokens off;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ ^/index\.php(/|$) {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT $realpath_root;
        fastcgi_hide_header X-Powered-By;
        include fastcgi_params;
        fastcgi_read_timeout 60s;
        internal;
    }

    # Any other .php file is not executable — prevents running uploaded scripts.
    location ~ \.php$ {
        return 404;
    }

    location ~ /\.(?!well-known) {
        deny all;
    }
}
NGINX

# -----------------------------------------------------------------------------
# Supervisord
# -----------------------------------------------------------------------------
COPY <<'SUPERVISOR' /etc/supervisord.conf
[supervisord]
nodaemon=true
logfile=/dev/stdout
logfile_maxbytes=0
pidfile=/var/run/supervisord.pid
user=root

[program:php-fpm]
command=php-fpm --nodaemonize
autostart=true
autorestart=true
priority=10
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:nginx]
command=nginx -g "daemon off;"
autostart=true
autorestart=true
priority=20
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
SUPERVISOR

# -----------------------------------------------------------------------------
# Application code
# -----------------------------------------------------------------------------
WORKDIR /app

# Requires a .dockerignore — otherwise .env, .git and a local vendor/ ship too.
COPY . .
COPY --from=vendor /app/vendor ./vendor

RUN mkdir -p \
    storage/app/public \
    storage/framework/cache/data \
    storage/framework/sessions \
    storage/framework/testing \
    storage/framework/views \
    storage/logs \
    bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

ENV LOG_CHANNEL=stderr \
    APP_ENV=production \
    APP_DEBUG=false

EXPOSE 80

# Laravel 11+ exposes /up. On older versions, point this at a route you own.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://127.0.0.1/up || exit 1

# -----------------------------------------------------------------------------
# Entrypoint
# -----------------------------------------------------------------------------
# Migrations are opt-in (RUN_MIGRATIONS=true) rather than unconditional: with
# more than one replica, every container would race the same migration.
# Preferred setup is a separate one-off job in your pipeline.
COPY <<'ENTRYPOINT' /entrypoint.sh
#!/bin/sh
set -e

# composer install ran with --no-scripts and without app code present, so the
# package manifest has to be built here, before anything is cached.
php artisan package:discover --ansi

if [ "${RUN_MIGRATIONS}" = "true" ]; then
    echo "Running migrations..."
    php artisan migrate --force
fi

php artisan config:cache
php artisan route:cache
php artisan view:cache

exec /usr/bin/supervisord -c /etc/supervisord.conf
ENTRYPOINT

RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]