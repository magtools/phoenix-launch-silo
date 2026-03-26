# Warp Service Version

## 1. Objetivo

Definir una estrategia única y explícita para seleccionar servicios de infraestructura por:

- dominio canónico: `db`, `cache`, `search`
- motor: `mysql|mariadb`, `redis|valkey`, `elasticsearch|opensearch`
- versión: tag concreta soportada y verificable

El objetivo no es cambiar todavía el comportamiento en código, sino dejar un plan sólido para:

1. eliminar inconsistencias entre wizard, `gandalf`, templates y comandos;
2. desacoplar la selección de servicio del nombre histórico del contenedor;
3. hacer que los defaults apunten a versiones con soporte vigente o razonable;
4. preservar compatibilidad con proyectos ya inicializados.

Contexto de producto:

- Magento representa el caso dominante del ecosistema Warp;
- la apertura a otras apps PHP debe ser gradual;
- la matriz inicial debe optimizar primero Magento y después extenderse a otros stacks cuando exista soporte real.

## 1.1 Dependencia de diseño

Este documento no define un modelo alternativo a `warp-sanitize.md`.

Debe leerse como una extensión específica para versionado de servicios sobre el marco ya aprobado en:

- [warp-sanitize.md](/srv2/www/htdocs/66/warp-engine/features/warp-sanitize.md)

Restricción explícita:

1. `warp-sanitize.md` fija la arquitectura canónica `service / engine / mode`;
2. `warp-service-version.md` solo puede detallar política de motores, versiones, defaults y UX de selección;
3. si aparece una contradicción, prevalece `warp-sanitize.md` hasta que ambos documentos se ajusten explícitamente.

## 2. Problema Actual

Hoy Warp tiene varias fuentes de verdad para versiones:

1. validaciones legacy de `gandalf`;
2. defaults del wizard de `init`;
3. templates que finalmente construyen la imagen;
4. aliases y naming histórico en comandos (`mysql`, `redis`, `elasticsearch`).

Esto genera inconsistencias como:

- el wizard habla de “MySQL” pero en x86 usa `mariadb`;
- `gandalf` valida versiones viejas que no coinciden con los defaults reales;
- `search` ya usa OpenSearch en templates, pero sigue arrastrando listas legacy de Elasticsearch;
- `cache` ya tiene alias `valkey`, pero no existe aún una política única de motor/versionado.

Además, hoy ya existe trabajo previo alineado con `warp-sanitize` en código:

1. contexto canónico por capability en [service_context.sh](/srv2/www/htdocs/66/warp-engine/.warp/lib/service_context.sh)
2. detección/autopoblado legacy -> canónico en [fallback.sh](/srv2/www/htdocs/66/warp-engine/.warp/lib/fallback.sh)
3. ayudas orientadas a `db` y `cache` en:
   - [mysql_help.sh](/srv2/www/htdocs/66/warp-engine/.warp/bin/mysql_help.sh)
   - [redis_help.sh](/srv2/www/htdocs/66/warp-engine/.warp/bin/redis_help.sh)

Por lo tanto, este plan debe partir de esa base y mejorarla, no reemplazarla.

## 3. Principios de Diseño

### 3.1 Dominio canónico vs motor real

La UX debe preguntar por el dominio funcional:

- `db`
- `cache`
- `search`

Esto está alineado con la decisión ya cerrada en `warp-sanitize.md`:

1. `db`
2. `cache`
3. `search`

No se deben introducir dominios alternativos ni volver a centrar el modelo en nombres legacy como `mysql`, `redis` o `elasticsearch`.

Y recién después por:

- motor
- versión

Ejemplos:

- `DB engine/version: mariadb 10.11.x`
- `CACHE engine/version: valkey 8.x`
- `SEARCH engine/version: opensearch 2.x`

Esto evita que el usuario tenga que inferir si un servicio “mysql” en realidad usa MariaDB, o si “elasticsearch” ya migró a OpenSearch.

### 3.2 Compatibilidad hacia atrás

Warp debe mantener compatibilidad con:

- proyectos existentes con variables legacy;
- nombres de contenedor y comandos históricos cuando sea necesario;
- templates ya generados en proyectos productivos.

La compatibilidad debe ser por traducción interna, no por seguir expandiendo nomenclatura ambigua.

Esto queda subordinado a la política ya fijada en `warp-sanitize.md`:

1. read-compat legacy;
2. write canonico;
3. `warp init` genera canonicas + legacy durante transición;
4. help y ejemplos orientados a canónico.

### 3.3 Fuente única de verdad

La matriz de motores, versiones soportadas y defaults debe vivir en una sola capa canónica.

Candidata natural:

- `.warp/variables.sh`

Desde allí deben derivar:

- wizard interactivo;
- validaciones `gandalf`;
- defaults de `.env.sample`;
- validaciones de `switch`;
- mensajes de ayuda y documentación.

Nota de alineación:

La matriz de versionado propuesta aquí no reemplaza el contrato de contexto de `warp-sanitize`.

El encastre esperado es:

1. `warp-sanitize` define:
   - `service`
   - `engine`
   - `mode`
   - variables canónicas
2. `warp-service-version` define:
   - motores disponibles por servicio
   - repositorios de imagen
   - tags sugeridos
   - defaults
   - política de validación de tags

### 3.4 Defaults conservadores pero vigentes

La versión por defecto no debe ser una arbitraria histórica.

Regla propuesta:

1. usar una versión con soporte vigente;
2. preferir la anteúltima menor/LTS estable dentro del motor elegido cuando eso reduzca riesgo de ruptura;
3. si no hay una política clara de “anteúltima”, usar una versión explícitamente marcada como `recommended`.

La idea es evitar:

- defaults EOL;
- saltos demasiado agresivos al último tag recién publicado;
- mezcla de tags viejos solo porque “alguna vez funcionaron”.

### 3.5 Sugerencias curadas y tag manual libre

Warp no debe operar con una whitelist rígida de tags.

La UX objetivo debe combinar:

1. una lista corta de tags sugeridos por Warp;
2. un link visible al repositorio de tags del motor;
3. una opción de ingreso manual de tag.

Regla de comportamiento:

1. si el tag está en la lista sugerida, se acepta;
2. si el tag no está sugerido pero existe realmente en el repo de imagen, también se acepta;
3. si el tag no existe, se rechaza con error claro.

Esto busca evitar dos problemas:

1. encerrar al operador en una whitelist artificial;
2. hacer depender el default únicamente de los “últimos tags” crudos publicados por el registry.

Consecuencia práctica:

- Warp orienta con una selección corta y razonable;
- el operador conserva libertad para usar tags más viejos o específicos;
- la validación real ocurre contra la existencia del tag, no contra una lista fija interna.

### 3.6 Magento-first y apertura gradual

Warp debe tratar Magento como caso rector de esta matriz.

Regla práctica:

1. `recommended`:
   - pensado para proyectos nuevos del caso dominante;
   - en la práctica, hoy debe optimizar primero Magento.
2. `compatibility`:
   - pensado para cubrir versiones concretas de Magento u otras apps PHP que realmente lo requieran;
   - entra cuando exista justificación funcional clara.
