# Feature: `warp telemetry scan` (estado actual)

Fecha: 2026-03-16

## 1) Objetivo funcional

`warp telemetry scan` ayuda a operar y dimensionar servicios clave del stack:

1. muestra consumo actual de memoria por servicio,
2. muestra configuración actual detectada,
3. calcula sugerencias de sizing para Elasticsearch, Redis y PHP-FPM,
4. marca alertas de presión de memoria sobre límites asignados.

Es un comando de solo lectura: no escribe `.env` ni modifica configs.

## 2) Comandos

```bash
warp telemetry
warp telemetry scan
warp telemetry scan --no-suggest
warp telemetry scan --json
warp telemetry config
```

`warp telemetry config` imprime una guía breve de referencia (archivo + parámetros) para ubicar rápidamente qué tocar en:

1. `.env`
2. `docker-compose-warp.yml`
3. `php-fpm.conf`
4. `redis.conf`
5. recomendación de tuning MySQL/MariaDB vía `warp mysql tuner` (MySQLTuner).

## 3) Datos que muestra

## 3.1 Host

1. RAM total.
2. Topología CPU detectada.
3. Cores físicos, threads lógicos, sockets y threads por core.
4. `THREADS` sugeridos para deploy (`logical_threads - WARP_HOST_THREADS_RESERVE`, mínimo `1`).

## 3.2 Uso por servicios

1. uso de contenedor (`docker stats`) para:
   - `php`
   - `mysql`
   - `elasticsearch`
   - `redis-cache`
   - `redis-fpc`
   - `redis-session`
2. uso interno (cuando aplica):
   - Redis: `used_memory`, `used_memory_peak`, `maxmemory` (INFO memory).
   - Elasticsearch/OpenSearch: `heap_used_in_bytes`, `heap_max_in_bytes` (nodes stats).
   - Fallback ES/OpenSearch si no se puede leer heap API:
     - `used`: aproximado desde `docker stats` del contenedor.
     - `assigned`: `ES_MEMORY` (si está seteado).

## 3.3 Configuración actual detectada

1. `ES_MEMORY`.
2. `REDIS_*_MAXMEMORY` y `REDIS_*_MAXMEMORY_POLICY`.
3. parámetros `pm.*` de PHP-FPM (`php-fpm.conf`).

## 4) Reglas de alertas (operación)

Se evalúa uso vs memoria asignada:

1. `>=75%` -> `WARNING`
2. `>=90%` -> `CRITICO`

Aplicación:

1. Redis: sobre `used_memory / maxmemory` (si `maxmemory` existe y es >0).
2. Elasticsearch/OpenSearch: sobre `heap_used / heap_assigned` (heap detectado o `ES_MEMORY`).

Si no hay límite asignado detectable, el reporte lo informa explícitamente.

## 5) Reglas de sugerencia implementadas

## 5.1 Redis (por instancia)

Base calculada con `used_memory`:

1. `<1GB`: +100% (`used * 2.0`)
2. `>=1GB`: +60% (`used * 1.6`)

Guardrail por pico (`used_memory_peak`):

1. `peak/base >=75%` -> sugerencia de seguridad mínima `max(base, peak*1.15)`.
2. `peak/base >=90%` -> sugerencia de seguridad mínima `max(base, peak*1.30)`.

Políticas sugeridas:

1. `redis-cache`: `allkeys-lru`
2. `redis-fpc`: `allkeys-lru`
3. `redis-session`: `noeviction`

## 5.2 Elasticsearch

Base calculada con `used_memory` (heap usado; o aproximación de contenedor si falla heap API):

1. `<1GB`: +70% (`used * 1.7`)
2. `>=1GB`: +50% (`used * 1.5`)

Guardrail por pico:

1. `peak/base >=75%` -> seguridad mínima `max(base, peak*1.15)`.
2. `peak/base >=90%` -> seguridad mínima `max(base, peak*1.30)`.

## 5.3 Redondeo (Redis/ES)

1. redondeo siempre hacia arriba a múltiplos de `64MB`.
2. mínimo absoluto: `64MB`.

## 5.4 PHP-FPM

`pm.max_children` se extrapola sobre un presupuesto de RAM para PHP, no sobre la RAM total bruta del host.

Presupuesto PHP:

### Con `docker-compose-warp.yml`

1. usar `MemTotal` del host como base del presupuesto PHP;
2. reservar `1GB` para sistema;
3. descontar solo servicios presentes en `docker-compose-warp.yml`;
4. Redis/Valkey:
   - `redis-cache`: `REDIS_CACHE_MAXMEMORY` o fallback `512MB`
   - `redis-fpc`: `REDIS_FPC_MAXMEMORY` o fallback `512MB`
   - `redis-session`: `REDIS_SESSION_MAXMEMORY` o fallback `256MB`
5. Search:
   - `elasticsearch`/`opensearch`: `ES_MEMORY` o fallback `1024MB`
6. DB:
   - `mysql`/`mariadb`: reserva heurística fija `2GB`
7. si un servicio no existe en `docker-compose-warp.yml`, no participa en el descuento;
8. el presupuesto final para PHP es `MemTotal - reserve_sistema - reserve_servicios`, con clamp mínimo de `1GB`.

