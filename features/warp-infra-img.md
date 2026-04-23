# Warp Infra Images: analisis PHP/Appdata en `example`

Fecha: 2026-04-16

## 1. Objetivo

Analizar las imagenes y contenedores `php` y `appdata` actualmente corriendo en `example`, para evaluar si son una base razonable para construir imagenes propias multiarch `linux/amd64` y `linux/arm64`.

Este documento complementa:

- [warp-infra.md](/srv2/www/htdocs/66/warp-engine/features/warp-infra.md)
- [warp-infra-img-appdata.md](/srv2/www/htdocs/66/warp-engine/features/warp-infra-img-appdata.md)
- [warp-infra-img-php.md](/srv2/www/htdocs/66/warp-engine/features/warp-infra-img-php.md)

Alcance:

1. inspeccion no destructiva de contenedores vivos;
2. inventario de runtime, extensiones y paquetes;
3. lectura de metadata e historia de imagenes;
4. riesgos para reconstruccion multiarch;
5. recomendaciones para una PoC.
6. la definicion concreta de Dockerfiles PoC vive en los archivos especificos de `appdata` y `php`.

No se incluyen valores sensibles de `.env`, credenciales, passwords ni configuracion privada del sitio.

## 2. Contenedores revisados

Proyecto Compose detectado para `example`:

- `example`

Contenedores relevantes:

| Servicio | Contenedor | Imagen | Estado observado |
| --- | --- | --- | --- |
| `php` | `example-php-1` | `summasolutions/php:8.4-fpm` | running |
| `appdata` | `example-appdata-1` | `summasolutions/appdata:latest` | running |

Imagenes locales:

| Imagen | Digest local | Arquitectura | OS | Tamano aprox. | Creada |
| --- | --- | --- | --- | ---: | --- |
| `summasolutions/php:8.4-fpm` | `sha256:6345cbb...` | `amd64` | `linux` | 1.75 GB | 2025-10-22 |
| `summasolutions/appdata:latest` | `sha256:f76ed2c...` | `amd64` | `linux` | 131 MB | 2021-04-05 |

Lectura:

1. ambas imagenes locales son `amd64`;
2. no hay soporte Arm local confirmado;
3. `php` es una imagen moderna en OS/PHP, pero contiene al menos un binario explicitamente `amd64`;
4. `appdata` es simple, pero esta basada en Debian Jessie.

## 2.1 Estado de PoC de imagenes propias

Se definieron Dockerfiles PoC en:

1. `images/appdata-poc/Dockerfile`;
2. `images/php/8.4-fpm-poc/Dockerfile`.

Validacion local `linux/amd64` del 2026-04-16:

| Imagen PoC | Resultado | Hallazgos |
| --- | --- | --- |
| `warp/appdata:bookworm-poc-amd64` | OK | Debian 12 bookworm, `rsync 3.2.7`, `x86_64`. |
| `warp/php:8.4-fpm-poc-amd64` | OK | PHP 8.4.20, Composer 2.9.7, Node 20.20.2, `msmtp 1.8.28`, extensiones Magento clave cargadas. |

Validacion local `linux/arm64`:

```text
FAIL: exec /bin/sh: exec format error
builder local: linux/amd64 (+3)
```

Lectura:

1. el bloqueo local no es del Dockerfile, sino del builder sin emulacion/binfmt para ejecutar capas Arm;
2. no conviene lanzar el build PHP `arm64` hasta tener un builder Arm real o QEMU/binfmt registrado;
3. la PoC `amd64` demuestra que la reconstruccion de `php` y `appdata` es viable sin copiar binarios x86-only;
4. la validacion `arm64` sigue pendiente y debe tratarse como hito separado antes de cualquier decision sobre `c7g`.

## 3. PHP: inventario runtime

### 3.1 Sistema base

El contenedor `example-php-1` reporta:

```text
Debian GNU/Linux 13 (trixie)
arch: x86_64
user runtime: www-data
```

Grupos del usuario `www-data`:

```text
www-data, kirk(501), warp(1000), spock(1001), scott(1002)
```

Esto confirma que la imagen ya fue modernizada respecto a los Dockerfiles legacy en `images/php/old`, que usaban bases PHP/Debian antiguas.

### 3.2 PHP

Version:

