# RFC: `health` operativo para `db`, `cache` y `search`

## Decision propuesta

**No conviene sobrecargar `info`**, porque hoy `warp db info`, `warp cache info` y `warp search info` ya cumplen una funcion de **config/connectivity info** y esa semantica sigue siendo util.

La recomendacion es:

- mantener `info` como salida orientada a configuracion, endpoint y runtime declarado;
- agregar un subcomando nuevo orientado a **estado real resumido del servicio**;
- usar el nombre canonico `health`:
  - `warp db health`
  - `warp cache health`
  - `warp search health`

La intencion de este RFC es cubrir justo el caso de uso operativo:

- ver rapido si el servicio responde;
- ver si contiene datos;
- ver una senal minima de que se esta poblando;
- evitar dumps verbosos o salidas masivas.

En otras palabras: **`info` describe como esta configurado el servicio; `health` muestra que esta pasando realmente en el servicio**.

## Objetivo funcional

Warp necesita una vista corta y accionable para infraestructura interna o externa, sin obligar al operador a entrar a cada CLI nativo.

El objetivo del nuevo comando es responder, con poca salida, preguntas como:

- `db`: que bases existen, cuantas tablas tiene cada una y si el motor responde;
- `cache`: que DB indices parecen estar en uso, con una descripcion humana breve y senales simples de volumen/actividad;
- `search`: que indices existen, cuantos docs tienen y si el cluster esta sano o poblado.

Esto debe funcionar sin romper el contrato actual:

- `warp db info` sigue existiendo;
- `warp cache info` sigue existiendo;
- `warp search info` sigue existiendo.

## Por que `health` y no `info`

`info` hoy ya esta asociado en el repo a:

- variables del entorno;
- host/puertos;
- version;
- paths;
- metadata de configuracion.

Si se mezcla con introspeccion de contenido real del servicio, `info` pasaria a tener dos responsabilidades:

1. mostrar configuracion declarada;
2. inspeccionar estado runtime.

Eso complica UX, testing y compatibilidad.

`health` comunica mejor la intencion operativa:

- consultar estado;
- leer una muestra minima del contenido;
- detectar si hay vida, datos o poblacion;
- sin prometer diagnostico profundo.

## Alcance funcional

Este RFC propone agregar:

- `warp db health`
- `warp cache health`
- `warp search health`

Tambien puede evaluarse mas adelante un agregador:

- `warp health`

Pero **no forma parte del alcance inicial**. Primero conviene estabilizar los tres subcomandos por capability.

## Principios de diseno

### 1. Salida corta

La salida debe ser breve y humana.

Regla propuesta:

- una cabecera de estado general;
- un resumen corto por servicio o scope;
- como maximo una lista corta de entidades;
- sin payloads JSON crudos por default.

No conviene que `health` se convierta en:

- `SHOW FULL TABLES` completo;
- `KEYS *`;
- `_cat/indices` sin filtro y sin limite.

### 2. Lectura segura

`health` debe ser **read-only**.

No debe:

- limpiar caches;
- crear indices;
- disparar reindex;
- modificar settings;
- ejecutar repair.

### 3. Operativo tanto en local como en external

Igual que otros comandos modernos del repo, `health` debe respetar:

- modo local por contenedor;
- modo external por variables canonicas del servicio.

Esto aplica a:

- `DB` / `MYSQL_*` / `DATABASE_*`
- `CACHE_*`
- `SEARCH_*`

### 4. Capacidad primero, engine despues

La UX visible debe seguir el dominio canonico:

- `db`
- `cache`
- `search`

Y no centrar la interfaz en nombres legacy:

- `mysql`
- `redis`
- `elasticsearch`

El engine puede informarse en la salida, pero no debe dominar el contrato CLI.

## Comportamiento propuesto

## `warp db health`

### Salida esperada

Resumen sugerido:

- engine/version
- mode: `local` o `external`
- endpoint efectivo
- health basico del motor
- listado corto de bases de datos
- count de tablas por base

Ejemplo conceptual:

```text
DB health: ok
Engine: mariadb 10.11
Mode: local
Endpoint: mysql:3306

Databases:
- magento: 412 tables
- magento_test: 0 tables
- information_schema: system
```

### Regla de contenido

No conviene listar todas las tablas.

La unidad de resumen debe ser:

- base de datos;
- cantidad de tablas;
- marcador simple de sistema/app cuando aplique.

### Health minimo

La salud minima puede basarse en:

- conectividad;
- `SELECT 1`;
- posibilidad de enumerar bases;
- posibilidad de contar tablas por schema.

Estados orientativos:

- `ok`: responde y permite leer metadata;
- `warn`: responde pero no hay bases de app o no se pueden contar todas;
- `error`: no responde o autenticacion invalida.

## `warp cache health`

### Salida esperada

Resumen sugerido:

- engine/version
- mode: `local` o `external`
- endpoint por scope
- health basico por scope
- DB index efectivo por scope
- breve descripcion humana del uso esperado
- una senal minima de ocupacion

Ejemplo conceptual:

```text
CACHE health: ok
Engine: valkey 8
Mode: local

Scopes:
- cache   db=0   ok   keys=1284   app cache
- fpc     db=1   ok   keys=320    full page cache
- session db=2   ok   keys=54     sessions
```

### Regla de contenido

La salida no debe listar keys.

La unidad de resumen debe ser:

- scope canonico;
- DB index usado;
- count aproximado o simple de keys;
- descripcion humana corta.

Descripcion sugerida:

- `cache`: `app cache`
- `fpc`: `full page cache`
- `session`: `sessions`

### Health minimo

La salud minima puede basarse en:

- `PING`;
- lectura de version;
- lectura de `INFO keyspace` o equivalente;
- mapeo scope -> DB index efectivo.

Estados orientativos:

- `ok`: responde y se pudo inspeccionar el keyspace;
- `warn`: responde pero el DB esperado esta vacio o no aparece;
- `error`: no responde o credenciales invalidas.

Nota:

- para cache vacio, `warn` no siempre significa problema;
- si el objetivo es mostrar “se esta poblando”, la salida debe priorizar claridad antes que severidad agresiva.

Por eso conviene contemplar mensajes tipo:

- `ok (empty)`
- `ok (in use)`
- `warn (db not detected)`

## `warp search health`

### Salida esperada

Resumen sugerido:

- engine/version
- mode: `local` o `external`
- endpoint efectivo
- cluster health
- cantidad corta de indices visibles
- docs count por indice

Ejemplo conceptual:

```text
SEARCH health: ok
Engine: opensearch 3.1
Mode: local
Endpoint: http://elasticsearch:9200
Cluster: yellow

Indices:
- magento2_product_1_v1: 15420 docs
- magento2_category_1_v1: 128 docs
- magento2_thesaurus_1: 0 docs
```

### Regla de contenido

No conviene mostrar mappings ni settings completos.

La unidad de resumen debe ser:

- indice;
- docs count;
- estado si esta disponible;
- limite de filas.

Conviene limitar la salida por default a una cantidad baja, por ejemplo:

- top 10 indices por nombre;
- o top 10 por docs count.

### Health minimo

La salud minima puede basarse en:

- `GET /`
- `GET /_cluster/health`
- `GET /_cat/indices`

Estados orientativos:

- `ok`: endpoint responde y el cluster devuelve health usable;
- `warn`: endpoint responde pero cluster `yellow` o sin indices;
- `error`: endpoint no responde, auth falla o cluster no puede consultarse.

Importante:

- en search, `yellow` no siempre implica incidencia local grave;
- por eso `yellow` conviene mapearlo a `warn`, no a `error`.

## Contrato UX propuesto

## Salida por defecto

Por default, `health` debe ser corta.

No recomiendo agregar flags de verbosidad en la primera etapa.

Si despues hiciera falta, se puede evaluar:

- `--json`
- `--verbose`
- `--limit=<n>`

Pero no hace falta abrir ese frente en la RFC inicial.

## Exit code

Regla propuesta:

- `0`: estado consultado con exito y sin error duro;
- `1`: fallo operativo real del chequeo.

Si un servicio responde pero esta vacio o en `warn`, no necesariamente debe devolver `1`.

La idea es que el comando sirva tanto para humanos como para automatizacion basica, sin volver inestable el contrato por estados intermedios esperables.

## Relacion con el codigo actual

Este RFC se apoya en que ya existen comandos base y helpers relacionados:

- [`.warp/bin/db.sh`](/srv2/www/htdocs/66/warp-engine/.warp/bin/db.sh)
- [`.warp/bin/mysql.sh`](/srv2/www/htdocs/66/warp-engine/.warp/bin/mysql.sh)
- [`.warp/bin/cache.sh`](/srv2/www/htdocs/66/warp-engine/.warp/bin/cache.sh)
- [`.warp/bin/redis.sh`](/srv2/www/htdocs/66/warp-engine/.warp/bin/redis.sh)
- [`.warp/bin/search.sh`](/srv2/www/htdocs/66/warp-engine/.warp/bin/search.sh)
- [`.warp/bin/elasticsearch.sh`](/srv2/www/htdocs/66/warp-engine/.warp/bin/elasticsearch.sh)
- [`.warp/lib/service_context.sh`](/srv2/www/htdocs/66/warp-engine/.warp/lib/service_context.sh)
- [`.warp/lib/cache_engine.sh`](/srv2/www/htdocs/66/warp-engine/.warp/lib/cache_engine.sh)
- [`.warp/lib/search_engine.sh`](/srv2/www/htdocs/66/warp-engine/.warp/lib/search_engine.sh)

La idea no es reemplazar `info`, sino construir arriba de estas capas una lectura runtime minima y consistente.

## Implementacion sugerida

### 1. Mantener `info` como esta

No romper:

- `warp db info`
- `warp cache info`
- `warp search info`

Si hace falta, solo ajustar help para dejar explicita la diferencia:

- `info`: configuracion y conectividad declarada
- `health`: estado real resumido del servicio

### 2. Agregar subcomandos `health`

Archivos esperables:

- ampliar dispatch en `db.sh`
- ampliar dispatch en `redis.sh` o capa canonica `cache`
- ampliar dispatch en `elasticsearch.sh` o capa canonica `search`
- actualizar `*_help.sh`

### 3. Reusar CLIs nativos con consultas minimas

Sin abrir shells interactivos ni comandos destructivos:

- DB:
  - consulta de schemas
  - count de tablas por schema
- Cache:
  - `PING`
  - `INFO server`
  - `INFO keyspace`
- Search:
  - `GET /`
  - `GET /_cluster/health`
  - `GET /_cat/indices`

### 4. Traducir datos tecnicos a salida humana

Este punto es importante.

No alcanza con imprimir la respuesta cruda del motor.

Warp deberia traducir a un resumen compacto:

- nombre
- cantidad
- estado
- breve descripcion funcional

## No objetivos

Este RFC no propone:

- un monitor continuo;
- metricas historicas;
- profiling;
- descubrir automaticamente “que app” creo cada indice o key;
- contar keys con operaciones costosas sobre toda la instancia;
- inspeccion profunda de contenido.

Tampoco propone en esta etapa:

- `warp rabbit health`
- `warp mail health`
- `warp php health`

Aunque el patron podria extenderse despues.

## Riesgos y tradeoffs

1. En cache, algunos contadores de keys pueden ser aproximados o variar segun engine/comando disponible.
2. En search, un cluster `yellow` puede ser normal en entornos locales de un solo nodo.
3. En DB, incluir schemas de sistema puede meter ruido si no se etiquetan claramente.
4. En external mode, el chequeo depende de que el host tenga binarios/cliente disponibles cuando no se use contenedor.

Por eso conviene que la primera version priorice:

- robustez;
- pocas consultas;
- salida estable;
- semantica simple.

## Validacion minima

Si esta RFC se implementa, la validacion minima deberia cubrir:

1. `./warp db info` sigue mostrando configuracion sin introspeccion pesada.
2. `./warp cache info` sigue mostrando configuracion sin introspeccion pesada.
3. `./warp search info` sigue mostrando configuracion sin introspeccion pesada.
4. `./warp db health --help`
5. `./warp cache health --help`
6. `./warp search health --help`
7. smoke local:
   - `./warp db health`
   - `./warp cache health`
   - `./warp search health`
8. smoke external donde aplique:
   - usando `DATABASE_*`, `CACHE_*`, `SEARCH_*`

## Resultado esperado

Warp queda con dos capas claras:

- `info`: como esta configurado el servicio
- `health`: si responde, si tiene contenido y una vista minima de su poblacion/salud

Eso preserva compatibilidad, mejora la operacion diaria y evita mezclar configuracion con introspeccion runtime en un mismo contrato ambiguo.