### Sin `docker-compose-warp.yml` (host-mode)

1. usar `MemTotal` del host como base para el presupuesto PHP;
2. reservar `1.5GB + 10%` de la RAM total del host;
3. el presupuesto final para PHP es `MemTotal - reserve`, con clamp mínimo de `1GB`;
4. si se detectan workers reales `php-fpm: pool ...`, el sizing calcula un rango:
   - `aggressive`: usando PSS promedio por worker cuando está disponible; si no, una aproximación privada desde `/proc/<pid>/statm` (`rss - shared`); si eso tampoco está disponible, RSS promedio de workers excluyendo el master
   - `conservative`: usando ese mismo promedio con uplift de `15%`
5. el valor simple expuesto en `suggested.php_fpm_*` corresponde al extremo conservador;
6. si no se detectan workers, host-mode hace fallback a la extrapolación por anclas usando el presupuesto PHP calculado.
7. `MemAvailable` se muestra aparte como señal de headroom actual del host, pero no participa en el presupuesto base.
8. si se detecta CPU real por worker, el reporte agrega una segunda referencia de `pm.max_children` por CPU:
   - base: `%CPU` promedio observado sobre `php-fpm: pool ...`
   - `aggressive`: `floor((logical_threads * 90) / avg_worker_cpu_pct)`
   - `conservative`: `floor((logical_threads * 90) / max(avg_worker_cpu_pct * 1.15, max_worker_cpu_pct))`
   - el `10%` restante por CPU lógico queda reservado para sistema/nginx

Sobre ese presupuesto, `pm.max_children` usa anclas:

1. `7.5GB -> 15`
2. `15.5GB -> 30`
3. `31.5GB -> 70`

Regla de redondeo para `pm.max_children`:

1. si resultado `<20`: `ceil(valor) + 1` (optimista).
2. si resultado `>=20`: `ceil(valor) + 2`.

Resto de parámetros:

1. `pm=dynamic`
2. `pm.start_servers`: `ceil(max_children*0.20)` con tope `15`.
3. `pm.min_spare_servers`: `ceil(max_children*0.20)` con tope `15`.
4. `pm.max_spare_servers`: `ceil(max_children*0.40)` con tope `30`.
5. `pm.max_requests`: `pm.max_children * 100`, con mínimo `1000` y máximo `5000`.

La salida texto muestra un bloque `[PHP SIZING BUDGET]` con el desglose usado para el cálculo. En host-mode, si hay workers observados, el reporte suma:

1. workers observados,
2. fuente de memoria por worker (`pss`, `statm_private` o `rss`),
3. memoria promedio por worker,
4. memoria conservadora por worker,
5. CPU promedio por worker,
6. CPU conservadora por worker,
7. rango `pm.max_children` conservador/agresivo por memoria,
8. estimación `pm.max_children` por CPU cuando aplica.

## 6) Salida para operador

El reporte incluye notas explícitas para facilitar interpretación:

1. qué métricas se usaron (`used` como base y `peak` como guardrail),
2. cuándo conviene tomar “seguridad mínima” en lugar de base,
3. una sección `[APP CONFIGS]` entre sugerencias y notas al operador.
4. `REDIS/VALKEY max_concurrency` calculado como `clamp(pm.max_children * 0.3, 5, 15)` con redondeo entero hacia arriba antes del clamp.
5. una sección `[PHP SIZING BUDGET]` con reservas de sistema/servicios y presupuesto final para PHP.
6. advertencias cuando no hay límites configurados.
7. un resumen inicial de capacidades del host para validar rápido si Warp leyó bien la topología CPU.

## 7) JSON

`--json` expone:

1. host (`ram_total`, `cores`),
2. uso de contenedores + métricas internas Redis/ES,
3. alertas por servicio,
4. configuración actual detectada,
5. sugerencias base y de seguridad mínima.
6. `app_redis_valkey_max_concurrency` derivado del `pm.max_children` sugerido.
7. desglose de presupuesto PHP en `config`:
   - `php_sizing_system_reserved_mb`
   - `php_sizing_redis_cache_reserved_mb`
   - `php_sizing_redis_fpc_reserved_mb`
   - `php_sizing_redis_session_reserved_mb`
   - `php_sizing_search_reserved_mb`
   - `php_sizing_db_reserved_mb`
   - `php_sizing_budget_mb`
   - `php_sizing_mode`
   - `php_worker_count`
   - `php_worker_mem_source`
   - `php_worker_rss_avg_mb`
   - `php_worker_rss_conservative_mb`
8. rango de host-mode en `suggested` cuando aplica:
   - `php_fpm_max_children_aggressive`
   - `php_fpm_max_requests_aggressive`
   - `php_fpm_max_children_range`
   - `php_fpm_max_children_cpu_estimate`
   - `php_fpm_max_children_cpu_aggressive`
   - `php_fpm_max_children_cpu_range`
9. métricas CPU observadas por worker en `config`:
   - `php_worker_cpu_avg_pct`
   - `php_worker_cpu_conservative_pct`

Campos host añadidos:

1. `cpu_summary`
2. `physical_cores`
3. `logical_threads`
4. `threads_per_core`
5. `sockets`
6. `threads_reserve`
7. `deploy_threads_suggested`
