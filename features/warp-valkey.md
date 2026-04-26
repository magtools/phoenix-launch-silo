# RFC: soporte Warp para `valkey/valkey:8.0-alpine`

## Decision propuesta

**Si, conviene reutilizar la misma carpeta, los mismos nombres de servicio y las mismas variables legacy**, igual que hoy Warp ya hace en otros casos donde mantiene el contrato historico y cambia el engine real por debajo.

La recomendacion es:

- mantener los nombres de servicio `redis-cache`, `redis-session` y `redis-fpc`
- mantener la carpeta `.warp/docker/config/redis`
- mantener la carpeta `.warp/setup/redis`
- mantener compatibilidad con variables legacy `REDIS_*`
- agregar `valkey.conf` dentro de `config/redis`
- resolver diferencias reales de engine con helpers/variables canonicas de runtime

En otras palabras: **no hace falta renombrar la capa "redis" a "valkey"**, pero si hace falta desacoplarla de binarios, usuario y paths hardcodeados.

## Alcance funcional

Este RFC **no esta atado a un proyecto puntual**.

El objetivo es que Warp pueda:

- seguir funcionando con Redis en proyectos existentes o en stacks que no usen Valkey
- ofrecer Valkey como engine local cuando el proyecto detectado sea compatible
- mantener Redis como opcion valida para versiones anteriores

### Umbral de soporte Magento

Para Magento, el soporte propuesto es:

- **Magento 2.4.8 en adelante**: Valkey soportado
- **versiones anteriores**: seguir con Redis como opcion por defecto o unica opcion compatible segun el perfil detectado

Esto es consistente con la direccion ya tomada en Warp: la compatibilidad se decide por contexto de aplicacion, pero el core del framework sigue siendo generico.

## Contexto actual

### Lo que ya esta preparado

Hay base real para soportar Valkey:

- `.warp/variables.sh` ya declara `WARP_CACHE_ENGINES=("redis" "valkey")`
- `.warp/variables.sh` ya define `WARP_CACHE_VALKEY_IMAGE_REPO="valkey/valkey"`
- `.warp/setup/redis/redis.sh` ya permite elegir `redis|valkey`
- `.warp/lib/app_context.sh` ya oculta o muestra Valkey segun compatibilidad Magento
- `.warp/lib/fallback.sh` ya puede detectar `valkey` desde el compose
- `.warp/bin/cache.sh` ya soporta `valkey-cli` en modo `CACHE_MODE=external`

La base existe, pero hoy sigue siendo **parcial**: alcanza para metadata, deteccion y parte del modo external, pero no para runtime local completo.

### Donde hoy se rompe el soporte local

El soporte actual a `valkey` no alcanza para modo local porque la capa de runtime sigue acoplada a Redis:

1. **Templates de setup**
   - `.warp/setup/redis/tpl/redis_cache.yml`
   - `.warp/setup/redis/tpl/redis_session.yml`
   - `.warp/setup/redis/tpl/redis_fpc.yml`

   Hoy hardcodean:

   - `redis-server`
   - `/usr/local/etc/redis/redis.conf`

2. **CLI y shell dentro del contenedor**
   - `.warp/bin/redis.sh`

   Hoy hardcodea:

   - `redis-cli`
   - `docker-compose exec -u redis ...`

3. **Bootstraps secundarios**
   - `.warp/setup/sandbox/sandbox-m2.sh`
   - `.warp/setup/init/gandalf.sh`

   Hoy fuerzan:

   - `CACHE_ENGINE=redis`
   - `./.warp/docker/config/redis/redis.conf`

4. **Ayudas y tooling auxiliar**
   - `.warp/bin/redis_help.sh`
   - `.warp/bin/memory.sh`

   Todavia describen Redis como si fuera el unico contrato local.

### Por que falla con `valkey/valkey:8.0-alpine`

Segun el contrato esperado por la imagen oficial de Valkey:

- el binario es `valkey-server`
- el cliente es `valkey-cli`
- el archivo de config esperado es `/usr/local/etc/valkey/valkey.conf`
- el usuario del contenedor es `valkey`

El setup actual de Warp genera contenedores usando contrato Redis:

- `redis-server`
- `redis-cli`
- `/usr/local/etc/redis/redis.conf`
- usuario `redis`

No conviene asumir aliases `redis-*` dentro de `valkey/valkey:8.0-alpine`, porque Warp ya aprendio en otros cambios que es mejor **reusar naming historico externo** y **parametrizar el contrato interno real**.

## Decision de naming y compatibilidad

### Mantener nombres de servicio

Se recomienda **mantener**:

- `redis-cache`
- `redis-session`
- `redis-fpc`

Motivo:

- `.warp/lib/service_context.sh` y `.warp/lib/fallback.sh` ya detectan esos servicios
- `.warp/bin/magento.sh` ya configura Magento contra esos hosts
- `.warp/bin/memory.sh` y helpers varios tambien dependen de esos nombres

Renombrarlos a `valkey-*` abriria un cambio transversal innecesario. El host interno puede seguir llamandose `redis-cache` aunque el engine sea Valkey, igual que el servicio `mysql` puede seguir existiendo aunque el image real cambie.