3. `legacy/manual`:
   - pensado para proyectos heredados, migraciones o stacks menos frecuentes;
   - no debe arrastrar defaults ni complejizar el flujo principal.

Consecuencia:

- el 99% Magento define el camino principal del wizard;
- otros ecosistemas PHP pueden ir entrando por capas de `compatibility` o `legacy/manual`;
- recién cuando tengan soporte sostenido y smoke equivalentes pueden aspirar a `recommended`.

## 4. Modelo Objetivo

### 4.1 DB

Preguntas objetivo en `warp init`:

1. `Do you want to add a DB service?`
2. `Choose DB engine: mysql | mariadb`
3. `Choose DB version: <lista filtrada por engine>`

Reglas:

- `db` es el dominio canónico;
- `mysql` y `mariadb` son motores;
- la imagen efectiva debe derivarse del motor elegido;
- si se usa `mariadb`, no debe presentarse como “MySQL version” en la UX.

Compatibilidad:

- mantener variables legacy `MYSQL_*` mientras conviva el formato antiguo;
- respetar el write path canónico ya definido en `warp-sanitize.md`;
- extender las variables canónicas con versionado cuando haga falta, por ejemplo:
  - `DB_ENGINE`
  - `DB_VERSION`
  - `DB_IMAGE`

### 4.2 Cache

Preguntas objetivo en `warp init`:

1. `Do you want to add a cache service?`
2. `Choose cache engine: redis | valkey`
3. `Choose cache version: <lista filtrada por engine>`

Alcance:

- aplica a `cache`, `session`, `fpc`;
- el motor debe ser coherente para los tres servicios salvo requerimiento explícito en contrario.

Compatibilidad:

- mantener `warp redis ...` como alias legacy;
- mantener `warp cache ...` como forma canónica;
- permitir que `valkey` sea un alias de engine, no un nuevo dominio separado.

Esto es consistente con la matriz legacy -> canónico ya cerrada en `warp-sanitize.md`.

### 4.3 Search

Preguntas objetivo en `warp init`:

1. `Do you want to add a search service?`
2. `Choose search engine: opensearch | elasticsearch`
3. `Choose search version: <lista filtrada por engine>`

Reglas:

- `search` es el dominio canónico;
- `opensearch` debe ser el default recomendado actual;
- `elasticsearch` queda solo si realmente seguimos soportando imágenes y templates compatibles.

Compatibilidad:

- conservar `warp elasticsearch ...` mientras exista el comando;
- promover `warp search ...` como interfaz canónica.

Esto es consistente con la política de alias ya cerrada en `warp-sanitize.md`.

## 5. Política de Matriz de Versiones

La matriz debe registrar por cada dominio:

1. motor;
2. repositorio de imagen;
3. versiones soportadas;
4. versión default;
5. clasificación visible de producto:
   - `recommended`
   - `compatibility`
   - `legacy/manual`

Ejemplo conceptual:

```bash
DB_ENGINES=("mysql" "mariadb")
DB_ENGINE_DEFAULT="mariadb"
DB_MARIADB_VERSIONS=("10.6.22" "10.6.25" "10.11.x")
DB_MARIADB_VERSION_DEFAULT="10.6.25"
DB_MARIADB_IMAGE_REPO="mariadb"
```

No implica que el formato final deba ser exactamente Bash arrays con ese naming. Sí implica que debe existir una sola representación canónica.

## 6. Criterios para Elegir Defaults

### 6.1 Reglas generales

Un default solo puede proponerse si:

1. la imagen/tag existe;
2. el motor tiene soporte vigente o razonablemente mantenido;
3. el tag no obliga a cambios de compatibilidad no controlados en proyectos nuevos.

La clasificación visible para el operador debe mantenerse simple:

1. `recommended`:
   - opción aconsejada para proyectos nuevos;
   - base natural del default del wizard;
   - debe tener soporte real y smoke en Warp.
2. `compatibility`:
   - opción soportada para versiones de app o proyectos existentes que lo necesiten;
   - no tiene por qué ser el default;
   - debe tener una validación explícita y acotada.
3. `legacy/manual`:
   - opción no recomendada para proyectos nuevos;
   - se mantiene para casos heredados o puntuales;
   - puede requerir selección manual y soporte más limitado.

Regla:

- `default` sigue siendo un atributo técnico;
- normalmente el `default` debe pertenecer a la categoría `recommended`.

### 6.2 Regla práctica recomendada

Para cada motor:

1. mantener como mínimo:
   - una opción `recommended`
   - una opción `compatibility` cuando el ecosistema real la justifique
2. elegir como `default` una versión estable no recién salida;
3. si el motor usa series mayores activas, preferir la anteúltima serie estable o la más conservadora aún soportada.

Esto apunta a:

- evitar defaults demasiado nuevos;
- permitir on-ramp seguro para proyectos nuevos;
- dejar una salida clara para proyectos que necesitan una versión previa.

### 6.4 Política de sugerencias

La lista visible en el wizard no debe intentar mostrar todos los tags del repo.

Regla propuesta:

1. mostrar idealmente 4 o 5 tags sugeridos por motor;
2. si un motor solo tiene 2 o 3 tags razonables para Warp, mostrar solo esos;
3. priorizar tags:
   - vigentes
   - estables
   - útiles para casos reales de Warp
4. incluir siempre una opción `custom tag`;
5. incluir siempre el link al repositorio de tags correspondiente.

Importante:

- “sugerido por Warp” no significa “único permitido”.

### 6.3 Revisión periódica

La matriz debe revisarse en cadencia definida, por ejemplo:

- trimestralmente;
- o cuando una imagen/tag salga de la categoría `recommended` o quede `inactive`.

## 7. Plan de Acción

Precondición:

- las fases de este documento deben ejecutarse sobre la base de `warp-sanitize`, no en paralelo ni en orden alternativo.

### Fase 1. Inventario y normalización documental

Objetivo:

- relevar todas las versiones/motores hoy hardcodeados.

Acciones:

1. listar motores, versiones y repositorios usados en:
   - `gandalf`
   - setup interactivo
   - templates
   - comandos `switch` y `info`
2. clasificar cada entrada como:
   - recommended
   - compatibility
   - legacy/manual
   - inconsistente
3. documentar la matriz objetivo en este feature.

Salida esperada:

- tabla única aprobada por servicio.

### Fase 2. Fuente única de verdad

Objetivo:

- mover la matriz canónica a una sola capa.

Acciones:

1. definir estructura canónica en `.warp/variables.sh`;
2. separar por dominio:
   - `db`
   - `cache`
   - `search`
3. modelar:
   - motores disponibles
   - repo de imagen
   - versiones soportadas
   - default
   - clasificación `recommended|compatibility|legacy/manual`

Salida esperada:

- helpers reutilizables para consultar motor/version por dominio.

Dependencia explícita:

1. reutilizar el contexto y fallback ya existentes;
2. no crear una segunda capa de resolución independiente de:
   - [service_context.sh](/srv2/www/htdocs/66/warp-engine/.warp/lib/service_context.sh)
   - [fallback.sh](/srv2/www/htdocs/66/warp-engine/.warp/lib/fallback.sh)

