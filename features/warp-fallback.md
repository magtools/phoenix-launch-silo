# Warp Fallback (propuesta de estandarizacion)

Fecha: 2026-03-17
Estado: runtime fallback en progreso (incluye modo host sin compose para comandos seleccionados)

## 1) Contexto operativo

Distribucion esperada de proyectos productivos:

1. 50% `full warp` (todos los servicios en Docker)
2. 40% `warp + rds`
3. 5% `warp + rds + redis/elastic externos`
4. 5% `warp presente`, pero infraestructura 100% externa (AWS)

Conclusión: Warp esta en el 100% de los proyectos, aunque algunos comandos deban operar sin contenedores para ciertos servicios.

## 2) Estado actual del codigo (post-sanitize)

## 2.1 MySQL

`warp db` (alias `warp mysql`) ya tiene pre-check/fallback externo para RDS:

1. detecta si falta servicio `mysql` en compose,
2. pregunta confirmacion de modo externo,
3. intenta bootstrap desde `app/etc/env.php`,
4. persiste en `.env` (`MYSQL_VERSION=rds`, host/port/user/pass/db),
5. usa cliente local (`mysql|mariadb|mysqldump|mariadb-dump`) cuando aplica.

Esto esta implementado en `.warp/bin/mysql.sh` (ruteado por `db_main`) y cubre `connect`, `dump`, `import`, `devdump`.

## 2.2 Redis

`warp cache` (alias `warp redis`/`warp valkey`) hoy depende de:

1. servicio inicializado (via variables en `.env`),
2. contenedores corriendo (`warp_check_is_running`),
3. `docker-compose exec redis-* ...`.

No existe fallback estandar a Redis/Valkey externo.

## 2.3 Elasticsearch

`warp search` (alias `warp elasticsearch`/`warp opensearch`) hoy depende de:

1. servicio en compose (`elasticsearch`),
2. contenedores corriendo,
3. accesos via `docker-compose exec` y `localhost:<puerto mapeado>`.

No existe fallback estandar a OpenSearch/Elasticsearch externo.

Nota: el naming canónico ya migro a `search`, pero la logica operativa sigue en backend local (`.warp/bin/elasticsearch.sh`), sin fallback external aplicado todavia.

## 2.4 PHP/Magento/Telemetry en modo host

Estado actual:

1. si `docker-compose-warp.yml` no existe, `warp` ya no fuerza precheck global de `docker`/`docker-compose` para comandos compatibles con fallback (`db|cache|search|php|magento|telemetry|info`),
2. `warp magento` y `warp ece-tools|ece-patches` ejecutan en host usando `php` local cuando falta compose,
3. `warp telemetry` puede correr en modo host y reportar recursos del host aunque no haya contenedores,
4. `warp php ssh` queda limitado a modo docker (sin compose informa error claro).

Flag de control:

1. `WARP_RUNTIME_MODE=auto|docker|host` (en `.env`),
2. `auto` usa deteccion por presencia de compose y capacidad de fallback del comando,
3. si falta compose y el contexto es ambiguo, comandos con fallback pueden preguntar y persistir modo en `.env`.

## 3) Problema a resolver

Hoy cada comando resuelve pre-checks de forma aislada.

Esto genera riesgo de:

1. logica duplicada,
2. criterios distintos entre comandos,
3. dificultad para extender el patron a Redis/Valkey y Elastic/OpenSearch.

## 4) Objetivo de diseno

Definir una capa comun de fallback que:

1. mantenga UX y forma de trabajo actual de `warp`,
2. no rompa proyectos `full warp`,
3. habilite modo externo por servicio con convencion unica,
4. permita que cada comando consuma helper compartido en lugar de reinventar pre-check.
5. use comandos canonicos `warp db|cache|search` con alias de compatibilidad.

## 5) Propuesta tecnica (helper comun)

La base ya existe en `.warp/lib/fallback.sh` y `.warp/lib/service_context.sh`:

1. `warp_fallback_compose_has_service <service>`
   - chequea servicio en compose (canonico).
2. `warp_fallback_autopopulate_mode_engine <capability>`
   - intenta autocompletar `*_MODE` y `*_ENGINE` si faltan o estan vacios.
3. `warp_service_context_load <capability>`
   - resuelve contexto operativo (`mode`, `engine`, host/puerto/scope) para `db|cache|search`.