```text
PHP 8.4.13
Zend OPcache 8.4.13
Xdebug 3.4.6
```

La imagen fue construida desde la linea oficial `docker-library/php` y compila PHP desde:

```text
https://www.php.net/distributions/php-8.4.13.tar.xz
```

Variables relevantes de imagen:

```text
PHP_VERSION=8.4.13
PHP_INI_DIR=/usr/local/etc/php
PHP_EXTRA_CONFIGURE_ARGS=--enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data --enable-intl --enable-opcache --enable-zip
```

### 3.3 Extensiones PHP cargadas

Extensiones relevantes para Magento:

```text
apcu=5.1.27
bcmath=8.4.13
curl=8.4.13
exif=8.4.13
ftp=8.4.13
gd=8.4.13
imagick=3.8.0
intl=8.4.13
ldap=8.4.13
mbstring=8.4.13
mongodb=2.1.4
mysqli=8.4.13
opcache=8.4.13
pcntl=8.4.13
pdo_mysql=8.4.13
pdo_pgsql=8.4.13
redis=6.2.0
soap=8.4.13
sockets=8.4.13
sodium=8.4.13
ssh2=1.3.1
xdebug=3.4.6
xsl=8.4.13
zip=1.22.6
```

Tambien estan presentes:

```text
dom, fileinfo, filter, hash, iconv, json, libxml, mysqlnd, openssl,
pdo_sqlite, posix, readline, session, sqlite3, tokenizer, xml,
xmlreader, xmlwriter, zlib
```

Lectura:

1. la cobertura de extensiones es buena para Magento 2.4.8;
2. `ftp` esta cargada, consistente con `PHP_EXTRA_LIBS=(ext-ftp)` en el proyecto;
3. no se detecto ionCube como modulo cargado; si alguna tienda lo requiere, debe tratarse como caso aparte;
4. la imagen contiene Xdebug, pero el uso productivo debe depender de configuracion y no de asumir que siempre esta deshabilitado.

### 3.4 Configuracion PHP montada

El contenedor carga:

```text
Loaded Configuration File: /usr/local/etc/php/php.ini
Scan dir: /usr/local/etc/php/conf.d
```

Archivos `.ini` detectados:

```text
10-php-ext-ioncube.ini
docker-fpm.ini
docker-php-ext-apcu.ini
docker-php-ext-bcmath.ini
docker-php-ext-exif.ini
docker-php-ext-ftp.ini
docker-php-ext-gd.ini
docker-php-ext-imagick.ini
docker-php-ext-intl.ini
docker-php-ext-ldap.ini
docker-php-ext-mongodb.ini
docker-php-ext-mysqli.ini
docker-php-ext-opcache.ini
docker-php-ext-pcntl.ini
docker-php-ext-pdo_mysql.ini
docker-php-ext-pdo_pgsql.ini
docker-php-ext-redis.ini
docker-php-ext-soap.ini
docker-php-ext-sockets.ini
docker-php-ext-sodium.ini
docker-php-ext-ssh2.ini
docker-php-ext-xdebug.ini
docker-php-ext-xsl.ini
docker-php-ext-zip.ini
ext-xdebug.ini
```

Nota:

`php.ini`, `ext-xdebug.ini` y `10-php-ext-ioncube.ini` estan montados desde el proyecto. La imagen propia debe proveer defaults razonables, pero Warp debe seguir permitiendo overrides por bind mount.

### 3.5 Tooling instalado

Herramientas detectadas:

```text
Composer 2.8.12
Node.js v20.19.5
npm 10.8.2
yarn 1.22.22
grunt-cli 1.5.0
grunt 1.5.3
gulp-cli 3.1.0
supervisord 4.2.5
mhsendmail, reemplazable por una alternativa multiarch o por envio SMTP directo al servicio local de mail
```

El comando `supervisorctl status` no encontro socket activo, por lo que supervisor esta instalado pero no necesariamente corriendo en este contenedor con la configuracion actual.

`php-fpm` no aparecio en `PATH` para el usuario `www-data` al ejecutar `php-fpm -v`, aunque el contenedor arranca con `docker-php-entrypoint php-fpm`. La PoC debe validar el path efectivo del binario y el arranque por `CMD`.

### 3.6 Paquetes Debian

Cantidad total aproximada:

```text
631 paquetes
```

Paquetes manuales relevantes detectados:

```text
apt-transport-https
autoconf
build-essential
ca-certificates
cron
curl
default-mysql-client
dpkg-dev
file
fontforge
g++
gcc
git
gnupg
imagemagick
libbz2-dev
libcurl4-gnutls-dev
libexif-dev
libfreetype-dev
libgd-dev
libicu-dev
libjpeg-dev
libldap2-dev
libmagickcore-dev
libmagickwand-dev
libmcrypt-dev
libonig-dev
libpng-dev
libpq-dev
librabbitmq-dev
libreadline-dev
libsodium-dev
libssh2-1-dev
libssl-dev
libtidy-dev
libwebp-dev
libxml2-dev
libxpm-dev
libxslt1-dev
libzip-dev
make
nodejs
openssh-client
pkg-config
re2c
supervisor
ttfautohint
unzip
vim
wget
xz-utils
zip
zlib1g-dev
```

Lectura:

La imagen es mas grande de lo minimo estrictamente necesario porque mezcla runtime, build deps, herramientas de desarrollo, Node tooling, supervisor, cron y clientes DB. Para Warp esto puede ser aceptable si se prioriza compatibilidad operativa, pero conviene decidir si la nueva imagen multiarch sera:

1. `dev/full`: compatible con el uso actual;
2. `runtime`: mas pequena y orientada a produccion;
3. ambas, con tags distintos.

## 4. PHP: historia de build recuperada

`docker history --no-trunc` permite reconstruir bastante del Dockerfile real.

Capas propias relevantes sobre `docker-library/php`:

```text
LABEL maintainer=Julio Arevalo <julio.arevalo@infracommerce.lat>
ENV PHP_EXTRA_CONFIGURE_ARGS=--enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data --enable-intl --enable-opcache --enable-zip
apt-get install ... cron supervisor build-essential ... nodejs ... default-mysql-client ... imagemagick ...
docker-php-ext-configure gd --with-freetype --with-jpeg
docker-php-ext-configure ldap --with-libdir=lib/x86_64-linux-gnu/
docker-php-ext-install ... bcmath xml exif ftp intl mbstring mysqli opcache pcntl pdo pdo_mysql pdo_pgsql posix simplexml soap sockets sodium xsl zip ldap
pecl install imagick ssh2-1.3.1 apcu mongodb redis xdebug
COPY /usr/bin/composer /usr/bin/composer
curl -sL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
npm install -g grunt-cli gulp-cli yarn
wget .../mhsendmail_linux_amd64
groupadd/useradd kirk, warp, spock, scott
WORKDIR /var/www/html
CMD ["php-fpm"]
```

Puntos positivos:

1. el Dockerfile real es bastante recuperable desde metadata;
2. la base ya es Debian 13 / PHP 8.4 moderno;
3. el set de extensiones es claro;
4. el build usa herramientas oficiales de `docker-library/php`;
5. la imagen ya agrupa convenciones Warp de usuarios, grupos y paths.

Puntos problematicos para Arm:

1. `ldap` esta configurado con `--with-libdir=lib/x86_64-linux-gnu/`; debe cambiar a deteccion multiarch via `dpkg-architecture --query DEB_BUILD_MULTIARCH` o equivalente.
2. `mhsendmail_linux_amd64` es binario x86; debe reemplazarse por binario por arquitectura, build desde fuente, alternativa multiarch o eliminarse si PHP envia SMTP directo al servicio local de mail.
3. no se probo que todas las extensiones PECL compilen en `arm64`.
4. NodeSource `setup_20.x` probablemente soporta Arm, pero debe validarse durante build multiarch.
5. la imagen incluye build deps en runtime; si se mantiene asi, el costo de mantenimiento baja pero el tamano sube.

## 5. PHP: capa writable del contenedor

`docker diff example-php-1` mostro muchos cambios runtime.

Cambios esperados/importantes:

```text
/etc/cron.d/cronfile
/usr/local/etc/php/php.ini
/usr/local/etc/php/conf.d/10-php-ext-ioncube.ini
/usr/local/etc/php/conf.d/ext-xdebug.ini
/var/www/.composer
/var/www/.npm
/var/www/.cache
/var/www/html
/var/log/php-fpm
/var/log/supervisor
```

