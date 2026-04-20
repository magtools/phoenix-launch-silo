# Warp PHP INI: xdebug/opcache enable-disable

Fecha: 2026-04-16

## 1. Objetivo

Definir como deberian funcionar:

```bash
warp xdebug enable
warp xdebug disable
warp xdebug status
warp opcache enable
warp opcache disable
warp opcache status
```

El objetivo es que Warp controle Xdebug y OPcache con archivos `.ini` generados desde `.sample`, sin editar manualmente `php.ini`, sin depender de `sed` sobre archivos activos, y sin versionar archivos efectivos de entorno en proyectos Magento.

Documento complementario:

```text
features/warp-phpini-command.md
```

## 2. Estado de avance

Este documento separa tres pasos:

1. Imagen PHP PoC: instalar `xdebug.so` sin auto-habilitar Xdebug.
2. Comando `warp opcache enable|disable|status` implementado para perfil `managed`.
3. Refactor de `warp xdebug enable|disable|status` implementado para perfil `managed`, manteniendo comportamiento legacy.

Estado al 2026-04-16:

1. Punto 1 avanzado en `images/php/8.4-fpm-poc/Dockerfile`.
2. La imagen `warp/php:8.4-fpm-poc-amd64` fue reconstruida y validada: `xdebug.so` existe, `xdebug` no aparece en `php -m`, OPcache sigue cargado.
3. `warp phpini profile status` fue agregado como diagnostico read-only.
4. `warp phpini profile legacy --dry-run` y `warp phpini profile managed --dry-run` fueron agregados como planificacion sin escritura.
5. `warp phpini profile legacy` fue agregado como escritura real segura: solo fija `WARP_PHP_INI_PROFILE=legacy`.
6. `warp phpini profile managed` fue agregado como migracion explicita a perfil managed.
7. `warp opcache enable|disable|status` fue agregado para controlar `zz-warp-opcache.ini`; al cambiar estado intenta recargar PHP-FPM y reinicia el servicio `php` solo si el reload falla.
8. `warp xdebug enable|disable|status` usa samples managed cuando `WARP_PHP_INI_PROFILE=managed`; fuera de ese perfil conserva el flujo historico.
9. El mount de OPcache usa `WARP_PHP_OPCACHE_VOLUME`: legacy monta un placeholder vacio fuera de `conf.d`, managed monta `zz-warp-opcache.ini` en `conf.d`.

Validacion local de la imagen PoC:

```text
xdebug.so installed, not loaded
PHP 8.4.20
with Zend OPcache v8.4.20
opcache.enable => On => On
opcache.enable_cli => Off => Off
```

Validacion de toggle por configuracion:

```text
php -d zend_extension=xdebug.so -m: xdebug cargado
php -d opcache.enable=0 -i: opcache.enable => Off => Off
```

## 3. Problema actual

Warp ya tiene `warp xdebug --enable|--disable|--status`, pero el flujo actual:

1. modifica `.warp/docker/config/php/ext-xdebug.ini` con `sed`;
2. comenta/descomenta `zend_extension`;
3. requiere contenedores corriendo;
4. mezcla archivo sample, archivo efectivo y estado runtime;
5. no contempla OPcache como feature operable.

Ese modelo funciona, pero es fragil:

1. no diferencia Xdebug 2 de Xdebug 3;
2. no permite deshabilitar Xdebug de forma limpia si la imagen lo carga desde un `.ini` interno;
3. no deja claro que OPcache se apaga por configuracion aunque la extension siga cargada;
4. los cambios locales pueden quedar como ruido en git si el `.gitignore` del proyecto no esta completo.

## 4. Principios

1. Los `.sample` son versionables.
2. Los `.ini` efectivos son estado local del proyecto y deben ir en `.gitignore`.
3. `enable` copia un sample conocido a un archivo efectivo.
4. `disable` borra o neutraliza el archivo efectivo.
5. Los comandos deben funcionar con contenedores apagados.
6. Si el contenedor PHP esta corriendo, Warp debe recargar PHP-FPM; si el reload falla, debe reiniciar el servicio `php`.
7. No se debe editar `php.ini` para toggles operativos.
8. El estado debe poder leerse desde archivos aunque PHP no este corriendo.
9. Cuando PHP esta corriendo, `status` debe contrastar archivo esperado contra `php -m` / `php -i`.

## 5. Layout propuesto

Directorio:

```text
.warp/docker/config/php/
```

Samples versionables:

