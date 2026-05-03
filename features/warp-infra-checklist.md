# Warp Infra Checklist

Fecha: 2026-04-16

Checklist de continuidad para la evaluacion multiarch `amd64/arm64`, imagenes propias y perfil PHP INI.

## Hecho

- [x] Analisis inicial de ROI multiarch `c7i` vs `c7g` con instancia `xlarge` y gp3 100 GB.
- [x] Reemplazo de nombres propios de proyectos por `example` en documentacion funcional.
- [x] Inspeccion de contenedores e imagenes PHP/appdata actuales.
- [x] Documentacion de hallazgos en `features/warp-infra-img.md`.
- [x] PoC Dockerfile `appdata` en `images/appdata-poc/`.
- [x] Build local `linux/amd64` de `warp/appdata:bookworm-poc-amd64`.
- [x] Smoke local `appdata` amd64 con Debian bookworm, `rsync` y estructura esperada.
- [x] PoC Dockerfile PHP 8.4 en `images/php/8.4-fpm-poc/`.
- [x] Reemplazo conceptual de servicio mail legacy/mhsendmail por Mailpit + `msmtp`.
- [x] Build local `linux/amd64` de `warp/php:8.4-fpm-poc-amd64`.
- [x] Validacion PHP 8.4 amd64: PHP, Composer, Node, npm, Yarn, msmtp.
- [x] Validacion OPcache presente en imagen PHP PoC.
- [x] Ajuste de imagen PHP PoC para instalar `xdebug.so` sin auto-habilitar Xdebug.
- [x] Validacion de Xdebug: `xdebug.so` instalado, no cargado por default.
- [x] Validacion de Xdebug a demanda con `zend_extension=xdebug.so`.
- [x] Validacion de OPcache a demanda con `opcache.enable=0`.
- [x] Comparacion de tamanos y paquetes entre imagen PoC PHP 8.4 y `summasolutions/php:8.4-fpm`.
- [x] Documentacion para build arm64 en instancia Graviton temporal en `features/warp-infra-buildarm.md`.
- [x] Documentacion de perfiles PHP INI `legacy` y `managed` en `features/warp-phpini.md`.
- [x] Definicion de samples managed/legacy bajo `features/warp-phpini-samples/`.
- [x] Validacion de samples managed contra imagen PHP PoC.
- [x] Documentacion del comando `warp phpini profile` en `features/warp-phpini-command.md`.
- [x] Implementacion read-only de `warp phpini profile status`.
- [x] Preflight en `warp start` que acepta imagenes configuradas locales de cualquier repo/tag y aborta tags PoC faltantes antes de pull remoto.
- [x] Implementacion de `warp phpini profile legacy --dry-run`.
- [x] Implementacion de `warp phpini profile managed --dry-run`.
- [x] Agregado `magtools` como repositorio DockerHub aceptado para nuevas imagenes PHP/appdata.
- [x] Agregados defaults nuevos `PHP_IMAGE_REPO=magtools` y `APPDATA_IMAGE_REPO=magtools`; `summasolutions` queda como override legacy explicito.
- [x] Orden futuro de repos PHP en validacion local: `magtools`, `66ecommerce`, `summasolutions`.
- [x] Implementacion de escritura real de `warp phpini profile legacy`.
- [x] Implementacion de escritura real de `warp phpini profile managed`.
- [x] Implementacion de creacion de `.ini` efectivos managed sin sobrescribir archivos existentes salvo `--force`.
- [x] Implementacion de `warp opcache enable|disable|status`.
- [x] Refactor conservador de `warp xdebug enable|disable|status` manteniendo compatibilidad legacy.
- [x] Agregado mount variable `WARP_PHP_OPCACHE_VOLUME` para `zz-warp-opcache.ini` solo en perfil managed.
- [x] Samples PHP INI movidos a `.warp/setup/php/config/php/{managed,legacy}` para viajar con el payload instalado.
- [x] Instalacion PHP copia defaults managed deshabilitados para `ext-xdebug.ini` y `zz-warp-opcache.ini` si faltan.
- [x] Agregado `.gitignore` para `zz-warp-opcache.ini` y overrides locales.
- [x] Documentado procedimiento de rollback managed -> legacy.
- [x] Generado bundle de prueba local en `../eprivee` con `.env.test`, `docker-compose-warp.yml.test` y `warp-infra-guide.md`.
- [x] Validado `warp phpini`, `warp xdebug` y `warp opcache` en proyecto Magento 2.4.8+ real (`../eprivee`) con imagenes `magtools`.
- [x] Corregida escritura de `.ini` managed para preservar file bind mounts escribiendo in-place.
- [x] Agregado guard en `warp start` para recrear `.warp/docker/config/php/ext-xdebug.ini` como archivo si Docker/Compose lo dejo como directorio vacio.
- [x] Agregado reload de PHP-FPM para `warp xdebug enable|disable` y `warp opcache enable|disable`, con fallback a restart del servicio `php`.
- [x] Ajustado sample managed de Xdebug a valores literales: `debug`, `trigger`, `172.17.0.1`, puerto `9003`.
- [x] Definidos tags modernos en DockerHub para Magento 2.4.8: `magtools/php:8.4.20-fpm` y `magtools/appdata:bookworm`.

