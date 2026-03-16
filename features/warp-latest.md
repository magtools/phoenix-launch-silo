# Warp Latest: mejoras funcionales del último año

Fecha: 2026-03-16

Este documento resume las mejoras recientes de Warp desde una mirada funcional, orientada a uso diario del equipo.

## Deploy unificado por entorno (`warp deploy`)

Warp ahora incluye un flujo de deploy nativo para `local` y `prod`, con configuración por proyecto en `.deploy`.

Qué aporta al equipo:

- un comando estándar para deploy (`warp deploy run`),
- validación previa con `warp deploy doctor`,
- configuración visible con `warp deploy show`,
- generación guiada de `.deploy` con `warp deploy set`,
- simulación de receta sin ejecutar (`--dry-run`),
- ejecución exclusiva de frontend/estáticos con `warp deploy static`.

Comandos:

- `warp deploy`: muestra ayuda de deploy.
- `warp deploy run`: ejecuta deploy completo según `.deploy`.
- `warp deploy static`: ejecuta solo pasos de estáticos/frontend.
- `warp deploy set`: crea o actualiza `.deploy`.
- `warp deploy show`: muestra la configuración activa.
- `warp deploy doctor`: valida prerequisitos.

Impacto funcional:

- menos scripts ad-hoc por proyecto,
- mayor previsibilidad del orden de pasos,
- mejor seguridad operativa en producción (confirmaciones y gates).

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

## Diagnóstico de memoria y sugerencias (`warp memory report`)

Se incorporó un reporte de memoria orientado a análisis:

- uso de memoria por servicios clave (`php`, `mysql`, `elasticsearch`, `redis-*`),
- lectura de configuración actual (si existe),
- sugerencias automáticas de umbrales según RAM del host.

Qué aporta al equipo:

- decisiones de capacity/tuning basadas en datos,
- visibilidad rápida de desalineaciones entre uso real y configuración,
- salida en texto y JSON para troubleshooting y documentación.

Comandos:

- `warp memory report`: reporte funcional de uso/configuración/sugerencias.
- `warp memory report --no-suggest`: muestra uso + config actual sin recomendaciones.
- `warp memory report --json`: salida estructurada para automatización.

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
- separación clara entre actualización de Warp e imágenes Docker.

Qué aporta al equipo:

- upgrades más confiables,
- mejor visibilidad cuando hay versión nueva o fallos de conectividad,
- menor riesgo de cambios sorpresivos en configuración de proyecto.

Comandos:

- `warp update`: actualiza binario/framework de Warp.
- `warp update --images`: actualiza imágenes Docker del proyecto.
- `warp update self`: aplica self-update local para flujo de desarrollo.

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

## Resultado global para el equipo

En conjunto, estas mejoras apuntan a:

- estandarizar operaciones repetitivas,
- reducir variabilidad entre proyectos,
- mejorar seguridad operativa en deploy/update,
- acortar tiempos de diagnóstico y puesta a punto.