### Fase 3. UX de setup

Objetivo:

- cambiar la interacción de `warp init` para preguntar por dominio, luego motor, luego versión.

Acciones:

1. reemplazar prompts ambiguos como “Choose MySQL version”;
2. preguntar:
   - `DB engine/version`
   - `CACHE engine/version`
   - `SEARCH engine/version`
3. ajustar links de referencia al repo correcto según motor elegido;
4. mostrar 6 o 7 tags sugeridos por motor;
5. permitir `custom tag`;
6. dejar defaults salidos de la matriz canónica.

Salida esperada:

- wizard consistente con la imagen real que se va a usar.

### Fase 4. Templates y variables runtime

Objetivo:

- hacer que la imagen efectiva derive del motor y versión elegidos.

Acciones:

1. revisar templates de DB para eliminar ambigüedad `mysql` vs `mariadb`;
2. revisar templates de cache para permitir `redis` o `valkey`;
3. revisar templates de search para distinguir si aún vale soportar ambos motores;
4. introducir variables canónicas nuevas si hace falta, sin romper las legacy.

Salida esperada:

- templates generados alineados con lo que el wizard prometió.

Restricción:

1. toda escritura nueva debe respetar la política `write canonico`;
2. las variables legacy solo deben mantenerse por compatibilidad de transición.

### Fase 5. Compatibilidad y migración

Objetivo:

- no romper proyectos existentes.

Acciones:

1. definir tabla de traducción de variables legacy a canónicas;
2. mantener aliases de comandos:
   - `redis` -> `cache`
   - `elasticsearch` -> `search`
3. documentar qué se conserva y qué pasa a deprecado;
4. no reescribir `.env` existentes automáticamente salvo acción explícita.

Salida esperada:

- proyectos nuevos salen con naming canónico;
- proyectos viejos siguen funcionando.

### Fase 6. Validación operativa

Objetivo:

- validar que la matriz y el setup no solo “parsean”, sino que arrancan.

Smoke mínimo por dominio:

1. `warp init --help`
2. proyecto nuevo con default canónico
3. `warp start`
4. `warp info`
5. comando funcional del servicio:
   - DB: conexión básica
   - CACHE: `redis-cli`/equivalente
   - SEARCH: health check

### Fase 7. Validación de tags

Objetivo:

- aceptar tags manuales válidos sin quedar atados a una whitelist interna.

Acciones:

1. implementar validación de existencia del tag contra el repo de imagen elegido;
2. distinguir entre:
   - tag sugerido por Warp
   - tag manual válido
   - tag inexistente
3. definir fallback si no hay conectividad:
   - usar tags sugeridos/documentados como base local;
   - advertir al usuario si intenta un tag manual y no puede validarse en ese momento.

Salida esperada:

- libertad para usar tags no sugeridos;
- error claro cuando el tag no existe;
- comportamiento controlado cuando el registry no está disponible.

## 8. Decisiones a Cerrar Antes de Implementar

Estas decisiones no pueden contradecir las ya cerradas en `warp-sanitize.md`.

Si un punto aquí reabre algo ya resuelto allí, debe considerarse no disponible salvo actualización explícita de ambos documentos.

### 8.1 DB

1. si `mariadb` pasa a ser el default canónico para x86;
2. si `mysql` queda como opción explícita;
3. cómo extender el modelo canónico con `DB_VERSION` y `DB_IMAGE` respetando la política ya cerrada de:
   - write canónico
   - generación dual en `warp init` durante transición

### 8.2 Cache

1. si `valkey` entra ya como opción real de setup o solo queda preparado el terreno;
2. si el default sigue siendo `redis` hasta tener templates y smoke tests equivalentes para `valkey`;
3. cómo exponer selección de engine/version sin romper la UX ya canónica de `warp cache`.

### 8.3 Search

1. si `elasticsearch` sigue siendo un motor soportado o solo legacy;
2. si `opensearch` queda como único default recomendado;
3. si se eliminan listas legacy que ya no aplican al template actual.

## 9. Recomendación Inicial

Antes de tocar código, la recomendación es aprobar esta dirección:

1. tomar como base obligatoria los dominios canónicos ya aprobados (`db`, `cache`, `search`);
2. separar explícitamente `engine` y `version`;
3. mover la matriz a una sola fuente de verdad;
4. usar defaults conservadores y aún soportados;
5. aplicar la compatibilidad legacy ya definida, sin reabrir el contrato de transición.

Observación:

Los puntos 1 y 5 ya están definidos por `warp-sanitize.md`. En esta feature solo resta aterrizarlos al problema específico de selección y versionado de imágenes.

## 10. Alcance Fuera de Esta Feature

No forma parte de este primer trabajo:

1. autodescubrir dinámicamente tags desde Docker Hub durante `init`;
2. migrar automáticamente proyectos existentes a variables canónicas;
3. reescribir todos los comandos históricos en una sola iteración;
4. soportar motores nuevos si no existe antes una matriz aprobada y smoke tests mínimos.

## 11. Resultado Esperado

Cuando esta línea de trabajo se complete, Warp debería poder expresar algo como:

- `DB: mariadb 10.11.x`
- `CACHE: redis 7.x`
- `SEARCH: opensearch 2.x`

sin contradicciones entre:

- wizard;
- `.env`;
- template final;
- comandos de operación;
- documentación.

## 12. Matriz Inicial Propuesta

Esta sección no implica todavía cambios en código. Define la orientación inicial para aprobar antes de implementar.

### 12.1 DB

Posición propuesta:

1. dominio canónico: `db`
2. motores contemplados:
   - `mariadb`
   - `mysql`
3. motor default recomendado:
   - `mariadb`

Justificación:

- hoy Warp ya cae en MariaDB en x86;
- MariaDB debe dejar de aparecer disfrazado como “MySQL”;
- `mysql` debe quedar como opción explícita, no como ambigüedad implícita.

Política de versiones:

1. mantener una opción `recommended`;
2. mantener una opción `compatibility` cuando haya base real en el ecosistema;
3. si existe una serie más nueva que la `recommended`, no promoverla automáticamente hasta validarla.

Orientación inicial de series:

- `mariadb`:
  - `recommended`: serie LTS vigente y conservadora
  - `compatibility`: serie actualmente usada por proyectos Warp existentes
- `mysql`:
  - `compatibility`: una serie explícita compatible con proyectos que realmente necesitan MySQL

Decisión práctica sugerida antes de codificar:

1. aprobar `mariadb` como default canónico;
2. aprobar una serie LTS vigente como default;
3. dejar `mysql` como opción explícita de compatibilidad, no como naming principal del wizard.

### 12.2 Cache

Posición propuesta:

1. dominio canónico: `cache`
2. motores contemplados:
   - `redis`
   - `valkey`
3. motor default recomendado para primera iteración:
   - `redis`

Justificación:

- Warp ya tiene servicios y comandos operativos con naming Redis;
- `valkey` ya asoma en ayuda/alias, pero todavía no tiene la misma profundidad de setup y templates;
- el terreno debe quedar listo para `valkey` sin forzar una migración en la primera fase.

Política de versiones:

1. `redis` debe tener una opción `recommended` vigente;
2. `valkey` debe quedar modelado en la matriz aunque no se active todavía como default;
3. el motor elegido debe aplicarse de forma coherente a `cache`, `session` y `fpc`.

Decisión práctica sugerida antes de codificar:

1. primera iteración:
   - `redis` real
   - `valkey` preparado en matriz y UX, o bien preparado solo internamente si todavía no hay templates
2. segunda iteración:
   - `valkey` como opción operativa completa cuando haya smoke tests equivalentes

Lectura de producto:

1. `redis` debe cubrir el camino `recommended`;
2. `valkey` solo debe subir a `compatibility` cuando exista justificación clara por versión de Magento y soporte real en Warp.

### 12.3 Search

Posición propuesta:

1. dominio canónico: `search`
2. motores contemplados:
   - `opensearch`
   - `elasticsearch`
3. motor default recomendado:
   - `opensearch`

Justificación:

- los templates actuales ya usan OpenSearch;
- las listas legacy de Elasticsearch están desalineadas del setup real;
- el naming canónico debe reflejar el motor efectivamente usado.

Política de versiones:

1. `opensearch` debe tener una opción `recommended` vigente;
2. `elasticsearch` solo debe permanecer si existe soporte real en templates, setup y smoke test;
3. una versión `legacy/manual` sin imagen válida en el repo actual no debe seguir figurando como soportada en la matriz canónica.

Decisión práctica sugerida antes de codificar:

1. primera iteración:
   - `opensearch` como único motor operativo recomendado
2. `elasticsearch`:
   - o queda fuera de la matriz canónica activa;
   - o queda marcado como `legacy/manual` hasta demostrar soporte real extremo a extremo

Lectura de producto:

1. `opensearch` cubre el camino `recommended`;
2. `elasticsearch` solo debe entrar como `compatibility` para líneas concretas de Magento que todavía lo requieran;
3. fuera de esos casos, `elasticsearch` debe mantenerse como `legacy/manual` o preparado.

## 13. Alcance por Iteraciones

### 13.1 Iteración 1

Objetivo:

- corregir el modelo mental y la matriz sin ampliar demasiado el radio de cambio.

Incluye:

1. prompts por `engine/version`
2. matriz única de versiones
3. defaults conservadores y vigentes
4. tags sugeridos por motor + `custom tag`
5. motores operativos mínimos:
   - `db`: `mariadb` default, `mysql` explícito
   - `cache`: `redis` default
   - `search`: `opensearch` default
6. validación de existencia del tag ingresado cuando haya conectividad

Se asume como base ya resuelta y no reabierta en esta iteración:

1. dominios canónicos `db|cache|search`
2. alias legacy activos
3. compatibilidad transicional legacy -> canónico

No incluye:

1. migración automática de proyectos existentes;
2. `valkey` operativo completo si no existe paridad de templates/comandos;
3. `elasticsearch` operativo completo si hoy no existe soporte real unificado;
4. autodiscovery dinámico de tags desde Internet en runtime.

Nota:

- mostrar sugerencias o validar un tag puntual no implica descargar ni sincronizar toda la lista de tags del registry.

### 13.2 Iteración 2

Objetivo:

- habilitar motores alternativos sin romper la base canónica.

Incluye, si se aprueba:

1. `cache -> valkey` con templates y smoke test equivalentes;
2. posible soporte real de `search -> elasticsearch`, solo si sigue siendo un caso de uso vigente;
3. revisión de comandos históricos para exponer mejor `cache` y `search` como superficies canónicas.

### 13.3 Iteración 3

Objetivo:

- limpiar deuda legacy ya controlada.

Incluye:

1. deprecación documental de prompts históricos ambiguos;
2. reducción de listas legacy duplicadas;
3. posible endurecimiento de validaciones para impedir combinaciones inconsistentes.

## 14. Criterios de Aprobación Previos a Implementación

Antes de tocar código debería quedar aprobado, como mínimo:

1. el motor default por servicio para Iteración 1;
2. la política de defaults:
   - conservador
   - vigente
   - no necesariamente el último tag publicado
3. la política de tags sugeridos vs tag manual libre
4. qué motores quedan:
   - `recommended`
   - `compatibility`
   - `legacy/manual`
   - preparados pero no expuestos todavía
5. si las variables canónicas nuevas convivirán con las legacy desde el primer rollout.

Base ya aprobada y fuera de discusión en este documento:

1. dominios canónicos `db|cache|search`
2. aliases `mysql|redis|valkey|elasticsearch|opensearch`
3. política transicional:
   - read-compat legacy
   - write canónico
   - `warp init` genera ambas durante transición

## 15. Recomendación Ejecutiva

La recomendación para avanzar sin sobre-extender el scope es:

1. aprobar ya este recorte de primera iteración:
   - `db`: `mariadb` default, `mysql` explícito
   - `cache`: `redis` default, `valkey` preparado
   - `search`: `opensearch` default
2. definir luego una matriz concreta de series/tags sugeridos por servicio;
3. recién después tocar:
   - setup interactivo
   - variables
   - templates
   - comandos legacy

En otras palabras:

- primero tomar como base el modelo ya aprobado;
- después aprobar la matriz;
- recién al final implementar.

## 16. Matriz Inicial v0

Esta matriz propone una base concreta para Iteración 1.

No equivale todavía a “matriz definitiva publicada”; sigue sujeta a:

1. smoke tests por motor/serie;
2. revisión de templates;
3. validación de compatibilidad con proyectos Warp existentes.

### 16.1 DB

#### 16.1.1 `mariadb`

Estado propuesto:

1. engine operativo en Iteración 1
2. engine default

Series/tags:

1. `recommended`:
   - serie `10.11.x` o la LTS vigente equivalente al momento del rollout
2. `compatibility`:
   - `10.6.22`
   - `10.6.25`

Motivo:

1. `10.6.x` ya aparece en proyectos Warp actuales;
2. `10.11.x` es una mejor base para proyectos nuevos si el smoke es estable;
3. no conviene seguir atando el default a una línea histórica solo por inercia.

Política de sugerencias iniciales:

1. mostrar tags sugeridos de la serie default vigente;
2. incluir al menos un tag `10.6.x` como opción de compatibilidad visible;
3. permitir `custom tag`.

Tags sugeridos iniciales para Iteración 1:

1. `10.6.22`
2. `10.6.25`
3. `10.11.x`:
   - fijar tag concreta después de smoke + verificación puntual de Hub al momento de implementar
4. `10.4`:
   - no como sugerido principal
   - solo como legacy/manual si se verifica puntualmente su disponibilidad real al momento del rollout

Nota:

 - para la serie `10.11.x` se aprueba la dirección funcional, pero la tag exacta debe fijarse al momento de implementación para evitar documentar una patch version no validada.
 - `10.4` no figura en la lista actual de tags soportados visibles del official image de MariaDB en Docker Hub; por eso no debe tratarse como sugerido estándar, pero sí puede quedar contemplado como caso legacy/manual si el operador lo necesita y el tag existe.

#### 16.1.2 `mysql`

Estado propuesto:

1. engine operativo en Iteración 1
2. no default