## Pendiente

- [ ] Crear y validar build `linux/arm64` de `appdata` en Graviton.
- [ ] Crear y validar build `linux/arm64` de PHP 8.4 en Graviton.
- [ ] Verificar si `magtools/appdata:bookworm` publica manifest `linux/amd64,linux/arm64`.
- [ ] Verificar si `magtools/php:8.4.20-fpm` publica manifest `linux/amd64,linux/arm64`.
- [ ] Probar stack real con `magtools/appdata:bookworm` y `magtools/php:8.4.20-fpm` en `linux/amd64`.
- [ ] Probar stack real con `magtools/appdata:bookworm` y `magtools/php:8.4.20-fpm` en `linux/arm64`.
- [ ] Decidir si `PHP_IMAGE_REPO` y `APPDATA_IMAGE_REPO` deben quedar como pregunta visible del wizard o solo override manual en `.env`.
- [ ] Validar que Magento 2.4.5/2.4.7 sigan en modo legacy sin cambios operativos.
- [ ] Medir performance comparativa real `c7i.xlarge` vs `c7g.xlarge`.
- [ ] Tomar decision ROI final antes de migrar produccion.

## Comandos de referencia

```bash
bash ./warp.sh phpini profile status
bash ./warp.sh phpini profile legacy --dry-run
bash ./warp.sh phpini profile managed --dry-run
bash ./warp.sh phpini profile managed --dry-run --prod
```

## Archivos clave

```text
features/warp-infra.md
features/warp-infra-img.md
features/warp-infra-img-appdata.md
features/warp-infra-img-php.md
features/warp-infra-buildarm.md
features/warp-phpini.md
features/warp-phpini-command.md
features/warp-phpini-samples/
images/appdata-poc/
images/php/8.4-fpm-poc/
```

## Checkpoint para nueva sesion

Fecha del checkpoint: 2026-04-16

### Estado corto

Estamos en fase de analisis + PoC controlada. Ya hay cambios de codigo pequeños y reversibles para preparar perfiles PHP INI y repositorios Docker, y ya se implemento la migracion explicita a `managed` mediante `warp phpini profile managed`.

El objetivo de fondo es evaluar si vale la pena pasar de instancias x86 `c5/c7i` a Graviton `c7g` usando imagenes multiarch propias para PHP/appdata. La conclusion ROI todavia queda pendiente de pruebas arm64 reales y medicion.

### Decisiones tomadas

1. `magtools` sera el DockerHub target para nuevas imagenes propias.
2. `summasolutions` queda como legacy.
3. Orden futuro de preferencia local para imagen PHP:
   - `magtools/php:${PHP_VERSION}`;
   - `66ecommerce/php:${PHP_VERSION}`;
   - `summasolutions/php:${PHP_VERSION}`.