```text
ext-xdebug.ini.sample
ext-xdebug.disabled.ini.sample
zz-warp-opcache-enable.ini.sample
zz-warp-opcache-disable.ini.sample
```

Archivos efectivos no versionables:

```text
ext-xdebug.ini
zz-warp-opcache.ini
```

Reglas:

1. `ext-xdebug.ini` controla si Xdebug se carga y con que configuracion.
2. `zz-warp-opcache.ini` controla valores de OPcache con precedencia alta.
3. Los samples se pueden regenerar con `warp init`, `warp php switch` o `warp reset`.
4. Los archivos efectivos se pueden crear/borrar con comandos Warp.

## 6. Gitignore Magento

Warp debe asegurar estas entradas en `.gitignore` del proyecto:

```gitignore
/.warp/docker/config/php/ext-xdebug.ini
/.warp/docker/config/php/zz-warp-opcache.ini
/.warp/docker/config/php/*-local.ini
```

Y debe permitir versionar samples:

```gitignore
!/.warp/docker/config/php/*.sample
```

Nota:

Actualmente Warp ya ignora `ext-xdebug.ini` y `ext-ioncube.ini`. Esta feature agregaria `zz-warp-opcache.ini` y un patron para overrides locales.

## 7. Xdebug

### 7.1 Requisito de imagen

Para que `warp xdebug disable` sea un apagado real, la imagen PHP debe cumplir esto:

1. `xdebug.so` puede estar instalado;
2. la imagen no debe cargar Xdebug desde un `.ini` interno permanente;
3. Xdebug solo debe cargarse si Warp monta/genera `ext-xdebug.ini` con `zend_extension`.

Si la imagen contiene un archivo como:

```text
/usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
```

entonces borrar `.warp/docker/config/php/ext-xdebug.ini` no alcanza, porque Xdebug puede seguir cargado desde la imagen.

Decision recomendada para imagenes Warp nuevas:

```text
instalar xdebug.so, pero no ejecutar docker-php-ext-enable xdebug en build.
```

Xdebug queda disponible, pero apagado por default.

### 7.2 Sample enable para Xdebug 3

Archivo:

```text
.warp/docker/config/php/ext-xdebug.ini.sample
```

Contenido recomendado para PHP moderno:

```ini
zend_extension=xdebug.so

xdebug.discover_client_host=0
xdebug.mode=debug
xdebug.start_with_request=trigger
xdebug.client_host=172.17.0.1
xdebug.client_port=9003
xdebug.idekey=PHPSTORM
xdebug.max_nesting_level=300
```

Variable `.env` recomendada para compatibilidad con integraciones que leen `XDEBUG_CONFIG`:

```dotenv
XDEBUG_CONFIG=client_host=172.17.0.1 client_port=9003
```

Notas:

1. El sample managed usa valores literales para que `warp xdebug enable|disable` aplique con reload de PHP-FPM sin depender de variables de entorno del contenedor.
2. Si se cambia `XDEBUG_CONFIG` o cualquier variable de `.env` consumida como entorno del contenedor, hay que recrear el servicio `php`; un reload de PHP-FPM no actualiza variables de entorno de Docker.
3. Para Linux se mantiene `172.17.0.1` como default operativo actual.
4. En macOS puede requerirse otro host (`host.docker.internal` o `10.254.254.254`) segun el entorno.
5. Xdebug 3 usa puerto `9003`; Xdebug 2 usaba `9000`.

### 7.3 Sample disabled

Archivo:

```text
.warp/docker/config/php/ext-xdebug.disabled.ini.sample
```

Contenido:

```ini
; Xdebug disabled by Warp.
; Intentionally no zend_extension here.
```

Este archivo es util si Compose necesita que exista siempre el archivo montado. Si el template Compose soporta archivo ausente sin efectos secundarios, `disable` puede borrar directamente `ext-xdebug.ini`.

### 7.4 Comandos Xdebug

`warp xdebug enable`:

1. en perfil `managed`, valida que exista `ext-xdebug.ini.sample`;
2. escribe `ext-xdebug.ini.sample` in-place sobre `ext-xdebug.ini` para preservar file bind mounts;
3. asegura `XDEBUG_CONFIG` en `.env` si falta;
4. conserva archivos custom salvo `--force`;
5. si el contenedor `php` esta corriendo, recarga PHP-FPM con `USR2`;
6. si el reload falla, reinicia el servicio `php` con Compose.

`warp xdebug disable`:

1. en perfil `managed`, escribe `ext-xdebug.disabled.ini.sample` in-place sobre `ext-xdebug.ini`;
2. conserva archivos custom salvo `--force`;
3. si el contenedor `php` esta corriendo, recarga PHP-FPM con `USR2`;
4. si el reload falla, reinicia el servicio `php` con Compose.

Fuera de `managed`, los comandos Xdebug mantienen el comportamiento historico basado en `sed` sobre `ext-xdebug.ini` y reinicio de `php`.

`warp xdebug status`:

Debe mostrar:

```text
config file: .warp/docker/config/php/ext-xdebug.ini
file state: enabled|disabled|missing
env config: XDEBUG_CONFIG=<value>
runtime module: loaded|not loaded|unknown
runtime mode: <xdebug.mode if available>
```

### 7.5 Compatibilidad Xdebug 2

Para PHP legacy, el sample debe ser especifico por version:

```ini
zend_extension=/usr/local/lib/php/extensions/no-debug-non-zts-<api>/xdebug.so
xdebug.remote_enable=1
xdebug.remote_port=9000
xdebug.remote_connect_back=0
xdebug.remote_host=172.17.0.1
xdebug.idekey=PHPSTORM
xdebug.max_nesting_level=300
```

Regla:

1. PHP `8.0+`: generar sample Xdebug 3.
2. PHP `7.x` y legacy: mantener sample compatible con Xdebug 2 si la imagen usa Xdebug 2.
3. No mezclar directivas de Xdebug 2 y 3 en el mismo archivo efectivo.

## 8. OPcache

### 8.1 Requisito de imagen

OPcache debe estar disponible en la imagen PHP.

Para produccion:

```text
opcache cargado y habilitado
```

Para desarrollo:

```text
opcache puede seguir cargado, pero opcache.enable=0
```

Nota importante:

Apagar OPcache por ini no es lo mismo que evitar que la extension se cargue. Para la necesidad operativa de desarrollo, alcanza con:

```ini
opcache.enable=0
opcache.enable_cli=0
```

Evitar cargar OPcache por completo requeriria que la imagen no lo habilite internamente, o que Warp controle tambien el `.ini` que contiene `zend_extension=opcache`.

### 8.2 Sample enable

Archivo:

```text
.warp/docker/config/php/zz-warp-opcache-enable.ini.sample
```

Contenido recomendado:

```ini
opcache.enable=1
opcache.enable_cli=0
opcache.validate_timestamps=0
opcache.revalidate_freq=0
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=100000
opcache.save_comments=1
```

Notas:

1. `validate_timestamps=0` es perfil produccion.
2. Magento en produccion debe acompañar esto con deploy correcto, cache flush y restart PHP-FPM cuando cambie codigo.
3. `opcache.save_comments=1` se mantiene por compatibilidad con frameworks/librerias que leen annotations/docblocks.

### 8.3 Sample disable

Archivo:

```text
.warp/docker/config/php/zz-warp-opcache-disable.ini.sample
```

Contenido recomendado:

```ini
opcache.enable=0
opcache.enable_cli=0
opcache.validate_timestamps=1
opcache.revalidate_freq=0
```

Notas:

1. Este perfil es para desarrollo.
2. El modulo puede aparecer en `php -m`, pero no cachea scripts.
3. Si un proyecto necesita probar con OPcache cargado pero validando timestamps, se puede agregar un tercer sample `zz-warp-opcache-dev.ini.sample`.

### 8.4 Comandos OPcache

`warp opcache enable`:

1. escribe `zz-warp-opcache-enable.ini.sample` in-place sobre `zz-warp-opcache.ini`;
2. conserva archivos custom salvo `--force`;
3. si el contenedor `php` esta corriendo, recarga PHP-FPM con `USR2`;
4. si el reload falla, reinicia el servicio `php` con Compose;
5. informa que el perfil activo es produccion.

`warp opcache disable`:

1. escribe `zz-warp-opcache-disable.ini.sample` in-place sobre `zz-warp-opcache.ini`;
2. conserva archivos custom salvo `--force`;
3. si el contenedor `php` esta corriendo, recarga PHP-FPM con `USR2`;
4. si el reload falla, reinicia el servicio `php` con Compose;
5. informa que el perfil activo es desarrollo.

`warp opcache status`:

Debe mostrar:

```text
config file: .warp/docker/config/php/zz-warp-opcache.ini
file state: enabled|disabled|missing
runtime module: loaded|not loaded|unknown
opcache.enable: On|Off|unknown
opcache.enable_cli: On|Off|unknown
opcache.validate_timestamps: value|unknown
```

