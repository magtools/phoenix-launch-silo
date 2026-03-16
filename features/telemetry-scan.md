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
2. Cores detectados.

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

`pm.max_children` se extrapola por RAM con anclas:

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
5. `pm.max_requests`: escalado por RAM, tope `5000`.

## 6) Salida para operador

El reporte incluye notas explícitas para facilitar interpretación:

1. qué métricas se usaron (`used` como base y `peak` como guardrail),
2. cuándo conviene tomar “seguridad mínima” en lugar de base,
3. advertencias cuando no hay límites configurados.

## 7) JSON

`--json` expone:

1. host (`ram_total`, `cores`),
2. uso de contenedores + métricas internas Redis/ES,
3. alertas por servicio,
4. configuración actual detectada,
5. sugerencias base y de seguridad mínima.
