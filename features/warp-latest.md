# Warp Latest: mejoras funcionales del último año

Fecha: 2026-03-24

Este documento resume las mejoras recientes de Warp desde una mirada funcional, orientada a uso diario del equipo.

Nota de continuidad de repositorio:

- este fork se mantiene como puente de compatibilidad e histórico,
- la evolución activa del proyecto continúa en `https://github.com/magtools/phoenix-launch-silo`.

## Agents privados por proyecto (`warp agents`)

Warp ahora puede orquestar un repositorio privado de automatizaciones auxiliares por proyecto, sin mezclar su lógica interna con el core.

Qué aporta al equipo:

- configuración versionable en `.warp/docker/config/agents/config.ini`,
- clone local en `.agents_md`, ignorado por Git,
- bootstrap con `warp agents install`,
- actualización bajo demanda con `warp agents update`,
- hook best-effort al final de `warp start` si existe `.agents_md/update.sh`.

Comandos:

- `warp agents install`: crea la config si falta, valida `AGENTS_REPO` como URL SSH, clona `.agents_md` y ejecuta `bash .agents_md/install.sh`.
- `warp agents update`: ejecuta `bash .agents_md/update.sh`.

## Deploy unificado por entorno (`warp deploy`)

Warp ahora incluye un flujo de deploy nativo para `local` y `prod`, con configuración por proyecto en `.deploy`.

Qué aporta al equipo:

- un comando estándar para deploy (`warp deploy run`),
- validación previa con `warp deploy doctor`,
- detección de `warp` global viejo vs wrapper delegador en PATH,
- configuración visible con `warp deploy show`,
- generación guiada de `.deploy` con `warp deploy set`,
- simulación de receta sin ejecutar (`--dry-run`),
- ejecución exclusiva de frontend/estáticos con `warp deploy static`.

Comandos:

- `warp deploy`: muestra ayuda de deploy (entrada informativa).
- `warp deploy run`: ejecuta deploy completo según `.deploy`.
- `warp deploy static`: ejecuta solo pasos de estáticos/frontend.
- `warp deploy set`: crea o actualiza `.deploy`.
- `warp deploy show`: muestra la configuración activa.
- `warp deploy doctor`: valida prerequisitos.

Impacto funcional:

- menos scripts ad-hoc por proyecto,
- mayor previsibilidad del orden de pasos,
- mejor seguridad operativa en producción (confirmaciones y gates),
- manejo de OPcache al cierre del deploy:
  - en `local`, si OPcache managed está activo, se desactiva y se recarga PHP-FPM;
  - en `prod`, PHP-FPM se recarga solo si OPcache managed está activo.

## Estado de contenedores estable (`warp ps`)

`warp ps` ahora evita depender del formato nativo de Compose v1/v2 para su salida principal.

Qué aporta al equipo:

- columnas estables (`IMAGE`, `CONTAINER`, `STATUS`, `PORTS`) en ambientes con `docker-compose` v1 o `docker compose` v2,
- `IMAGE` usa nombre corto (`img:version`) para evitar diferencias por namespace/proveedor,
- salida nativa disponible con `warp ps --raw`,
- formatos útiles para scripts:
  - `warp ps --services`,
  - `warp ps -q`,
  - `warp ps --format json`,
  - `warp ps --format names`.

## Frontend Hyvä integrado (`warp hyva`)

Se consolidó un comando dedicado para flujos Hyvä:

- descubrimiento de themes,
- instalación de dependencias,
- generación/build/watch,
- ejecución por theme o por lote.

Qué aporta al equipo:

- onboarding más simple en proyectos Hyvä,
- menos trabajo manual con npm en contenedor,
- flujo repetible para build local y productivo.

Comandos:

- `warp hyva discover`: detecta themes y genera configuración.
- `warp hyva setup[:theme]`: instala dependencias y prepara theme(s).
- `warp hyva prepare[:theme]`: ejecuta solo generación.
- `warp hyva build[:theme]`: compila assets.
- `warp hyva watch[:theme]`: modo watch para desarrollo.
- `warp hyva list`: muestra themes detectados.

## Calidad de código Magento más completa (`warp audit`)

`warp audit` pasó a ser el nombre canónico del helper de calidad de código Magento, reemplazando a `warp scan`, y cubre más chequeos del flujo técnico diario.

Qué aporta al equipo:

- ejecución directa por herramienta o por menú,
- misma UX para `phpcs`, `phpcbf`, `phpmd`, `phpcompat` y `phpstan`,
- soporte de ruta puntual con `--path <ruta>` sin volver a preguntar path,
- integración de `PHPCompatibility` para validar compatibilidad de versión de PHP,
- integración de `PHPStan` usando configuración base del proyecto,
- salida más limpia y legible en CLI y logs,
- checks PR más útiles al sumar compatibilidad PHP sobre `app/code`.

Comandos:

- `warp audit`: menú principal de auditoría.
- `warp audit --path <ruta>`: menú de herramientas sobre una ruta puntual.
- `warp audit pr`: abre menú de scope para PR checks (`custom path`, `default` o vendor-level paths).
- `warp audit --pr`: PR checks no interactivos sobre defaults del proyecto.
- `warp audit integrity` / `warp audit -i`: `setup:di:compile` + PR checks.
- `warp audit phpcs --path <ruta>`: PHPCS directo sobre una ruta.
- `warp audit phpcbf --path <ruta>`: PHPCBF directo sobre una ruta.
- `warp audit phpmd --path <ruta>`: PHPMD directo sobre una ruta.
- `warp audit phpcompat --path <ruta>`: PHPCompatibility directo sobre una ruta.
- `warp audit risky --path <ruta>`: búsqueda de primitives riesgosas sobre una ruta.
- `warp audit phpstan`: PHPStan sobre el scope default de `phpstan.neon.dist`.
- `warp audit phpstan --path <ruta>`: PHPStan sobre una ruta puntual.
- `warp audit phpstan --level <n>`: override puntual de level para una corrida.
- `warp audit phpstan --level <n> --path <ruta>`: override puntual de level sobre una ruta puntual.
- `warp audit integrity` ahora también corre risky primitive audit en `app/code` y `phpstan --level 1` sobre `app/code`.

Impacto funcional:

- menos necesidad de scripts auxiliares por proyecto,
- mejor cobertura de calidad/compatibilidad sin salir de Warp,
- más consistencia entre chequeos interactivos y chequeos directos,
- menor ruido en logs de análisis.

## Diagnóstico explícito de runtime PHP (`warp php --version`)

Se agregó una forma directa de consultar la versión real del runtime PHP.

Qué aporta al equipo:

- permite confirmar rápidamente drift entre `.env` y contenedor real,
- sirve como apoyo para troubleshooting y para el target version de `PHPCompatibility`,
- evita tener que entrar al contenedor solo para validar versión.

Comando:

- `warp php --version`: imprime la versión real del runtime PHP.

## Compatibilidad ampliada con Compose y runtime mixto

Warp mejoró su tolerancia a entornos donde el proyecto no cae exactamente en el caso clásico de `full warp`.

Qué aporta al equipo:

- compatibilidad real con `docker compose` plugin v2 además de `docker-compose`,
- menor fricción en hosts donde no existe binario global `docker-compose`,
- mejor soporte para comandos que pueden operar sin compose local,
- menos bloqueos innecesarios en proyectos con infraestructura parcial o externa.

Impacto funcional:

- si falta `docker-compose` pero existe `docker compose`, Warp puede operar con fallback interno,
- comandos compatibles como `warp magento`, `warp php`, `warp telemetry`, `warp info` y flujos ligados a fallback ya no quedan atados al mismo precheck rígido,
- mejora la experiencia en proyectos con topologías mixtas: local + servicios externos o incluso infraestructura 100% externa con Warp presente.