4. Templates nuevos permiten override:
   - `PHP_IMAGE_REPO`;
   - `APPDATA_IMAGE_REPO`;
   - `APPDATA_VERSION`.
5. Defaults para nuevos proyectos:
   - `PHP_IMAGE_REPO=magtools`;
   - `WARP_PHP_IMAGE_FAMILY=magtools`;
   - `APPDATA_IMAGE_REPO=magtools`;
   - `APPDATA_VERSION=bookworm`.
6. Perfil PHP INI:
   - `legacy`: default para proyectos existentes y Magento `2.4.5/2.4.7`;
   - `managed`: futuro para Magento `2.4.8+` con imagen PHP nueva compatible.
7. La imagen PHP nueva debe instalar `xdebug.so` pero no auto-habilitar Xdebug.
8. OPcache se controla por `.ini`; no hace falta descargar la extension para desarrollo.
9. Los `.ini` managed se escriben in-place para no romper file bind mounts activos.
10. Los toggles managed recargan PHP-FPM con `USR2`; si falla, reinician el servicio `php`.
11. Cambios de variables de entorno en `.env` requieren recrear el servicio `php`; un reload de PHP-FPM no cambia el entorno Docker.
12. Tags modernos publicados para Magento 2.4.8:
   - `PHP_IMAGE_REPO=magtools`;
   - `PHP_VERSION=8.4.20-fpm`;
   - `APPDATA_IMAGE_REPO=magtools`;
   - `APPDATA_VERSION=bookworm`.

### Codigo ya tocado

```text
warp.sh
.warp/bin/start.sh
.warp/bin/phpini.sh
.warp/bin/phpini_help.sh
.warp/bin/opcache.sh
.warp/bin/opcache_help.sh
.warp/bin/xdebug.sh
.warp/bin/xdebug_help.sh
.warp/lib/php_fpm.sh
.warp/lib/check.sh
.warp/setup/init/base.sh
.warp/setup/init/gandalf.sh
.warp/setup/init/tpl/appdata.yml
.warp/setup/php/config/php/.warp-empty.ini
.warp/setup/php/php.sh
.warp/setup/php/tpl/php.yml
```

Resumen de codigo:

1. `warp.sh` agrega dispatch `phpini)` y permite `phpini` en host runtime.
2. `.warp/bin/phpini.sh` implementa:
   - `warp phpini profile status`;
   - `warp phpini profile legacy --dry-run`;
   - `warp phpini profile managed --dry-run`;
   - `warp phpini profile managed --dry-run --prod`;
   - escritura real de `warp phpini profile legacy`;
   - escritura real de `warp phpini profile managed`.
3. `.warp/bin/phpini.sh` conserva archivos `.ini` efectivos existentes salvo `--force`.
4. `.warp/bin/opcache.sh` implementa:
   - `warp opcache status`;
   - `warp opcache enable`;
   - `warp opcache disable`;
   - `warp opcache reload`;
   - aliases `--status`, `--enable`, `--disable`, `--reload`;
   - `--dry-run`;
   - `--force` para sobrescribir archivos custom.
