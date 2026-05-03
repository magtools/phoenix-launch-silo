# Warp Infra Images: PoC PHP 8.4 Multiarch

Fecha: 2026-04-16

## 1. Objetivo

Definir una PoC de imagen PHP propia, multiarch, compatible con un stack Magento moderno tipo `example`, reemplazando `summasolutions/php:8.4-fpm`.

Estado actualizado:

```text
Tag moderno DockerHub: magtools/php:8.4.20-fpm
Tags PoC historicos: magtools/php:8.4-fpm-poc-amd64, magtools/php:8.4-fpm-poc-arm64, magtools/php:8.4-fpm-poc
```

Para nuevas pruebas de Magento 2.4.8 usar `magtools/php:8.4.20-fpm`. Los tags `*-poc-*` quedan como historial de build/smoke.

Este archivo complementa:

- [warp-infra.md](/srv2/www/htdocs/66/warp-engine/features/warp-infra.md)
- [warp-infra-img.md](/srv2/www/htdocs/66/warp-engine/features/warp-infra-img.md)

La PoC debe probar primero `linux/amd64` y despues `linux/arm64`.

## 2. Principios

1. No copiar literalmente los Dockerfiles legacy de `images/php/old`.
2. Usar base oficial `php:8.4-fpm`.
3. Instalar extensiones en build time, no en cada arranque.
4. Evitar binarios x86-only.
5. Mantener compatibilidad con mounts actuales de Warp.
6. Mantener `www-data` como usuario runtime.
7. Mantener usuarios/grupos historicos de Warp mientras se valida compatibilidad.

Perfil Warp esperado:

```dotenv
WARP_PHP_INI_PROFILE=managed
```

Esta PoC no cambia el contrato de proyectos legacy. El perfil `managed` debe reservarse para stacks nuevos o migrados explicitamente, idealmente Magento `2.4.8+`, donde la imagen PHP cumple que Xdebug esta instalado pero no auto-habilitado.

## 3. Mail local y reemplazo de `mhsendmail`

`mhsendmail_linux_amd64` no debe entrar en la nueva imagen porque es binario x86.

Alternativas aceptables:

1. configurar Magento/PHP para enviar por SMTP directo a un servicio local de mail;
2. usar `msmtp` como binario sendmail-compatible multiarch;
3. usar otro wrapper sendmail-compatible que exista para `amd64` y `arm64`;
4. eliminar sendmail local si todos los proyectos usan un modulo SMTP.

Opcion recomendada para PoC:

1. servicio local de mail: Mailpit;
2. reemplazo de `mhsendmail`: `msmtp`;
3. `sendmail_path`: `/usr/bin/msmtp -t`.

Motivos:

1. Mailpit publica imagen Docker multiarch;
2. Mailpit soporta UI/API con autenticacion basica mediante `MP_UI_AUTH` o `MP_UI_AUTH_FILE`;
3. Mailpit soporta SMTP auth/TLS si se requiere;
4. `msmtp` esta disponible como paquete Debian y no depende de binarios x86.

Fuentes:

1. Mailpit features: https://mailpit.axllent.org/docs/
2. Mailpit HTTP/UI auth: https://mailpit.axllent.org/docs/configuration/http/
3. Mailpit SMTP config: https://mailpit.axllent.org/docs/configuration/smtp/
4. Mailpit sending messages: https://mailpit.axllent.org/docs/usage/sending-messages/
5. Mailpit storage: https://mailpit.axllent.org/docs/configuration/email-storage/

## 4. Servicio local de mail PoC

Compose conceptual:

```yaml
mail:
  image: axllent/mailpit:latest
  env_file: .env
  environment:
    MP_UI_AUTH_FILE: "/mail-config/ui-auth.txt"
    MP_MAX_MESSAGES: "${MAIL_MAX_MESSAGES:-100}"
    MP_DATABASE: "/mail-data/mailpit.db"
  ports:
    - "1025"
    - "127.0.0.1:${MAIL_BINDED_PORT:-8025}:8025"
  volumes:
    - "./.warp/docker/volumes/mail:/mail-data"
    - "./.warp/docker/config/mail:/mail-config:ro"
  networks:
    - back
```

Notas:

1. `MP_UI_AUTH_FILE` protege UI/API con basic auth.
2. Se prefiere archivo montado para evitar credenciales visibles en `docker inspect`.
3. El SMTP puede quedar sin auth dentro de la red Docker en desarrollo, o habilitarse luego si hace falta.
4. En Warp conviene mantener el servicio legacy `mailhog` por compatibilidad aunque el capability/documentacion sea `mail`.

Variables sugeridas:

```dotenv
MAIL_ENGINE=mailpit
MAIL_VERSION=v1.29
MAIL_SMTP_HOST=mailhog
MAIL_SMTP_PORT=1025
MAIL_BINDED_PORT=8025
MAIL_MAX_MESSAGES=100
```

## 5. Configuracion PHP mail PoC

Archivo ini sugerido:

```ini
sendmail_path = /usr/bin/msmtp -t
```

Archivo `/etc/msmtprc` sugerido:

```text
defaults
auth off
tls off
logfile /proc/self/fd/2

account default
host mail
port 1025
from dev@example.local
```

Notas:

1. `auth off` es suficiente si el SMTP queda solo en red Docker local.
2. Si se habilita SMTP auth en Mailpit, `msmtp` puede usar usuario/password desde archivo montado.
3. Para desarrollo, la autenticacion mas importante es la UI/API expuesta al host.

## 6. Dockerfile PoC

Archivo propuesto:

```text
images/php/8.4-fpm-poc/Dockerfile
```

Contenido:

```dockerfile
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
```

## 7. Archivos auxiliares PoC

