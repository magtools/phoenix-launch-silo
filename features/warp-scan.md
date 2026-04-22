# Warp Audit

Fecha: 2026-03-24
Estado: Magento implementado con `phpcompat` y `phpstan`

## Objetivo

Definir `warp audit` como comando canónico para ejecutar chequeos de calidad de código con foco en Magento, dejando una base para enchufar otros frameworks PHP.

Nota de naming:

1. `warp audit` reemplaza a `warp scan` como nombre CLI.
2. esta feature mantiene su archivo histórico `warp-scan.md`, pero el comando funcional vigente pasa a ser `warp audit`.

## Alcance MVP

1. `warp audit` muestra menú de acciones.
2. `warp audit pr` abre un menú de scope para PR checks:
   - `cancel`
   - `custom path`
   - `default` (ejecuta el comportamiento actual del proyecto)
   - paths vendor-level:
     - `app/code/<Vendor>`
     - `app/design/adminhtml/<Vendor>`
     - `app/design/frontend/<Vendor>`
3. `warp audit --pr` ejecuta PR checks no interactivos sobre el scope default actual:
   - PHPCS (`severity>=7`) sobre `app/code` y `app/design`.
   - PHPMD con `TestPR.xml`.
   - PHPCompatibility sobre `app/code`.
4. `warp audit integrity` / `warp audit -i`:
   - corre `warp magento setup:di:compile` usando el mismo patrón de resolución de entrypoint local ya fijado en `deploy` (`./warp`, `warp.sh` o `warp` en `PATH`).
   - luego corre PR checks sobre el scope default no interactivo.
   - luego corre `warp audit risky --path app/code`.
   - luego corre `warp audit phpstan --level 1 --path app/code`.
5. `warp audit --path <ruta>` abre menú de acciones sobre una ruta arbitraria dentro del proyecto sin volver a mostrar menú de paths.
6. `warp audit phpcs --path <ruta>` ejecuta `PHPCS` directo sobre la ruta indicada.
7. `warp audit phpcbf --path <ruta>` ejecuta `PHPCBF` directo sobre la ruta indicada.
8. `warp audit phpmd --path <ruta>` ejecuta `PHPMD` directo sobre la ruta indicada.
9. `warp audit phpcompat --path <ruta>` ejecuta `PHPCompatibility` sobre la ruta indicada.
10. `warp audit risky --path <ruta>` ejecuta una auditoría de risky primitives sobre la ruta indicada.
11. `warp audit phpstan` ejecuta el scope default definido por `phpstan.neon.dist`.
12. `warp audit phpstan --path <ruta>` ejecuta `PHPStan` sobre una ruta puntual.
13. `warp audit phpstan --level <n>` permite override puntual del level sin tocar `phpstan.neon.dist`.

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

`warp audit` detecta automáticamente:

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
   - ejecutar herramientas con el mismo runtime (host/docker) ya centralizado en `audit_run_php_bin`.

## Apéndice: implementación actual y criterios de diseño para `phpcompat` y `phpstan`

### Objetivo

`warp audit` ya expone tres acciones nuevas:

1. `phpcompat`
2. `phpstan`
3. `risky`

Estas capacidades se integran sin degradar el comportamiento existente de:

1. `pr` / `--pr`
2. `integrity` / `-i`
3. `phpcs`
4. `phpcbf`
5. `phpmd`

`features/codeanalyzer.sh` se toma como ejemplo funcional de uso.
`features/php-compat.md` se toma como contexto de implementación y comportamiento esperado.
No se busca portar literalmente ese script a Warp, sino integrar estas capacidades dentro de la arquitectura y runtime propios de `warp audit`.

### Restricción operativa

Estas dos acciones se ejecutan dentro del contenedor PHP, igual que `phpcs` y `phpmd`.

Por lo tanto:

1. `warp audit phpcompat` requiere contenedor PHP corriendo.
2. `warp audit phpstan` requiere contenedor PHP corriendo.

No se usa host-mode para estas dos acciones dentro de `warp audit`.

Esto mantiene consistencia con el enfoque actual del comando y evita diferencias de entorno entre host y contenedor.

### Principios de diseño

1. No degradar `warp audit` actual.
2. Mantener el runtime centralizado de Warp:
   - `docker-compose exec -T php ...`
   - o `docker exec -i <container> ...` cuando exista override explícito por `WARP_AUDIT_PHP_CONTAINER`
3. Validar dependencias por acción, no con un gate global único.
4. No sobrescribir configuración existente del proyecto.
5. Mantener reportes bajo `var/static` con el mismo patrón general de salida de `warp audit`.

### Acciones implementadas

#### 1. `warp audit phpcompat`

Valida compatibilidad de PHP sobre una ruta del proyecto.

Comportamiento esperado:

1. Reutiliza `phpcs` como binario base.
2. Exige que el standard `PHPCompatibility` esté disponible.
3. Limita extensiones a `php,phtml`.
4. Soporta ejecución por path puntual.
5. Genera reporte en `var/static`.

Comando ejecutado como referencia:

```bash
php vendor/squizlabs/php_codesniffer/bin/phpcs \
  --standard=PHPCompatibility \
  --runtime-set testVersion <phpVersion> \
  --extensions=php,phtml \
  <path>
```

Resolución de versión objetivo:

1. Fuente preferida: versión real del runtime PHP dentro del contenedor.
2. Fallback: `PHP_VERSION` desde `.env`.
3. Normalización obligatoria a `major.minor`:
   - `8.4.13` => `8.4`
   - `8.4-fpm` => `8.4`

Motivo:

1. La versión real del contenedor es más exacta que `.env`.
2. `PHPCompatibility` trabaja mejor con una versión objetivo normalizada.
3. `.env` queda como fallback defensivo si por alguna razón no puede resolverse el runtime.

Validaciones necesarias:

1. existe `vendor/squizlabs/php_codesniffer/bin/phpcs`
2. `phpcs -i` lista `PHPCompatibility`

Si falta el standard, el mensaje debe sugerir:

```bash
./warp composer require --dev magento/php-compatibility-fork
./warp composer exec -- phpcs -i
```

#### 2. `warp audit phpstan`

#### 3. `warp audit risky`

Realiza una auditoría rápida de primitives riesgosas sobre una ruta puntual.

Comportamiento esperado:

1. Busca patrones como `eval(`, `base64_decode(`, `system(`, `shell_exec(`, `passthru(`, `assert(`, `proc_open(`, `preg_replace(.../e)`, `create_function(`, `hash_equals(md5(` y uso directo de superglobals sensibles.
2. Limita el análisis a archivos PHP-like (`php`, `phtml`, `phar`, `inc`).
3. Ignora líneas que son comentario puro para evitar ruido obvio.
4. Genera reporte en `var/static`.
5. Soporta ejecución por path puntual igual que `phpcs` o `phpmd`.

Ejecuta análisis estático con PHPStan.

Comportamiento esperado:

1. Usa `vendor/bin/phpstan`.
2. Soporta path puntual.
3. Usa configuración de proyecto desde `phpstan.neon.dist`.
4. Genera reporte en `var/static`.

Estrategia de ejecución actual:

1. `warp audit phpstan`
   - ejecuta `phpstan analyse`
   - usa el scope default definido por `phpstan.neon.dist`
2. `warp audit phpstan --path <ruta>`
   - ejecuta `phpstan analyse <path>`
3. `warp audit phpstan --level <n>`
   - aplica un override puntual de `level` para esa corrida
4. `warp audit phpstan --level <n> --path <ruta>`
   - combina override de `level` con una ruta puntual
5. en el menú principal, `phpstan` ejecuta directamente el scope default
6. en `warp audit --path <ruta>`, `phpstan` corre sobre la ruta elegida

Referencia:

1. Si se elige una ruta puntual:
   ```bash
   php vendor/bin/phpstan analyse <path>
   ```
2. Si se ejecuta sobre alcance por defecto:
   ```bash
   php vendor/bin/phpstan analyse
   ```

Importante:

1. `level`, exclusiones y `tmpDir` deben quedar en `phpstan.neon.dist`
2. no conviene duplicar esa configuración rígidamente en CLI
3. `--level` existe solo como override puntual; el default sigue viviendo en `phpstan.neon.dist`

Si falta el binario, el mensaje debe sugerir:

```bash
./warp composer require --dev phpstan/phpstan
./warp composer exec -- phpstan --version
```

### Configuración base versionada para PHPStan

`warp audit` debe manejar una plantilla base de PHPStan con la misma filosofía de bootstrap ya usada para `TestPR.xml`.

Fuente versionada propuesta:

1. `.warp/setup/init/config/lint/phpstan.neon.dist`

Destino en proyecto:

1. `./phpstan.neon.dist`

Política de materialización:

1. si `./phpstan.neon.dist` ya existe, no tocarlo
2. si no existe, copiar desde la plantilla versionada de Warp
3. informar con mensaje visible cuando la copia se realiza por primera vez

Motivo de guardar el archivo en root del proyecto:

1. PHPStan resuelve naturalmente su configuración en root
2. este archivo representa configuración del análisis del proyecto
3. a diferencia de `TestPR.xml`, aquí el destino natural de runtime no es `.warp/docker/config/lint`, sino el root del proyecto

### Relación con `TestPR.xml`

Se mantiene sin cambios la estrategia actual de `TestPR.xml`:

1. fuente versionada en Warp
2. runtime interno en `.warp/docker/config/lint/TestPR.xml`
3. fallback desde `app/devops/TestPR.xml` si existe

