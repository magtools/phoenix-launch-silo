Feature: warp profiler
Fecha: 2026-04-18

Resumen
-------
Proveer un comando `warp profiler` para mostrar estado y activar/desactivar el profiler PHP (nativo/HTML/CSV) y el logging/profiling de DB. Inspirado en features/mysql-devdump.md y ../eprivee/var/profiling.md. Objetivo: habilitar diagnósticos controlados sin riesgo de llenar disco ni dejar profiling activo en producción.

Motivación
----------
- Facilitar encendido/apagado seguro y reproducible de herramientas de profiling.
- Evitar modificaciones manuales en env.php o creación accidental de grandes logs.
- Unificar UX: `warp profiler status|php|db --enable|--disable`.

Alcance
-------
Incluye:
- php profiler (html / csv) toggle via var/profiler.flag semantics ya presentes.
- db logger/profiler toggle modificando de forma segura la sección `db_logger` y la clave `profiler` en app/etc/env.php.
- Limpieza / truncado opcional de logs tras deshabilitar.

Nota: El profiler de PHP y el de DB deben poder activarse/desactivarse de forma independiente (comandos separados y flags independientes).

No incluye:
- Cambios intrusivos en bootstrap.php ni reescritura de app code. (Evitar si posible.)

User stories
------------
- Como dev, quiero ver si el profiler PHP o DB está activo: `warp profiler status`.
- Como dev, quiero activar el profiler HTML para medir una request: `warp profiler php --enable html`.
- Como dev, quiero activar el profiler CSV para una única request: `warp profiler php --enable csv`.
- Como dev, quiero habilitar el DB logger en modo controlado (umbral 50ms, sin stacktrace): `warp profiler db --enable controlled`.
- Como dev, quiero deshabilitar rápidamente todas las trazas: `warp profiler --disable --all`.

CLI (propuesta)
---------------
- warp profiler status
- warp profiler php --enable [html|csv]  # csv escribirá var/log/profiler.csv; html usará var/profiler.flag = "html"
- warp profiler php --disable            # borra var/profiler.flag y/o lo trunca
- warp profiler db --enable [controlled|full]
- warp profiler db --disable
- warp profiler logs --truncate [db|profiler|all]
- Opciones globales: --no-cache-clean (no ejecutar cache:clean), --force (permite aplicar cambios en production y truncados no interactivos)

Implementación: opciones y riesgos
----------------------------------
1) PHP profiler (file-toggle)
   - Usa el comportamiento existente: var/profiler.flag
   - Implementación: crear/overwrite var/profiler.flag con los contenidos adecuados ("html" o JSON para CSV).
   - Comportamiento seguro: para Magento, la edición/activación automática se realiza sin preguntas sólo si el proyecto está en modo developer. En production la acción requiere `--force` para aplicar cualquier cambio.
   - Ventaja: no tocar app/etc/env.php, reversible, idempotente.
   - Riesgo: si el proyecto no respeta var/profiler.flag, documentar precondición.

2) DB logger / profiler (edición segura de env.php)
   - Política: edición automática de app/etc/env.php queda permitida únicamente cuando se detecta Magento y el proyecto está en modo developer; en production el comando requiere `--force`.
   - Método recomendado: editar `env.php` como texto con backup previo.
     - Si existe el bloque `db_logger`, reemplazarlo completo.
     - Si no existe, agregarlo antes del cierre final `];` del array principal.
     - Para Smile DebugToolbar, sólo editar `enabled => false` si ya existe un bloque `profiler` con `Smile\\DebugToolbar\\DB\\Profiler`.
   - No depender de PHP CLI para inspeccionar o reescribir `app/etc/env.php`.
   - Respaldo: crear un único backup `app/etc/env.php.warp-profiler-backup` antes de escribir, sobrescribiéndolo en cada ejecución.
   - `app/etc/env.php` no debe reemplazarse por otro archivo temporal; debe mantenerse y editarse/sobrescribirse en sitio para conservar ownership/permisos.
   - Post-cambio (por defecto): ejecutar `./warp magento cache:clean config` salvo que se pase `--no-cache-clean`.
   - No ejecutar `./warp magento app:config:import` como parte de este comando.
   - Fallback: si env.php tiene formato no estándar o la edición falla, abortar y mostrar pasos manuales para aplicar el cambio.

3) Truncado y prevención de disco lleno
   - Al desactivar, truncar los logs asociados para evitar consumo de disco y dejar la próxima medición desde cero.
   - `status` debe mostrar tamaños actuales de logs relevantes.
   - Para truncado manual con `logs --truncate`, requerir `--force` cuando no haya terminal interactiva.