`images/php/8.4-fpm-poc/docker-php-mail.ini`:

```ini
sendmail_path = /usr/bin/msmtp -t
```

`images/php/8.4-fpm-poc/msmtprc`:

```text
defaults
auth off
tls off
logfile /proc/self/fd/2

account default
host mail
port 1025
from dev@example.local
```

## 8. Build

Primero `amd64`:

```bash
docker build --platform linux/amd64 \
  -t warp/php:8.4-fpm-poc-amd64 \
  -f images/php/8.4-fpm-poc/Dockerfile \
  images/php/8.4-fpm-poc
```

Resultado local del 2026-04-16:

```text
OK: warp/php:8.4-fpm-poc-amd64
base efectiva: php:8.4-fpm
OS efectivo: Debian 13 trixie
arch runtime: x86_64
```

Luego `arm64` o multiarch:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t magtools/php:8.4.20-fpm \
  -f images/php/8.4-fpm-poc/Dockerfile \
  images/php/8.4-fpm-poc \
  --push
```

Estado `arm64` local:

No se lanzo el build PHP `arm64` en este host porque el build `arm64` de `appdata` fallo antes por falta de soporte de ejecucion `arm64` en el builder local:

```text
exec /bin/sh: exec format error
docker buildx ls: linux/amd64 (+3)
```

Antes de gastar tiempo en PHP `arm64`, hay que habilitar uno de estos caminos:

1. builder nativo Arm, idealmente una instancia Graviton temporal;
2. builder `buildx` con QEMU/binfmt registrado;
3. CI que publique manifest multiarch desde builders separados.

## 9. Smokes

### 9.1 Imagen

```bash
docker run --rm warp/php:8.4-fpm-poc-amd64 php -v
docker run --rm warp/php:8.4-fpm-poc-amd64 php -m
docker run --rm warp/php:8.4-fpm-poc-amd64 composer --version
docker run --rm warp/php:8.4-fpm-poc-amd64 node --version
docker run --rm warp/php:8.4-fpm-poc-amd64 msmtp --version
```

Smoke local `amd64` ejecutado:

```text
arch: x86_64
PHP: 8.4.20
Composer: 2.9.7
Node.js: v20.20.2
npm: 10.8.2
Yarn: 1.22.22
msmtp: 1.8.28
```

Extensiones validadas en runtime despues del primer build amd64:

```text
apcu
bcmath
gd
imagick
intl
mongodb
opcache
pdo_mysql
redis
soap
ssh2
xdebug
xsl
zip
```

Validacion posterior con la imagen ajustada:

La PoC fue ajustada para que `xdebug.so` quede instalado pero no cargado por default. A partir de este cambio, `xdebug` ya no debe aparecer en `php -m` salvo que Warp genere o monte `ext-xdebug.ini` con `zend_extension=xdebug.so`.

Smoke local `amd64` ejecutado despues del ajuste:

```text
xdebug.so installed, not loaded
PHP 8.4.20
with Zend OPcache v8.4.20
opcache.enable => On => On
opcache.enable_cli => Off => Off
```

Tambien se valido que la imagen permite el comportamiento esperado por configuracion:

```text
php -d zend_extension=xdebug.so -m: xdebug cargado
php -d opcache.enable=0 -i: opcache.enable => Off => Off
```

Extensiones minimas esperadas:

```text
apcu
bcmath
curl
exif
ftp
gd
imagick
intl
ldap
mbstring
mongodb
mysqli
opcache
pcntl
pdo_mysql
pdo_pgsql
redis
soap
sockets
sodium
ssh2
xdebug
xsl
zip
```

Para la imagen PoC ajustada, interpretar `xdebug` como "binario `xdebug.so` instalado y disponible", no como extension cargada por default.

### 9.2 Compose

Reemplazo temporal:

```yaml
php:
  image: magtools/php:8.4.20-fpm

mail:
  image: axllent/mailpit:latest
```

Validaciones:

```bash
docker compose config
docker compose up -d php mail
docker exec example-php-1 php -m
docker exec example-php-1 composer check-platform-reqs
docker exec example-php-1 bin/magento --version
docker exec example-php-1 bin/magento cache:status
```

### 9.3 Mail

Enviar mail por `mail()`/sendmail-compatible:

```bash
docker exec example-php-1 php -r 'mail("dev@example.local", "warp test", "ok");'
```

Validar que aparece en Mailpit UI.

## 10. Criterios de aceptacion

1. Build exitoso en `linux/amd64`.
2. Build exitoso en `linux/arm64`.
3. No quedan binarios `*_amd64` requeridos en runtime.
4. `ldap` compila con libdir dinamico.
5. `msmtp` reemplaza correctamente `mhsendmail` para desarrollo.
6. Mailpit cubre captura local de mails con UI protegible por auth.
7. Magento `2.4.8-p4` pasa `composer check-platform-reqs`.
8. `bin/magento` ejecuta.
9. PHP-FPM responde en el stack.
10. La imagen no requiere instalacion de extensiones en arranque.

## 11. Riesgos

1. `imagick`, `mongodb`, `redis`, `ssh2`, `xdebug` pueden variar por arquitectura o version PECL.
2. NodeSource debe validarse en `arm64`.
3. `msmtp` cambia comportamiento frente a `mhsendmail`; hay que probar `mail()` y flujos Magento reales.
4. La imagen sigue siendo grande si conserva build deps y tooling frontend.
5. Xdebug dentro de imagen runtime puede ser indeseable para produccion.

## 12. Decision esperada

Si esta PoC pasa en `amd64` y luego en `arm64`, PHP deja de ser el bloqueo tecnico principal para `c7g` en stacks Magento modernos.

No implica soportar PHP legacy ni todos los servicios auxiliares de Warp.