## Comandos canónicos por capability (`warp db`, `warp cache`, `warp search`)

Durante este ciclo se consolidó una dirección más clara de naming y responsabilidad operacional.

Qué aporta al equipo:

- una capa canónica orientada a capability en lugar de nombres históricos de tecnología,
- menor deuda de naming en comandos y ayudas,
- mejor base para operar servicios locales o externos con el mismo comando funcional.

Comandos y compatibilidad:

- `warp db` como superficie canónica para base de datos.
- `warp cache` como superficie canónica para cache.
- `warp search` como superficie canónica para búsqueda.
- se mantienen alias legacy:
  - `warp mysql`
  - `warp redis`
  - `warp valkey`
  - `warp elasticsearch`
  - `warp opensearch`

Impacto funcional:

- el operador puede pensar primero en la capability (`db`, `cache`, `search`) y no en el nombre histórico del contenedor,
- la compatibilidad hacia atrás se preserva sin forzar una migración abrupta de comandos.

## Fallback operativo para servicios externos

Warp avanzó en una capa más explícita de contexto y fallback para entornos con servicios fuera de Docker local.

Qué aporta al equipo:

- mejor soporte para DB externa,
- base común para cache/búsqueda en modo `external`,
- menor duplicación de lógica de detección y validación entre comandos.

Impacto funcional:

- `warp db`/`warp mysql` ya contemplan mejor escenarios RDS/external,
- `warp cache` y `warp search` avanzan hacia un comportamiento consistente entre modo local y externo,
- `warp cache` ahora puede bootstrappear `cache/fpc/session` remotos desde `app/etc/env.php` y resolver DB por scope,
- `warp search` ahora puede bootstrappear `SEARCH_*` desde `app/etc/env.php` cuando falta el servicio local,
- se endurecieron guardas para operaciones sensibles en modo externo, especialmente `flush`.

Resultado práctico:

- menos fallos ambiguos cuando falta un servicio en `docker-compose-warp.yml`,
- mejor separación entre operación local de contenedor y operación contra endpoints externos.

## Selección y defaults de versión más consistentes en `warp init`

Se reforzó la base para que `warp init` resuelva motores/versiones de infraestructura con una estrategia más coherente.

Qué aporta al equipo:

- menos inconsistencias entre wizard, templates y defaults reales,
- mejor alineación entre servicio canónico, engine y versión,
- una base más clara para defaults vigentes y verificables.

Impacto funcional:

- mejora la previsibilidad al elegir stack de DB/cache/search,
- reduce desalineaciones históricas entre naming legacy y motor real,
- prepara mejor el terreno para upgrades de Magento y servicios asociados.

## Diagnóstico de memoria y sugerencias (`warp telemetry scan`)

Se incorporó un reporte de memoria orientado a análisis:

- uso de memoria por servicios clave (`php`, `mysql`, `elasticsearch`, `redis-*`),
- lectura de configuración actual (si existe),
- sugerencias automáticas de umbrales según RAM y consumo real.

Evolución funcional reciente:

- Redis y Elasticsearch ahora se recomiendan usando `used_memory` como base.
- Se agrega guardrail por `used_memory_peak` para proponer un “mínimo de seguridad”.
- Se incorporan alertas operativas por presión de memoria:
  - `>=75%` warning
  - `>=90%` crítico
- PHP-FPM pasó a extrapolación por RAM con redondeo optimista para `pm.max_children`
  (incluye ajuste adicional en servidores medianos/grandes).

Qué aporta al equipo:

- decisiones de capacity/tuning basadas en datos,
- visibilidad rápida de desalineaciones entre uso real y configuración,
- separación clara entre uso de contenedor y uso interno de servicio,
- salida en texto y JSON para troubleshooting y documentación,