Lectura:

1. la capa writable del contenedor no debe usarse como fuente para crear la nueva imagen;
2. contiene caches de npm/PDepend/analisis, montajes de proyecto y configuracion local;
3. la fuente de verdad para reconstruir la imagen debe ser `docker history`, `php -m`, paquetes apt y archivos bajo `images/php`;
4. los archivos montados desde Warp deben seguir siendo montajes, no baked-in en la imagen.

## 6. Appdata: inventario runtime

### 6.1 Sistema base

El contenedor `example-appdata-1` reporta:

```text
Debian GNU/Linux 8 (jessie)
arch: x86_64
user runtime: root
```

Proceso principal:

```text
/bin/sh /startup.sh
```

Proceso auxiliar:

```text
/usr/bin/rsync --daemon --config /etc/rsyncd.conf
```

Version rsync:

```text
rsync 3.1.1
```

Paquetes manuales:

```text
iproute2
iputils-ping
rsync
```

Cantidad total aproximada:

```text
118 paquetes
```

### 6.2 Entrypoint de imagen

La imagen trae `/docker-entrypoint.sh` con esta funcion:

```text
1. crear /etc/rsyncd.conf si no existe;
2. iniciar rsync daemon;
3. ejecutar el CMD recibido.
```

Configuracion rsync generada:

```text
uid = root
gid = root
use chroot = yes
log file = /dev/stdout
reverse lookup = no
[warp]
    hosts allow = *
    read only = false
    path = /var/www/html
    comment = docker volume
```

### 6.3 Startup montado por Warp

`/startup.sh` esta montado desde:

```text
example/.warp/docker/config/appdata/startup.sh
```

Funciones principales:

1. ajustar permisos de `/var/www/.composer`;
2. loop infinito cada 3600 segundos;
3. `chmod/chgrp` sobre `/var/www/html`;
4. asegurar permisos de `bin/magento`;
5. asegurar permisos de `bin/console` para Oro si existe;
6. asegurar permiso de ejecucion para `warp`.

Lectura:

`appdata` no solo comparte volumen; tambien corrige permisos periodicamente. Esa conducta debe preservarse o reemplazarse por otra estrategia explicita si se elimina appdata.

### 6.4 Historia de build

`docker history --no-trunc summasolutions/appdata:latest` muestra una imagen simple:

```text
FROM debian:jessie
ENV DEBIAN_FRONTEND=noninteractive
apt-get install --no-install-recommends rsync
EXPOSE 873
COPY docker-entrypoint.sh /docker-entrypoint.sh
chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
```

Esto coincide con `images/appdata/Dockerfile`.

### 6.5 Capa writable del contenedor

`docker diff example-appdata-1` mostro:

```text
/etc/rsyncd.conf
/startup.sh
/var/www/.composer
/var/www/.bashrc
/var/www/html
```

Lectura:

1. son cambios esperables por entrypoint y bind mounts;
2. no hay evidencia de estado propio complejo;
3. appdata es de bajo riesgo para reconstruccion multiarch.

## 7. Comparacion con `images/`

### 7.1 PHP

`images/php/<version>/Dockerfile` actual:

1. parte de `summasolutions/php:<version>`;
2. copia `setup-php-modules-summa`;
3. copia `php-custom-entrypoint`;
4. instala `sudo`;
5. permite a `www-data` ejecutar sudo sin password;
6. arranca `php-custom-entrypoint`.

Pero `summasolutions/php:8.4-fpm` inspeccionada ya parece una imagen base completa, no solo el wrapper del repo.

Diferencia importante:

No hay `images/php/8.4-fpm/Dockerfile` local. Para reconstruir `8.4-fpm` multiarch hay que crear uno nuevo usando:

1. `docker history` de `summasolutions/php:8.4-fpm`;
2. convenciones de `images/php/old`;
3. `images/php/common` si se mantiene instalacion dinamica por `PHP_EXTRA_LIBS`;
4. validaciones contra `example`.

### 7.2 Appdata

`images/appdata/Dockerfile` coincide con la imagen inspeccionada.

Conclusion:

`appdata` puede reconstruirse casi 1:1, pero conviene cambiar base a Debian actual o Alpine. Es la primera imagen candidata para PoC.