5. `.warp/bin/xdebug.sh` conserva el flujo legacy si `WARP_PHP_INI_PROFILE` no es `managed`.
6. `.warp/bin/xdebug.sh` usa samples managed para `enable|disable|status` si el perfil es `managed`.
7. `php.yml` usa `WARP_PHP_OPCACHE_VOLUME` para montar OPcache en `conf.d` solo cuando `phpini profile managed` lo activa.
8. `.warp/lib/check.sh` agrega ignores para `zz-warp-opcache.ini` y `*-local.ini`.
9. `.warp/bin/start.sh` busca imagen PHP local en orden `magtools`, `66ecommerce`, `summasolutions`.
10. `php.yml` y `appdata.yml` usan variables de repo con default legacy.
11. setup agrega defaults retrocompatibles a `.env.sample`.
12. `../eprivee/.env.test` y `../eprivee/docker-compose-warp.yml.test` nacieron para probar tags PoC; para pruebas nuevas usar los tags finales `magtools/php:8.4.20-fpm` y `magtools/appdata:bookworm`.
13. `../eprivee/warp-infra-guide.md` documenta el flujo de prueba, managed/legacy y rollback.
14. `.warp/lib/php_fpm.sh` agrega helper compartido para detectar el contenedor `php`, recargar PHP-FPM con `USR2` y reiniciar el servicio `php` como fallback.
15. `warp xdebug/opcache` escriben samples in-place cuando el archivo efectivo ya existe para preservar el mount activo.
16. El sample managed de Xdebug usa valores literales y no placeholders `${XDEBUG_*}`:
   - `xdebug.discover_client_host=0`;
   - `xdebug.mode=debug`;
   - `xdebug.start_with_request=trigger`;
   - `xdebug.client_host=172.17.0.1`;
   - `xdebug.client_port=9003`;
   - `xdebug.idekey=PHPSTORM`.

### Documentacion/PoC ya creada

```text
features/warp-infra.md
features/warp-infra-img.md
features/warp-infra-img-appdata.md
features/warp-infra-img-php.md
features/warp-infra-buildarm.md
features/warp-phpini.md
features/warp-phpini-command.md
features/warp-phpini-samples/
features/warp-infra-checklist.md
images/appdata-poc/
images/php/8.4-fpm-poc/
```

### Samples importantes

Managed:

```text
features/warp-phpini-samples/managed/ext-xdebug.ini.sample
features/warp-phpini-samples/managed/ext-xdebug.disabled.ini.sample
features/warp-phpini-samples/managed/zz-warp-opcache-enable.ini.sample
features/warp-phpini-samples/managed/zz-warp-opcache-disable.ini.sample
features/warp-phpini-samples/managed/env.phpini.sample
```

Legacy:

```text
features/warp-phpini-samples/legacy/ext-xdebug.ini.sample
features/warp-phpini-samples/legacy/env.phpini.sample
```

### Validaciones ya corridas

Sintaxis:

```bash
bash -n .warp/bin/phpini.sh
bash -n .warp/bin/phpini_help.sh
bash -n .warp/bin/start.sh
bash -n .warp/setup/init/base.sh
bash -n .warp/setup/php/php.sh
bash -n .warp/setup/init/gandalf.sh
bash -n warp.sh
```

Comandos:

```bash
bash ./warp.sh phpini --help
bash ./warp.sh phpini profile status
bash ./warp.sh phpini profile legacy --dry-run
bash ./warp.sh phpini profile managed --dry-run
bash ./warp.sh phpini profile managed --dry-run --prod
bash ./warp.sh phpini profile managed --dev
bash ./warp.sh phpini profile managed --prod --force
bash ./warp.sh opcache --help
bash ./warp.sh opcache status
bash ./warp.sh opcache enable --dry-run
bash ./warp.sh xdebug --help
bash ./warp.sh phpini profile legacy
```

Escritura real de legacy probada en copia temporal, no en repo fuente:

```bash
cp -a /srv2/www/htdocs/66/warp-engine /tmp/warp-engine-phpini-legacy-test
cd /tmp/warp-engine-phpini-legacy-test
bash ./warp.sh phpini profile legacy
sed -n '/WARP_PHP_INI_PROFILE/p' .env
bash ./warp.sh phpini profile status
```

Resultado esperado:

```text
WARP_PHP_INI_PROFILE=legacy
configured profile: legacy
effective profile: legacy
source: .env
```

Imagen PHP PoC validada localmente:

```text
warp/php:8.4-fpm-poc-amd64
PHP 8.4.20
Composer 2.9.7
Node.js 20.20.2
npm 10.8.2
Yarn 1.22.22
msmtp 1.8.28
xdebug.so instalado pero no cargado por default
OPcache cargado
```

