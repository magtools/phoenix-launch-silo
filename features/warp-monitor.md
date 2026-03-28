# Warp Monitor

Fecha: 2026-03-28

## Objetivo

Proponer un futuro comando `warp monitor` orientado a observación operativa en vivo o por polling, separado de:

- `warp info`: resumen actual del stack
- `warp telemetry`: snapshot técnico de capacidad, sizing y configuración
- `warp security`: triage de intrusión y toolkit

La idea es que `warp monitor` cubra runtime y comportamiento en curso.

## Rol del comando

`warp monitor` debería servir para:

1. observar estado vivo de servicios y contenedores,
2. detectar degradación operativa antes de una caída visible,
3. concentrar señales que hoy obligan a combinar `docker stats`, logs y checks manuales,
4. ofrecer un modo compacto tipo consola operativa.

## Diferencia funcional frente a otros comandos

`warp info`

- responde: qué está levantado, cómo está configurado, qué contenedores existen.

`warp telemetry`

- responde: cómo está dimensionado el host o servicio, qué configuración actual y sugerida conviene.

`warp monitor`

- respondería: qué está pasando ahora mismo.

## Alcance inicial propuesto

Una primera versión de `warp monitor` podría observar:

1. estado de contenedores:
   - running / exited / restarting
   - health
   - restart count
2. consumo live:
   - CPU
   - memoria
3. presión de servicios:
   - PHP-FPM saturación básica
   - Redis memoria/evictions
   - MySQL conexiones
   - Search health
4. tráfico/errores:
   - 4xx / 5xx recientes
   - burst de errores
   - top endpoints
   - top IPs
5. procesos funcionales:
   - cron
   - consumers
   - indexers

## Modos de operación

### 1. Snapshot

Comando:

1. `warp monitor`

Comportamiento:

1. imprime un estado resumido actual,
2. sin loop,
3. pensado para troubleshooting rápido.

### 2. Watch

Comando:

1. `warp monitor --watch`
2. `warp monitor --watch 5`

Comportamiento:

1. refresco cada `N` segundos,
2. vista compacta de consola,
3. útil para deploys, picos de tráfico o incidentes.

### 3. Vistas por dominio

Comandos posibles:

1. `warp monitor web`
2. `warp monitor db`
3. `warp monitor cache`
4. `warp monitor search`
5. `warp monitor queue`

Comportamiento:

1. reduce ruido,
2. muestra solo señales del área elegida.

## UX CLI propuesta

Formato general:

```text
[MONITOR]
mode: watch (5s)
host: nominal
web: warning
db: nominal
cache: nominal
search: nominal
queue: warning
```

Bloques posibles:

```text
[CONTAINERS]
php:       running healthy
nginx:     running healthy
mysql:     running
redis:     running
search:    running

[LOAD]
php cpu:   32%
php mem:   612MB
mysql mem: 480MB
redis mem: 110MB

[WEB]
5xx last 5m:      12
top endpoint:     /checkout/cart
top ip:           10.0.0.25

[QUEUE]
consumers:        3 running
cron delay:       warning
indexers:         ready
```

## Señales útiles de fase 1

### Contenedores

Inputs:

1. `docker ps`
2. `docker inspect`
3. `docker stats --no-stream`

Señales:

1. container down
2. unhealthy
3. restart count anómalo
4. consumo extremo de CPU/memoria

### Web

Inputs:

1. access logs
2. error logs

Señales:

1. burst de 5xx
2. burst de 499/502/504
3. endpoint caliente
4. IP dominante

### PHP

Inputs:

1. estado de contenedor PHP
2. logs PHP-FPM si existen
3. procesos PHP-FPM

Señales:

1. saturación sostenida
2. workers agotados
3. reinicios frecuentes

### DB

Inputs:

1. MySQL/MariaDB status básico
2. conexiones activas
3. slow log si está disponible

Señales:

1. conexiones altas
2. lock/wait sostenido
3. slow queries recurrentes

### Cache

Inputs:

1. Redis `INFO`

Señales:

1. memoria alta
2. evictions
3. fragmentation anómala

### Search

Inputs:

1. endpoint de health de Elasticsearch/OpenSearch

Señales:

1. cluster yellow/red
2. memoria JVM alta
3. timeouts o no respuesta

### Queue / cron

Inputs:

1. procesos consumidores
2. logs de cron/consumers
3. indexers

Señales:

1. consumers caídos
2. backlog funcional
3. cron degradado

## Salida y severidad

Una primera propuesta simple:

- `nominal`
- `warning`
- `critical`

Cada bloque podría derivar su propio estado, y `warp monitor` mostrar un estado agregado.

## Consideraciones de diseño

1. no mezclar con `telemetry`; monitor es runtime vivo, no sizing.
2. no mezclar con `security`; monitor es salud operativa, no intrusión.
3. mantener modo one-shot como default.
4. evitar depender de herramientas externas no estándar.
5. si hay modo watch, cuidar ancho y estabilidad visual de la consola.

## Futuras extensiones

1. `--json`
2. `--watch N`
3. `--compact`
4. `--service <name>`
5. thresholds configurables por `.env`
6. correlación con `telemetry`
7. alertas operativas simples por color

## Recomendación inicial

Si se retoma esta feature, el orden razonable sería:

1. `warp monitor` snapshot
2. estado de contenedores + `docker stats`
3. vista `web`
4. vista `queue`
5. modo `--watch`