4. `warp_fallback_bootstrap_if_needed <service>`
   - si falta servicio local, ofrece activar modo externo con prompt estandar.
5. `warp_fallback_require_running_or_external <service>`
   - gate comun para comandos operativos.
6. `warp_fallback_env_set <KEY> <VALUE>`
   - escritura segura y uniforme de `.env`.
7. `warp_fallback_env_get <KEY>`
   - lectura estandarizada de variables (wrapper de `warp_env_read_var`).
8. `warp_fallback_require_vars <service> <var1> <var2> ...`
   - valida lista de variables requeridas y resuelve prompts/autopoblado cuando corresponda.

Estado: helper implementado y runtime ya integrado en comandos canonicos `cache`/`search` (pendientes mejoras puntuales).

## 6) Contrato de configuracion propuesto

La estandarizacion se apoya en `SERVICE_MODE/SERVICE_ENGINE` por servicio, sin romper variables existentes.

## 6.1 DB (migracion compatible)

1. canonico: `DB_MODE=local|external`
2. canonico: `DB_ENGINE=mysql|mariadb`
3. compatibilidad legacy: `MYSQL_VERSION=rds` sigue vigente como señal de externo.
4. fallback: si `DB_MODE` o `DB_ENGINE` faltan, se autopueblan por deteccion actual:
   - externo/local por compose + `MYSQL_VERSION`,
   - engine por `MYSQL_DOCKER_IMAGE` y/o binarios disponibles.
5. mantiene read-compat con `DATABASE_*`/`MYSQL_*`.

## 6.2 Redis/Valkey (nuevo)

Canonico:

1. `CACHE_MODE=local|external`
2. `CACHE_ENGINE=redis|valkey`
3. `CACHE_SCOPE=cache|session|fpc|remote`

Conexion (scope inicial simple):

1. `CACHE_HOST`
2. `CACHE_PORT`
3. `CACHE_USER` (opcional, ACL)
4. `CACHE_PASSWORD` (opcional)

Decision actual: para externo usar un unico endpoint (`CACHE_HOST/CACHE_PORT/CACHE_PASSWORD`), no 3 endpoints.

## 6.3 Elastic/OpenSearch (nuevo)

Propuesta de bandera:

1. `SEARCH_MODE=local|external`
2. `SEARCH_ENGINE=elasticsearch|opensearch`

Conexion:

1. `SEARCH_HOST`
2. `SEARCH_PORT`
3. `SEARCH_SCHEME=http|https`
4. `SEARCH_USER` (opcional)
5. `SEARCH_PASSWORD` (opcional)

## 6.4 Alias de comandos (compatibilidad de naming)

1. se mantienen comandos oficiales:
   - `warp db`
   - `warp cache`
   - `warp search`
2. se agregan alias:
   - `warp mysql` -> `warp db`
   - `warp redis` / `warp valkey` -> `warp cache`
   - `warp elasticsearch` / `warp opensearch` -> `warp search`

## 7) Reglas de compatibilidad

1. Sin cambios en `warp init/start/stop` en fase 1.
2. Si el modo es `local`, todo sigue igual que hoy.
3. Si falta servicio local pero hay modo externo valido, no bloquear comando por `warp_check_is_running` para ese servicio.
4. Si un servicio no existe en `docker-compose-warp.yml`, `warp init/start/stop/restart` no debe fallar ni sugerir accion para agregarlo.
5. El acceso/operacion de ese servicio queda encapsulado en su comando canónico (`warp db|cache|search ...`) y su fallback.
6. Ausencia de `docker-compose-warp.yml` puede representar modo host: no debe bloquear comandos con fallback explícito.

## 8) Roadmap sugerido (iterativo y reversible)

## Fase A (base de arquitectura) - completada

1. extraer helper comun en `.warp/lib/fallback.sh` + `.warp/lib/service_context.sh`,
2. crear comandos canonicos `db|cache|search` con alias,
3. dual-write de variables canonicas en setup,
4. validar ayudas minimas:
   - `./warp --help`
   - `./warp db --help`
   - `./warp info --help`

## Fase B (fallback runtime cache) - en progreso

1. agregar modo externo en `warp cache` (`cli`, `flush`, `monitor`) usando `warp_service_context_load cache`,
2. mantener servicios `redis-cache|redis-session|redis-fpc` para modo local,
3. aplicar bloqueo de `flush` external con confirmacion explicita `y|Y` (sin `--force`).

Estado actual:

1. `cache.sh` enruta external/local por contexto.
2. `cache flush` external usa confirmacion explicita `y|Y`.
3. `cache ssh` external se bloquea con mensaje de uso alternativo.

## Fase C (fallback runtime search) - en progreso

1. introducir modo externo en `warp search` usando `warp_service_context_load search`,
2. compatibilizar naming y mensajes (`elasticsearch`/`opensearch`),
3. adaptar comandos que hoy asumen contenedor local (`flush`, metricas, snapshots) con guardas claras.

Estado actual:

1. `search.sh` enruta external/local por contexto.
2. `search flush` external usa confirmacion explicita `y|Y` y bloquea `--force`.
3. `search ssh` y `search switch` en external se bloquean por politica.

## 11) Checklist tecnica siguiente iteracion

1. `cache info` external: conectividad real (`PING`) y version de servidor ya implementadas.
2. `cache cli/monitor` external: soporte de `CACHE_USER`/`CACHE_PASSWORD` implementado (compatibilidad ACL basica).
3. `search info` external: health por `GET /` y `GET /_cluster/health` implementado.
4. `search flush` external: parseo HTTP/errores JSON robusto implementado (incluye `index_not_found_exception`).
5. mover gradualmente logica legacy de `redis.sh`/`elasticsearch.sh` al canónico para reducir duplicacion.
6. agregar smoke de runtime external controlado (fixtures `.env` con `CACHE_MODE=external` y `SEARCH_MODE=external`).

## 12) Apendice: Hallazgos y Propuestas

## 12.1 Hallazgo: bloqueo `--force` incompleto en flush external

Contexto:

1. hoy se evalua `--force` en posiciones fijas (`$1`/`$2`),
2. un orden alternativo de argumentos podria bypassar el bloqueo.

Propuesta 1:

1. iterar todos los argumentos (`for _arg in "$@"`) en `cache flush` y `search flush`,
2. si aparece `--force` en cualquier posicion: error y abortar.

## 12.2 Hallazgo: bug legacy en `redis_info` local

Contexto:

1. `REDIS_SESSION_VERSION` y `REDIS_FPC_VERSION` se leen desde `REDIS_CACHE_VERSION`,
2. el output de info puede mostrar datos incorrectos para session/fpc.

Propuesta 2:

1. corregir lecturas en `.warp/bin/redis.sh`:
   - `REDIS_SESSION_VERSION` <- `REDIS_SESSION_VERSION`
   - `REDIS_FPC_VERSION` <- `REDIS_FPC_VERSION`
2. aplicar mismo ajuste para `*_CONF` si corresponde.

## 12.3 Hallazgo: dependencia `curl` no validada en search external

Contexto:

1. fallback search external usa `curl`,
2. si falta binario, el mensaje de error no es explicito para el operador.

Propuesta 3:

1. agregar precheck `command -v curl` en ruta external de `search`,
2. si no existe, abortar con guia clara de instalacion por distro.

## 12.4 Hallazgo: `CACHE_USER` no reflejado en setup/templates

Contexto:

1. runtime soporta `CACHE_USER`,
2. setup dual-write actual no genera variable canonica `CACHE_USER`.

Propuesta 4:

1. agregar `CACHE_USER=` (vacio por default) en templates/setup donde se escriben `CACHE_*`,
2. documentar comportamiento ACL (cuando usar `CACHE_USER` + `CACHE_PASSWORD`).

## 12.5 Hallazgo: desalineacion residual en ayudas/mensajes

Contexto:

1. existen textos legacy en opciones/ayudas (ej. `--elasticsearch`),
2. aunque hay compatibilidad, puede confundir a usuarios nuevos.

Propuesta 5:

1. mantener aliases legacy funcionales,
2. pero en help principal priorizar naming canonico y marcar legacy como alias explicitamente,
3. unificar ejemplos a `warp db|cache|search`.

## 12.6 Hallazgo: falta smoke externo automatizable

Contexto:

1. se validaron ayudas y sintaxis,
2. no hay smoke reproducible para `MODE=external` sin infraestructura real.

Propuesta 6:

1. definir fixtures `.env` minimos para external (cache/search),
2. agregar smoke no destructivo:
   - `cache info` external (sin flush),
   - `search info` external (sin flush),
3. dejar `flush` external fuera de smoke automatico y probar manualmente con confirmacion.

Implementacion inicial:

1. fixture cache: `features/fixtures/fallback-cache-external.env.sample`
2. fixture search: `features/fixtures/fallback-search-external.env.sample`
3. smoke recomendado (manual, no destructivo):
   - exportar variables del fixture al `.env` de prueba,
   - ejecutar `./warp cache info`,
   - ejecutar `./warp search info`.

## 12.7 Plan de fallback `docker-compose` -> `docker compose`

Objetivo:

1. mantener compatibilidad de scripts legacy que invocan `docker-compose`,
2. permitir ejecucion en entornos modernos donde solo existe `docker compose` (plugin v2),
3. evitar depender de symlink global/manual en el host.

Diagnostico base (codigo actual):

1. `warp.sh` exige `hash docker-compose` en runtime docker,
2. hay llamadas directas a `docker-compose` distribuidas en comandos y libs,
3. `warp_check_docker_version` lee version via `docker-compose version --short`,
4. `deploy doctor` y otros checks validan solo binario legacy.

Decision de diseno:

1. preferir fallback interno en `warp`,
2. no requerir symlink global como solucion oficial,
3. mantener symlink/documentacion solo como workaround opcional para casos extremos.

### 12.7.1 Fases

Fase D1 (detector + shim reversible):

1. agregar resolucion de compose en bootstrap:
   - si existe `docker-compose`, usarlo,
   - si no existe, validar `docker compose version`,
   - si v2 esta disponible, exponer wrapper `docker-compose` local al proceso `warp`.
2. prioridad de ejecucion:
   - `docker-compose` real (si existe),
   - fallback wrapper hacia `docker compose`,
   - error claro si no existe ninguna opcion.
3. no modificar sistema operativo del usuario ni rutas globales.

Fase D2 (normalizacion de checks):

1. adaptar checks de arranque y doctor para aceptar cualquiera de los dos backends,
2. mantener mensajes claros indicando backend activo (`legacy` o `plugin v2`),
3. sanitizar parseo de version para v2 (p.ej. prefijo `v`).

Fase D3 (endurecimiento + mantenimiento):

1. centralizar helper de compose (single source of truth),
2. prohibir nuevas llamadas directas fuera del helper en cambios futuros,
3. documentar troubleshooting para diferencias v1/v2.

### 12.7.2 Criterios de seguridad

1. no usar `sudo`, no crear symlinks globales automaticamente,
2. no ejecutar acciones destructivas por habilitar fallback,
3. fallback solo cambia metodo de invocacion, no semantica de `init/start/stop`.

### 12.7.3 Validacion minima obligatoria

Con `docker-compose` legacy disponible:

1. `./warp --help`
2. `./warp init --help`
3. `./warp start --help`
4. `./warp stop --help`
5. `./warp info --help`

Con solo `docker compose` disponible (sin `docker-compose` en PATH):

1. `./warp --help`
2. `./warp init --help`
3. `./warp start --help`
4. `./warp stop --help`
5. `./warp info --help`
6. `./warp docker ps` (smoke del passthrough compose)

### 12.7.4 Riesgos y mitigaciones

Riesgo 1: divergencias menores de flags/salida entre v1 y v2.

1. mitigacion: smoke de comandos canonicos y ajuste puntual de parsing.

Riesgo 2: parseo de version no numerico en compose v2.

1. mitigacion: normalizar `version --short` antes de comparar minimos.

Riesgo 3: dependencia accidental de binario global del host.

1. mitigacion: wrapper local y deteccion en runtime por comando.

### 12.7.5 Baseline operativo compose

1. baseline legacy declarado: `docker-compose >= 1.29`,
2. backend moderno soportado: `docker compose` (plugin v2),
3. con este baseline se elimina `version:` de templates compose para evitar warning deprecado en v2.

## 9) Riesgos y decisiones acordadas

1. `flush` en servicios externos: advertencia explicita + confirmacion obligatoria.
2. Instalacion automatica de clientes locales: mantener opt-in con prompt (como MySQL).
3. Redis externo: una sola conexion global (endpoint unico).
4. Naming: mantener canonicos `db|cache|search` y alias de compatibilidad.

## 10) Criterio de exito para la feature fallback

1. un solo patron de pre-check para servicios stateful,
2. mismo flujo mental para operador y developer,
3. cero regresiones en proyectos `full warp`,
4. soporte explicito a combinaciones mixtas (Docker + externos),
5. extensible a nuevos servicios sin duplicar logica.
