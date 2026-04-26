# RFC: soporte Warp para `valkey/valkey:8.0-alpine`

## Decision propuesta

**Si, conviene reutilizar la misma carpeta y la misma denominacion historica**, igual que hoy se hace con `mysql/mariadb`.

La recomendacion es:

- mantener los nombres de servicio `redis-cache`, `redis-session` y `redis-fpc`
- mantener la carpeta `.warp/docker/config/redis`
- mantener la carpeta `.warp/setup/redis`
- mantener compatibilidad con variables legacy `REDIS_*`
- resolver las diferencias reales de engine con variables/helpers de contrato (`server bin`, `cli bin`, `container user`, `container config path`, `default config file`)

En otras palabras: **no hace falta renombrar la capa "redis" a "valkey"**, pero si hace falta desacoplarla de binarios y paths hardcodeados.

## Contexto actual

### Lo que ya esta preparado

Hay base real para soportar Valkey:

- `.warp/variables.sh` ya declara `WARP_CACHE_ENGINES=("redis" "valkey")`
- `.warp/variables.sh` ya define `WARP_CACHE_VALKEY_IMAGE_REPO="valkey/valkey"`
- `.warp/setup/redis/redis.sh` ya permite elegir `redis|valkey`
- `.warp/lib/app_context.sh` ya oculta o muestra Valkey segun compatibilidad Magento
- `.warp/lib/fallback.sh` ya puede detectar `valkey` desde el compose
- `.warp/bin/cache.sh` ya soporta `valkey-cli` en modo `CACHE_MODE=external`

Ademas, este proyecto esta en `magento/product-community-edition 2.4.8-p4` (`composer.json`), version donde Adobe ya lista **Valkey 8** como dependencia soportada.

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

Segun la documentacion del image oficial de Valkey:

- el binario es `valkey-server`
- el cliente es `valkey-cli`
- el archivo de config esperado es `/usr/local/etc/valkey/valkey.conf`
- el usuario del contenedor es `valkey`

El setup actual de Warp genera contenedores usando contrato Redis:

- `redis-server`
- `redis-cli`
- `/usr/local/etc/redis/redis.conf`
- usuario `redis`

No conviene asumir aliases `redis-*` dentro de `valkey/valkey:8.0-alpine`, porque el Dockerfile oficial documenta y valida `valkey-server` / `valkey-cli`, no `redis-server` / `redis-cli`.

## Decision de naming

### Mantener nombres de servicio

Se recomienda **mantener**:

- `redis-cache`
- `redis-session`
- `redis-fpc`

Motivo:

- `.warp/lib/service_context.sh` y `.warp/lib/fallback.sh` ya detectan esos servicios
- `.warp/bin/magento.sh` ya configura Magento contra esos hosts
- `.warp/bin/memory.sh` y helpers varios tambien dependen de esos nombres

Renombrarlos a `valkey-*` abriria un cambio transversal innecesario. El host interno puede seguir llamandose `redis-cache` aunque el engine sea Valkey, igual que el servicio `mysql` sigue existiendo cuando el image real es MariaDB.

### Mantener carpetas `redis`

Tambien se recomienda **mantener**:

- `.warp/docker/config/redis`
- `.warp/setup/redis`

Motivo:

- ya estan referenciadas por setup, docs, env samples y tooling
- la carpeta representa la capacidad "cache local key/value" historica, no necesariamente el vendor del engine
- evita migraciones de paths y reduce riesgo

## Propuesta tecnica

### 1. Introducir un contrato de engine para cache

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

La idea es replicar el patron `mysql/mariadb`: **mismo servicio, distinto image/contrato interno**.

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

Esto coincide con lo que pediste: misma estructura y misma denominacion, agregando los archivos especificos del otro motor.

No recomiendo cambiar el nombre de la carpeta a `valkey`, porque rompe el objetivo de compatibilidad y no aporta valor tecnico.

### 4. Mantener `REDIS_*` como variables de slot, no de engine

Conviene **mantener**:

- `REDIS_CACHE_VERSION`
- `REDIS_SESSION_VERSION`
- `REDIS_FPC_VERSION`
- `REDIS_*_CONF`