## 9. Perfiles recomendados

### 9.1 Produccion

```bash
warp opcache enable
warp xdebug disable
```

Resultado esperado:

```text
OPcache: loaded + enabled
Xdebug: not loaded
```

### 9.2 Desarrollo default

```bash
warp opcache disable
warp xdebug disable
```

Resultado esperado:

```text
OPcache: loaded but disabled
Xdebug: not loaded
```

### 9.3 Desarrollo con debug

```bash
warp opcache disable
warp xdebug enable
```

Resultado esperado:

```text
OPcache: loaded but disabled
Xdebug: loaded
```

## 10. Aplicacion en PHP-FPM

Los cambios en carga de extensiones y OPcache requieren que PHP-FPM vuelva a leer la configuracion.

Comportamiento implementado:

1. si contenedor PHP no esta corriendo, solo modificar archivos;
2. si contenedor PHP esta corriendo, recargar PHP-FPM con `kill -USR2 1`;
3. si el reload falla, reiniciar solo el servicio `php`;
4. no recrear contenedores para cambios de `.ini`;
5. recrear el servicio `php` solo cuando cambian variables de entorno de Docker, por ejemplo `XDEBUG_CONFIG`.

Ejemplos:

```bash
warp xdebug enable
warp opcache disable
```

## 11. Compose y mounts

Estado actual de templates:

```yaml
- ./.warp/docker/config/php/php.ini:/usr/local/etc/php/php.ini
- ./.warp/docker/config/php/ext-xdebug.ini:/usr/local/etc/php/conf.d/ext-xdebug.ini
- ./.warp/docker/config/php/ext-ioncube.ini:/usr/local/etc/php/conf.d/10-php-ext-ioncube.ini
```

Para OPcache se debe agregar:

```yaml
- ${WARP_PHP_OPCACHE_VOLUME:-./.warp/docker/config/php/.warp-empty.ini:/tmp/.warp-opcache.ini}
```

Consideracion:

Si Compose monta un archivo que no existe en host, Docker puede crear un directorio y romper el arranque. Por eso hay dos caminos validos:

1. mantener siempre archivos efectivos, usando samples enable/disable;
2. asegurar los archivos efectivos antes de `warp start`.

Recomendacion inicial:

```text
mantener siempre ext-xdebug.ini y zz-warp-opcache.ini como archivos efectivos generados.
```

Implementacion actual:

1. `warp start` asegura `.warp/docker/config/php/ext-xdebug.ini` antes de invocar Compose.
2. Si falta, lo crea desde sample disponible o como archivo vacio.
3. Si Docker/Compose lo dejo como directorio vacio, Warp lo recrea como archivo y avisa.
4. Si el directorio tiene contenido, Warp no lo borra y aborta con mensaje operativo.

En ese modelo:

1. `xdebug disable` escribe el sample disabled en vez de borrar;
2. `opcache disable` escribe el sample disable;
3. los archivos siguen ignorados por git.
4. `phpini profile managed` cambia `WARP_PHP_OPCACHE_VOLUME` para montar `zz-warp-opcache.ini` en PHP `conf.d`.
5. `phpini profile legacy` vuelve a montar `.warp-empty.ini` fuera de PHP `conf.d`.

Si luego se cambia Compose para tolerar archivos ausentes, `xdebug disable` puede borrar el archivo efectivo.

## 12. Contrato CLI

Forma principal:

```bash
warp xdebug enable
warp xdebug disable
warp xdebug status

warp opcache enable
warp opcache disable
warp opcache status
```

Aliases aceptables por compatibilidad:

```bash
warp xdebug --enable
warp xdebug --disable
warp xdebug --status

warp opcache --enable
warp opcache --disable
warp opcache --status
```

Flags comunes:

```text
--force       overwrite a custom managed ini file
--dry-run     show planned managed changes without writing
```

Ejemplo:

```bash
warp xdebug enable
```

## 13. Validaciones

Xdebug:

```bash
docker compose exec -T php php -m | grep -i xdebug
docker compose exec -T php php -i | grep -E '^xdebug.mode|^xdebug.client_host|^xdebug.client_port'
```

OPcache:

```bash
docker compose exec -T php php -m | grep -i 'Zend OPcache'
docker compose exec -T php php -i | grep -E '^opcache.enable|^opcache.enable_cli|^opcache.validate_timestamps'
```

