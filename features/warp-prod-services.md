# RFC: compose de produccion para servicios internos

## Decision propuesta

**Si, conviene agregar un template separado de produccion** para que `mysql`, `redis-*` y `elasticsearch` no queden abiertos a Internet, pero sigan siendo accesibles desde el mismo server por CLI al entrar por SSH.

La decision propuesta es:

- mantener `docker-compose-warp.yml.sample` como base actual legacy/dev
- agregar `docker-compose-warp.prod.yml.sample`
- generar ambos samples por default en `init`
- dejar que el TL decida manualmente en el server si toma el sample `prod`
- en el template `prod`, bindear puertos sensibles a `127.0.0.1`

Esto evita ruido innecesario en `.env` y evita abrir una matriz de politicas por servicio cuando el caso de uso real es mucho mas simple.

## Objetivo funcional

El objetivo no es dejar DB/cache/search solo dentro de la red Docker.

El objetivo es:

- que sigan siendo accesibles desde el host del server
- que se puedan usar por CLI al entrar por SSH
- que no queden publicados en `0.0.0.0`
- que la app siga resolviendo por la red Docker interna como hoy

En otras palabras:

- **dev/legacy**: comportamiento actual
- **prod**: mismos servicios, pero accesibles solo por `127.0.0.1`

## Diferencia operativa entre los dos perfiles

### `docker-compose-warp.yml.sample`

Sigue representando el contrato actual de desarrollo/legacy:

- MySQL publicado como hoy
- Redis/Valkey publicado como hoy
- OpenSearch publicado como hoy

Esto preserva compatibilidad y evita romper flujos existentes.

### `docker-compose-warp.prod.yml.sample`

Representa el contrato endurecido para server:

- MySQL accesible por `127.0.0.1`
- Redis/Valkey accesible por `127.0.0.1`
- OpenSearch accesible por `127.0.0.1`
- no accesibles desde Internet salvo que otra capa los reexponga

Esto permite:

- `mysql -h 127.0.0.1 -P ...`
- `redis-cli -h 127.0.0.1 -p ...`
- `curl http://127.0.0.1:9200`

sin dejar los puertos en escucha publica.

## Problema actual

Hoy los templates actuales publican:

- MySQL con host port explicito
- Redis con host port aleatorio
- OpenSearch con host ports aleatorios

Como usan `ports:` sin bind de loopback, Docker los publica en `0.0.0.0`.

Consecuencia:

- accesibles desde el host local
- pero tambien accesibles desde otras interfaces del server

Para un server de produccion, ese default es demasiado permisivo.

## Alcance tecnico

La RFC cubre:

- templates Compose
- seleccion del compose correcto desde `init`
- seleccion equivalente desde `gandalf`
- documentacion operativa

La RFC **no** propone:

- cambiar hostnames internos
- cambiar puertos internos
- cambiar `mysql`, `redis-cache`, `redis-session`, `redis-fpc`, `elasticsearch`
- introducir una matriz compleja de `DB_EXPOSURE/CACHE_EXPOSURE/SEARCH_EXPOSURE`

## Propuesta tecnica

### 1. Mantener el compose actual como legacy/dev

Se mantiene:

- `docker-compose-warp.yml.sample`

como base actual para desarrollo o compatibilidad historica.

No hace falta endurecerla ni meter condicionales nuevas ahi.

## 2. Agregar un compose especifico de produccion

Agregar:

- `docker-compose-warp.prod.yml.sample`

Este template debe ser equivalente al stack actual, pero con los servicios internos publicados solo a loopback.

Ejemplos deseados:

### MySQL en prod

```yaml
mysql:
  ports:
    - "127.0.0.1:${DATABASE_BINDED_PORT}:3306"
```

### Redis cache en prod

```yaml
redis-cache:
  ports:
    - "127.0.0.1:${REDIS_CACHE_BINDED_PORT}:6379"
```

### Redis session en prod

```yaml
redis-session:
  ports:
    - "127.0.0.1:${REDIS_SESSION_BINDED_PORT}:6379"
```

### Redis fpc en prod

```yaml
redis-fpc:
  ports:
    - "127.0.0.1:${REDIS_FPC_BINDED_PORT}:6379"
```

### OpenSearch en prod

```yaml
elasticsearch:
  ports:
    - "127.0.0.1:${SEARCH_HTTP_BINDED_PORT}:9200"
    - "127.0.0.1:${SEARCH_TRANSPORT_BINDED_PORT}:9300"
```

Con esto:

- el servicio sigue accesible por CLI desde el server
- no queda escuchando en interfaces externas

### 3. Generar ambos samples sin pedir decision en setup

La decision de usar `prod` no deberia bloquear `init`.

La propuesta es:

- `init` genera siempre `docker-compose-warp.yml.sample`
- `init` genera siempre `docker-compose-warp.prod.yml.sample`
- `docker-compose-warp.yml` sigue naciendo desde el sample `dev/legacy`
- el TL decide manualmente si en server quiere copiar o tomar el sample `prod`

Esto desacopla:

- la preparacion del proyecto
- de la decision operativa final del server

Y evita meter preguntas extra en el wizard para un caso que no siempre aplica.