Series/tags:

1. `compatibility`:
   - `8.0`
2. `legacy/manual`:
   - `5.7`

Motivo:

1. `8.0` sigue siendo el baseline natural para proyectos que requieren MySQL real;
2. `5.7` debe tratarse como compatibilidad controlada, no como opción protagonista para proyectos nuevos.

Tags sugeridos iniciales para Iteración 1:

1. `8.0`
2. `5.7`

### 16.2 Cache

#### 16.2.1 `redis`

Estado propuesto:

1. engine operativo en Iteración 1
2. engine default

Series/tags:

1. `recommended`:
   - `7.2`
2. `compatibility`:
   - `7.x` reciente que pase smoke
3. `legacy/manual`:
   - `5.0`

Motivo:

1. `7.2` ya figura en templates canónicos del setup;
2. `5.0` existe en proyectos legacy y debe seguir entrando como custom o sugerencia de compatibilidad;
3. no conviene fijar el default a una `8.x` o `latest` sin validar impacto en comandos y config.

Política de sugerencias iniciales:

1. priorizar tags `7.2.x` y `7.x` estables;
2. incluir `5.0` como opción visible de compatibilidad;
3. permitir `custom tag`.

Tags sugeridos iniciales para Iteración 1:

1. `7.2`
2. `6.2`
3. `5.0`

Tags opcionales para evaluación posterior:

1. una `7.2.x` concreta una vez verificada en Hub al momento del rollout
2. una `8.x` solo después de smoke explícito

#### 16.2.2 `valkey`

Estado propuesto:

1. engine de `compatibility` Magento-first en Etapa 8
2. no default
3. no `recommended`

Series/tags:

1. `compatibility`:
   - `8`
2. no fijar opción `recommended` en esta etapa
3. habilitar la matriz visible del engine solo cuando existan:
   - templates equivalentes
   - smoke tests equivalentes
   - criterios operativos equivalentes a Redis

Motivo:

1. el naming y alias ya están encaminados;
2. Magento 2.4.8 ya tiene base oficial para `valkey 8`;
3. la superficie operativa de Warp todavía sigue siendo esencialmente Redis;
4. primero hay que garantizar paridad real de setup/runtime.

Tags sugeridos iniciales:

1. `8`
2. no mostrar otras series de `valkey` en esta etapa

Regla de exposición:

1. `valkey 8` solo debe mostrarse como `compatibility`;
2. la justificación principal es Magento 2.4.8 y líneas compatibles posteriores;
3. fuera de esos casos, `redis` sigue siendo el camino `recommended`.

### 16.3 Search

#### 16.3.1 `opensearch`

Estado propuesto:

1. engine operativo en Iteración 1
2. engine default

Series/tags:

1. `recommended`:
   - serie `2.x` vigente y estable, a fijar con tag concreta luego del smoke
2. `compatibility`:
   - `2.12.0`

Motivo:

1. los templates actuales ya usan OpenSearch;
2. `2.12.0` ya existe en el setup actual y sigue siendo un punto de compatibilidad conocido;
3. para proyectos nuevos conviene promover una `2.x` vigente, no arrastrar automáticamente el default histórico.

Política de sugerencias iniciales:

1. mostrar una selección corta de `2.x` activas y estables;
2. incluir `2.12.0` como opción de compatibilidad visible mientras siga vigente el flujo actual;
3. permitir `custom tag`.

Tags sugeridos iniciales para Iteración 1:

1. `2.12.0`
2. `2.19.5`

Tags para evaluación posterior:

1. una `2.x` más nueva como `recommended`, si pasa smoke
2. no promover `3.x` en Iteración 1

#### 16.3.2 `elasticsearch`

Estado propuesto:

1. engine de `compatibility` acotada en Etapa 8
2. no default
3. no `recommended`

Series/tags:

1. `compatibility`:
   - `7.17`
2. `legacy/manual`:
   - `7.16`
3. no listar otras series como soportadas en la matriz activa sin:
   - template vigente
   - setup vigente
   - smoke tests reales

Motivo:

1. Magento 2.4.5 y 2.4.6 siguen justificando una capa de compatibilidad con Elasticsearch;
2. `7.17` es la opción de compatibilidad principal;
3. `7.16` solo tiene sentido como caso heredado/manual;
4. mantener listas legacy sin soporte probado solo aumenta ambigüedad.

Tags sugeridos iniciales:

1. `7.17`
2. `7.16` solo como `legacy/manual`

Regla de exposición:

1. `elasticsearch 7.17` solo debe mostrarse como `compatibility`;
2. la justificación principal es Magento 2.4.5 y 2.4.6;
3. fuera de esos casos, `opensearch` sigue siendo el camino `recommended`.

## 16.4 Resumen Operativo de Sugeridos v0

Para no sobreactuar soporte antes de tiempo, la shortlist inicial propuesta es:

1. DB / `mariadb`:
   - `10.6.22`
   - `10.6.25`
   - una `10.11.x` a fijar en implementación
   - `10.4` solo como legacy/manual
2. DB / `mysql`:
   - `8.0`
   - `5.7`
3. CACHE / `redis`:
   - `7.2`
   - `6.2`
   - `5.0`
4. SEARCH / `opensearch`:
   - `2.12.0`
   - `2.19.5`

Regla práctica:

1. esta shortlist es para UX y defaults orientados;
2. no cierra la puerta a `custom tag`;
3. no convierte automáticamente a todos estos tags en `recommended`.

Regla de cantidad:

1. el objetivo de UX es mostrar 4 o 5 sugeridos por motor cuando tenga sentido;
2. si un motor solo tiene 2 o 3 candidatos razonables y vigentes, no se fuerza relleno artificial.

## 16.5 Notas de verificación temporal

Estado relevado sobre Docker Hub al 2026-03-21:

1. Redis official image muestra explícitamente como series soportadas:
   - `7.2.13`, `7.2`
   - `6.2.21`, `6.2`
   - `8.6.1`, `8.6`
2. MariaDB official image muestra explícitamente como series soportadas visibles:
   - `10.11.16`, `10.11`
   - `10.6.25`, `10.6`
3. La lista visible actual de MariaDB no muestra `10.4` como tag soportada vigente.
4. OpenSearch tags visibles incluyen:
   - `2`
   - `2.19.5`

Implicancia:

1. `redis 6.2` puede entrar como sugerido legacy visible sin forzar una excepción;
2. `mariadb 10.4` debe tratarse como legacy/manual, no como sugerido principal, salvo verificación puntual posterior.

## 19. Plan de Acción Ejecutable

Este plan baja la feature a etapas acotadas, reversibles y testeables.

### Etapa 1. Cerrar contrato documental

Objetivo:

- congelar el alcance funcional antes de tocar código.

Incluye:

1. aprobar shortlist inicial por servicio;
2. aprobar política:
   - 4 o 5 sugeridos idealmente
   - `custom tag`
   - validación de existencia real
3. aprobar qué motores quedan:
   - `recommended` en Iteración 1
   - preparados
   - `compatibility`
   - `legacy/manual`

Salida:

1. `features/warp-service-version.md` queda como fuente de verdad funcional para esta línea de trabajo.

