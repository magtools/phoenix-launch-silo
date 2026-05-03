# RFC: soporte Warp para OpenSearch 3.1

## Decision propuesta

**Si, conviene agregar soporte explicito a OpenSearch 3.1 en Warp**, pero siguiendo el mismo criterio aplicado en `features/warp-valkey.md`:

- mantener el contrato externo historico donde ya existe
- desacoplar el contrato interno real del engine
- no depender de cambios manuales en proyectos
- no montar arboles completos de configuracion cuando solo se necesitan archivos puntuales

La recomendacion es:

- mantener el nombre de servicio `elasticsearch`
- mantener compatibilidad con variables legacy `ES_*`
- mantener las variables canonicas `SEARCH_*`
- exponer `3.1.x` como version seleccionable de OpenSearch en `init`
- hacer que `gandalf` use el mismo catalogo canonico de versiones
- dejar de montar `./.warp/docker/config/opensearch` completa
- mapear solo los archivos o directorios realmente requeridos por la imagen

En otras palabras: **no hace falta renombrar la capa "elasticsearch" a "opensearch"**, pero si hace falta volver explicito el contrato interno de runtime para que Warp pueda arrancar OpenSearch 3.1 de forma reproducible.

## Alcance funcional

Este RFC cubre el soporte de Warp para:

- `warp init`
- `warp init --mode-gandalf`
- templates de `docker-compose-warp.yml`
- archivos base de configuracion OpenSearch
- variables generadas en `.env.sample` / `.env`

Este RFC **no** cambia todavia el default global de OpenSearch en todos los proyectos ni declara que cualquier stack Magento quede automaticamente validado con 3.1.

El objetivo es que Warp pueda:

- seguir funcionando con OpenSearch 2.x en proyectos existentes
- ofrecer OpenSearch 3.1 como opcion real de setup, sin retoques manuales
- mantener el host historico `elasticsearch:9200`
- preparar una base de configuracion minima y controlada para OpenSearch

## Contexto actual

### Lo que ya esta preparado

Hay base parcial para OpenSearch:

- `.warp/variables.sh` ya declara `WARP_SEARCH_ENGINES=("opensearch" "elasticsearch")`
- `.warp/variables.sh` ya define `WARP_SEARCH_OPENSEARCH_IMAGE_REPO="opensearchproject/opensearch"`
- `.warp/setup/elasticsearch/elasticsearch.sh` ya deja elegir `opensearch|elasticsearch`
- `.warp/lib/app_context.sh` ya usa `opensearch` como engine recomendado
- `.warp/bin/search.sh` ya soporta lectura canonica desde `SEARCH_*` y desde `env.php`

La base existe, pero hoy el soporte local sigue siendo **incompleto**.

### Donde hoy se rompe el soporte real

El soporte actual no alcanza para OpenSearch 3.1 sin cambios manuales:

1. **Catalogo de versiones**
   - `.warp/variables.sh`

   Hoy solo sugiere:

   - `2.19.5`
   - `2.12.0`

   No existe una opcion canonica `3.1.x`.

2. **Template de compose**
   - `.warp/setup/elasticsearch/tpl/elasticsearch.yml`

   Hoy hardcodea paths de OpenSearch y ademas monta:

   - `./.warp/docker/config/opensearch:/usr/share/opensearch/config`

   Eso fuerza el arbol completo de config dentro del contenedor.

3. **Instalacion de plugin en runtime**
   - `.warp/setup/elasticsearch/tpl/elasticsearch.yml`

   Hoy hace:

   - `opensearch-plugin install analysis-phonetic`

   en el arranque del contenedor.

4. **Gandalf**
   - `.warp/setup/init/gandalf.sh`
   - `.warp/setup/init/gandalf-validations.sh`

   Hoy `gandalf`:

   - asume `SEARCH_ENGINE=opensearch`
   - no escribe `SEARCH_VERSION` ni `SEARCH_IMAGE`
   - valida `--elasticsearch=` contra una lista legacy que no coincide con `WARP_SEARCH_*`

5. **Config base faltante en el repo**
   - el template monta `./.warp/docker/config/opensearch`
   - pero ese arbol no existe en este repo base

   Eso deja a `init` dependiendo de archivos creados o copiados fuera del contrato visible de Warp.

## Problema principal de configuracion

El requisito de este RFC es correcto: **no conviene seguir montando toda la carpeta de configuracion**.

Motivos:

- arrastra archivos legacy entre majors
- hace opaco que archivos necesita realmente Warp
- aumenta riesgo de incompatibilidades en `keystore`, plugins o subdirectorios auxiliares
- complica separar configuracion base de estado mutable

