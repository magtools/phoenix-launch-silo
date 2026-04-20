# Warp PHP INI Command

Fecha: 2026-04-16

## 1. Objetivo

Definir el comando:

```bash
warp phpini profile status
warp phpini profile legacy
warp phpini profile managed
```

Estado al 2026-04-16:

```text
implementado: warp phpini profile status
implementado: warp phpini profile legacy --dry-run
implementado: warp phpini profile managed --dry-run
implementado: escritura real de warp phpini profile legacy
implementado: escritura real de warp phpini profile managed
```

Este comando no reemplaza inicialmente a:

```bash
warp xdebug
warp opcache
```

Su objetivo es controlar de forma explicita el perfil de gestion de `.ini` PHP:

```dotenv
WARP_PHP_INI_PROFILE=legacy
WARP_PHP_INI_PROFILE=managed
```

## 2. Alcance

`warp phpini` debe ser un comando de control de perfil y diagnostico.

Debe poder:

1. leer el perfil efectivo;
2. escribir el perfil en `.env`;
3. explicar si el perfil fue inferido o definido explicitamente;
4. validar si la imagen PHP seleccionada parece compatible con `managed`;
5. generar archivos efectivos solo cuando se pida una migracion explicita.

No debe:

1. cambiar imagen PHP;
2. modificar `docker-compose-warp.yml` automaticamente en proyectos existentes;
3. recrear contenedores automaticamente;
4. migrar proyectos legacy por inferencia.

## 3. Subcomandos

### 3.1 `warp phpini profile status`

Salida esperada:

```text
PHP INI profile
---------------
configured profile: managed|legacy|not set
effective profile: managed|legacy
source: .env|inferred
app profile: magento-2.4.8+|magento-2.4.7|magento|general|unknown
php version: 8.4-fpm|...
image family: magtools|warp|summasolutions|66ecommerce|custom|unknown
managed compatible: yes|no|unknown
```

Si Docker esta disponible y el contenedor PHP esta corriendo, puede agregar:

```text
runtime xdebug: loaded|not loaded|unknown
runtime opcache: loaded|not loaded|unknown
runtime opcache.enable: On|Off|unknown
```

El comando debe funcionar aunque los contenedores esten apagados.

### 3.2 `warp phpini profile legacy`

Accion:

1. escribir `WARP_PHP_INI_PROFILE=legacy` en `.env`;
2. no borrar `zz-warp-opcache.ini`;
3. no tocar `ext-xdebug.ini`;
4. informar que los comandos `warp xdebug --enable|--disable|--status` mantienen comportamiento historico.

Salida esperada:

```text
PHP INI profile set to legacy.
Existing PHP ini files were not modified.
```

### 3.3 `warp phpini profile managed`

Accion minima:

1. validar compatibilidad basica;
2. escribir `WARP_PHP_INI_PROFILE=managed` en `.env`;
3. crear archivos efectivos si faltan:
   - `.warp/docker/config/php/ext-xdebug.ini`;
   - `.warp/docker/config/php/zz-warp-opcache.ini`;
4. usar defaults conservadores:
   - Xdebug disabled;
   - OPcache disabled si el proyecto parece desarrollo;
   - OPcache enabled solo si se solicita perfil produccion explicito.

Salida esperada:

```text
PHP INI profile set to managed.
Xdebug effective config: disabled
OPcache effective config: development
```

Flags futuros:

```text
--prod      crea zz-warp-opcache.ini desde enable sample
--dev       crea zz-warp-opcache.ini desde disable sample
--force     permite managed con compatibilidad unknown y sobrescribe ini managed existentes
--dry-run   muestra cambios sin escribir
```

## 4. Inferencia

La inferencia debe ser conservadora.

Reglas:

```text
.env contiene WARP_PHP_INI_PROFILE -> usar ese valor
proyecto existente sin variable      -> legacy
Magento <= 2.4.7                    -> legacy
Magento 2.4.8+ + imagen warp        -> managed permitido
Magento sin version confiable        -> legacy
PHP generico                         -> legacy salvo opt-in
```

La inferencia puede sugerir `managed`, pero no debe migrar sola un proyecto existente.

## 5. Compatibilidad de imagen