### Mantener carpetas `redis`

Tambien se recomienda **mantener**:

- `.warp/docker/config/redis`
- `.warp/setup/redis`

Motivo:

- ya estan referenciadas por setup, docs, env samples y tooling
- la carpeta representa la capacidad historica de cache local, no el vendor puntual
- evita migraciones de paths y reduce riesgo

### Mantener variables legacy `REDIS_*`

Conviene **mantener**:

- `REDIS_CACHE_VERSION`
- `REDIS_SESSION_VERSION`
- `REDIS_FPC_VERSION`
- `REDIS_*_CONF`
- `REDIS_*_MAXMEMORY`
- `REDIS_*_MAXMEMORY_POLICY`

Aunque el engine real sea Valkey.

Motivo:

- esas variables hoy describen slots funcionales del stack
- ya forman parte del contrato historico de `.env` y `.env.sample`
- Warp suele reusar nombres existentes cuando cambia el contenido real por detras

El engine real debe seguir viviendo en variables canonicas ya alineadas a capability:

- `CACHE_MODE`
- `CACHE_ENGINE`
- `CACHE_VERSION`
- `CACHE_IMAGE_REPO`
- `CACHE_SCOPE`
- `CACHE_HOST`
- `CACHE_PORT`

## Propuesta tecnica

### 1. Introducir un helper de contrato de engine para cache

Agregar una capa helper central para cache local, por ejemplo en `.warp/lib/`, que resuelva desde `CACHE_ENGINE`:

- `CACHE_SERVER_BIN`
- `CACHE_CLI_BIN`
- `CACHE_CONTAINER_USER`
- `CACHE_CONTAINER_CONFIG_PATH`
- `CACHE_DEFAULT_HOST_CONFIG`

Valores propuestos:

| CACHE_ENGINE | CACHE_SERVER_BIN | CACHE_CLI_BIN | CACHE_CONTAINER_USER | CACHE_CONTAINER_CONFIG_PATH | CACHE_DEFAULT_HOST_CONFIG |
| --- | --- | --- | --- | --- | --- |
| redis | redis-server | redis-cli | redis | /usr/local/etc/redis/redis.conf | ./.warp/docker/config/redis/redis.conf |
| valkey | valkey-server | valkey-cli | valkey | /usr/local/etc/valkey/valkey.conf | ./.warp/docker/config/redis/valkey.conf |

Importante:

- esto **no implica** que todas esas variables deban persistirse en `.env`
- el contrato interno puede resolverse por helper en setup/runtime
- en `.env` conviene persistir solo lo necesario para compatibilidad y compose

### 2. Parametrizar templates existentes en vez de duplicar servicios

Los templates actuales pueden seguir llamandose:

- `.warp/setup/redis/tpl/redis_cache.yml`
- `.warp/setup/redis/tpl/redis_session.yml`
- `.warp/setup/redis/tpl/redis_fpc.yml`

Pero deberian usar variables en lugar de valores hardcodeados:

- `image: ${CACHE_IMAGE_REPO:-redis}:${REDIS_*_VERSION}`
- mount a `${CACHE_CONTAINER_CONFIG_PATH}`
- command `${CACHE_SERVER_BIN}`

Con esto no hace falta crear `valkey_cache.yml`, `valkey_session.yml`, etc.

### 3. Reutilizar la misma carpeta de config con archivos por motor

La recomendacion es **misma carpeta, archivos distintos**:

- `.warp/docker/config/redis/redis.conf`
- `.warp/docker/config/redis/valkey.conf`
- `.warp/setup/redis/config/redis/redis.conf`
- `.warp/setup/redis/config/redis/valkey.conf`

Esto sigue el patron historico de Warp: mismo path esperado por tooling, distinto contenido segun engine.

No recomiendo cambiar el nombre de la carpeta a `valkey`, porque rompe compatibilidad y no aporta valor tecnico.

### 4. Resolver el archivo default segun engine

Cuando el engine seleccionado sea:

- `redis`: default `./.warp/docker/config/redis/redis.conf`
- `valkey`: default `./.warp/docker/config/redis/valkey.conf`

Esto aplica a:

- wizard principal en `.warp/setup/redis/redis.sh`
- `gandalf`
- `sandbox`
- samples de entorno

### 5. Mantener el contrato CLI externo de Magento

No veo razon para cambiar:

- `--cache-backend=redis`
- `--page-cache=redis`
- `--session-save=redis`

A nivel Magento, Valkey entra como compatibilidad del backend Redis; no hace falta abrir un contrato CLI nuevo del lado de `warp magento`.

## Impacto en scripts

### `.warp/setup/redis/redis.sh`

Debe:

- dejar de preguntar siempre por `./.warp/docker/config/redis/redis.conf`
- resolver default segun engine
- seguir escribiendo `REDIS_*` como contrato legacy
- escribir `CACHE_ENGINE`, `CACHE_VERSION` y `CACHE_IMAGE_REPO` como canonicos

No hace falta inflar `.env` con todo el contrato interno si puede resolverse por helper.

### `.warp/bin/redis.sh`

