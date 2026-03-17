# Warp Sanitize (service/engine/mode)

Fecha: 2026-03-17
Estado: analisis para ejecucion

## 1) Decision asumida

Se avanza con un retrabajo de arquitectura de comandos y configuracion basado en:

1. `service`: capacidad funcional estable (`db`, `cache`, `search`, `queue`).
2. `engine`: tecnologia concreta (`mysql|mariadb`, `redis|valkey`, `elasticsearch|opensearch`, etc.).
3. `mode`: ubicacion/operacion (`local|external`).

Objetivo: separar semantica funcional de implementacion tecnica para reducir deuda de naming y facilitar engines futuros.

## 2) Principios de implementacion

1. Cero breaking changes en fase inicial.
2. Mantener comandos legacy (`warp mysql`, `warp redis`, `warp elasticsearch`) funcionando.
3. Introducir comandos capability-first (`warp db`, `warp cache`, `warp search`) como nueva capa canonica.
4. Resolver comportamiento por helper comun (`fallback + config + deteccion + validacion`).
5. Migracion progresiva con warnings y observabilidad.

## 3) Modelo de configuracion objetivo

## 3.1 Variables canonicas nuevas

1. `DB_MODE`, `DB_ENGINE`
2. `CACHE_MODE`, `CACHE_ENGINE`
3. `SEARCH_MODE`, `SEARCH_ENGINE`

Variables de conexion por capability:

1. DB: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`
2. CACHE: `CACHE_HOST`, `CACHE_PORT`, `CACHE_PASSWORD`
3. SEARCH: `SEARCH_SCHEME`, `SEARCH_HOST`, `SEARCH_PORT`, `SEARCH_USER`, `SEARCH_PASSWORD`

## 3.2 Compatibilidad backward

Durante migracion:

1. DB acepta lectura/escritura espejo con `DATABASE_*`, `MYSQL_VERSION`, `MYSQL_DOCKER_IMAGE`.
2. CACHE acepta coexistencia con `REDIS_*` actual.
3. SEARCH acepta coexistencia con `ES_*` actual.
4. Si faltan variables nuevas, autopoblado por deteccion desde variables legacy y compose.

## 4) Superficie de comandos objetivo

## 4.1 Comandos canonicos nuevos

1. `warp db ...`
2. `warp cache ...`
3. `warp search ...`

## 4.2 Alias y compatibilidad

1. `warp mysql` -> `warp db --engine mysql|mariadb` (resolver por contexto)
2. `warp redis` y `warp valkey` -> `warp cache`
3. `warp elasticsearch` y `warp opensearch` -> `warp search`

Regla: no remover comandos legacy en la primera etapa.

## 5) Plan de accion (ejecutable)

## Fase 0: Inventario y contrato

1. inventariar comandos y funciones acopladas a naming legacy (`mysql`, `redis-*`, `elasticsearch`).
2. definir contrato de helper comun (`lib/fallback.sh` + `lib/service_context.sh`).
3. definir tabla de mapeo `legacy <-> canonico` por variable y comando.

Entregables:

1. matriz de mapeo en `features/warp-sanitize.md`.
2. firmas finales de funciones helper.

## Fase 1: Capa de contexto comun

1. crear resolver de contexto por capability:
   - `warp_service_context_load <capability>`
   - salida: `CAP_MODE`, `CAP_ENGINE`, `CAP_IS_LOCAL_SERVICE_PRESENT`, `CAP_CONN_*`.
2. agregar autopoblado no destructivo:
   - si variable canonica falta, inferir desde legacy y persistir.
3. mantener flujo actual de prompts donde ya existe (ejemplo DB externo).

Entregables:

1. nueva libreria incluida en `.warp/includes.sh`.
2. smoke de comandos help sin regresion.

## Fase 2: Routing de comandos

1. agregar dispatch en `warp.sh` para `db|cache|search`.
2. convertir handlers legacy en wrappers finos hacia handlers canonicos.
3. agregar alias de engines (`valkey`, `opensearch`) sin duplicar implementacion.

Entregables:

1. dispatch backward compatible.
2. help actualizado con comandos nuevos + legacy.

## Fase 3: Adaptacion operativa por capability

1. DB:
   - consolidar logica RDS/external en handler canonico.
2. CACHE:
   - unificar `redis-cache|redis-session|redis-fpc` bajo contexto capability + reglas legacy.
   - externo con endpoint unico.
3. SEARCH:
   - adaptar operaciones que asumen contenedor local (`flush`, snapshot, metrics) con guardas por mode/engine.

Entregables:

1. comandos funcionales en local y external para cada capability.
2. warnings claros cuando una operacion no aplica a external.

## Fase 4: Endurecimiento y deprecacion gradual

1. agregar warnings deprecacion en comandos legacy (sin romper).
2. documentar fecha/version objetivo de deprecacion real.
3. validar update/self-update para no pisar configuraciones custom.

Entregables:

1. checklist de compatibilidad en `features/`.
2. notas de release con matriz de impacto.

## 6) Pros

1. Modelo mental estable para operadores y devs (`service` no cambia aunque cambie engine).
2. Menos deuda de naming historico en codigo y docs.
3. Escalabilidad para engines futuros sin crear comandos nuevos.
4. Menos duplicacion de pre-check/fallback por comando.
5. Mejor soporte de topologias mixtas (local + external).

## 7) Contras y costos

1. Alto costo inicial de refactor en scripts Bash legacy.
2. Riesgo de regresion en paths poco usados (flush/snapshot/switch).
3. Complejidad temporal por coexistencia de variables legacy y canonicas.
4. Mayor superficie de testing por alias, wrappers y modos.
5. Posible confusion inicial del equipo hasta estabilizar mensajes/help.

## 8) Riesgos tecnicos esperados

1. Acoples ocultos a `elasticsearch` en `deploy`, `memory`, `fix` y docs.
2. Acoples a nombres de servicio Docker (`redis-cache`, `elasticsearch`, `mysql`) en comandos `exec`.
3. Ambiguedad entre puertos internos de contenedor y puertos externos en modo `external`.
4. Operaciones destructivas en modo externo (flush/drop/switch) sin gate robusto.
5. Drift entre `.env` y `.env.sample` durante migracion.

## 9) Mitigaciones propuestas

1. Introducir feature-flag temporal (ej. `WARP_SANITIZE_V2=1`) para rollout progresivo.
2. Centralizar guardas destructivas en helper comun de confirmacion.
3. Mantener trazas de resolucion de contexto en modo verbose (`--debug-context`).
4. Ejecutar validacion minima AGENTS + smoke por capability afectada.
5. Agregar pruebas de regresion de ayuda/dispatch en CI (si aplica).

## 10) Preguntas y estado

1. Canonico DB: `db` (resuelto).
2. Variables nuevas/legacy: read-compat legacy + write canonico (resuelto).
3. `cache` local/external: mantener `cache|session|fpc` local y agregar scope `remote` para external (resuelto).
4. `cache flush` / `search flush` external: bloqueo con confirmacion explicita `y|Y`, sin `--force` (resuelto).
5. Politica de deprecacion: por version fechada `yyyy.mm.dd` (resuelto).
6. `warp info`: prioridad canonica (resuelto).
7. `warp init`: generar canonicas + legacy en transicion (resuelto).
8. Alias: comandos y subcomandos; help orientado a canonico (resuelto).

## 11) Checklist de validacion minima por fase

Basado en AGENTS.md:

1. `./warp --help`
2. `./warp init --help`
3. `./warp start --help`
4. `./warp stop --help`
5. `./warp info --help`

Adicional por feature:

1. `./warp mysql --help`, `./warp db --help`
2. `./warp redis --help`, `./warp valkey --help`, `./warp cache --help`
3. `./warp elasticsearch --help`, `./warp opensearch --help`, `./warp search --help`

## 12) Recomendacion de siguiente paso

Primero cerrar la matriz de mapeo exacta de variables legacy/canonicas y las firmas definitivas del helper.
Sin ese contrato, la implementacion puede divergir rapido entre comandos.

## 13) Decisiones cerradas (2026-03-17)

## 13.1 Estrategia general

1. migrar a comandos canonicos y files canonicos como objetivo principal:
   - `db`, `cache`, `search`.
2. mantener alias de compatibilidad para comandos y subcomandos legacy.
3. help y ejemplos orientados a canonico; alias solo para no romper flujo diario.

## 13.2 Plan por etapas pequenas

1. Etapa A: fallback comun + contexto (`service/engine/mode`).
2. Etapa B: migracion global `mysql -> db` (manteniendo alias `mysql`).
3. Etapa C: migracion global `redis -> cache` (manteniendo alias `redis` y `valkey`).
4. Etapa D: migracion global `elasticsearch -> search` (manteniendo alias `elasticsearch` y `opensearch`).

Nota: en esta etapa D la capability canonica es `search` (no `cache`).

## 13.3 Politica de variables

1. Read compatibility en fallback:
   - si variable canonica no existe, leer legacy.
2. Write canonico:
   - toda generacion/grabacion/autopoblado escribe variables nuevas.
3. `warp init` genera ambas (canonicas + legacy) durante transicion.
4. `warp info` muestra primero canonico.

## 13.4 Cache local vs external

1. mantener distincion local actual (`cache/session/fpc`).
2. agregar scope explicito para externo con endpoint unico.
3. nombre propuesto para scope externo: `remote`.
4. el resolver de contexto decide si opera en subservicios locales o endpoint remoto.

## 13.5 Politica de flush en external

1. `cache flush` y `search flush` en external no usan `--force`.
2. siempre requieren validacion interactiva con respuesta explicita `y` o `Y`.
3. `Enter` vacio no confirma.

## 13.6 Deprecacion y versionado

1. deprecacion en dos pasos.
2. paso 1: alias activo + warning suave en comandos legacy.
3. paso 2: retiro planificado con fecha/version definida en `features/legacy.md`.
4. definir retiro por version de release (formato `yyyy.mm.dd`) y no por cantidad de releases.

## 14) Matriz legacy -> canonico (Fase 0)

## 14.1 Comandos raiz

1. `warp mysql` -> `warp db`
2. `warp redis` -> `warp cache`
3. `warp valkey` -> `warp cache` (alias engine)
4. `warp elasticsearch` -> `warp search`
5. `warp opensearch` -> `warp search` (alias engine)

## 14.2 Subcomandos DB

1. `warp mysql info` -> `warp db info`
2. `warp mysql connect` -> `warp db connect`
3. `warp mysql dump <db>` -> `warp db dump <db>`
4. `warp mysql import <db>` -> `warp db import <db>`
5. `warp mysql ssh` -> `warp db ssh`
6. `warp mysql switch <ver>` -> `warp db switch <ver>`
7. `warp mysql tuner [opts]` -> `warp db tuner [opts]`
8. `warp mysql devdump` -> `warp db devdump`
9. `warp mysql devdump:<app>` -> `warp db devdump:<app>`
10. `warp mysql --update` -> `warp db --update`

## 14.3 Subcomandos CACHE

1. `warp redis info` -> `warp cache info`
2. `warp redis cli <cache|session|fpc>` -> `warp cache cli <cache|session|fpc>`
3. `warp redis monitor <cache|session|fpc>` -> `warp cache monitor <cache|session|fpc>`
4. `warp redis ssh <cache|session|fpc> [--root|--redis]` -> `warp cache ssh <cache|session|fpc> [--root|--cache]`
5. `warp redis flush <cache|session|fpc|--all>` -> `warp cache flush <cache|session|fpc|--all>`
6. `warp valkey ...` -> mismo routing que `warp cache ...`

## 14.4 Subcomandos SEARCH

1. `warp elasticsearch info` -> `warp search info`
2. `warp elasticsearch ssh [--root|--elasticsearch]` -> `warp search ssh [--root|--search]`
3. `warp elasticsearch flush` -> `warp search flush`
4. `warp elasticsearch switch <ver>` -> `warp search switch <ver>`
5. `warp opensearch ...` -> mismo routing que `warp search ...`

## 14.5 Variables DB

1. Canonicas nuevas: `DB_MODE`, `DB_ENGINE`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`.
2. Legacy leidas en compat: `MYSQL_VERSION`, `MYSQL_DOCKER_IMAGE`, `DATABASE_HOST`, `DATABASE_BINDED_PORT`, `DATABASE_NAME`, `DATABASE_USER`, `DATABASE_PASSWORD`, `DATABASE_ROOT_PASSWORD`, `MYSQL_CONFIG_FILE`.
3. Regla: `MYSQL_VERSION=rds` => `DB_MODE=external`.
4. Regla: `MYSQL_DOCKER_IMAGE` mariadb => `DB_ENGINE=mariadb`; caso contrario `mysql`.
5. Regla: `DATABASE_*` -> `DB_*` equivalente.