## Diagnóstico de scraping en access logs (`warp scan scraping`)

Warp agrega un scanner read-only para detectar patrones compatibles con scraping
costoso sobre access logs locales o externos.

Qué aporta al equipo:

- analiza logs plain y `.gz` de Nginx/PHP-FPM sin modificar configuración,
- soporta `--path`, `--since`, `--window`, `--page-gap`, `--json`, `--save`,
  `--output` y `--output-dir`,
- reporta clientes sospechosos, paths calientes, familias de user-agent y
  firmas por `path + query normalizada + ua_family`,
- muestra progreso interactivo tipo `pv` en `stderr` con fase actual, bytes
  ingeridos, líneas vistas y líneas parseadas,
- mantiene `stdout` limpio para reportes humanos, JSON y redirecciones,
- permite desactivar el progreso con `--no-progress`.

Impacto funcional:

- ayuda a investigar scrapers que rotan IP agrupando por firma,
- evita la sensación de comando colgado durante ingesta, métricas finales y
  render del reporte,
- reduce el costo de cierre del análisis calculando métricas de paginación por
  cliente sin recorrer globalmente todas las páginas por cada cliente.

Comandos:

- `warp scan scraping --path /var/log/nginx/access.log --top 20`
- `warp scan scraping --since 24h --window 5m`
- `warp scan scraping --json --output var/log/warp-scan-scraping.json`
- `warp scan scraping --no-progress`

## Security scan y check más útiles (`warp security`)

`warp security` siguió ajustando el balance entre señal real y ruido operativo.

Qué aporta al equipo:

- `warp security scan` ahora explica mejor por qué un archivo fue marcado (`path - indicator [class]`),
- `warp security check` mantiene el detalle en `var/log/warp-security.log` y copia histórica rotada,
- se corrigió un descarte incorrecto de líneas con comentarios inline (`// phpcs:ignore`) que ocultaba señales reales como `base64_decode()` en `app/code`,
- se evita marcar como skimmer un `new WebSocket` genérico dentro de librerías conocidas de `pub/static` como `jquery/uppy`,
- `warp security scan` suma además un check rápido de PHP bajo `pub/` excluyendo `pub/errors` y los entrypoints core de Magento, y una verificación aparte para detectar si esos entrypoints fueron modificados,
- `warp security scan` y `warp security check` crean `.known-paths`, `.known-files` y `.known-findings` si faltan, para que la lógica de paths/archivos esperados y findings aceptados viva en archivos del proyecto y no en hardcodes,
- esa exclusión no silencia señales más fuertes: si aparecen `wss://`, `RTCPeerConnection`, `createDataChannel` o `new Function(event.data)`, el hallazgo se mantiene.

Impacto funcional:

- menos falsos positivos en assets frontend legítimos,
- mejor visibilidad de primitives riesgosas fuera de `pub`,
- mayor confianza en el score y en los `attention paths` mostrados por `scan`.
- mejores señales para prevenir saturación antes de impacto al negocio.

Comandos:

- `warp telemetry` / `warp telemetry scan`: reporte funcional de uso/configuración/sugerencias.
- `warp telemetry scan --no-suggest`: muestra uso + config actual sin recomendaciones.
- `warp telemetry scan --json`: salida estructurada para automatización.
- `warp telemetry config`: guía rápida de dónde configurar memoria por servicio (Redis, Search, PHP-FPM) y referencia MySQL/MariaDB con MySQLTuner.

## Base inicial para seguridad operativa (`warp security`)

Warp ahora incorpora una superficie inicial para triage de seguridad:

- `warp security`: entrada principal y ayuda
- `warp security scan`: pasada rápida heurística para decidir si conviene correr `check`
- `warp security check`: corre una fase read-only sobre filesystem, IOC, logs y host; escribe `var/log/warp-security.log` y una copia rotada
- `warp security toolkit`: lista comandos manuales de análisis y limpieza por familia/superficie

