# RFC: perfiles finales de compose para servicios internos

## Decision implementada

Warp ahora genera tres archivos finales no trackeados:

- `docker-compose-warp.yml.dev`
- `docker-compose-warp.yml.prod`
- `docker-compose-warp.yml`

Y mantiene el sample trackeado:

- `docker-compose-warp.yml.sample`

La decision final fue:

1. usar `docker-compose-warp.yml.sample` como base de ensamblado
2. resolver desde ahi un compose final `dev`
3. derivar desde `dev` un compose final `prod`
4. dejar `docker-compose-warp.yml` como alias activo del perfil que matchea la decision de red tomada en `warp init`

Con eso:

- si el proyecto se configura para trabajar en paralelo, `docker-compose-warp.yml` queda alineado a `docker-compose-warp.yml.dev`
- si el proyecto se configura para trabajar de a uno, `docker-compose-warp.yml` queda alineado a `docker-compose-warp.yml.prod`

## Objetivo funcional

El objetivo es separar tres conceptos:

- sample versionado
- compose final de desarrollo
- compose final endurecido para host local/server

Y a la vez evitar que el usuario tenga que copiar manualmente archivos despues de `init`.

## Semantica de cada archivo

### `docker-compose-warp.yml.sample`

Es la base trackeada del setup.

No representa directamente el compose activo del proyecto.

### `docker-compose-warp.yml.dev`

Es el compose final de desarrollo:

- mantiene el comportamiento historico
- preserva la exposicion actual de servicios
- es el perfil natural cuando el usuario elige trabajar en paralelo

### `docker-compose-warp.yml.prod`

Es el compose final endurecido:

- MySQL publicado en `127.0.0.1`
- Redis/Valkey publicado en `127.0.0.1`
- OpenSearch publicado en `127.0.0.1`

Sigue siendo accesible desde el mismo host:

- `mysql -h 127.0.0.1 -P ...`
- `redis-cli -h 127.0.0.1 -p ...`
- `curl http://127.0.0.1:9200`

Pero deja de estar publicado en interfaces externas.

### `docker-compose-warp.yml`

Es el compose activo por defecto.

No tiene semantica fija por nombre. Su semantica depende de la decision de red tomada en `warp init`:

- modo paralelo: copia de `docker-compose-warp.yml.dev`
- modo single-project: copia de `docker-compose-warp.yml.prod`

## Regla de seleccion automatica

Warp usa la decision de red del proyecto para elegir el compose activo.

Regla actual:

- si `HTTP_HOST_IP != 0.0.0.0`, el perfil es `dev`
- si `HTTP_HOST_IP = 0.0.0.0`, el perfil es `prod`

Eso se apoya en el contrato historico del wizard:

- paralelo implica IP dedicada de contenedor
- single-project implica bind normal en host

## Implementacion tecnica

### Flujo final

1. `init` ensambla el sample
2. `init` resuelve el compose final base
3. Warp guarda ese resultado como `docker-compose-warp.yml.dev`
4. Warp deriva `docker-compose-warp.yml.prod` desde `docker-compose-warp.yml.dev`
5. Warp activa en `docker-compose-warp.yml` el perfil que corresponde segun la decision de red

### Derivacion de `prod`

`docker-compose-warp.yml.prod` no nace de fragments `*_prod.yml` ni de un sample paralelo.

Se deriva desde `docker-compose-warp.yml.dev`, reescribiendo solo los bindings sensibles:

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

## Integracion con `.env`

Para que la seleccion del compose activo sea coherente, `warp init` actualiza `.env` con la decision real del wizard sin tocar `.env.sample`.

Eso evita que un proyecto creado antes para modo paralelo arrastre en `.env` puertos o `HTTP_HOST_IP` viejos al reconfigurarse como single-project.

En la practica:

- `.env.sample` preserva la base versionada/historica
- `.env` refleja la decision actual del entorno
- `docker-compose-warp.yml` se activa con el perfil correcto a partir de esa decision

## Archivos relevantes

La implementacion actual vive principalmente en:

- [`.warp/lib/compose_sample.sh`](../.warp/lib/compose_sample.sh)
- [`.warp/setup/init/info.sh`](../.warp/setup/init/info.sh)
- [`.warp/setup/init/developer.sh`](../.warp/setup/init/developer.sh)
- [`.warp/setup/init/autoload.sh`](../.warp/setup/init/autoload.sh)
- [`.warp/lib/check.sh`](../.warp/lib/check.sh)
- [`.warp/bin/reset.sh`](../.warp/bin/reset.sh)

## Git y limpieza

Estos tres archivos finales no deben trackearse:

- `docker-compose-warp.yml`
- `docker-compose-warp.yml.dev`
- `docker-compose-warp.yml.prod`

Y `reset --hard` debe limpiarlos.

## Compatibilidad legacy

Este enfoque preserva compatibilidad porque:

- el sample trackeado sigue existiendo
- el compose activo sigue llamandose `docker-compose-warp.yml`
- el perfil `dev` conserva la semantica historica
- el perfil `prod` es una derivacion controlada y reversible

## Riesgos y tradeoffs

1. `prod` sigue siendo accesible desde procesos del mismo host; no equivale a aislamiento total.
2. Clientes remotos que dependian de puertos abiertos hacia otras interfaces dejaran de funcionar con el perfil `prod`.
3. La heuristica `HTTP_HOST_IP = 0.0.0.0 => prod` es pragmatica, pero acopla topologia de red con postura de exposicion.

## Validacion minima

1. `warp init` en modo paralelo genera:
   - `docker-compose-warp.yml.dev`
   - `docker-compose-warp.yml.prod`
   - `docker-compose-warp.yml` activo igual a `dev`
2. `warp init` en modo single-project genera:
   - `docker-compose-warp.yml.dev`
   - `docker-compose-warp.yml.prod`
   - `docker-compose-warp.yml` activo igual a `prod`
3. `docker-compose-warp.yml.prod` queda con bindings `127.0.0.1` para MySQL, Redis y OpenSearch.
4. `.env.sample` no se pisa con la reconfiguracion.
5. `.env` refleja la decision actual del wizard.

## Resultado esperado

Warp ofrece ahora:

- un sample versionado
- un compose final `dev`
- un compose final `prod`
- un compose activo por defecto que sigue automaticamente la decision de red del proyecto

Eso mantiene operabilidad local y de server sin pedir pasos manuales para activar el perfil correcto.