4) Extensibilidad y conectores
   - Estructura de extensibilidad (similar a mysql devdump profiles):
     - Directorio: `/.warp/bin/profiler/connectors/`
     - Cada conector: `/<app>.sh` exporta funciones estándar:
       - `profiler_connector_status`
       - `profiler_connector_php_enable <html|csv>`
       - `profiler_connector_php_disable`
       - `profiler_connector_db_enable <controlled|full>`
       - `profiler_connector_db_disable`
       - `profiler_connector_logs_truncate <db|profiler|all>`
       - `profiler_connector_help`
     - Detección y selección de conector:
       - Si existe un único conector, se usará por defecto.
       - Si hay varios conectores, `warp profiler` preguntará cuál usar y podrá guardar la preferencia en `.env` como `WARP_PROFILER_CONNECTOR=<app>` para no preguntar de nuevo.
       - Detección heurística adicional: existencia de `app/etc/env.php`, `app/bootstrap.php`, `wp-config.php` o composer metadata para sugerir el conector adecuado.
     - Si no hay conector, usar modo genérico (php profiler via var/profiler.flag + logs truncation operations).
   - Primer conector: `magento` — implementará automáticamente las reglas descritas (edición de env.php en dev-mode + cache clean config). Para proyectos Magento en modo production, el conector imprimirá los pasos y requerirá `--force`.
   - Independencia: los conectores deberán soportar activación/desactivación independientes para PHP y DB (dos operaciones separadas) y reflejar estado por separado en `warp profiler status`.
   - En el MVP no se implementa override por contenedor para profiler.

5) Container override
   - No se implementa en el MVP. La mayoría de operaciones son sobre archivos del repo.
   - El conector puede invocar `warp magento cache:clean config` resolviendo el entrypoint local en este orden: `./warp`, `./warp.sh`, `warp`.

Decisiones acordadas (aplicar ahora)
-----------------------------------
- Permitir edición automática de `app/etc/env.php` sólo para Magento en modo developer.
- Ejecutar por defecto `./warp magento cache:clean config` tras editar env.php (salvo `--no-cache-clean`).
- No ejecutar `./warp magento app:config:import`.
- Umbral por defecto para "controlled" DB logger: 0.05s.
- Iniciar con conector `magento`; comportamiento en production: mostrar pasos y requerir `--force` para aplicar cambios.
- `db --disable` apaga también `connection/default/profiler/enabled` cuando existe, pero `db --enable` no enciende Smile DebugToolbar.
- `php --disable`, `db --disable` y `--disable --all` truncan logs asociados.

Preguntas / dudas pendientes
---------------------------
- Ninguna para el MVP.


Plan de acción (tareas)
-----------------------
1. Especificación mínima y archivos de ayuda (RFC) — este documento. (DONE)
2. Implementar script de toggles:
   - Crear `.warp/bin/profiler.sh` + help `.warp/bin/profiler_help.sh` + conector `.warp/bin/profiler/connectors/magento.sh`.
   - Subtareas:
     a) Funciones: status_php(), enable_php(mode), disable_php(), status_db(), enable_db(mode), disable_db(), truncate_logs(target).
     b) Helpers: backup_envphp(), write_envphp_text()
3. Incluir en `.warp/includes.sh` y dispatch en warp.sh.
4. Tests manuales mínimos:
   - `./warp --help`
   - `./warp profiler status`
   - `./warp profiler php --enable html` -> verify var/profiler.flag
   - `./warp profiler php --disable` -> verify flag removed
   - `./warp profiler db --enable controlled` -> verify env.php backup + changed values + cache clean
   - `./warp profiler db --disable` -> verify disabled values + Smile profiler disabled + logs truncated
5. Documentar en features/ (este archivo) y actualizar README snippets.
6. Release notes: mencionar flag and safety backups.

Criterios de aceptación
-----------------------
- `warp profiler status` devuelve estado correcto para PHP and DB.
- Enabling PHP profiler creates correct var/profiler.flag and does not change env.php.
- Enabling DB profiler overwrites the single profiler backup and updates app/etc/env.php in place; cache cleaned unless --no-cache-clean.
- Disable restores recommended settings and truncates associated logs.
- Production env.php writes require `--force`.

Preguntas / dudas para discutir
------------------------------
- Cerradas para el MVP.

Siguientes pasos propuestos
--------------------------
- Confirm respuestas a las preguntas anteriores.
- Implementar `.warp/bin/profiler.sh` y help, luego pruebas locales.

Notas
-----
- La implementación propuesta intenta ser lo menos intrusiva posible: usar var/profiler.flag para PHP y editar env.php con backups para DB.
- Evitar hacer cambios en bootstrap.php o incluir nuevos puntos de activación sin revisión extensa.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
