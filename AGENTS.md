# AGENTS.md

## 1) Alcance del repositorio

Este repositorio **no es una aplicación Magento**.  
Es un **framework/helper CLI en Bash** para crear y operar infraestructura Docker Compose para proyectos PHP (Magento, Oro o PHP genérico).

Estado del repositorio:

- este repo/fork se mantiene como puente de compatibilidad e histórico;
- la continuidad activa del proyecto vive en `https://github.com/magtools/phoenix-launch-silo`.

Objetivo principal del agente en este repo:

- Mantener y mejorar el comando `warp`.
- Preservar compatibilidad de inicialización (`warp init`) y operación (`warp start/stop`).
- Evitar cambios riesgosos o destructivos sin confirmación explícita.

## 2) Arquitectura base

Puntos de entrada y capas:

- `warp.sh`: entrypoint principal, validaciones, dispatch de comandos, auto-instalación por payload `__ARCHIVE__`.
- `.warp/variables.sh`: rutas, nombres de archivos, versiones mínimas, matrices de PHP/extensiones.
- `.warp/includes.sh`: carga librerías y todos los subcomandos.
- `.warp/lib/*.sh`: utilidades compartidas (env, checks, red, mensajes, preguntas).
- `.warp/bin/*.sh`: implementación de comandos (`init`, `start`, `stop`, `php`, `mysql`, `logs`, etc.).
- `.warp/setup/*`: wizard, plantillas y generación de `.env` / `docker-compose-warp.yml` / configs.

## 3) Flujos operativos canónicos

Secuencia esperada:

1. `./warp init` (o `--no-interaction` / `--mode-gandalf`)
2. `./warp start`
3. `./warp info` / `./warp logs`
4. `./warp stop` (o `./warp stop --hard`)

Comandos clave de mantenimiento:

- `warp php switch <version>`
- `warp mysql switch <version>`
- `warp update` (actualización del binario/framework)
- `warp update --images`
- `warp docker <args>`

## 4) Guía de release y update

Reglas actuales del proceso de release:

- `release.sh` debe setear `WARP_VERSION` con fecha `yyyy.mm.dd` antes del build.
- `release.sh` debe generar `dist/version.md` con esa fecha.
- `release.sh` debe generar `dist/sha256sum.md` con SHA-256 de `dist/warp`.

Reglas actuales del proceso de update runtime:

- Fuente remota:
  - base URL: `https://raw.githubusercontent.com/magtools/phoenix-launch-silo/refs/heads/master/dist`
  - `dist/version.md`
  - `dist/sha256sum.md`
  - `dist/warp`
- Directorio temporal: `./var/warp-update`.
- Estado persistente de aviso: `./var/warp-update/.pending-update`.
- Validación obligatoria de checksum SHA-256 antes de reemplazar `./warp`.
- La actualización de `.warp` debe extraer payload en temporal y copiar al proyecto **sin tocar** `.warp/docker/config`.
- `warp update` no debe ejecutar wizard ni `init`, ni procesos de setup que modifiquen `config`.
- Al finalizar, limpiar contenido temporal de update (la carpeta `var` puede quedar).
- Si `warp` queda actualizado, `.pending-update` debe quedar vacío.
- Si hay versión más nueva, `.pending-update` debe contener mensaje visible de update pendiente.
- Si falla la lectura remota, `.pending-update` debe contener mensaje de error de conexión.

Reglas de chequeo automático de versión:

- Frecuencia: cada 7 días (archivo `.self-update-warp`).
- Si el check remoto falla: reintento en 1 día (no en 7).
- Excluir comandos: `mysql`, `start`, `stop`.
- El chequeo automático se ejecuta al final del comando (no al inicio), para no perder visibilidad.
- El chequeo automático informa versión nueva disponible; no debe disparar setup ni update automático.
- La salida pendiente/error debe mostrarse al final de cada comando (excepto exclusiones) leyendo `.pending-update`.
- No debe existir ningún path de update que dispare `warp_setup --force`, `warp_setup update` o `--self-update`.

## 5) Reglas para cambios de código

- Priorizar cambios en plantillas y setup:
  - `.warp/setup/*/tpl/*`
  - `.warp/setup/*/*.sh`
- Evitar hardcodear lógica específica de Magento si aplica al core genérico.
- Mantener comportamiento Linux/macOS cuando corresponda.
- No romper compatibilidad de variables existentes en `.env` y `.env.sample`.
- Si se agrega un comando, incluir:
  - archivo `.warp/bin/<cmd>.sh`
  - archivo `.warp/bin/<cmd>_help.sh`
  - inclusión en `.warp/includes.sh`
  - dispatch en `warp.sh` si aplica
- Si un subcomando necesita invocar `warp` desde otro script Bash:
  - **no asumir** que `warp` existe en `PATH`;
  - reutilizar el patrón ya establecido en `.warp/bin/deploy.sh` (`deploy_warp_exec`);
  - resolver en este orden:
    - `./warp`
    - `./warp.sh`
    - `warp`
  - usar ese entrypoint resuelto para llamadas internas como `magento`, `search`, `hyva`, etc.