Para marcar `managed compatible: yes`, Warp debe poder confirmar o inferir:

```text
imagen familia warp
o imagen familia magtools
PHP_VERSION >= 8.4-fpm
Xdebug instalado pero no cargado por default
OPcache disponible
```

Sin contenedor corriendo, la compatibilidad puede quedar:

```text
unknown
```

En ese caso, `profile managed` debe requerir:

```text
--force
```

si el proyecto no es nuevo.

## 6. Archivos de implementacion

Archivos nuevos:

```text
.warp/bin/phpini.sh
.warp/bin/phpini_help.sh
```

Cambios requeridos:

```text
warp.sh
.warp/lib/check.sh
.warp/setup/php/config/php/*
.warp/setup/php/tpl/php.yml
features/warp-phpini.md
features/warp-phpini-command.md
```

`warp.sh` debe agregar dispatch:

```bash
phpini)
shift 1
warp_run_loaded_command phpini_main "phpini" "$@"
;;
```

`warp_command_supports_host_runtime` debe incluir:

```text
phpini
```

porque `profile status` y cambio de `.env` no requieren Docker.

## 7. Ayuda CLI esperada

`warp phpini --help`:

```text
Usage:
 warp phpini profile [status|legacy|managed] [options]

Options:
 -h, --help       display this help message
 --dry-run        show planned changes without writing
 --force          allow unknown compatibility and overwrite managed ini files
 --prod           initialize managed OPcache with production profile
 --dev            initialize managed OPcache with development profile
```

`help` global:

```text
phpini            manage PHP ini profile for Xdebug and OPcache
```

## 8. Reglas de escritura `.env`

La implementacion debe usar helper comun si existe. Si no existe, debe preservar:

1. comentarios;
2. orden del archivo tanto como sea razonable;
3. salto final;
4. permisos existentes.

Regla:

```text
si key existe: reemplazar la primera ocurrencia no comentada
si key no existe: agregar al final en bloque "# Warp PHP INI profile"
```

Keys iniciales:

```dotenv
WARP_PHP_INI_PROFILE=managed
WARP_PHP_IMAGE_FAMILY=magtools
XDEBUG_CONFIG=client_host=172.17.0.1 client_port=9003
```

## 9. Reglas de archivos efectivos

En `managed`, los archivos efectivos deben existir para evitar que Docker cree directorios cuando Compose monta archivos individuales.

Defaults:

```text
ext-xdebug.ini      <- ext-xdebug.disabled.ini.sample
zz-warp-opcache.ini <- zz-warp-opcache-disable.ini.sample
```

Con `--prod`:

```text
zz-warp-opcache.ini <- zz-warp-opcache-enable.ini.sample
```

No sobrescribir archivos efectivos existentes salvo:

```text
--force
```

Si el archivo existe y difiere, informar:

```text
existing file kept: .warp/docker/config/php/ext-xdebug.ini
```

Guard de arranque:

- `warp start` asegura `.warp/docker/config/php/ext-xdebug.ini` antes de invocar Compose.
- si falta, lo crea desde sample disponible o como archivo vacío.
- si existe como directorio vacío, lo reemplaza por archivo.
- si existe como directorio no vacío, aborta con mensaje claro para mover/remover ese directorio manualmente.

## 10. Smokes futuros

Sin Docker:

```bash
warp phpini profile status
warp phpini profile legacy --dry-run
warp phpini profile managed --dry-run
```

Con imagen PoC:

```bash
warp phpini profile managed --dev
warp xdebug status
warp opcache status
```

Los toggles managed escriben los `.ini` efectivos in-place para preservar file bind mounts. Si el contenedor `php` esta corriendo, `warp xdebug enable|disable` y `warp opcache enable|disable` intentan recargar PHP-FPM con `USR2`; si falla el reload, reinician el servicio `php` con Compose.

El reload aplica cambios de `.ini`. Si se cambia `XDEBUG_CONFIG` u otra variable de `.env` que Docker inyecta al contenedor, hay que recrear el servicio `php` para que el entorno del contenedor cambie.

Validacion runtime esperada:

```text
xdebug: not loaded
opcache.enable: Off
```

Con `--prod`:

```text
xdebug: not loaded
opcache.enable: On
opcache.validate_timestamps: Off
```