Escritura real de managed probada en copia temporal, no en repo fuente:

```bash
cp -a /srv2/www/htdocs/66/warp-engine /tmp/warp-engine-phpini-managed-test2
cd /tmp/warp-engine-phpini-managed-test2
bash ./warp.sh phpini profile managed --dev
bash ./warp.sh phpini profile managed --prod --force
bash ./warp.sh phpini profile managed --dev --prod --dry-run
```

Resultados esperados:

```text
WARP_PHP_INI_PROFILE=managed
ext-xdebug.ini creado desde ext-xdebug.disabled.ini.sample
zz-warp-opcache.ini creado desde disable sample en --dev
zz-warp-opcache.ini sobrescrito desde enable sample en --prod --force
--dev --prod devuelve error y exit code 1
```

Escritura real de OPcache probada en copia temporal, no en repo fuente:

```bash
cp -a /srv2/www/htdocs/66/warp-engine /tmp/warp-engine-opcache-test
cd /tmp/warp-engine-opcache-test
bash ./warp.sh opcache status
bash ./warp.sh opcache disable --dry-run
bash ./warp.sh opcache disable
bash ./warp.sh opcache --enable
bash ./warp.sh opcache disable --force
```

Resultados esperados:

```text
status muestra file state missing si falta zz-warp-opcache.ini
status muestra file state empty si zz-warp-opcache.ini existe vacio
disable crea perfil development con opcache.enable=0
enable crea perfil production con opcache.enable=1
archivo custom se conserva salvo --force; archivo vacio se puede reemplazar sin --force
reload PHP-FPM si php esta corriendo; fallback restart del servicio php si falla
```

Escritura real de Xdebug managed probada en copia temporal, no en repo fuente:

```bash
cp -a /srv2/www/htdocs/66/warp-engine /tmp/warp-engine-xdebug-test
cd /tmp/warp-engine-xdebug-test
bash ./warp.sh xdebug status
bash ./warp.sh xdebug enable --dry-run
bash ./warp.sh xdebug enable
bash ./warp.sh xdebug --status
bash ./warp.sh xdebug --disable
bash ./warp.sh xdebug enable --force
```

Resultados esperados:

```text
status muestra file state missing si falta ext-xdebug.ini
status muestra file state disabled si ext-xdebug.ini existe vacio
enable crea perfil enabled desde ext-xdebug.ini.sample
disable crea perfil disabled desde ext-xdebug.disabled.ini.sample
archivo custom se conserva salvo --force; archivo vacio se puede reemplazar sin --force
aliases --enable, --disable y --status siguen aceptados
perfil legacy mantiene sed/reinicio, reporta archivo vacio como disabled y no simula enable si falta ;zend_extension
perfil managed escribe in-place, recarga PHP-FPM y no recrea contenedor
```

Mount OPcache managed probado en copia temporal, no en repo fuente:

```bash
cp -a /srv2/www/htdocs/66/warp-engine /tmp/warp-engine-mount-test
cd /tmp/warp-engine-mount-test
bash ./warp.sh phpini profile managed --dev
sed -n '/WARP_PHP_INI_PROFILE/p;/WARP_PHP_OPCACHE_VOLUME/p' .env
bash ./warp.sh phpini profile legacy
sed -n '/WARP_PHP_INI_PROFILE/p;/WARP_PHP_OPCACHE_VOLUME/p' .env
```

Resultados esperados:

```text
managed: WARP_PHP_OPCACHE_VOLUME=./.warp/docker/config/php/zz-warp-opcache.ini:/usr/local/etc/php/conf.d/99-warp-opcache.ini
legacy:  WARP_PHP_OPCACHE_VOLUME=./.warp/docker/config/php/.warp-empty.ini:/tmp/.warp-opcache.ini
.warp/docker/config/php/.warp-empty.ini existe
```

Bundle de prueba generado en proyecto `../eprivee`:

```text
../eprivee/.env.test
../eprivee/docker-compose-warp.yml.test
../eprivee/warp-infra-guide.md
../eprivee/.warp/docker/config/php/.warp-empty.ini
../eprivee/.warp/docker/config/php/zz-warp-opcache.ini
```

Validacion realizada:

```bash
cd ../eprivee
docker compose --env-file .env.test -f docker-compose-warp.yml.test config --quiet
```

Resultado esperado:

```text
exit code 0
```

Imagenes historicas configuradas en el bundle inicial:

```text
magtools/php:8.4-fpm-poc-amd64
magtools/appdata:bookworm-poc-amd64
```

Imagenes modernas recomendadas para nuevas pruebas:

```text
magtools/php:8.4.20-fpm
magtools/appdata:bookworm
```

Samples managed validados contra la imagen PHP PoC:

```text
ext-xdebug.ini.sample -> xdebug cargado
ext-xdebug.disabled.ini.sample -> xdebug no cargado
zz-warp-opcache-enable.ini.sample -> opcache.enable On, validate_timestamps Off
zz-warp-opcache-disable.ini.sample -> opcache.enable Off, validate_timestamps On
```

Validacion real en `../eprivee` con `magtools/php:8.4-fpm-poc-amd64`:

```text
warp phpini profile managed --dev creo archivos efectivos disabled
warp xdebug enable escribio ext-xdebug.ini in-place y recargo PHP-FPM
warp opcache enable escribio zz-warp-opcache.ini in-place y recargo PHP-FPM
el ID y StartedAt del contenedor php no cambiaron durante reload
xdebug enabled: loaded=yes, mode=debug, start_with_request=trigger, client_host=172.17.0.1, port=9003
opcache enabled: opcache.enable=1, validate_timestamps=0
xdebug/opcache disable recargo PHP-FPM y dejo runtime dev
```

### Advertencias para el siguiente agente

1. No extender `managed` escribiendo archivos sin respetar `--dry-run` y `--force`.
2. No sobrescribir `.warp/docker/config/php/ext-xdebug.ini` ni `zz-warp-opcache.ini` si existen, salvo `--force`.
3. No tocar proyectos Magento `2.4.5/2.4.7`; deben seguir en `legacy`.
4. `magtools` queda como proveedor por defecto para nuevos proyectos; `summasolutions` se conserva como proveedor legacy explicito.
5. `features/changes.md` puede aparecer modificado por la alineacion del capability `mail` con backend Mailpit y compat legacy `mailhog`; no fue parte central de esta tarea.
6. El repo fuente no tiene `./warp`; validar con `bash ./warp.sh`.
7. El hook de update puede mostrar error remoto de GitHub/raw; no esta relacionado con esta feature.
8. `bash ./warp.sh docker ps` falla en el repo fuente porque no hay `docker-compose-warp.yml`.
9. Builds arm64 locales fallaron por falta de soporte builder/QEMU; usar Graviton segun `features/warp-infra-buildarm.md`.

### Proximo paso recomendado

Validar localmente:

```bash
cd ../eprivee
docker compose --env-file .env.test -f docker-compose-warp.yml.test up -d
docker compose --env-file .env.test -f docker-compose-warp.yml.test exec php php -v
docker compose --env-file .env.test -f docker-compose-warp.yml.test exec php php -i | grep -E 'opcache.enable|opcache.validate_timestamps|xdebug.mode'
docker compose --env-file .env.test -f docker-compose-warp.yml.test down
```

Reglas del proximo paso:

1. probar `../eprivee` con `PHP_VERSION=8.4.20-fpm` y `APPDATA_VERSION=bookworm`;
2. verificar manifests DockerHub de `magtools/php:8.4.20-fpm` y `magtools/appdata:bookworm`;
3. validar que Magento 2.4.5/2.4.7 sigan en `legacy`;
4. validar migraciones legacy dejando `summasolutions` como override explicito cuando corresponda;
5. regenerar `dist/warp`, `dist/version.md` y `dist/sha256sum.md` cuando se cierre esta tanda.