Produccion esperada:

```text
Xdebug: no aparece en php -m
OPcache: opcache.enable => On
```

Desarrollo esperado:

```text
Xdebug: aparece solo cuando se habilita
OPcache: opcache.enable => Off
```

## 14. Cambios requeridos cuando se implemente

Archivos probables:

```text
.warp/bin/phpini.sh
.warp/bin/phpini_help.sh
.warp/bin/xdebug.sh
.warp/bin/xdebug_help.sh
.warp/bin/opcache.sh
.warp/bin/opcache_help.sh
.warp/includes.sh
warp.sh
.warp/setup/php/config/php/*
.warp/setup/php/tpl/php.yml
.warp/lib/check.sh
features/warp-phpini.md
```

Reglas de implementacion:

1. no usar `sed` para comentar/descomentar `zend_extension`;
2. escribir samples in-place sobre archivos efectivos existentes para preservar file bind mounts;
3. preservar soporte del comando legacy `warp xdebug --enable`;
4. agregar `warp opcache` como comando nuevo;
5. agregar `warp phpini profile` como selector explicito `legacy|managed`;
6. actualizar `.gitignore` del proyecto en `warp init`;
7. no asumir que los contenedores estan corriendo;
8. detectar y advertir si la imagen carga Xdebug internamente;
9. documentar diferencias entre "extension cargada" y "feature habilitada".

Notas de integracion CLI:

1. `.warp/includes.sh` autoload de `.warp/bin/*.sh` ya cubre `phpini.sh`;
2. `warp.sh` igual necesita un case explicito `phpini)`;
3. `warp_command_supports_host_runtime` debe incluir `phpini`;
4. `phpini_help.sh` debe exponer `phpini` en el help global;
5. el comando debe funcionar sin `docker-compose-warp.yml` para permitir diagnostico previo a `warp start`.

## 15. Decision abierta

Queda por decidir al implementar:

1. si `xdebug disable` borra `ext-xdebug.ini` o escribe un disabled sample;
2. si los templates Compose seguiran montando archivos individuales o cambiaran a otro patron;
3. si la imagen PHP nueva debe dejar Xdebug instalado pero no habilitado por default;
4. si OPcache debe tener solo `enable/disable` o tambien perfiles `prod/dev`.

Decision recomendada para el primer paso:

1. usar archivos efectivos siempre presentes para no romper Compose;
2. `xdebug disable` escribe `ext-xdebug.disabled.ini.sample`;
3. `opcache enable/disable` escribe samples a `zz-warp-opcache.ini`;
4. imagen PHP nueva instala Xdebug pero no lo auto-habilita;
5. OPcache queda disponible y se controla por override `zz-warp-opcache.ini`.

## 16. Retrocompatibilidad

El cambio debe ser retrocompatible para proyectos existentes mientras sigan usando imagenes actuales, especialmente proyectos Magento `2.4.5` y `2.4.7` que deben operar por un tiempo con el flujo conocido.

Regla de compatibilidad:

```text
proyectos existentes: comportamiento legacy por defecto
proyectos nuevos PHP 8.4 / Magento 2.4.8+: nuevo patron por opt-in
```

### 16.1 Imagenes actuales

Las imagenes actuales pueden traer Xdebug habilitado internamente desde un archivo de la imagen, por ejemplo:

```text
/usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
```

En ese caso, controlar solamente:

```text
.warp/docker/config/php/ext-xdebug.ini
```

no garantiza que `warp xdebug disable` descargue Xdebug de verdad. Puede desactivar el `zend_extension` montado por Warp, pero Xdebug puede seguir cargado desde la imagen.

Por eso, para imagenes actuales:

1. no cambiar el contrato de arranque por defecto;
2. mantener compatibilidad con `warp xdebug --enable|--disable|--status`;
3. no asumir que `disable` significa "modulo no cargado";
4. documentar `status` como estado del archivo Warp si no se puede verificar runtime;
5. no agregar `zz-warp-opcache.ini` a proyectos existentes salvo opt-in o regeneracion controlada.

### 16.2 Imagenes nuevas PHP 8.4 / Magento 2.4.8+

Para imagenes nuevas, la regla cambia:

```text
Xdebug instalado, pero no auto-habilitado por la imagen.
OPcache instalado y controlable por override ini.
```

Esto permite que los comandos futuros tengan semantica real:

```text
warp xdebug disable  -> Xdebug no aparece en php -m
warp xdebug enable   -> Xdebug aparece en php -m
warp opcache disable -> opcache.enable=0
warp opcache enable  -> opcache.enable=1
```