Aunque el engine sea Valkey.

Motivo:

- esas variables hoy identifican el **slot funcional** (`cache`, `session`, `fpc`), no solo el vendor
- cambiarlas a `VALKEY_*` obligaria a duplicar codigo y compatibilidad

El engine real debe vivir en las variables canonicas:

- `CACHE_ENGINE`
- `CACHE_VERSION`
- `CACHE_IMAGE_REPO`

Y en las nuevas variables de contrato propuestas arriba.

## Impacto en scripts

### `.warp/setup/redis/redis.sh`

Debe dejar de preguntar siempre por `./.warp/docker/config/redis/redis.conf` y resolver el default segun engine.

Tambien debe exportar las nuevas variables canonicas de contrato, no solo `CACHE_ENGINE` y `CACHE_IMAGE_REPO`.

### `.warp/bin/redis.sh`

Debe dejar de asumir:

- `redis-cli`
- usuario `redis`

Cambio recomendado:

- para `cli`, `monitor` y `flush`, usar `${CACHE_CLI_BIN}` dentro del contenedor
- para `ssh`, mapear `--cache` al usuario canonico `${CACHE_CONTAINER_USER}`
- mantener `--redis` como alias legacy, pero no como unica opcion real

### `.warp/bin/cache.sh`

Ya esta bastante bien para modo external. En modo local puede seguir delegando a `redis.sh`, pero `redis.sh` primero debe quedar engine-aware.

### `.warp/setup/sandbox/sandbox-m2.sh`

Hoy esta clavado a Redis. Debe reutilizar la misma resolucion de engine que el setup principal o, al menos, aceptar `CACHE_ENGINE` y `CACHE_IMAGE_REPO`.

### `.warp/setup/init/gandalf.sh`

Mismo problema que sandbox: hoy fija `CACHE_ENGINE=redis` y path `redis.conf`.

### `.warp/bin/memory.sh`

No bloquea el arranque, pero si se quiere soporte completo debe:

- detectar `CACHE_CLI_BIN`
- dejar de documentar solo `redis-server /usr/local/etc/redis/redis.conf`

## Magento: que no cambiaria

### `warp magento setup:config:set`

No veo razon para cambiar:

- `--cache-backend=redis`
- `--page-cache=redis`
- `--session-save=redis`

En el vendor de Magento 2.4.8-p4 siguen existiendo clases y opciones `Redis`, y no aparecen flags especificos `valkey`. A nivel Magento, Valkey entra como compatibilidad del backend Redis, no como backend CLI distinto.

Por eso:

- **si hay que cambiar el contenedor**
- **no hace falta cambiar la integracion CLI de Magento**

## Implementacion recomendada

### Fase 1: soporte local minimo y seguro

1. Crear helper de contrato de engine cache
2. Parametrizar templates `redis_*.yml`
3. Agregar `valkey.conf` en setup + docker/config
4. Hacer `redis.sh` engine-aware para `cli`, `monitor`, `ssh` y `flush`
5. Exportar nuevas variables canonicas desde `.warp/setup/redis/redis.sh`

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

### Runtime local

- `docker compose config` resuelve `valkey-server`
- el mount apunta a `/usr/local/etc/valkey/valkey.conf`
- `warp cache info`
- `warp cache cli cache`
- `warp cache monitor cache`
- `warp cache flush cache`
- `warp cache ssh cache --cache`

### Magento

- `warp magento setup:config:set` sigue configurando cache/fpc/session sin cambios de flags
- `app/etc/env.php` queda apuntando a `redis-cache`, `redis-fpc`, `redis-session`

## Conclusiones

La base para soportar Valkey ya existe, pero hoy esta **incompleta** y limitada sobre todo a metadata de setup y al modo external.

La estrategia correcta no es crear una rama paralela con nombres `valkey-*`, sino **reusar la capa actual `redis` como nombre historico/canonico del capability cache** y desacoplar solo el contrato interno del engine.

Eso deja un cambio acotado, consistente con el patron ya usado para `mysql/mariadb`, y evita romper:

- nombres de servicios
- tooling ya existente
- integracion Magento
- paths y volumes actuales

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