Qué aporta al equipo:

- una base homogénea para investigar indicios de compromiso,
- separación explícita entre análisis read-only y cleanup manual,
- salida operativa breve con score, severity/suspicion y línea de estado,
- guía operativa para familias recientes como PolyShell, SessionReaper y CosmicSting.

Impacto funcional:

- Warp no ejecuta limpieza destructiva en esta feature,
- `toolkit` prioriza comandos seguros de inspección y cuarentena,
- `.known-paths` permite documentar paths no trackeados esperados sin blanquear PHP peligroso dentro de `pub/`.

## Redis más configurable por entorno

Warp pasó de una configuración Redis “implícita” a una más controlada:

- uso efectivo de `redis.conf` en contenedores,
- parámetros de memoria/política por servicio vía `.env`,
- separación funcional de cache/fpc vs session,
- compatibilidad con recomendaciones de operación para Magento.

Qué aporta al equipo:

- tuning más seguro en producción,
- ajustes rápidos por ambiente sin rearmar imágenes,
- menor riesgo de degradación por políticas de memoria incorrectas.

Comandos:

- `warp redis info`: muestra información de servicios Redis configurados.
- `warp redis cli <cache|session|fpc>`: acceso a redis-cli por servicio.
- `warp redis monitor <cache|session|fpc>`: monitoreo de comandos en tiempo real.
- `warp redis flush <cache|session|fpc|--all>`: limpieza de datos por servicio.

## Mantenimiento y actualización del propio Warp (`warp update`)

Se fortaleció el flujo de actualización del framework:

- verificación de integridad (checksum) antes de reemplazo,
- control de estado de update pendiente,
- chequeo automático de versión sin interrumpir comandos críticos,
- creación no destructiva de `ext-xdebug.ini` y `zz-warp-opcache.ini` vacíos si faltan,
- verificación de `.gitignore` para esos INI efectivos locales,
- separación clara entre actualización de Warp e imágenes Docker.

Origen remoto actual del update runtime:

- `https://raw.githubusercontent.com/magtools/phoenix-launch-silo/refs/heads/master/dist/version.md`
- `https://raw.githubusercontent.com/magtools/phoenix-launch-silo/refs/heads/master/dist/sha256sum.md`
- `https://raw.githubusercontent.com/magtools/phoenix-launch-silo/refs/heads/master/dist/warp`

Qué aporta al equipo:

- upgrades más confiables,
- mejor visibilidad cuando hay versión nueva o fallos de conectividad,
- menor riesgo de cambios sorpresivos en configuración de proyecto,
- recomendación operativa clara para instalar un wrapper delegador de `warp` en PATH cuando el binario global queda viejo.

Comandos:

- `warp update`: actualiza binario/framework de Warp.
- `warp update --images`: actualiza imágenes Docker del proyecto.
- `warp update self` / `warp update --self`: aplica self-update local para flujo de desarrollo; si el remoto es mas nuevo, deja la marca normal de update pendiente.

## Diagnóstico rápido de MySQL con MySQLTuner (`warp mysql tuner`)

Se agregó un atajo operativo para ejecutar MySQLTuner sobre el servicio DB del proyecto.

Qué aporta al equipo:

- evita pasos manuales para descargar el script,
- usa carpeta de trabajo estándar (`./var` o `/tmp`),
- detecta si falta Perl e intenta instalación por distro conocida con confirmación previa,
- ejecuta MySQLTuner con conexión alineada al `.env` del proyecto (local o externa).

Comportamiento de conexión:

- entorno local con contenedor DB: usa `localhost` y puerto mapeado (`DATABASE_BINDED_PORT` o `docker-compose port`).
- si el puerto efectivo es `3306`, conecta a `localhost` sin forzar `--port`.
- entorno externo (`MYSQL_VERSION=rds`): usa `DATABASE_HOST`, `DATABASE_BINDED_PORT`, `DATABASE_USER`, `DATABASE_PASSWORD`.
- salida de logs del servidor filtrada por defecto para reducir ruido; usar `warp mysql tuner -vvv` para incluirla completa.
- color habilitado por defecto (salvo `--nocolor`).

