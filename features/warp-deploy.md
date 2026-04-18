# Feature: `warp deploy` (implementado)

Fecha: 2026-03-15

## 1) Objetivo

Agregar un orquestador de deploy para `local` y `prod` que:

1. use comandos existentes de Warp,
2. sea no destructivo por defecto,
3. soporte `--dry-run`,
4. permita configurar flujo por proyecto con `.deploy`.

## 2) Comandos disponibles

```bash
warp deploy
warp deploy run
warp deploy static
warp deploy set
warp deploy show
warp deploy doctor
warp deploy --dry-run
warp deploy run --dry-run
warp deploy run --yes
```

Comportamiento:

1. `warp deploy` muestra ayuda.
2. `warp deploy run` ejecuta deploy completo.
3. `warp deploy static` ejecuta solo frontend/estáticos según `ENV`.
4. Si falta `.deploy`, `run`/`static` ejecutan `set` antes de continuar.
5. `--dry-run` imprime pasos sin ejecutar comandos.
6. `--yes` omite confirmación interactiva de `prod`.
7. `--dry-run` y `--yes` funcionan antes o después de `run`.
8. `--dry-run` imprime la receta de pasos y termina sin ejecutar `doctor` ni comandos de deploy.

## 3) Archivo `.deploy`

Ubicación: raíz del proyecto (`$PROJECTPATH/.deploy`).

Reglas:

1. se genera con `warp deploy set`,
2. se agrega a `.gitignore` automáticamente (`/.deploy`),
3. se versiona con `DEPLOY_SCHEMA_VERSION=1`,
4. al cargar un `.deploy` viejo, Warp agrega defaults opcionales faltantes como `FRONT_STATIC_THEMES=`.

Override opcional para estáticos frontend en `prod`:

- `FRONT_STATIC_THEMES` vacío: deploya todos los themes frontend.
- `FRONT_STATIC_THEMES` con valores: deploya solo el subset indicado.
- Formato: códigos de theme separados por espacios, por ejemplo:
  `FRONT_STATIC_THEMES="Example/hyva-example Example/hyva-website"`
- si el subset contiene un child theme, Magento resuelve el fallback del parent automáticamente.
- incluir también el parent solo cuando ese parent se usa directamente en otro website/store.

## 4) Detección de entorno (`ENV`)

Orden:

1. Si existe `app/etc/env.php`:
   - `MAGE_MODE=production` -> `ENV=prod`
   - `MAGE_MODE=developer` -> `ENV=local`
2. Si no se puede detectar:
   - prompt: `Es entorno de desarrollo? [y/N]`

## 5) Flujo implementado

## 5.1 `deploy doctor`

Valida:

1. `docker-compose-warp.yml`,
2. `.env`,
3. binarios `docker` y `docker-compose`,
4. estado runtime (o `AUTO_START=1`),
5. existencia de `themes.js` cuando `RUN_GRUNT=1`,
6. config Hyva cuando `RUN_HYVA=1`,
7. estado de `warp` en PATH:
   - si existe wrapper delegador, informa `[ok]`,
   - si detecta binario viejo real, informa `[warn]` y muestra como reemplazar ese `warp` de sistema con `.warp/setup/bin/warp-wrapper.sh`,
8. en proyectos Magento:
   - `app/etc/config.php` existe,
   - `app/etc/config.php` tiene escritura para user y group (`ug+w`),
9. en `prod`: `THREADS`, `ADMIN_I18N`, `FRONT_I18N`.

## 5.2 `deploy run`

Secuencia:

1. carga `.deploy`,
2. si `ENV=prod`, imprime aviso explicito:
   - el deploy no ejecuta `git pull`,
   - el working tree debe contener ya los cambios correctos.
3. ejecuta `doctor`,
4. confirma `prod` si `CONFIRM_PROD=1` (salvo `--yes`),
5. si `AUTO_START=1` y contenedores apagados: `warp start`,
6. si `prod` y `USE_MAINTENANCE=1`: `maintenance:enable`,
7. `warp composer install` (usa `COMPOSER_FLAGS`),
8. `setup:upgrade` (si `RUN_SETUP_UPGRADE=1`),
9. `setup:di:compile` (si `RUN_DI_COMPILE=1`),
10. frontend:
   - local: grunt/hyva según flags y existencia de archivos,
   - prod: `hyva build` (si aplica) y static deploy admin/frontend,
11. `search flush` (si `RUN_SEARCH_FLUSH=1`),
12. `indexer:reindex` (si `RUN_REINDEX=1`),
13. `cache:flush` (si `RUN_CACHE_FLUSH=1`),
14. si activó maintenance: `maintenance:disable`.

Todas las etapas fallan en corto circuito: si una falla, corta el deploy.

Formato de salida en `run`:

- cada paso se imprime con título entre dos líneas de 80 caracteres `=`.

## 5.3 `deploy static`

Ejecuta solo pasos de frontend/estáticos:

1. `ENV=local`:
   - `grunt exec` + `grunt less` si `RUN_GRUNT=1`,
   - `hyva prepare/build` según flags (`RUN_HYVA`, `HYVA_PREPARE`, `HYVA_BUILD`).
2. `ENV=prod`:
   - `hyva build` si aplica,
   - `setup:static-content:deploy` admin/frontend según flags (`RUN_STATIC_ADMIN`, `RUN_STATIC_FRONT`).
   - si `FRONT_STATIC_THEMES` está definido, el deploy de `frontend` agrega `--theme <code>` por cada theme configurado.

## 6) Variables principales soportadas

Comunes:

- `DEPLOY_SCHEMA_VERSION`
- `ENV`
- `AUTO_START`
- `USE_MAINTENANCE`
- `COMPOSER_FLAGS`
- `RUN_SETUP_UPGRADE`
- `RUN_DI_COMPILE`
- `RUN_REINDEX`
- `RUN_CACHE_FLUSH`
- `RUN_SEARCH_FLUSH`
- `SEARCH_FLUSH_CMD`
- `CONFIRM_PROD`

Local:

- `RUN_GRUNT`
- `RUN_HYVA`
- `HYVA_PREPARE`
- `HYVA_BUILD`

Prod:

- `RUN_STATIC_ADMIN`
- `RUN_STATIC_FRONT`
- `ADMIN_I18N`
- `FRONT_I18N`
- `FRONT_STATIC_THEMES` (opcional; vacío = todos los themes frontend)
- `THREADS` (detectado desde threads lógicos del host menos `WARP_HOST_THREADS_RESERVE`; mínimo `1`)
- `STATIC_EXTRA_FLAGS`

Override de capacidad host:

- `.env`: `WARP_HOST_THREADS_RESERVE`
- default: `1`
- si falta en `.env`, Warp lo agrega al final con el valor default cuando necesita calcular threads del host

## 7) Limitaciones de V1

1. No modifica permisos ni ejecuta acciones destructivas de Git.
2. No aplica cambios automáticos en `.env` (solo orquesta deploy).
3. No hay rollback automático multi-step.
4. No escribe logs dedicados por etapa en `var/log/warp-deploy` (pendiente).

## 8) Archivos implementados

1. `.warp/bin/deploy.sh`
2. `.warp/bin/deploy_help.sh`
3. `.warp/includes.sh` (include del comando)
4. `warp.sh` (dispatch `deploy`)

## 9) Validación mínima ejecutada

1. `./warp.sh --help`
2. `./warp.sh init --help`
3. `./warp.sh start --help`
4. `./warp.sh stop --help`
5. `./warp.sh info --help`
6. `./warp.sh deploy --help`
