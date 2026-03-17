# Warp Fallback (propuesta de estandarizacion)

Fecha: 2026-03-17
Estado: analisis / iteracion 1

## 1) Contexto operativo

Distribucion esperada de proyectos productivos:

1. 50% `full warp` (todos los servicios en Docker)
2. 40% `warp + rds`
3. 5% `warp + rds + redis/elastic externos`
4. 5% `warp presente`, pero infraestructura 100% externa (AWS)

Conclusión: Warp esta en el 100% de los proyectos, aunque algunos comandos deban operar sin contenedores para ciertos servicios.

## 2) Estado actual del codigo (baseline)

## 2.1 MySQL

`warp mysql` ya tiene pre-check/fallback externo para RDS:

1. detecta si falta servicio `mysql` en compose,
2. pregunta confirmacion de modo externo,
3. intenta bootstrap desde `app/etc/env.php`,
4. persiste en `.env` (`MYSQL_VERSION=rds`, host/port/user/pass/db),
5. usa cliente local (`mysql|mariadb|mysqldump|mariadb-dump`) cuando aplica.

Esto esta implementado en `.warp/bin/mysql.sh` y cubre `connect`, `dump`, `import`, `devdump`.

## 2.2 Redis

`warp redis` hoy depende de:

1. servicio inicializado (via variables en `.env`),
2. contenedores corriendo (`warp_check_is_running`),
3. `docker-compose exec redis-* ...`.

No existe fallback estandar a Redis/Valkey externo.

## 2.3 Elasticsearch

`warp elasticsearch` hoy depende de:

1. servicio en compose (`elasticsearch`),
2. contenedores corriendo,
3. accesos via `docker-compose exec` y `localhost:<puerto mapeado>`.

No existe fallback estandar a OpenSearch/Elasticsearch externo.

Nota: el setup actual ya usa imagen `opensearchproject/opensearch`, pero el comando y naming siguen centrados en `elasticsearch`.

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
5. mantenga los comandos actuales `warp redis` y `warp elasticsearch` (sin crear comandos nuevos).

## 5) Propuesta tecnica (helper comun)

Crear `.warp/lib/fallback.sh` con API minima:

1. `warp_fallback_service_mode <service>`
   - retorna `local|external|disabled|unknown` segun `.env` + compose.
2. `warp_fallback_compose_has_service <service>`
   - chequea servicio en compose (canonico).
3. `warp_fallback_bootstrap_if_needed <service>`
   - si falta servicio local, ofrece activar modo externo con prompt estandar.
4. `warp_fallback_require_running_or_external <service>`
   - gate comun para comandos operativos.
5. `warp_fallback_env_set <KEY> <VALUE>`
   - escritura segura y uniforme de `.env`.
6. `warp_fallback_env_get <KEY>`
   - lectura estandarizada de variables (wrapper de `warp_env_read_var`).
7. `warp_fallback_autopopulate_mode_engine <service>`
   - intenta autocompletar `*_MODE` y `*_ENGINE` si faltan o estan vacios, usando deteccion existente del servicio.
8. `warp_fallback_require_vars <service> <var1> <var2> ...`
   - valida lista de variables requeridas y resuelve prompts/autopoblado cuando corresponda.

Implementacion: el comando de servicio solo declara las variables a observar; el helper centraliza seteo, lectura, validacion y autopoblado.

## 6) Contrato de configuracion propuesto

La estandarizacion se apoya en `SERVICE_MODE/SERVICE_ENGINE` por servicio, sin romper variables existentes.

## 6.1 MySQL (migracion compatible)

1. nuevo: `MYSQL_MODE=local|external`
2. nuevo: `MYSQL_ENGINE=mysql|mariadb`
3. compatibilidad legacy: `MYSQL_VERSION=rds` sigue vigente como señal de externo.
4. fallback: si `MYSQL_MODE` o `MYSQL_ENGINE` faltan, se autopueblan por deteccion actual:
   - externo/local por compose + `MYSQL_VERSION`,
   - engine por `MYSQL_DOCKER_IMAGE` y/o binarios disponibles.
5. conserva `DATABASE_*` actual.

## 6.2 Redis/Valkey (nuevo)

Propuesta de bandera:

1. `REDIS_MODE=local|external`
2. `REDIS_ENGINE=redis|valkey`

Conexion (scope inicial simple):

1. `REDIS_HOST`
2. `REDIS_PORT`
3. `REDIS_PASSWORD` (opcional)

Decision actual: para externo usar un unico endpoint (`REDIS_HOST/REDIS_PORT/REDIS_PASSWORD`), no 3 endpoints.

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
   - `warp redis`
   - `warp elasticsearch`
2. se agregan alias:
   - `warp valkey` -> ejecuta flujo de `warp redis`
   - `warp opensearch` -> ejecuta flujo de `warp elasticsearch`
3. no se crean archivos de comando nuevos para alias; solo dispatch hacia los comandos existentes.

## 7) Reglas de compatibilidad

1. Sin cambios en `warp init/start/stop` en fase 1.
2. Si el modo es `local`, todo sigue igual que hoy.
3. Si falta servicio local pero hay modo externo valido, no bloquear comando por `warp_check_is_running` para ese servicio.
4. Si un servicio no existe en `docker-compose-warp.yml`, `warp init/start/stop/restart` no debe fallar ni sugerir accion para agregarlo.
5. El acceso/operacion de ese servicio queda encapsulado en su comando directo (`warp mysql|redis|elasticsearch ...`) y su fallback.

## 8) Roadmap sugerido (iterativo y reversible)

## Fase A (primera implementacion)

1. extraer helper comun en `.warp/lib/fallback.sh`,
2. adaptar MySQL para usar helper sin cambiar UX,
3. validar ayudas minimas:
   - `./warp --help`
   - `./warp mysql --help`
   - `./warp info --help`

## Fase B (Redis/Valkey)

1. agregar modo externo en `warp redis` (`cli`, `flush`, `monitor` con alcance definido),
2. mantener servicios `redis-cache|redis-session|redis-fpc` para modo local,
3. resolver naming engine (`redis` vs `valkey`) en mensajes/clientes,
4. agregar alias `warp valkey` al mismo comando.

## Fase C (Elastic/OpenSearch)

1. introducir modo externo en `warp elasticsearch`,
2. compatibilizar naming y mensajes (`elasticsearch`/`opensearch`),
3. adaptar comandos que hoy asumen contenedor local (`flush`, metricas, snapshots) con guardas claras,
4. agregar alias `warp opensearch` al mismo comando.

## 9) Riesgos y decisiones acordadas

1. `flush` en servicios externos: advertencia explicita + confirmacion obligatoria.
2. Instalacion automatica de clientes locales: mantener opt-in con prompt (como MySQL).
3. Redis externo: una sola conexion global (endpoint unico).
4. Naming: mantener `warp redis`/`warp elasticsearch` y sumar alias `valkey`/`opensearch`.

## 10) Criterio de exito para la feature fallback

1. un solo patron de pre-check para servicios stateful,
2. mismo flujo mental para operador y developer,
3. cero regresiones en proyectos `full warp`,
4. soporte explicito a combinaciones mixtas (Docker + externos),
5. extensible a nuevos servicios sin duplicar logica.
