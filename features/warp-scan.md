# Warp Scan

Fecha: 2026-03-20
Estado: MVP Magento implementado

## Objetivo

Agregar `warp scan` para ejecutar chequeos de calidad de código con foco en Magento, dejando una base para enchufar otros frameworks PHP.

## Alcance MVP

1. `warp scan` muestra menú de acciones.
2. `warp scan pr` y `warp scan --pr` ejecutan PR checks:
   - PHPCS (`severity>=7`) sobre `app/code` y `app/design`.
   - PHPMD con `TestPR.xml`.
3. `warp scan integrity` / `warp scan -i`:
   - corre `warp magento setup:di:compile` usando el mismo patrón de resolución de entrypoint local ya fijado en `deploy` (`./warp`, `warp.sh` o `warp` en `PATH`).
   - luego corre `warp scan pr`.
4. `warp scan --path <ruta>` abre menú de acciones sobre una ruta arbitraria dentro del proyecto (`testpr|phpcs|phpmd`).

## Reglas TestPR

Fuente versionada:

1. `.warp/setup/init/config/lint/TestPR.xml`

Runtime:

1. `.warp/docker/config/lint/TestPR.xml`

Resolución en ejecución:

1. si existe runtime, se usa runtime.
2. si runtime no existe y existe `app/devops/TestPR.xml`, se crea `./.warp/docker/config/lint` y se copia desde `app/devops`.
3. si no existe `app/devops`, se copia desde la fuente versionada de setup.

## Compatibilidad PHPMD

`warp scan` detecta automáticamente:

1. `vendor/phpmd/phpmd/bin/phpmd` (Magento 2.4.8+),
2. `vendor/phpmd/phpmd/src/bin/phpmd` (Magento <=2.4.7),

además de fallback de subcomando para versiones que cambian la sintaxis (`phpmd` / `analyze` / `check`).

## Base de extensión para otros frameworks

El comando incluye detección de framework:

1. Magento (implementado),
2. Laravel (hook pendiente),
3. WordPress (hook pendiente).

Política actual:

1. para frameworks no-Magento, mensaje explícito `not implemented yet`.
2. para enchufes futuros, mantener un contrato simple por framework:
   - resolver paths de código por defecto,
   - resolver rulesets,
   - ejecutar herramientas con el mismo runtime (host/docker) ya centralizado en `scan_run_php_bin`.