### 4. Agregar variables de host port explicitas donde hoy no existen

Para que el template `prod` sea reproducible, Redis y Search no deberian depender de host ports aleatorios.

Conviene introducir variables nuevas para el perfil `prod`:

- `REDIS_CACHE_BINDED_PORT`
- `REDIS_SESSION_BINDED_PORT`
- `REDIS_FPC_BINDED_PORT`
- `SEARCH_HTTP_BINDED_PORT`
- `SEARCH_TRANSPORT_BINDED_PORT`

MySQL ya tiene:

- `DATABASE_BINDED_PORT`

Estas variables no necesitan forzarse en el perfil legacy/dev si hoy el contrato no las usa.

## 5. Mantener la red interna intacta

No conviene cambiar:

- `mysql:3306`
- `redis-cache:6379`
- `redis-session:6379`
- `redis-fpc:6379`
- `elasticsearch:9200`

La app debe seguir consumiendo los servicios internos como hoy.

Esta RFC solo cambia la exposicion hacia el host.

## Archivos afectados

### Nuevos archivos

- `.warp/setup/.../tpl/docker-compose-warp.prod.yml.sample` o path equivalente segun el ensamblado actual del compose

Como Warp hoy compone servicios por fragmentos, probablemente el resultado correcto no sea un unico archivo mantenido a mano, sino una variante `prod` de los fragments afectados.

Eso implica definir claramente como se ensambla el compose final `prod`.

### Templates a revisar

- `.warp/setup/mysql/tpl/database.yml`
- `.warp/setup/mysql/tpl/database_custom.yml`
- `.warp/setup/mysql/tpl/database_arm.yml`
- `.warp/setup/mysql/tpl/database_mysql.yml`
- `.warp/setup/redis/tpl/redis_cache.yml`
- `.warp/setup/redis/tpl/redis_session.yml`
- `.warp/setup/redis/tpl/redis_fpc.yml`
- `.warp/setup/elasticsearch/tpl/elasticsearch.yml`

### Setup y generacion de samples

- `.warp/setup/init/*`
- `.warp/setup/init/gandalf.sh`
- `.warp/setup/init/gandalf-validations.sh`

## Tooling auxiliar a revisar

Algunos comandos hoy asumen que los puertos estan publicados al host.

Hay que revisar especialmente:

- `.warp/bin/mysql.sh`
- `.warp/bin/elasticsearch.sh`
- `.warp/bin/memory.sh`

En el perfil `prod` eso igual deberia seguir funcionando, porque el host port existira, solo que en `127.0.0.1`.

O sea:

- el impacto es mucho menor que en un modelo `docker-only`
- no deberia requerir grandes cambios de tooling

## Compatibilidad legacy

Este enfoque es mas legacy-compatible que introducir politicas por capability.

Motivos:

- el compose actual no cambia
- los proyectos viejos siguen igual
- el perfil `prod` es opt-in
- la complejidad queda en la seleccion del compose y no en cientos de ramas en templates y `.env`

Tambien mete menos ruido porque evita:

- `DB_EXPOSURE`
- `CACHE_EXPOSURE`
- `SEARCH_EXPOSURE`
- y variantes por servicio

## Riesgos

1. **Duplicacion de YAML**
   - puede haber repeticion entre `dev` y `prod`

2. **Ensamblado de fragments**
   - Warp no trabaja solo con un archivo compose monolitico; hay que definir bien como nace la variante `prod`

3. **Herramientas externas**
   - clientes remotos que hoy conecten a MySQL/Redis/Search desde fuera del host dejaran de poder hacerlo

4. **Confundir “no publico” con “aislado”**
   - bindear a `127.0.0.1` reduce exposicion, pero no equivale a esconder el servicio de otros procesos del mismo host

## Plan de implementacion recomendado

1. Definir el mecanismo de seleccion de compose `dev` vs `prod`.
2. Crear variante `prod` para MySQL, Redis y Search con binds a `127.0.0.1`.
3. Agregar variables de host port explicitas para Redis y Search.
4. Adaptar `init` y `gandalf` para generar ambos samples por default.
5. Actualizar documentacion y ayudas CLI donde se asuma exposicion publica.

## Validacion minima

Ademas de la validacion base del repo, conviene probar:

1. `dev` genera el compose actual sin cambios de comportamiento.
2. `prod` genera bindings `127.0.0.1:...` para MySQL.
3. `prod` genera bindings `127.0.0.1:...` para Redis.
4. `prod` genera bindings `127.0.0.1:...` para OpenSearch.
5. desde el mismo server funcionan:
   - `mysql -h 127.0.0.1 -P ...`
   - `redis-cli -h 127.0.0.1 -p ...`
   - `curl http://127.0.0.1:...`
6. desde otra maquina no hay acceso a esos puertos.

## Resultado esperado

Al cerrar este RFC, Warp deberia permitir dos perfiles claros:

- `docker-compose-warp.yml.sample`
  - legado/desarrollo

- `docker-compose-warp.prod.yml.sample`
  - servicios internos accesibles por el host local del server
  - no accesibles desde Internet

Ese balance es el correcto para este caso: **mantener operabilidad por SSH sin dejar MySQL, Redis y Search abiertos al mundo**.