## 6) Seguridad y operaciones destructivas

Acciones consideradas destructivas o sensibles:

- `warp reset --hard`
- `warp volume --rm <php|mysql>`
- `rm -rf` sobre `.warp/docker/volumes/*` o `.warp/`
- operaciones con `sudo`, `chown`, `chmod` masivo (ej. `warp fix ...`)

Regla obligatoria para agentes:

- **Pedir confirmación explícita al usuario** antes de ejecutar cualquier acción destructiva o de permisos masivos.
- Si el impacto es ambiguo, asumir riesgo y pedir confirmación.

## 7) Supuestos de entorno

- Requiere `docker` y Compose en alguna de estas variantes:
  - `docker-compose >= 1.29` (legacy v1),
  - `docker compose` (plugin v2).
- Warp implementa fallback interno: si falta `docker-compose` pero existe `docker compose`, genera shim local en `./var/warp-bin/docker-compose`.
- No se requiere ni se recomienda crear symlink global de `docker-compose` como solución por defecto.
- Patrón adoptado para comandos que pueden ejecutar sobre un contenedor PHP existente:
  - exponer override explícito por env var (`WARP_<FEATURE>_PHP_CONTAINER=<container_name>`),
  - validar primero con `docker inspect --format '{{.State.Running}}'` que el contenedor exista y esté corriendo,
  - si el override existe y está corriendo, ejecutar con `docker exec -i ...`,
  - si no hay override, usar el flujo estándar del proyecto (`docker-compose exec` / runtime host según corresponda),
  - si el override existe pero no está corriendo, abortar con mensaje claro `container not running: <name>`.
- También requiere `ed` y `tr`.
- En macOS pueden intervenir `docker-sync` y `rsync`.
- Para flujos con `warp rsync`, asumir mínimo `rsync >= 3.1.1` (en macOS el `rsync` del sistema puede ser incompatible).
- La configuración de proyecto (`.env`, `docker-compose-warp.yml`, variantes `-mac`, `-dev`, `-selenium`) puede no existir hasta correr `warp init`.
- Para Elasticsearch, puede requerirse configuración de host (`vm.max_map_count=262144`) según SO.
- Si se usan imágenes de DB privadas (ECR/registry privado), considerar expiración de token/login como causa común de fallos en `pull`.

## 8) Estrategia de validación mínima

Luego de cambios en core/setup/comandos, validar como mínimo:

1. `./warp --help`
2. `./warp init --help`
3. `./warp start --help`
4. `./warp stop --help`
5. `./warp info --help`
6. `./warp docker ps` (smoke compose passthrough)

Si este repo fuente no incluye binario `./warp`, usar fallback equivalente:

1. `bash ./warp.sh --help`
2. `bash ./warp.sh init --help`
3. `bash ./warp.sh start --help`
4. `bash ./warp.sh stop --help`
5. `bash ./warp.sh info --help`
6. `bash ./warp.sh docker ps` (smoke compose passthrough)

Si el cambio toca comandos específicos, validar también su `--help` y un smoke básico del flujo afectado.

## 9) Fuentes de verdad internas

Orden de prioridad para entender comportamiento real:

1. Código en `warp.sh`, `.warp/lib`, `.warp/bin`, `.warp/setup`
2. `README.md`
3. `wiki_docs/*`
4. `CHANGES.md`

Si hay conflicto entre docs y código, **prevalece el código** y se debe documentar la discrepancia.

Notas sobre documentación:

- `wiki_docs/` es la fuente editable de documentación.
- `docs/` es output generado de MkDocs (no editar manualmente HTML/CSS generado salvo necesidad explícita de build/publicación).
- Parte de la wiki es legacy (versiones/comandos históricos); validar siempre contra el código actual antes de implementar cambios.
- `features/` contiene documentación funcional de Warp (estado/decisiones por feature); no es necesario cargarla al inicio, solo considerar que está disponible como referencia puntual.

## 10) Reglas operativas adicionales

- Tras `warp init`, validar `.gitignore` para evitar versionar artefactos de framework (`.warp/bin`, `.warp/lib`, `.warp/setup`, dumps/volúmenes, etc.).
- En errores de `warp start` por puertos (`80/443`), priorizar diagnóstico no destructivo (servicios locales ocupando puertos) antes de sugerir `reset`.
- En troubleshooting, preferir primero acciones reversibles; para `reset --hard` o borrado de volúmenes, pedir confirmación explícita.

## 11) Estilo de colaboración recomendado

- Proponer cambios pequeños y reversibles.
- Explicar impacto en `init/start/stop` antes de editar.
- Enumerar riesgos en cambios de red, volúmenes y permisos.
- Para refactors grandes: separar en pasos y validar en cada paso.