## 14.6 Variables CACHE

1. Canonicas nuevas: `CACHE_MODE`, `CACHE_ENGINE`, `CACHE_SCOPE`, `CACHE_HOST`, `CACHE_PORT`, `CACHE_PASSWORD`.
2. Legacy leidas en compat (local): `REDIS_CACHE_VERSION`, `REDIS_SESSION_VERSION`, `REDIS_FPC_VERSION`.
3. Legacy leidas en compat (local): `REDIS_CACHE_CONF`, `REDIS_SESSION_CONF`, `REDIS_FPC_CONF`.
4. Legacy leidas en compat (local): `REDIS_CACHE_BINDED_PORT`, `REDIS_SESSION_BINDED_PORT`, `REDIS_FPC_BINDED_PORT`.
5. Regla: presencia de `REDIS_*_VERSION` => `CACHE_MODE=local`.
6. Regla: `CACHE_SCOPE=cache|session|fpc` para local; `CACHE_SCOPE=remote` para external.
7. Regla: engine detectado por imagen/configuracion: `redis` default, `valkey` si aplica.

## 14.7 Variables SEARCH

1. Canonicas nuevas: `SEARCH_MODE`, `SEARCH_ENGINE`, `SEARCH_SCHEME`, `SEARCH_HOST`, `SEARCH_PORT`, `SEARCH_USER`, `SEARCH_PASSWORD`.
2. Legacy leidas en compat: `ES_VERSION`, `ES_MEMORY` (y host/puerto detectados por compose cuando local).
3. Regla: presencia de servicio `elasticsearch|opensearch` en compose => `SEARCH_MODE=local`.
4. Regla: `SEARCH_ENGINE=opensearch` cuando imagen local es `opensearchproject/opensearch`; si no, `elasticsearch`.
5. Regla: para external, conexion solo por variables `SEARCH_*`.

