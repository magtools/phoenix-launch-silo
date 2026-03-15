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
warp deploy set
warp deploy show
warp deploy doctor
warp deploy --dry-run
warp deploy run --dry-run
warp deploy run --yes
```

Comportamiento:

1. `warp deploy` y `warp deploy run` son equivalentes.
2. Si falta `.deploy`, `run` ejecuta `set` antes de continuar.
3. `--dry-run` imprime pasos sin ejecutar comandos.
4. `--yes` omite confirmación interactiva de `prod`.

## 3) Archivo `.deploy`

Ubicación: raíz del proyecto (`$PROJECTPATH/.deploy`).

Reglas:

1. se genera con `warp deploy set`,
2. se agrega a `.gitignore` automáticamente (`/.deploy`),
3. se versiona con `DEPLOY_SCHEMA_VERSION=1`.

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
7. en `prod`: `THREADS`, `ADMIN_I18N`, `FRONT_I18N`.

## 5.2 `deploy run`

Secuencia:

1. carga `.deploy`,
2. ejecuta `doctor`,
3. confirma `prod` si `CONFIRM_PROD=1` (salvo `--yes`),
4. si `AUTO_START=1` y contenedores apagados: `warp start`,
5. si `prod` y `USE_MAINTENANCE=1`: `maintenance:enable`,
6. `warp composer install` (usa `COMPOSER_FLAGS`),
7. `setup:upgrade` (si `RUN_SETUP_UPGRADE=1`),
8. `setup:di:compile` (si `RUN_DI_COMPILE=1`),
9. frontend:
   - local: grunt/hyva según flags y existencia de archivos,
   - prod: `hyva build` (si aplica) y static deploy admin/frontend,
10. `search flush` (si `RUN_SEARCH_FLUSH=1`),
11. `indexer:reindex` (si `RUN_REINDEX=1`),
12. `cache:flush` (si `RUN_CACHE_FLUSH=1`),
13. si activó maintenance: `maintenance:disable`.

Todas las etapas fallan en corto circuito: si una falla, corta el deploy.

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
- `THREADS`
- `STATIC_EXTRA_FLAGS`

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