### 16.3 Estrategia recomendada de migracion

La implementacion debe distinguir perfiles:

```dotenv
WARP_PHP_INI_PROFILE=legacy
WARP_PHP_INI_PROFILE=managed
```

Perfil `legacy`:

1. default para proyectos existentes;
2. mantiene `ext-xdebug.ini` historico;
3. conserva aliases `--enable`, `--disable`, `--status`;
4. no exige `zz-warp-opcache.ini`;
5. no cambia samples de Xdebug 2/legacy en proyectos ya inicializados.

Perfil `managed`:

1. default para nuevos stacks PHP 8.4 / Magento 2.4.8+;
2. usa `ext-xdebug.ini.sample` y `ext-xdebug.disabled.ini.sample`;
3. usa `zz-warp-opcache-enable.ini.sample` y `zz-warp-opcache-disable.ini.sample`;
4. valida runtime con `php -m` y `php -i`;
5. requiere imagen que no auto-habilite Xdebug.

### 16.4 Criterio practico

Para Magento `2.4.5` y `2.4.7`, conservar las imagenes actuales y el flujo actual hasta que el proyecto sea migrado explicitamente.

Para Magento `2.4.8+`, habilitar el nuevo contrato junto con la imagen PHP nueva. Ese es el punto natural para cambiar la forma de trabajo sin arrastrar riesgo a proyectos que siguen en mantenimiento.

## 17. Contrato de perfiles

La implementacion debe introducir una variable explicita:

```dotenv
WARP_PHP_INI_PROFILE=legacy
```

Valores validos:

```text
legacy
managed
```

Regla:

1. si la variable existe, manda la variable;
2. si no existe, Warp infiere un default conservador;
3. la inferencia nunca debe migrar un proyecto existente a `managed` sin una senal explicita;
4. `warp init` puede escribir el default elegido en `.env.sample` y `.env`.

### 17.1 Defaults

Default recomendado:

```text
proyecto ya inicializado sin WARP_PHP_INI_PROFILE: legacy
nuevo proyecto con PHP_VERSION < 8.4-fpm: legacy
nuevo proyecto Magento <= 2.4.7: legacy
nuevo proyecto Magento 2.4.8+ con imagen Warp PHP nueva: managed
nuevo proyecto PHP generico: legacy, salvo opt-in
```

Motivo:

1. las imagenes actuales pueden cargar Xdebug internamente;
2. los templates actuales montan `ext-xdebug.ini` como archivo individual;
3. OPcache ya puede venir habilitado por la imagen;
4. cambiar el contrato de `.ini` puede modificar performance y debugging de proyectos en mantenimiento.

Nota operativa:

- aunque el perfil sea `legacy`, `warp start` mantiene `ext-xdebug.ini` como archivo para evitar que Compose cree un directorio en esa ruta de bind mount.

### 17.2 Reuso de app_context

Warp ya tiene deteccion de contexto en:

```text
.warp/lib/app_context.sh
```

La implementacion no deberia duplicar parsing de Magento. Debe reutilizar:

```text
WARP_APP_FRAMEWORK
WARP_APP_VERSION
WARP_MAGENTO_SERIES
WARP_MAGENTO_PATCH
WARP_APP_COMPAT_PROFILE
```

Perfiles relevantes ya esperables:

```text
magento-2.4.8+
magento-2.4.7
magento-2.4.6
magento-2.4.5
magento
general
```

Decision:

1. `magento-2.4.8+` puede usar `managed` solo si la imagen PHP seleccionada soporta el contrato nuevo;
2. `magento-2.4.7`, `magento-2.4.6`, `magento-2.4.5` deben quedar en `legacy` por defecto;
3. `magento` sin version confiable debe quedar en `legacy`;
4. `general` debe quedar en `legacy` salvo opt-in.

### 17.3 Deteccion de imagen compatible

No alcanza con mirar `PHP_VERSION=8.4-fpm`. Tambien importa el repo de imagen.

El perfil `managed` requiere una imagen que cumpla:

```text
xdebug.so instalado
sin docker-php-ext-xdebug.ini interno
opcache disponible
php -d zend_extension=xdebug.so -m carga Xdebug
php -d opcache.enable=0 -i apaga OPcache
```

Regla recomendada:

```text
WARP_PHP_IMAGE_FAMILY=summasolutions -> legacy
WARP_PHP_IMAGE_FAMILY=66ecommerce    -> legacy
WARP_PHP_IMAGE_FAMILY=magtools       -> managed permitido
WARP_PHP_IMAGE_FAMILY=warp           -> managed permitido para PoC local
WARP_PHP_IMAGE_FAMILY=custom         -> legacy salvo WARP_PHP_INI_PROFILE=managed
```

Si no existe `WARP_PHP_IMAGE_FAMILY`, Warp puede inferir:

```text
summasolutions/php:* -> summasolutions
66ecommerce/php:*    -> 66ecommerce
magtools/php:*       -> magtools
warp/php:*          -> warp
otro                -> custom
```

### 17.4 Comportamiento por perfil

`legacy`:

```text
warp xdebug --enable  -> conserva comportamiento historico con ext-xdebug.ini
warp xdebug --disable -> conserva comportamiento historico con ext-xdebug.ini
warp xdebug --status  -> informa estado del archivo y, si puede, runtime con advertencia
warp opcache *        -> no disponible por defecto o solo informativo
```

`managed`:

```text
warp xdebug enable    -> escribe sample enable in-place en ext-xdebug.ini y recarga PHP-FPM
warp xdebug disable   -> escribe sample disabled in-place en ext-xdebug.ini y recarga PHP-FPM
warp xdebug status    -> compara archivo + env + runtime
warp opcache enable   -> escribe sample enable in-place en zz-warp-opcache.ini y recarga PHP-FPM
warp opcache disable  -> escribe sample disable in-place en zz-warp-opcache.ini y recarga PHP-FPM
warp opcache status   -> compara archivo + runtime
```

Aliases:

```text
--enable, --disable, --status siguen funcionando en ambos perfiles.
```

### 17.5 Mensajes esperados

Si un proyecto `legacy` ejecuta `warp opcache disable`:

```text
OPcache managed mode is not enabled for this project.
Set WARP_PHP_INI_PROFILE=managed only after validating the PHP image contract.
```

Si un proyecto `legacy` ejecuta `warp xdebug --disable` y runtime sigue cargando Xdebug:

```text
Xdebug was disabled in Warp config, but it is still loaded by the PHP image.
The current image likely enables Xdebug internally.
```

Si un proyecto `managed` usa una imagen incompatible:

```text
Managed PHP INI profile requires a PHP image that does not auto-enable Xdebug.
Detected Xdebug loaded without ext-xdebug.ini.
```

### 17.6 Migracion explicita

La migracion debe ser voluntaria y reversible.

Comando futuro opcional:

```bash
warp phpini profile managed
warp phpini profile legacy
warp phpini profile status
```

Primer paso minimo sin comando nuevo:

```dotenv
WARP_PHP_INI_PROFILE=managed
```

Checklist de migracion:

1. cambiar a imagen PHP nueva compatible;
2. agregar `WARP_PHP_INI_PROFILE=managed`;
3. generar samples nuevos;
4. crear `ext-xdebug.ini` disabled por defecto;
5. crear `zz-warp-opcache.ini` segun ambiente;
6. reiniciar PHP;
7. validar `php -m` y `php -i`.

Rollback:

1. volver `WARP_PHP_INI_PROFILE=legacy`;
2. volver `WARP_PHP_OPCACHE_VOLUME` al placeholder:

```dotenv
WARP_PHP_OPCACHE_VOLUME=./.warp/docker/config/php/.warp-empty.ini:/tmp/.warp-opcache.ini
```

3. volver a imagen PHP/appdata anterior si hace falta:

```dotenv
PHP_IMAGE_REPO=summasolutions
PHP_VERSION=<version legacy del proyecto>
APPDATA_IMAGE_REPO=summasolutions
APPDATA_VERSION=latest
```

4. restaurar `ext-xdebug.ini` legacy desde sample anterior si fue reemplazado:

```bash
cp .warp/docker/config/php/ext-xdebug.ini.sample .warp/docker/config/php/ext-xdebug.ini
```

5. recrear/reiniciar PHP para soltar cambios de entorno o mounts anteriores:

```bash
docker compose --env-file .env -f docker-compose-warp.yml down
docker compose --env-file .env -f docker-compose-warp.yml up -d
```

Con el template actual no hace falta quitar una linea del compose para rollback: el mount queda controlado por `WARP_PHP_OPCACHE_VOLUME`.

### 17.7 Impacto en templates

Para mantener retrocompatibilidad, los templates deben poder generarse en dos variantes:

`legacy`:

```yaml
- ./.warp/docker/config/php/ext-xdebug.ini:/usr/local/etc/php/conf.d/ext-xdebug.ini
```

`managed`:

```yaml
- ./.warp/docker/config/php/ext-xdebug.ini:/usr/local/etc/php/conf.d/ext-xdebug.ini
- ./.warp/docker/config/php/zz-warp-opcache.ini:/usr/local/etc/php/conf.d/zz-warp-opcache.ini
```

No se debe agregar el mount de `zz-warp-opcache.ini` a proyectos existentes si no se migra el perfil, porque Docker puede crear directorios si el archivo no existe y porque cambia el contrato operativo.

### 17.8 Estado recomendado inicial por ambiente

Produccion `managed`:

```text
ext-xdebug.ini: disabled sample
zz-warp-opcache.ini: enable sample
```

Desarrollo `managed`:

```text
ext-xdebug.ini: disabled sample
zz-warp-opcache.ini: disable sample
```

Desarrollo con debug `managed`:

```text
ext-xdebug.ini: enable sample
zz-warp-opcache.ini: disable sample
```

## 18. Samples PoC versionados

Mientras esta feature siga en fase de analisis, los samples exactos quedan versionados bajo:

```text
features/warp-phpini-samples/
```

Estos archivos no son consumidos por Warp todavia. Funcionan como contrato de implementacion para mover luego a:

```text
.warp/setup/php/config/php/
```

### 18.1 Managed

Archivos:

```text
features/warp-phpini-samples/managed/ext-xdebug.ini.sample
features/warp-phpini-samples/managed/ext-xdebug.disabled.ini.sample
features/warp-phpini-samples/managed/zz-warp-opcache-enable.ini.sample
features/warp-phpini-samples/managed/zz-warp-opcache-disable.ini.sample
features/warp-phpini-samples/managed/env.phpini.sample
```

Uso esperado:

```text
warp xdebug enable:
  write ext-xdebug.ini.sample in-place -> .warp/docker/config/php/ext-xdebug.ini
  reload PHP-FPM, fallback restart php service

warp xdebug disable:
  write ext-xdebug.disabled.ini.sample in-place -> .warp/docker/config/php/ext-xdebug.ini
  reload PHP-FPM, fallback restart php service

warp opcache enable:
  write zz-warp-opcache-enable.ini.sample in-place -> .warp/docker/config/php/zz-warp-opcache.ini
  reload PHP-FPM, fallback restart php service

warp opcache disable:
  write zz-warp-opcache-disable.ini.sample in-place -> .warp/docker/config/php/zz-warp-opcache.ini
  reload PHP-FPM, fallback restart php service
```

### 18.2 Legacy

Archivos:

```text
features/warp-phpini-samples/legacy/ext-xdebug.ini.sample
features/warp-phpini-samples/legacy/env.phpini.sample
```

Uso esperado:

```text
referencia de compatibilidad solamente
no reemplazar automaticamente samples de proyectos ya inicializados
mantener soporte de --enable, --disable y --status
```

### 18.3 Regla de promocion

Cuando se implemente:

1. copiar los samples `managed` a `.warp/setup/php/config/php/`;
2. generar archivos efectivos solo si `WARP_PHP_INI_PROFILE=managed`;
3. mantener los samples legacy existentes para proyectos actuales;
4. actualizar `warp init`, `warp php switch` y `warp update` sin forzar migraciones;
5. agregar tests/smokes para copiar samples y validar runtime.

### 18.4 Validacion local de samples managed

Los samples `managed` fueron montados contra la imagen PoC:

```text
warp/php:8.4-fpm-poc-amd64
```

Resultados:

```text
ext-xdebug.ini.sample:
  xdebug cargado
  xdebug.discover_client_host => Off
  xdebug.mode => debug
  xdebug.start_with_request => trigger
  xdebug.client_host => 172.17.0.1
  xdebug.client_port => 9003
  xdebug.idekey => PHPSTORM
  xdebug.max_nesting_level => 300

ext-xdebug.disabled.ini.sample:
  xdebug no cargado

zz-warp-opcache-enable.ini.sample:
  opcache.enable => On
  opcache.enable_cli => Off
  opcache.validate_timestamps => Off
  opcache.memory_consumption => 256
  opcache.max_accelerated_files => 100000

zz-warp-opcache-disable.ini.sample:
  opcache.enable => Off
  opcache.enable_cli => Off
  opcache.validate_timestamps => On
```
