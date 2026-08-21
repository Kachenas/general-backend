# Stage 1: Install PHP dependencies
FROM php:8.5-fpm-alpine AS composer

RUN apk add --no-cache \
    libpq-dev \
    icu-dev \
    libzip-dev \
    && docker-php-ext-install \
    pdo_pgsql \
    pgsql \
    intl \
    bcmath \
    zip \
    opcache

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app

COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-interaction --prefer-dist --optimize-autoloader

COPY . .
RUN composer dump-autoload --optimize

# Stage 2: Production image
FROM php:8.5-fpm-alpine AS production

RUN apk add --no-cache \
    nginx \
    supervisor \
    libpq-dev \
    icu-dev \
    libzip-dev \
    && docker-php-ext-install \
    pdo_pgsql \
    pgsql \
    intl \
    bcmath \
    zip \
    opcache \
    && rm -rf /var/cache/apk/*

# Configure PHP-FPM
RUN sed -i 's/^listen = .*/listen = 127.0.0.1:9000/' /usr/local/etc/php-fpm.d/www.conf

# Configure Nginx
RUN rm -f /etc/nginx/http.d/default.conf
COPY <<'NGINX' /etc/nginx/http.d/default.conf
server {
    listen 80;
    server_name _;
    root /app/public;
    index index.php;

    charset utf-8;
    client_max_body_size 64M;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known) {
        deny all;
    }

}
NGINX

# Configure Supervisord
COPY <<'SUPERVISOR' /etc/supervisord.conf
[supervisord]
nodaemon=true
logfile=/dev/stdout
logfile_maxbytes=0
pidfile=/var/run/supervisord.pid

[program:php-fpm]
command=php-fpm --nodaemonize
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:nginx]
command=nginx -g "daemon off;"
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
SUPERVISOR

# Configure OPcache for production
RUN echo "opcache.enable=1" >> /usr/local/etc/php/conf.d/opcache.ini \
    && echo "opcache.memory_consumption=128" >> /usr/local/etc/php/conf.d/opcache.ini \
    && echo "opcache.interned_strings_buffer=8" >> /usr/local/etc/php/conf.d/opcache.ini \
    && echo "opcache.max_accelerated_files=10000" >> /usr/local/etc/php/conf.d/opcache.ini \
    && echo "opcache.validate_timestamps=0" >> /usr/local/etc/php/conf.d/opcache.ini

WORKDIR /app

# Copy application code
COPY . .

# Copy vendor from composer stage
COPY --from=composer /app/vendor ./vendor

# Set permissions
RUN chown -R www-data:www-data /app/storage /app/bootstrap/cache \
    && chmod -R 775 /app/storage /app/bootstrap/cache

ENV LOG_CHANNEL=stderr

EXPOSE 80

# Entrypoint: run migrations, cache config/routes, start supervisord
COPY <<'ENTRYPOINT' /entrypoint.sh
#!/bin/sh
set -e

php artisan migrate --force
php artisan config:cache
php artisan route:cache
exec /usr/bin/supervisord -c /etc/supervisord.conf
ENTRYPOINT
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