Debe dejar de asumir:

- `redis-cli`
- usuario `redis`

Cambio recomendado:

- para `cli`, `monitor` y `flush`, usar el binario resuelto por engine
- para `ssh`, mapear `--cache` al usuario canonico del engine
- mantener `--redis` como alias legacy, pero no como unica opcion real

### `.warp/bin/cache.sh`

Ya esta bien orientado en modo external. En modo local puede seguir delegando a `redis.sh`, pero `redis.sh` primero debe quedar engine-aware.

### `.warp/setup/sandbox/sandbox-m2.sh`

Hoy esta clavado a Redis. Debe reutilizar la misma resolucion de engine que el setup principal o, como minimo:

- usar Redis en perfiles sin soporte Valkey
- usar Valkey solo cuando el perfil detectado sea Magento 2.4.8+

### `.warp/setup/init/gandalf.sh`

Mismo problema que sandbox: hoy fija `CACHE_ENGINE=redis` y path `redis.conf`.

Debe alinearse al mismo criterio de compatibilidad y default path.

### `.warp/bin/memory.sh`

No bloquea el arranque, pero para soporte completo debe:

- detectar `CACHE_CLI_BIN`
- dejar de documentar solo `redis-server /usr/local/etc/redis/redis.conf`
- poder leer `valkey.conf` cuando corresponda

## Implementacion recomendada

### Fase 1: soporte local minimo y seguro

1. Crear helper de contrato de engine cache
2. Parametrizar templates `redis_*.yml`
3. Agregar `valkey.conf` en setup + docker/config
4. Hacer `redis.sh` engine-aware para `cli`, `monitor`, `ssh` y `flush`
5. Resolver defaults por engine en `.warp/setup/redis/redis.sh`

### Fase 2: cerrar bootstraps alternativos

1. Ajustar `.warp/setup/sandbox/sandbox-m2.sh`
2. Ajustar `.warp/setup/init/gandalf.sh`
3. Ajustar `redis.env` sample

### Fase 3: tooling y docs

1. Ajustar `.warp/bin/memory.sh`
2. Ajustar `.warp/bin/redis_help.sh`
3. Ajustar ayuda visible para hablar de "cache service (redis/valkey)" de forma consistente

## Checklist de validacion

### Setup

- elegir `redis` genera compose valido como hoy
- elegir `valkey` genera compose valido con image `valkey/valkey:8.0-alpine`
- `.env` resultante deja `CACHE_ENGINE=valkey`
- `.env` resultante deja `CACHE_IMAGE_REPO=valkey/valkey`
- el config path default para Valkey apunta a `./.warp/docker/config/redis/valkey.conf`
- el config path default para Redis sigue apuntando a `./.warp/docker/config/redis/redis.conf`

### Runtime local

- `docker compose config` resuelve `valkey-server`
- el mount apunta a `/usr/local/etc/valkey/valkey.conf`
- `warp cache info`
- `warp cache cli cache`
- `warp cache monitor cache`
- `warp cache flush cache`
- `warp cache ssh cache --cache`

### Compatibilidad Magento

- en Magento 2.4.8+ se puede ofrecer `valkey` como engine soportado
- en versiones anteriores Warp mantiene `redis` como path seguro/compatible
- `warp magento setup:config:set` sigue configurando cache/fpc/session sin cambios de flags
- `app/etc/env.php` queda apuntando a `redis-cache`, `redis-fpc`, `redis-session`

### Smoke core de Warp

- `./warp --help`
- `./warp init --help`
- `./warp start --help`
- `./warp stop --help`
- `./warp info --help`
- `./warp docker ps`

## Conclusiones

La estrategia correcta no es abrir una rama paralela con nombres `valkey-*`, sino **reusar la capa historica `redis` como naming externo y desacoplar el contrato interno del engine**.

Eso deja un cambio acotado, consistente con como Warp se viene moviendo:

- reusar variables existentes
- reusar nombres de servicio
- reusar paths conocidos
- cambiar contenido y comportamiento interno cuando el engine lo requiere

Con ese enfoque:

- Magento 2.4.8+ puede usar Valkey
- versiones anteriores siguen funcionando con Redis
- no se rompe compatibilidad de `.env`, tooling ni helpers existentes

## Archivos relevados

- `.warp/variables.sh`
- `.warp/lib/app_context.sh`
- `.warp/lib/fallback.sh`
- `.warp/lib/service_context.sh`
- `.warp/bin/cache.sh`
- `.warp/bin/redis.sh`
- `.warp/bin/redis_help.sh`
- `.warp/bin/magento.sh`
- `.warp/bin/memory.sh`
- `.warp/setup/redis/redis.sh`
- `.warp/setup/redis/tpl/redis_cache.yml`
- `.warp/setup/redis/tpl/redis_session.yml`
- `.warp/setup/redis/tpl/redis_fpc.yml`
- `.warp/setup/redis/tpl/redis.env`
- `.warp/setup/redis/config/redis/redis.conf`
- `.warp/docker/config/redis/redis.conf`
- `.warp/setup/sandbox/sandbox-m2.sh`
- `.warp/setup/init/gandalf.sh`