En OpenSearch 3.1 esto es especialmente sensible porque el salto de major vuelve mas fragil el reuso ciego de configuracion y data heredadas.

## Decision de compatibilidad

### Mantener nombre de servicio `elasticsearch`

Se recomienda **mantener**:

- servicio Compose `elasticsearch`
- hostname `elasticsearch`
- `SEARCH_HOST=elasticsearch`
- configuraciones Magento/ElasticSuite que ya apuntan a `elasticsearch:9200`

Motivo:

- `.warp/bin/magento.sh` ya escribe `smile_elasticsuite_core_base_settings/es_client/servers elasticsearch:9200`
- `.warp/lib/service_context.sh` ya usa `elasticsearch` como host por defecto en modo local
- cambiar el hostname abriria una migracion transversal innecesaria

El engine real puede ser OpenSearch 3.1 aunque el contrato externo siga usando `elasticsearch`.

### Mantener variables legacy `ES_*`

Conviene **mantener**:

- `ES_VERSION`
- `ES_MEMORY`
- `ES_PASSWORD`

Y a la vez seguir poblando:

- `SEARCH_MODE`
- `SEARCH_ENGINE`
- `SEARCH_VERSION`
- `SEARCH_IMAGE`
- `SEARCH_SCHEME`
- `SEARCH_HOST`
- `SEARCH_PORT`

Motivo:

- `ES_*` siguen siendo parte del contrato historico del repo
- `SEARCH_*` ya son la capa canonica moderna
- ambos contratos ya conviven hoy y no hace falta romper ninguno

### Mantener `opensearch` como engine recomendado

No veo razon para cambiar:

- `WARP_SEARCH_ENGINE_DEFAULT="opensearch"`

Pero **no** recomiendo cambiar todavia el default tag global a `3.1.x` hasta que existan smokes reales sobre el flujo generado por Warp.

## Propuesta tecnica

### 1. Extender el catalogo canonico de search

En `.warp/variables.sh`:

- agregar `3.1.x` a `WARP_SEARCH_OPENSEARCH_TAGS_SUGGESTED`
- mantener `WARP_SEARCH_OPENSEARCH_TAG_DEFAULT` en `2.19.5` por ahora
- dejar `2.12.0` como legacy/default operativo para proyectos antiguos solo donde corresponda

Recomendacion concreta:

- usar una entrada `3.1.0` o `3.1.1` segun el tag que el equipo valide manualmente
- no promoverla a default en esta primera etapa

Esto habilita `init` interactivo sin forzar adopcion masiva.

### 2. Introducir un helper canonico de runtime search

Conviene agregar una capa helper para search local, similar al enfoque propuesto en `warp-valkey`, que resuelva desde `SEARCH_ENGINE`:

- `SEARCH_CONTAINER_NAME`
- `SEARCH_CONTAINER_USER`
- `SEARCH_DATA_PATH`
- `SEARCH_CONFIG_PATH`
- `SEARCH_PLUGIN_BIN`
- `SEARCH_SERVER_BIN`
- `SEARCH_HOST_CONFIG_FILE`
- `SEARCH_HOST_SECURITY_DIR`

Valores iniciales propuestos para `opensearch`:

- `SEARCH_CONTAINER_NAME=elasticsearch`
- `SEARCH_CONTAINER_USER=opensearch`
- `SEARCH_DATA_PATH=/usr/share/opensearch/data`
- `SEARCH_CONFIG_PATH=/usr/share/opensearch/config/opensearch.yml`
- `SEARCH_PLUGIN_BIN=/usr/share/opensearch/bin/opensearch-plugin`
- `SEARCH_SERVER_BIN=/usr/share/opensearch/bin/opensearch`
- `SEARCH_HOST_CONFIG_FILE=./.warp/docker/config/opensearch/opensearch.yml`
- `SEARCH_HOST_SECURITY_DIR=./.warp/docker/config/opensearch/opensearch-security`

Importante:

- esto **no implica** persistir todas esas variables en `.env`
- Warp puede resolverlas en setup/runtime
- el objetivo es sacar paths hardcodeados de templates y scripts

### 3. Dejar de montar el arbol completo `config/`

En `.warp/setup/elasticsearch/tpl/elasticsearch.yml` no conviene seguir usando:

- `./.warp/docker/config/opensearch:/usr/share/opensearch/config`

La recomendacion es mapear solo lo requerido.

Opcion base propuesta:

- `./.warp/docker/config/opensearch/opensearch.yml:/usr/share/opensearch/config/opensearch.yml`

Y solo agregar mounts adicionales cuando sean realmente necesarios, por ejemplo:

- `./.warp/docker/config/opensearch/opensearch-security:/usr/share/opensearch/config/opensearch-security`

si el stack sigue requiriendo ese directorio.

No recomiendo montar:

- `opensearch.keystore`
- `performance-analyzer/`
- `notifications/`
- `observability/`

salvo que Warp los genere o los valide explicitamente.

La regla deberia ser:

- **archivo puntual por default**
- **directorio puntual solo si hay una necesidad funcional clara**

### 4. Versionar una configuracion minima en el repo

El repo necesita una base visible para OpenSearch, porque hoy el template referencia un path que no existe.

Se recomienda agregar al menos:

- `.warp/setup/elasticsearch/config/opensearch/opensearch.yml`

Y que `init`/`gandalf` copien esa base a:

- `.warp/docker/config/opensearch/opensearch.yml`

Solo si el archivo destino no existe.

Si el stack requiere configuracion de security, entonces tambien versionar:

- `.warp/setup/elasticsearch/config/opensearch/opensearch-security/...`

Pero sin copiar arboles innecesarios.

La RFC no exige que toda la configuracion viva inline en el template. Lo que exige es que Warp controle la base de config y no dependa de cambios manuales invisibles.

### 5. Unificar `init` y `gandalf` sobre el mismo contrato

`.warp/setup/elasticsearch/elasticsearch.sh` ya usa helpers canonicos de version.

`gandalf` debe alinearse.

Cambios propuestos:

- hacer que `.warp/setup/init/gandalf-validations.sh` valide contra `WARP_SEARCH_*` y no contra una lista fija legacy
- hacer que `.warp/setup/init/gandalf.sh` escriba tambien:
  - `SEARCH_VERSION`
  - `SEARCH_IMAGE`
  - `ES_PASSWORD`
- resolver `SEARCH_ENGINE` y `SEARCH_IMAGE` igual que en `init`
- permitir que `gandalf` pueda recibir una version OpenSearch 3.1 valida sin caer en validaciones de Elasticsearch historico

El objetivo es que el mismo setup resulte coherente tanto en wizard interactivo como en modo no interactivo.

### 6. Revisar la instalacion de `analysis-phonetic`

La instalacion opportunistic en cada arranque es fragil.

Problemas:

- agrega dependencia de red al boot
- vuelve no determinista el primer start
- mezcla provisionamiento de imagen con arranque del servicio

Opciones recomendadas, en este orden:

1. mantener plugin runtime solo como compatibilidad temporal, pero moverlo detras de una variable explicita
2. preferir una imagen derivada con plugin preinstalado
3. o bien permitir OpenSearch 3.1 sin plugin por defecto y documentar el opt-in del plugin

Para esta RFC, la decision minima deberia ser:

- no asumir que el plugin se instala bien solo porque el contenedor arranco
- dejar claro si OpenSearch 3.1 depende de `analysis-phonetic` o no

### 7. Tratar data y config como concerns distintos

El volumen actual:

- `./.warp/docker/volumes/elasticsearch/data:/usr/share/opensearch/data`

mezcla una convencion heredada con el data path real de OpenSearch.

La recomendacion es dejar el host path alineado con el data path real de OpenSearch:

- usar `.warp/docker/volumes/elasticsearch/data`
- el data path interno debe resolverse por helper
- un upgrade 2.x -> 3.1 en dev debe preferir data limpia y reindex

Warp no deberia insinuar que migrar el volumen existente es seguro por defecto.

## Impacto en archivos

### `.warp/variables.sh`

Debe:

- agregar la version `3.1.x` al catalogo de OpenSearch
- mantener `2.19.5` como default hasta nuevo smoke

### `.warp/setup/elasticsearch/elasticsearch.sh`

Debe:

- seguir usando `SEARCH_*` como contrato canonico
- elegir version 3.1 desde el catalogo
- dejar preparado el copiado de config base minima

### `.warp/setup/elasticsearch/tpl/elasticsearch.yml`

Debe dejar de asumir:

- montaje completo de `./.warp/docker/config/opensearch`
- instalacion implicita y silenciosa de plugin como unica estrategia

Debe pasar a usar:

- mounts puntuales
- variables/helper de runtime search

### `.warp/setup/elasticsearch/tpl/elasticsearch.env`

Debe reflejar:

- el nuevo catalogo sugerido
- el contrato canonico `SEARCH_*`
- cualquier nueva variable minima necesaria para config/plugin

### `.warp/setup/init/gandalf.sh`

Debe:

- generar el mismo bloque de search que `init`
- escribir `SEARCH_VERSION` y `SEARCH_IMAGE`
- poblar `ES_PASSWORD` si el template lo requiere

### `.warp/setup/init/gandalf-validations.sh`

Debe:

- dejar de validar search contra una lista fija de versiones legacy
- usar el mismo origen de verdad que `init`

### Nuevos archivos esperables

Como minimo:

- `.warp/setup/elasticsearch/config/opensearch/opensearch.yml`

Probablemente tambien:

- `.warp/docker/config/opensearch/.gitkeep` o mecanismo equivalente si Warp necesita crear la carpeta en `init`

Si termina siendo necesario security:

- `.warp/setup/elasticsearch/config/opensearch/opensearch-security/*`

pero solo si Warp va a administrarlo realmente.

## Decision sobre el mapping de config

La decision propuesta para esta RFC es:

- **por default, mapear solo `opensearch.yml`**
- evaluar `opensearch-security/` por separado
- no montar `config/` completa

Razon:

- es el minimo cambio que baja riesgo
- hace visible que parte de la configuracion es realmente contrato Warp
- evita transportar basura legacy entre OpenSearch 2.x y 3.x

Si algun proyecto requiere mas archivos, ese caso debe modelarse como excepcion explicita y no como comportamiento default del framework.

## Compatibilidad esperada con proyectos

Este RFC asume:

- proyectos existentes con `SEARCH_ENGINE=opensearch` y `ES_VERSION=2.12.0` deben seguir pudiendo operar
- proyectos nuevos o ajustados deberian poder seleccionar `3.1.x` desde `init`
- proyectos que hoy dependen de cambios manuales en `../eprivee` deben poder converger al contrato oficial de Warp

No se propone:

- renombrar el comando `warp elasticsearch`
- renombrar el servicio Docker a `opensearch`
- forzar migracion automatica de data

## Riesgos

1. **Plugin `analysis-phonetic`**
   - si el plugin no matchea exactamente la version del core, el arranque puede fallar

2. **Security config heredada**
   - si un proyecto depende de archivos hoy copiados a mano, pasar a mounts puntuales puede dejar al descubierto dependencias no modeladas

3. **Gandalf divergente**
   - si no se unifica con `init`, OpenSearch 3.1 podria “funcionar” solo en wizard interactivo

4. **Volumen de data legado**
   - reusar indices 2.x sobre 3.1 puede ser fuente de fallos aunque el contenedor arranque

## Plan de implementacion recomendado

1. Agregar RFC y acordar el contrato final de mounts puntuales.
2. Extender catalogo `WARP_SEARCH_OPENSEARCH_*` con `3.1.x`.
3. Versionar config minima de OpenSearch en `.warp/setup/elasticsearch/config/opensearch/`.
4. Parametrizar template `elasticsearch.yml` para mounts puntuales y runtime canonico.
5. Alinear `gandalf` y `gandalf-validations` con el mismo catalogo y mismas variables.
6. Definir estrategia del plugin `analysis-phonetic`.
7. Hacer smokes de `init`/`gandalf`/`start`.

## Validacion minima

Ademas de la validacion base del repo:

1. `./warp --help`
2. `./warp init --help`
3. `./warp start --help`
4. `./warp stop --help`
5. `./warp info --help`
6. `./warp docker ps`

Conviene agregar para este feature:

1. `./warp init` eligiendo `SEARCH_ENGINE=opensearch` y tag `3.1.x`
2. `./warp init --mode-gandalf ... --elasticsearch=<tag-3.1.x>`
3. inspeccion del `docker-compose-warp.yml` generado para verificar mounts puntuales
4. smoke de `./warp start`
5. verificacion de que el servicio siga resolviendo como `elasticsearch:9200`
6. verificacion de que `.env` incluya `SEARCH_VERSION` y `SEARCH_IMAGE` tambien en `gandalf`

## Resultado esperado

Al cerrar este RFC, Warp deberia quedar en condiciones de:

- ofrecer OpenSearch 3.1 de forma opt-in
- generar la configuracion correcta desde `init` y `gandalf`
- dejar de depender de montajes manuales de carpetas completas
- preservar el contrato historico que consumen Magento y scripts legacy

Ese es el mismo patron que ya se aplico con Valkey: **compatibilidad externa estable, runtime interno parametrizado**.
