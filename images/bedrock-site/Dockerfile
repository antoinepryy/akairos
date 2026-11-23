# Bedrock WordPress image: code and plugins are baked in by Composer,
# media go to S3 and sessions/cache to Redis, so containers hold no state.
# Kubernetes variant: runs as www-data (uid 33) on port 8080, so it passes
# Pod Security "restricted", with a read-only root filesystem (the chart
# mounts emptyDirs on /tmp and Apache's run and lock directories).

FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --no-progress --prefer-dist --optimize-autoloader --no-scripts

FROM php:8.4-apache
RUN apt-get update \
 && apt-get install -y --no-install-recommends libjpeg62-turbo-dev libpng-dev libwebp-dev libfreetype6-dev libzip-dev libicu-dev \
 && docker-php-ext-configure gd --with-jpeg --with-webp --with-freetype \
 && docker-php-ext-install -j"$(nproc)" mysqli gd exif zip intl opcache \
 && pecl install redis && docker-php-ext-enable redis \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL -o /usr/local/lib/wp-cli.phar https://github.com/wp-cli/wp-cli/releases/download/v2.12.0/wp-cli-2.12.0.phar \
 && a2enmod rewrite headers remoteip \
 && sed -i 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf \
 && sed -i '/Listen 443/d' /etc/apache2/ports.conf

COPY docker/php.ini /usr/local/etc/php/conf.d/zz-bedrock.ini
COPY docker/vhost.conf /etc/apache2/sites-available/000-default.conf
COPY docker/entrypoint.sh /usr/local/bin/bedrock-entrypoint
COPY docker/wp /usr/local/bin/wp
COPY docker/healthz.php /var/www/healthz.php

WORKDIR /var/www/html
COPY --from=vendor /app/vendor ./vendor
COPY --from=vendor /app/web ./web
COPY config ./config
COPY web/app/mu-plugins/*.php ./web/app/mu-plugins/
COPY web/index.php web/wp-config.php ./web/
COPY wp-cli.yml ./
# Redis object-cache drop-in baked in (`wp redis enable` would write it into a throwaway container)
RUN cp web/app/plugins/redis-cache/includes/object-cache.php web/app/object-cache.php
# Code owned by root, read-only for Apache: a compromised PHP process cannot
# rewrite the site. Only Apache's runtime directories belong to www-data.
RUN chown -R www-data:www-data /var/run/apache2 /var/lock/apache2

ENV WP_CLI_CACHE_DIR=/tmp/wp-cli HOME=/tmp
USER 33:33
EXPOSE 8080

# No HEALTHCHECK: Kubernetes probes /healthz (see apps/bedrock).

ENTRYPOINT ["bedrock-entrypoint"]
CMD ["apache2-foreground"]
