# syntax=docker/dockerfile:1.7
FROM php:8.4-fpm

LABEL maintainer="Warp"

ENV DEBIAN_FRONTEND=noninteractive
ENV PHP_EXTRA_CONFIGURE_ARGS="--enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data --enable-intl --enable-opcache --enable-zip"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        apt-transport-https \
        autoconf \
        build-essential \
        ca-certificates \
        cron \
        curl \
        default-mysql-client \
        dpkg-dev \
        file \
        fontforge \
        g++ \
        gcc \
        git \
        gnupg \
        imagemagick \
        libbz2-dev \
        libcurl4-gnutls-dev \
        libexif-dev \
        libfreetype-dev \
        libgd-dev \
        libicu-dev \
        libjpeg-dev \
        libldap2-dev \
        libltdl-dev \
        libmagic-dev \
        libmagickcore-dev \
        libmagickwand-dev \
        libmcrypt-dev \
        libonig-dev \
        libpng-dev \
        libpq-dev \
        librabbitmq-dev \
        libreadline-dev \
        libsodium-dev \
        libssh2-1-dev \
        libssl-dev \
        libtidy-dev \
        libwebp-dev \
        libxml2-dev \
        libxpm-dev \
        libxslt1-dev \
        libzip-dev \
        make \
        msmtp \
        msmtp-mta \
        openssh-client \
        pkg-config \
        re2c \
        supervisor \
        ttfautohint \
        unzip \
        vim \
        wget \
        xz-utils \
        zip \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    deb_multiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-configure ldap --with-libdir="lib/${deb_multiarch}"; \
    docker-php-ext-install -j"$(nproc)" \
        bcmath \
        exif \
        ftp \
        gd \
        intl \
        ldap \
        mbstring \
        mysqli \
        opcache \
        pcntl \
        pdo_mysql \
        pdo_pgsql \
        soap \
        sockets \
        xsl \
        zip

RUN set -eux; \
    pecl update-channels; \
    pecl install imagick ssh2-1.3.1 apcu mongodb redis xdebug; \
    docker-php-ext-enable imagick ssh2 apcu mongodb redis; \
    docker-php-ext-enable sodium || true; \
    test -f "$(php-config --extension-dir)/xdebug.so"; \
    rm -rf /tmp/pear

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

RUN set -eux; \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -; \
    apt-get update; \
    apt-get install -y --no-install-recommends nodejs; \
    npm install -g grunt-cli gulp-cli yarn; \
    npm cache clean --force; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    mkdir -p /var/www/.ssh /var/log/php-fpm /etc/msmtp; \
    touch /var/log/php-fpm/access.log /var/log/php-fpm/fpm-error.log /var/log/php-fpm/fpm-php.www.log; \
    chown -R www-data:www-data /var/www /var/log/php-fpm; \
    chmod -R g+w /var/www

RUN set -eux; \
    groupadd -g 501 kirk; \
    useradd -g 501 -u 501 -d /var/www/html -s /bin/bash kirk; \
    groupadd -g 1000 warp; \
    useradd -g 1000 -u 1000 -d /var/www/html -s /bin/bash warp; \
    groupadd -g 1001 spock; \
    useradd -g 1001 -u 1001 -d /var/www/html -s /bin/bash spock; \
    groupadd -g 1002 scott; \
    useradd -g 1002 -u 1002 -d /var/www/html -s /bin/bash scott; \
    usermod -aG 501 www-data; \
    usermod -aG 1000 www-data; \
    usermod -aG 1001 www-data; \
    usermod -aG 1002 www-data

COPY msmtprc /etc/msmtprc
COPY docker-php-mail.ini /usr/local/etc/php/conf.d/docker-php-mail.ini

RUN set -eux; \
    chown root:root /etc/msmtprc; \
    chmod 0644 /etc/msmtprc; \
    php -m | grep -E '^(bcmath|gd|intl|mbstring|pdo_mysql|redis|soap|xsl|zip)$'

WORKDIR /var/www/html

EXPOSE 9000
CMD ["php-fpm"]