Para `phpstan.neon.dist` no se propone replicar el mismo destino físico, sino el mismo principio operativo:

1. Warp provee una plantilla versionada
2. el archivo se materializa automáticamente solo si falta
3. no se sobrescribe configuración existente del proyecto

### Criterios de implementación en `warp audit`

La integración robusta de `phpcompat` y `phpstan` desacopla las validaciones de dependencias por acción.

Cambio estructural aplicado:

1. `warp audit` ya no usa un gate global único orientado a `PHPCS + PHPMD`
2. cada acción valida sus dependencias reales

Modelo actual:

1. `pr` / `test PR`
   - requiere `phpcs`
   - requiere `phpmd`
   - requiere `TestPR.xml`
   - en scope `default`, ejecuta además `phpcompat` sobre `app/code`
   - en scope por path/vendor, ejecuta el mismo suite completo sobre la ruta elegida
2. `phpcs`
   - requiere solo `phpcs`
3. `phpcbf`
   - requiere solo `phpcbf`
4. `phpmd`
   - requiere solo `phpmd`
5. `phpcompat`
   - requiere `phpcs`
   - requiere standard `PHPCompatibility`
6. `phpstan`
   - requiere `vendor/bin/phpstan`
   - asegura `phpstan.neon.dist` si falta

Beneficio:

1. cada acción falla solo por sus dependencias reales
2. se evita degradar casos válidos donde exista PHPStan pero no PHPMD, o viceversa

### Integración con la UX actual

Menú principal actual:

1. `cancel`
2. `phpcs`
3. `phpcbf`
4. `phpmd`
5. `phpcompat`
6. `phpstan`
7. `test PR`

Menú por path actual:

1. `cancel`
2. `phpcs`
3. `phpcbf`
4. `phpmd`
5. `phpcompat`
6. `phpstan`
7. `test PR`

Reglas importantes:

1. `pr` abre un menú de scope con `cancel`, `custom path`, `default` y vendors de `app/code` / `app/design`
2. `--pr` conserva la ejecución directa sobre el default del proyecto
3. `pr` e `integrity` ya incorporan `phpcompat` dentro de su scope correspondiente
4. `pr` e `integrity` no incorporan `phpstan` implícitamente en esta etapa

Motivo:

1. `pr` mantiene una semántica concreta y acotada
2. `phpcompat` agrega cobertura útil de compatibilidad sin cambiar demasiado el costo del flujo
3. `phpstan` sigue siendo una pasada más pesada y conviene mantenerla explícita

### Resolución de versión PHP para `phpcompat`

Orden recomendado:

1. si el contenedor PHP está disponible, leer la versión real del runtime desde el contenedor
2. si no puede resolverse la versión real, usar `PHP_VERSION` desde `.env`
3. normalizar siempre a `major.minor`

Esto permite:

1. máxima precisión cuando el runtime real está disponible
2. comportamiento predecible cuando la metadata del proyecto y el runtime no coinciden exactamente
3. un fallback razonable sin romper el comando por una sola fuente de verdad ausente

`warp php --version` expone esta misma versión real de runtime como comando explícito de diagnóstico.

### Riesgos que se deben evitar

1. No volver `warp audit` dependiente siempre de PHPMD.
2. No sobrescribir `phpstan.neon.dist` si el proyecto ya lo define.
3. No hardcodear configuración de PHPStan en varias capas a la vez.
4. No mezclar `phpcompat` o `phpstan` dentro de `pr` sin un contrato nuevo explícito.
5. No ejecutar `phpcompat` ni `phpstan` fuera del contenedor dentro de `warp audit`.

Comportamiento de `--path`:

1. `warp audit --path <ruta>` no vuelve a mostrar menú de paths
2. abre directamente el menú de herramientas sobre esa ruta
3. `phpcs`, `phpcbf`, `phpmd`, `phpcompat` y `phpstan` usan la ruta seleccionada
4. `test PR` sobre `--path` ejecuta los checks PR solo sobre esa ruta

Subcomandos directos expuestos actualmente:

1. `warp audit phpcs --path <ruta>`
2. `warp audit phpcbf --path <ruta>`
3. `warp audit phpmd --path <ruta>`
4. `warp audit phpcompat --path <ruta>`
5. `warp audit risky --path <ruta>`
6. `warp audit phpstan`
7. `warp audit phpstan --path <ruta>`
8. `warp audit phpstan --level <n>`
9. `warp audit phpstan --level <n> --path <ruta>`

### Resultado esperado

Con esta extensión, `warp audit` gana tres chequeos nuevos de valor real:

1. `phpcompat` para compatibilidad de versión de PHP
2. `phpstan` para análisis estático y bugs probables

sin modificar el alcance actual de `pr`, sin sobrescribir configuración del proyecto y manteniendo el mismo modelo de ejecución dentro del contenedor PHP.