Comando:

- `warp mysql tuner`: descarga/valida dependencias y ejecuta MySQLTuner.

## Dev dumps por aplicación (`warp mysql devdump`)

Se incorporó un flujo de dumps livianos para desarrollo basado en perfiles de exclusión por app.

Qué aporta al equipo:

- evita mantener scripts ad-hoc por proyecto,
- permite generar dumps más pequeños sin datos sensibles/voluminosos,
- habilita extensión simple agregando archivos de perfiles (sin tocar el core),
- soporta selección de perfil o combinación de todos para la misma app.

Comandos:

- `warp mysql devdump`: helper con descripción y apps disponibles.
- `warp mysql devdump:magento`: ejecuta devdump Magento con selección de perfiles.

## Soporte de base externa para `warp mysql` (modo `rds`)

Los comandos de MySQL ahora contemplan escenarios donde no hay servicio `mysql` en Docker y la base es externa.

Qué aporta al equipo:

- evita fallos ambiguos cuando el servicio `mysql` no está en `docker-compose-warp.yml`,
- permite pasar a modo externo con confirmación del operador,
- autocompleta credenciales desde `app/etc/env.php` cuando existe,
- usa cliente local para `connect` y `dump`, con instalación asistida si falta,
- permite limpiar `DEFINER` del stream del dump con una opción nativa.

Comandos afectados:

- `warp mysql connect`: en `rds` conecta a host externo.
- `warp mysql dump <db>`: en `rds` dumpea contra host externo.
- `warp mysql dump -s <db>` / `warp mysql dump --strip-definers <db>`: remueve cláusulas `DEFINER` del dump streameado antes de escribirlo.
- `warp mysql import <db>`: en `rds` no importa; imprime comando sugerido y password.

## Setup de Grunt más guiado (`warp grunt setup`)

Además del comando clásico de ejecución, ahora existe setup dedicado para Grunt:

- prepara archivos base cuando faltan,
- instala dependencias npm en contenedor,
- normaliza permisos para evitar bloqueos posteriores.

Qué aporta al equipo:

- menos fricción en proyectos legacy/frontend clásico,
- reducción de errores por permisos al instalar como root,
- mejor compatibilidad con distintos contenedores PHP.

Comandos:

- `warp grunt setup`: prepara archivos base e instala dependencias de Grunt.
- `warp grunt exec`: republica symlinks/artefactos frontend.
- `warp grunt less`: compila LESS/CSS.
- `WARP_GRUNT_PHP_CONTAINER=<container> warp grunt ...`: ejecuta contra un contenedor PHP específico.

## Compatibilidad de plataforma y versiones (Magento/OpenSearch)

Durante el último año también se incorporaron ajustes de compatibilidad para reducir fricción en upgrades y arranque de entornos.

Qué aporta al equipo:

- mejor soporte operativo para proyectos Magento en ramas recientes (incluyendo ajustes para 2.4.7/2.4.8),
- correcciones en setup de OpenSearch/Elasticsearch y variables asociadas,
- alineación de defaults de setup para PHP/MySQL y componentes auxiliares,
- menor riesgo de fallos de bootstrap por combinaciones de versión.

Impacto funcional:

- inicializaciones más estables con `warp init`,
- menos correcciones manuales post-setup,
- mayor consistencia entre proyectos al migrar versiones de stack.

## Resultado global para el equipo

En conjunto, estas mejoras apuntan a:

- estandarizar operaciones repetitivas,
- reducir variabilidad entre proyectos,
- mejorar seguridad operativa en deploy/update,
- acortar tiempos de diagnóstico y puesta a punto.