## 8. Estrategia de reconstruccion propuesta

### 8.1 Appdata

PoC sugerida:

```text
FROM debian:bookworm-slim
install rsync, iproute2, iputils-ping si siguen siendo necesarios
COPY docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
```

Validaciones:

1. `rsync --version`;
2. arranque de daemon;
3. generacion de `/etc/rsyncd.conf`;
4. ejecucion de `/startup.sh` montado;
5. permisos sobre `bin/magento`, `vendor`, `warp`.

Complejidad: baja.

Riesgo principal:

Cambios de comportamiento de permisos por diferencias entre Debian Jessie y base moderna.

### 8.2 PHP 8.4

PoC sugerida:

```text
FROM php:8.4-fpm
instalar paquetes apt requeridos
docker-php-ext-configure gd
docker-php-ext-configure ldap con libdir multiarch dinamico
docker-php-ext-install extensiones core
pecl install imagick ssh2 apcu mongodb redis xdebug
instalar composer
instalar node 20 + npm + yarn + grunt-cli + gulp-cli
instalar o reemplazar mhsendmail por alternativa multiarch, o configurar envio SMTP directo al servicio local de mail
crear usuarios/grupos kirk/warp/spock/scott
crear paths /var/www/.ssh, /var/log/php-fpm
WORKDIR /var/www/html
CMD php-fpm
```

Validaciones minimas contra `example`:

1. `php -v` debe ser compatible con Magento `2.4.8-p4`;
2. `php -m` debe incluir el set actual;
3. versiones PECL criticas deben ser equivalentes o aceptables:
   - `imagick`
   - `redis`
   - `mongodb`
   - `ssh2`
   - `apcu`
   - `xdebug`
4. `composer check-platform-reqs`;
5. `bin/magento --version`;
6. `bin/magento cache:status`;
7. smoke web con PHP-FPM;
8. cron/supervisor si el proyecto los usa realmente;
9. build multiarch `linux/amd64,linux/arm64`.

Complejidad: media.

Riesgos:

1. `mhsendmail_linux_amd64`;
2. `ldap` con ruta x86;
3. PECL sobre Arm;
4. diferencias Node/npm/yarn;
5. Xdebug y extensiones de debug en imagen runtime;
6. mantener una imagen grande de 1.75 GB.

## 9. Decision tecnica preliminar

La inspeccion confirma que la estrategia `appdata/php propias + resto oficiales` es viable para una fase de PoC.

Lectura por imagen:

| Imagen | Viabilidad multiarch | Esfuerzo | Comentario |
| --- | --- | --- | --- |
| `appdata` | Alta | Bajo | Rehacer sobre Debian moderno. |
| `php:8.4-fpm` propia | Media/alta | Medio | Hay suficiente metadata para reconstruir, con fixes Arm claros. |
| DB/cache/search/web | Alta con oficiales | Bajo/medio | Mantener oficiales y validar manifests. |
| imagenes legacy completas | Baja/media | Alto | No incluir en alcance inicial. |

Recomendacion para decision ROI:

1. hacer primero PoC de `appdata` multiarch;
2. hacer PoC de `php:8.4-fpm` multiarch solo para el perfil Magento moderno;
3. no intentar PHP legacy multiarch en esta etapa;
4. no incluir Selenium, Varnish, Elasticsearch legacy, RabbitMQ ni Postgres propios en el primer alcance;
5. medir build time, tamano de imagen, arranque, `php -m`, Magento CLI y smoke web antes de decidir implementacion en Warp.

## 10. Comandos usados

Comandos de inspeccion ejecutados:

```bash
docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
docker inspect example-php-1
docker inspect example-appdata-1
docker inspect summasolutions/php:8.4-fpm
docker inspect summasolutions/appdata:latest
docker exec example-php-1 ...
docker exec example-appdata-1 ...
docker history --no-trunc summasolutions/php:8.4-fpm
docker history --no-trunc summasolutions/appdata:latest
docker diff example-php-1
docker diff example-appdata-1
```

Notas:

1. `docker inspect` del contenedor contiene variables de entorno sensibles; no se copiaron a este documento.
2. `docker diff` de PHP es muy grande por caches de herramientas y archivos montados; se resumio en categorias.
3. No se ejecuto ningun comando destructivo.