Validación:

1. revisión manual de consistencia con:
   - `warp-sanitize.md`
   - `legacy.md`
   - `warp-fallback.md`

### Etapa 2. Matriz canónica en variables

Objetivo:

- introducir una sola fuente de verdad para engines, tags sugeridos y defaults.

Incluye:

1. agregar estructura canónica en `.warp/variables.sh`;
2. separar por capability:
   - `db`
   - `cache`
   - `search`
3. modelar por engine:
   - repo de imagen
   - suggested tags
   - recommended
   - compatibility
   - legacy/manual

No incluye:

1. cambio todavía del wizard interactivo;
2. cambio todavía de templates.

Validación:

1. `bash -n .warp/variables.sh`
2. `./warp --help`
3. `./warp info --help`

### Etapa 3. Helper de consulta de versión sugerida

Objetivo:

- evitar que setup y help repliquen listas hardcodeadas.

Incluye:

1. helper(s) para consultar:
   - engines por capability
   - suggested tags por engine
   - default por engine
2. salida simple y reutilizable desde Bash legacy.

No incluye:

1. validación online de tags;
2. cambios de runtime de servicios.

Validación:

1. smoke local de helper por capability:
   - db
   - cache
   - search
2. `bash -n` de archivos tocados

### Etapa 4. UX de `warp init`

Objetivo:

- cambiar prompts de servicio a `engine/version` respetando contrato canónico.

Incluye:

1. DB:
   - prompt de engine
   - prompt de version sugerida + `custom tag`
2. CACHE:
   - prompt de engine
   - prompt de version sugerida + `custom tag`
3. SEARCH:
   - prompt de engine
   - prompt de version sugerida + `custom tag`
4. links al repo correcto por engine

Restricción:

1. `warp init` sigue generando canonicas + legacy durante transición.

Validación:

1. `./warp init --help`
2. smoke interactivo en proyecto dummy:
   - DB default
   - CACHE default
   - SEARCH default
3. revisión de `.env.sample` generado

### Etapa 5. Templates por engine

Objetivo:

- hacer que el compose generado refleje realmente el engine seleccionado.

Incluye:

1. DB:
   - resolver `mysql` vs `mariadb`
2. CACHE:
   - preparar `redis`
   - dejar `valkey` solo si existe template equivalente validado
3. SEARCH:
   - mantener `opensearch`
   - no abrir `elasticsearch` real sin soporte completo

Validación:

1. `./warp start --help`
2. `./warp stop --help`
3. smoke de compose generado:
   - inspección de imagen por servicio
4. `docker compose config` o `docker-compose config` en proyecto de prueba

### Etapa 6. Validación manual de tag

Objetivo:

- aceptar `custom tag` sin whitelist cerrada.

Incluye:

1. validación puntual del tag ingresado;
2. mensaje claro si:
   - existe
   - no existe
   - no pudo validarse por conectividad

Restricción:

1. si no hay conectividad, Warp no debe bloquear defaults sugeridos ya conocidos;
2. para `custom tag` sin validación disponible, el comportamiento debe quedar explícitamente definido antes de implementar.

Validación:

1. tag sugerido conocido
2. tag manual válido
3. tag inexistente
4. simulación de falta de conectividad

### Etapa 7. Smoke por capability

Objetivo:

- validar que la selección de engine/version no quede solo en docs y prompts.

Casos mínimos:

1. DB:
   - `mariadb` default
   - `mysql` explícito
2. CACHE:
   - `redis` default
3. SEARCH:
   - `opensearch` default

Validación:

1. `./warp --help`
2. `./warp init --help`
3. `./warp start --help`
4. `./warp stop --help`
5. `./warp info --help`
6. proyecto dummy:
   - `warp init`
   - `warp start`
   - `warp info`

### Etapa 8. Motores preparados

Objetivo:

- decidir si `valkey` y/o `elasticsearch` pasan de preparados a operativos.

Entrada requerida:

1. template equivalente
2. smoke equivalente
3. comportamiento coherente en comandos canonicos
4. justificación funcional explícita por versión de Magento o caso real equivalente

Si no se cumple:

1. quedan documentados como `prepared` o `legacy/manual`
2. no se exponen como opción operativa principal

Regla de producto para esta etapa:

1. Etapa 8 no abre motores “porque existen”, sino porque cubren compatibilidad real del ecosistema;
2. Magento sigue siendo el caso rector;
3. si otra app PHP necesita esos motores, entra por la misma categoría `compatibility`, no como camino `recommended`.

Decisión inicial para Etapa 8:

1. `cache / valkey`:
   - abrir `valkey 8` como `compatibility`
   - no hacerlo `recommended`
   - mantener `redis` como camino principal
2. `search / elasticsearch`:
   - abrir `7.17` como `compatibility`
   - dejar `7.16` como `legacy/manual`
   - mantener `opensearch` como camino principal

Condición de exposición en wizard:

1. si Warp puede detectar versión de Magento compatible, debe priorizar la opción `compatibility` correspondiente;
2. si no puede detectarla, debe mostrar estas opciones claramente etiquetadas como:
   - `compatibility`
   - `legacy/manual`
3. nunca deben competir visualmente con la opción `recommended` como si fueran equivalentes.

### 19.1 Matriz Magento-first de exposición

Esta matriz define cuándo Warp debería ofrecer motores/tags de `compatibility` o `legacy/manual` para Magento.

No reemplaza la matriz canónica general; la especializa para el caso dominante del ecosistema.

#### 19.1.1 Cache

1. Magento `2.4.8+`:
   - `recommended`: `redis 7.2`
   - `compatibility`: `valkey 8`
2. Magento `2.4.7`:
   - `recommended`: `redis 7.2`
   - `compatibility`: `valkey 8` solo desde `2.4.7-p6`
3. Magento `2.4.6`:
   - `recommended`: `redis 6.2` o `redis 7.2` según matriz general aprobada del proyecto
   - `compatibility`: `valkey 8` solo desde `2.4.6-p11`
4. Magento `2.4.5`:
   - `recommended`: `redis 6.2` o `redis 7.2` según matriz general aprobada del proyecto
   - `compatibility`: `valkey 8` solo desde `2.4.5-p13`
5. Magento `< 2.4.5`:
   - no ofrecer `valkey 8`

Regla de producto:

1. `valkey 8` nunca debe aparecer como `recommended` en esta etapa;
2. si Warp no puede determinar la versión exacta de Magento, no debe promover `valkey 8` por inferencia amplia;
3. `valkey 8` solo debe aparecer cuando el perfil detectado o el override manual lo justifiquen.

#### 19.1.2 Search

1. Magento `2.4.8+`:
   - `recommended`: `opensearch 2.x`
   - no ofrecer `elasticsearch` salvo override/manual
2. Magento `2.4.7`:
   - `recommended`: `opensearch 2.x`
   - no ofrecer `elasticsearch` salvo caso documentado puntual
3. Magento `2.4.6`:
   - `recommended`: `opensearch 2.x`
   - `compatibility`: `elasticsearch 7.17`