## 15) Contrato tecnico helper (listo para Etapa A)

## 15.1 Librerias objetivo

1. `.warp/lib/fallback.sh`
2. `.warp/lib/service_context.sh`

## 15.2 API de contexto

1. `warp_service_context_load <capability>`
2. input valido: `db|cache|search`
3. output por variables exportadas:
4. `WARP_CTX_CAPABILITY`
5. `WARP_CTX_MODE` (`local|external|unknown`)
6. `WARP_CTX_ENGINE` (`mysql|mariadb|redis|valkey|elasticsearch|opensearch|unknown`)
7. `WARP_CTX_LOCAL_SERVICE_PRESENT` (`true|false`)
8. `WARP_CTX_SCOPE` (`cache|session|fpc|remote|none`)
9. `WARP_CTX_HOST`, `WARP_CTX_PORT`, `WARP_CTX_USER`, `WARP_CTX_PASSWORD`, `WARP_CTX_DBNAME`, `WARP_CTX_SCHEME`
10. return code `0` ok; `1` capability invalida; `2` contexto insuficiente.

## 15.3 API de fallback/config

1. `warp_fallback_env_get <KEY>`
2. `warp_fallback_env_set <KEY> <VALUE>`
3. `warp_fallback_env_has <KEY>`
4. `warp_fallback_compose_has_service <service>`
5. `warp_fallback_autopopulate_mode_engine <capability>`
6. `warp_fallback_require_vars <capability> <var...>`
7. `warp_fallback_bootstrap_if_needed <capability>`
8. `warp_fallback_require_running_or_external <capability>`

## 15.4 Reglas de retorno estandar

1. `0`: exito
2. `10`: variable requerida faltante
3. `11`: compose no disponible/no parseable
4. `12`: modo no resuelto (`local|external`)
5. `13`: engine no resuelto
6. `14`: servicio local requerido no corriendo
7. `15`: operacion bloqueada por politica de seguridad (ej. flush external sin confirmacion `y|Y`)

## 15.5 Politica de prompts

1. el helper pregunta solo cuando no puede inferir de forma segura.
2. para acciones destructivas en external, confirmacion estricta `y|Y`.
3. respuesta vacia o distinta de `y|Y` equivale a cancelar.
4. no se admite bypass por `--force` para `cache flush` y `search flush` en external.

## 15.6 Politica de persistencia

1. lectura: primero canonico, luego legacy.
2. escritura: solo canonico.
3. excepcion transitoria: `warp init` escribe canonico y legacy.
4. `features/legacy.md` define cuando retirar la excepcion.

## 16) Etapa A-setup (inventario minimo)

Archivos de setup a incluir en la migracion de variables:

1. `.warp/setup/mysql/tpl/database.env`
2. `.warp/setup/redis/tpl/redis.env`
3. `.warp/setup/elasticsearch/tpl/elasticsearch.env`
4. `.warp/setup/*/*.sh` que escriben variables (`echo \"VAR=...\" >> .env.sample`)

Objetivo A-setup:

1. mantener generacion legacy actual,
2. agregar generacion canonica en paralelo (`DB_*`, `CACHE_*`, `SEARCH_*`),
3. evitar drift entre runtime y `warp init`.

## 17) Estado de avance (Etapa A)

Implementado:

1. librerias base: `.warp/lib/fallback.sh`, `.warp/lib/service_context.sh`.
2. inclusion en runtime: `.warp/includes.sh`.
3. dual-write en setup principal:
   - `.warp/setup/mysql/database.sh`
   - `.warp/setup/redis/redis.sh`
   - `.warp/setup/elasticsearch/elasticsearch.sh`
4. dual-write en setup alterno:
   - `.warp/setup/init/gandalf.sh`
   - `.warp/setup/sandbox/sandbox-m2.sh`
5. defaults canonicos en templates:
   - `.warp/setup/mysql/tpl/database.env`
   - `.warp/setup/redis/tpl/redis.env`
   - `.warp/setup/elasticsearch/tpl/elasticsearch.env`

Validacion ejecutada:

1. `bash -n` en archivos modificados: OK.
2. smoke help:
   - `./warp --help`: 0
   - `./warp init --help`: 0
   - `./warp start --help`: 1 (imprime help, comportamiento actual)
   - `./warp stop --help`: 1 (imprime help, comportamiento actual)
   - `./warp info --help`: 0
