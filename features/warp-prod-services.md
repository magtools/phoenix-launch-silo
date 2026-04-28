# RFC: compose de produccion para servicios internos

## Decision implementada

Warp mantiene el contrato actual de desarrollo/legacy y agrega un artefacto final de produccion:

- `docker-compose-warp.yml.sample`
- `docker-compose-warp.yml`
- `docker-compose-warp.yml.prod`

La decision final fue **no** sostener un arbol paralelo de templates `*_prod.yml` ni un sample `prod` separado.

En cambio:

1. `init` genera el compose normal como hoy
2. Warp resuelve `docker-compose-warp.yml`
3. al final del setup deriva `docker-compose-warp.yml.prod` desde ese compose ya resuelto
4. en esa derivacion solo cambia los bindings sensibles a `127.0.0.1`

Esto reduce drift y evita que `prod` herede placeholders o bloques vacios del sample.

## Objetivo funcional

El objetivo no es esconder DB/cache/search dentro de la red Docker.

El objetivo es:

- mantener acceso por CLI desde el mismo server al entrar por SSH
- evitar exposicion en `0.0.0.0`
- preservar la red interna Docker para la app

En otras palabras:

- `dev/legacy`: comportamiento actual
- `prod`: mismos servicios, pero publicados solo en `127.0.0.1`

## Diferencia operativa

### `docker-compose-warp.yml.sample`

Sigue siendo la base legacy/dev:

- MySQL como hoy
- Redis/Valkey como hoy
- OpenSearch como hoy

### `docker-compose-warp.yml.prod`

Es un compose final listo para server:

- MySQL accesible por `127.0.0.1`
- Redis/Valkey accesible por `127.0.0.1`
- OpenSearch accesible por `127.0.0.1`
- no accesibles desde Internet salvo que otra capa los reexponga

Eso permite, por ejemplo:

- `mysql -h 127.0.0.1 -P ...`
- `redis-cli -h 127.0.0.1 -p ...`
- `curl http://127.0.0.1:9200`

## Problema que resuelve

Los templates actuales usan `ports:` sin bind explicito a loopback.

Consecuencia:

- accesibles desde el host local
- pero tambien desde otras interfaces del server

Para server productivo, eso es demasiado permisivo para:

- `mysql`
- `redis-cache`
- `redis-session`
- `redis-fpc`
- `elasticsearch`

## Implementacion tecnica

### Derivacion desde compose final

El punto clave es que `prod` se genera desde `docker-compose-warp.yml`, no desde `docker-compose-warp.yml.sample`.

Eso implica:

- cualquier bloque `## BEGIN ... ##` ya resuelto en el compose normal queda tambien resuelto en `prod`
- no hace falta duplicar fragments de setup
- no hace falta sostener un segundo ensamblado del stack

### Reescrituras aplicadas

En la derivacion a `prod`, Warp reescribe solo estos bindings:

#### MySQL

```yaml
mysql:
  ports:
    - "127.0.0.1:${DATABASE_BINDED_PORT}:3306"
```

#### Redis cache

```yaml
redis-cache:
  ports:
    - "127.0.0.1:${REDIS_CACHE_BINDED_PORT:-6379}:6379"
```

#### Redis session

```yaml
redis-session:
  ports:
    - "127.0.0.1:${REDIS_SESSION_BINDED_PORT:-6380}:6379"
```

#### Redis fpc

```yaml
redis-fpc:
  ports:
    - "127.0.0.1:${REDIS_FPC_BINDED_PORT:-6381}:6379"
```

#### OpenSearch

```yaml
elasticsearch:
  ports:
    - "127.0.0.1:${SEARCH_HTTP_BINDED_PORT:-9200}:9200"
    - "127.0.0.1:${SEARCH_TRANSPORT_BINDED_PORT:-9300}:9300"
```

## Variables requeridas

Para que el compose `prod` sea reproducible, Warp deja disponibles:

- `DATABASE_BINDED_PORT`
- `REDIS_CACHE_BINDED_PORT`
- `REDIS_SESSION_BINDED_PORT`
- `REDIS_FPC_BINDED_PORT`
- `SEARCH_HTTP_BINDED_PORT`
- `SEARCH_TRANSPORT_BINDED_PORT`

La red interna no cambia:

- `mysql:3306`
- `redis-cache:6379`
- `redis-session:6379`
- `redis-fpc:6379`
- `elasticsearch:9200`

## Archivos relevantes

La implementacion actual vive principalmente en:

- [`.warp/lib/compose_sample.sh`](../.warp/lib/compose_sample.sh)
- [`.warp/setup/init/info.sh`](../.warp/setup/init/info.sh)
- [`.warp/setup/mysql/database.sh`](../.warp/setup/mysql/database.sh)
- [`.warp/setup/redis/redis.sh`](../.warp/setup/redis/redis.sh)
- [`.warp/setup/elasticsearch/elasticsearch.sh`](../.warp/setup/elasticsearch/elasticsearch.sh)
- [`.warp/setup/init/gandalf.sh`](../.warp/setup/init/gandalf.sh)

Y `docker-compose-warp.yml.prod` queda ignorado en Git igual que `docker-compose-warp.yml`.

## Compatibilidad legacy

Este enfoque preserva mejor compatibilidad porque:

- `docker-compose-warp.yml` no cambia de semantica
- los proyectos viejos siguen funcionando igual
- `prod` es opt-in y manual
- no agrega ruido tipo `DB_EXPOSURE`, `CACHE_EXPOSURE`, `SEARCH_EXPOSURE`

## Riesgos y tradeoffs

1. `127.0.0.1` reduce exposicion, pero no aísla el servicio de otros procesos del mismo host.
2. Clientes remotos que hoy entren directo a MySQL/Redis/Search desde fuera del host dejaran de poder hacerlo con `prod`.
3. Si alguien modifica `docker-compose-warp.yml` a mano despues de `init`, tendra que volver a derivar o actualizar tambien `docker-compose-warp.yml.prod`.

## Validacion minima

Ademas de la validacion base del repo, conviene verificar:

1. `docker-compose-warp.yml` mantiene el comportamiento actual.
2. `docker-compose-warp.yml.prod` queda con bindings `127.0.0.1` para MySQL.
3. `docker-compose-warp.yml.prod` queda con bindings `127.0.0.1` para Redis.
4. `docker-compose-warp.yml.prod` queda con bindings `127.0.0.1` para OpenSearch.
5. desde el mismo server funcionan:
   - `mysql -h 127.0.0.1 -P ...`
   - `redis-cli -h 127.0.0.1 -p ...`
   - `curl http://127.0.0.1:...`
6. desde otra maquina no hay acceso a esos puertos.

## Resultado esperado

Warp ofrece dos salidas claras:

- `docker-compose-warp.yml`
  - compose activo por defecto
  - legado/desarrollo

- `docker-compose-warp.yml.prod`
  - compose final listo para server
  - servicios internos accesibles por el host local
  - no accesibles desde Internet

Ese balance es el buscado: mantener operabilidad por SSH sin dejar MySQL, Redis y Search abiertos al mundo.