4. Magento `2.4.5`:
   - `recommended`: `opensearch 2.x`
   - `compatibility`: `elasticsearch 7.17`
   - `legacy/manual`: `elasticsearch 7.16`
5. Magento `< 2.4.5`:
   - fuera del camino principal de esta feature;
   - cualquier uso de `elasticsearch` debe quedar como `legacy/manual`

Regla de producto:

1. `elasticsearch 7.17` solo debe mostrarse como `compatibility`;
2. `elasticsearch 7.16` no debe mostrarse como sugerencia normal; solo como `legacy/manual` o entrada manual;
3. si Warp no puede determinar la versión exacta de Magento, `opensearch` sigue siendo la opción visible principal.

#### 19.1.3 Política de fallback cuando no se detecta Magento

Si Warp no puede detectar versión de Magento, debe comportarse así:

1. seguir mostrando el camino `recommended` general:
   - `redis`
   - `opensearch`
2. permitir `compatibility`:
   - `elasticsearch 7.17`
3. mostrar siempre esas opciones con etiqueta explícita;
4. no elevar automáticamente una opción `compatibility` a default.

Nota:

1. `valkey 8` queda fuera del fallback general cuando no hay versión Magento exacta o override explícito, porque su soporte real depende de patch level.

#### 19.1.4 Fuente funcional de la matriz Magento

La base funcional de esta submatriz debe mantenerse alineada con requisitos oficiales de Adobe Commerce:

- [System requirements](https://experienceleague.adobe.com/en/docs/commerce-operations/installation-guide/system-requirements)

Regla:

1. si Adobe cambia compatibilidad oficial de motores relevantes, esta sección debe actualizarse antes de promover nuevos defaults o sugerencias.

### 19.2 Estrategia de detección de versión Magento en `warp init`

La detección de versión no debe depender de tener contenedores levantados ni de ejecutar `bin/magento`.

Debe resolverse a partir de archivos del proyecto, por orden de confianza.

#### 19.2.1 Orden de detección propuesto

1. `composer.lock`
   - buscar paquetes raíz/versiones instaladas de Magento;
   - esta es la fuente preferida cuando existe, porque refleja versión resuelta real.
2. `composer.json`
   - usar constraints del proyecto cuando no exista `composer.lock`;
   - sirve como aproximación, pero tiene menor certeza que el lock.
3. fallback por framework
   - si el proyecto fue marcado como `m2` pero no hay señal suficiente de versión, Warp debe asumir “Magento detectado, versión no resuelta”.
4. sin detección
   - si no se puede confirmar Magento, aplicar la matriz general y exponer compatibilidades solo con etiqueta explícita.

#### 19.2.2 Señales concretas a inspeccionar

Señales prioritarias:

1. `composer.lock`:
   - `magento/product-community-edition`
   - `magento/product-enterprise-edition`
   - `magento/project-community-edition`
   - `magento/project-enterprise-edition`
2. `composer.json`:
   - mismas claves si aparecen como dependencia o paquete raíz
3. señales secundarias de framework:
   - `bin/magento`
   - `app/etc/env.php`

Regla:

1. `bin/magento` y `app/etc/env.php` sirven para detectar “esto es Magento”;
2. no sirven como fuente principal para resolver la versión exacta durante `init`.

#### 19.2.3 Niveles de confianza

Warp debería clasificar la detección así:

1. `exact`
   - versión concreta obtenida desde `composer.lock`
2. `constraint`
   - rango o serie inferida desde `composer.json`
3. `framework_only`
   - proyecto Magento detectado sin versión resoluble
4. `unknown`
   - no se pudo detectar Magento con confianza suficiente

#### 19.2.4 Comportamiento del wizard según confianza

1. `exact`
   - aplicar directamente la matriz Magento-first;
   - priorizar opciones `compatibility` relevantes para esa versión.
2. `constraint`
   - aplicar matriz Magento-first de forma conservadora;
   - si el constraint no permite resolver patch level, no habilitar compatibilidades que dependan de patch exacto como `valkey 8`.
3. `framework_only`
   - mantener `recommended` general visible;
   - mostrar solo compatibilidades que no dependan de patch exacto;
   - no asumir que `valkey 8` corresponde.
4. `unknown`
   - usar solo la matriz general;
   - permitir `compatibility` y `legacy/manual` solo como opciones explícitas.

#### 19.2.5 Reglas de implementación

1. la detección debe vivir en helpers reutilizables, no embebida en cada setup de servicio;
2. debe ejecutarse una vez por `init` y reutilizar su resultado para `db`, `cache` y `search`;
3. no debe requerir red;
4. no debe requerir `composer install`;
5. no debe requerir PHP del host;
6. si hay conflicto entre `composer.lock` y `composer.json`, prevalece `composer.lock`.

#### 19.2.6 Extensibilidad a otros frameworks

Para no sobre-extender la feature:

1. la primera implementación debe resolver solo Magento;
2. el diseño del helper debe permitir enchufar luego detectores por framework:
   - Laravel
   - WordPress/WooCommerce
   - Oro
3. esos detectores futuros solo deberían aportar:
   - framework
   - versión detectada
   - nivel de confianza
4. la lógica de clasificación `recommended|compatibility|legacy/manual` debe permanecer común.

### 19.3 Contrato mínimo del helper de detección

Antes de implementar código, Warp debe fijar un contrato simple y estable para el detector de aplicación.

La idea es que `init` consuma un único resultado normalizado, sin conocer detalles de parsing por framework.

#### 19.3.1 Variables expuestas

El helper debería poblar, como mínimo:

1. `WARP_APP_FRAMEWORK`
   - valores iniciales:
     - `magento`
     - `oro`
     - `php`
     - `unknown`
2. `WARP_APP_VERSION`
   - versión detectada o constraint normalizado;
   - ejemplos:
     - `2.4.8`
     - `2.4.6-p11`
     - `2.4.5`
     - `^2.4.6`
3. `WARP_APP_VERSION_CONFIDENCE`
   - valores:
     - `exact`
     - `constraint`
     - `framework_only`
     - `unknown`
4. `WARP_APP_VERSION_SOURCE`
   - valores:
     - `composer.lock`
     - `composer.json`
     - `framework_signal`
     - `manual`
     - `unknown`

Opcionalmente, puede poblar:

1. `WARP_MAGENTO_SERIES`
   - ejemplo:
     - `2.4.8`
     - `2.4.6`
     - `2.4.5`
2. `WARP_MAGENTO_PATCH`
   - ejemplo:
     - `p11`
     - `p13`
3. `WARP_APP_COMPAT_PROFILE`
   - valores iniciales propuestos:
     - `general`
     - `magento`
     - `magento-2.4.8+`
     - `magento-2.4.6`
     - `magento-2.4.5`

#### 19.3.2 Reglas del contrato

1. si `WARP_APP_FRAMEWORK != magento`, no debe intentarse aplicar la submatriz Magento-first;
2. si `WARP_APP_VERSION_CONFIDENCE=unknown`, debe prevalecer la matriz general;
3. `WARP_APP_VERSION` puede contener constraint, pero solo `exact` habilita decisiones automáticas más agresivas;
4. `WARP_APP_COMPAT_PROFILE` debe derivarse del detector, no calcularse por separado en cada setup.

#### 19.3.3 Uso esperado desde `init`

Flujo esperado:

1. `init` ejecuta una sola vez el helper de detección;
2. el helper exporta las variables del contrato;
3. los setups de:
   - `db`
   - `cache`
   - `search`
   consumen ese estado ya resuelto;
4. la selección de `recommended|compatibility|legacy/manual` se decide contra:
   - matriz general
   - perfil de compatibilidad detectado

#### 19.3.4 API de helper propuesta

Interfaz mínima sugerida:

1. archivo:
   - `.warp/lib/app_context.sh`
2. función principal:
   - `warp_app_context_detect`
3. funciones auxiliares:
   - `warp_app_context_detect_framework`
   - `warp_app_context_detect_magento_version`
   - `warp_app_context_resolve_profile`

Salida esperada:

1. variables exportadas al shell actual;
2. sin output ruidoso en stdout durante `init` normal;
3. mensajes solo en modo debug o cuando la detección sea ambigua y afecte el wizard.

#### 19.3.5 Regla de override manual

Aunque exista autodetección, Warp debería reservar un override manual futuro.

Propuesta:

1. permitir variables o flags para forzar:
   - framework
   - versión
   - perfil de compatibilidad
2. el override manual debe prevalecer sobre la autodetección;
3. esa capacidad no es obligatoria en la primera implementación, pero el contrato no debe impedirla.

### 19.4 Checklist de implementación

Esta checklist traduce el documento a pasos concretos de código.

#### 19.4.1 Helpers y contexto

1. crear `.warp/lib/app_context.sh`
2. implementar:
   - `warp_app_context_detect`
   - `warp_app_context_detect_framework`
   - `warp_app_context_detect_magento_version`
   - `warp_app_context_resolve_profile`
3. incluir la librería en `.warp/includes.sh`
4. ejecutar la detección una sola vez al inicio de `init`

Validación mínima:

1. proyecto Magento con `composer.lock`
2. proyecto Magento solo con `composer.json`
3. proyecto con `bin/magento` pero sin versión resoluble
4. proyecto PHP genérico

#### 19.4.2 Integración con `init`

1. `init` debe consumir el contexto detectado antes de preguntar servicios;
2. `db`, `cache` y `search` no deben recalcular framework/version por su cuenta;
3. el wizard debe mostrar:
   - `recommended`
   - `compatibility`
   - `legacy/manual`
   como etiquetas visibles y consistentes

Validación mínima:

1. Magento `2.4.8+` debe exponer `valkey 8` como `compatibility`
2. Magento `2.4.7-p6+`, `2.4.6-p11+` y `2.4.5-p13+` deben exponer `valkey 8` como `compatibility`
3. Magento `2.4.6` debe exponer `elasticsearch 7.17` como `compatibility`
4. Magento `2.4.5` debe exponer `elasticsearch 7.17` como `compatibility` y `7.16` como `legacy/manual`
4. proyecto sin detección Magento no debe perder `redis` y `opensearch` como camino principal

#### 19.4.3 Matriz y resolución por perfil

1. mantener la matriz general en `.warp/variables.sh`
2. agregar resolución por perfil detectado sin duplicar listas hardcodeadas en setup
3. si una opción depende de perfil Magento, su exposición debe pasar por helper común

Validación mínima:

1. `general` no debe promover motores `compatibility` a default
2. `magento-2.4.8+` debe habilitar `valkey 8`
3. `magento-2.4.7-p6+`, `2.4.6-p11+` y `2.4.5-p13+` deben habilitar `valkey 8`
4. `magento-2.4.6` debe habilitar `elasticsearch 7.17`
5. `magento-2.4.5` debe habilitar `7.17` y dejar `7.16` solo como `legacy/manual`

#### 19.4.4 Templates y runtime

1. no abrir un motor en wizard si el template/runtime no lo soporta;
2. `valkey` solo puede exponerse cuando exista paridad real con Redis en setup y compose;
3. `elasticsearch` solo puede exponerse cuando exista template vigente y smoke real

Validación mínima:

1. compose generado refleja engine/tag elegido
2. `warp start`
3. `warp info`
4. health/smoke básico del servicio

#### 19.4.5 Compatibilidad y fallback

1. si la detección falla, aplicar matriz general;
2. si la detección es parcial (`constraint` o `framework_only`), no asumir compatibilidad agresiva;
3. `custom tag` sigue pasando por la misma validación ya definida

Validación mínima:

1. no regressión del flujo actual de `init`
2. no regressión de variables legacy en `.env.sample`
3. no regressión en `warp start/stop/info`

### 19.5 Definición de terminado para la siguiente implementación

La próxima implementación puede considerarse completa cuando cumpla todo esto:

1. existe un helper común de contexto de app;
2. `init` detecta Magento sin depender de contenedores;
3. el wizard cambia la exposición de `cache/search` según perfil Magento detectado;
4. `valkey 8` solo aparece como `compatibility`;
5. `elasticsearch 7.17` solo aparece como `compatibility`;
6. `elasticsearch 7.16` solo aparece como `legacy/manual` o entrada manual;
7. si no hay detección fiable, `redis` y `opensearch` siguen siendo el camino principal;
8. la validación mínima de `--help`, `init`, `start`, `stop`, `info` y smoke compose sigue pasando.

## 20. Orden Recomendado de Implementación

1. Etapa 1: contrato documental
2. Etapa 2: matriz canónica
3. Etapa 3: helpers
4. Etapa 4: prompts de `init`
5. Etapa 5: templates
6. Etapa 6: validación de `custom tag`
7. Etapa 7: smoke por capability
8. Etapa 8: motores preparados

## 21. Criterio de Corte

Se considera que Iteración 1 está cumplida cuando:

1. `warp init` pregunta por `engine/version` en `db`, `cache`, `search`;
2. usa shortlist sugerida + `custom tag`;
3. genera variables canónicas y legacy en transición;
4. el compose refleja el engine elegido al menos para:
   - `mariadb|mysql`
   - `redis`
   - `opensearch`
5. los smoke mínimos pasan sin regresión.

## 17. Reglas de Promoción de Estado

Para pasar un engine/tag de `prepared` o `legacy/manual` a `compatibility` o `recommended`, deben cumplirse estos mínimos:

1. el tag existe en el repo de imagen elegido;
2. `warp init` lo puede generar sin incoherencias de naming;
3. `warp start` levanta el servicio con el template vigente;
4. `warp info` o el comando canónico del servicio reflejan correctamente:
   - mode
   - engine
   - versión
5. existe al menos un smoke operativo del servicio.

## 18. Orden Recomendado Para Cerrar la Matriz

1. cerrar primero DB:
   - `mariadb` default
   - `mysql` explícito
2. luego cache:
   - `redis` default
   - `valkey` preparado
3. por último search:
   - `opensearch` default
   - `elasticsearch` solo si sigue justificándose

Motivo:

1. DB y cache impactan más proyectos y más comandos;
2. search ya está más encaminado a un engine dominante (`opensearch`);
3. `valkey` y `elasticsearch` son los puntos donde más fácil sería sobre-extender el alcance.
