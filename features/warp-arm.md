# Warp Arm: Graviton y Apple Silicon

Fecha: 2026-06-01

## 1. Objetivo

Investigar que haria falta para que el stack generado por Warp funcione de forma util y repetible en:

1. servidores AWS Graviton (`linux/arm64`, normalmente `aarch64`);
2. hardware Apple Silicon local (`macOS` en M1/M2/M3 con Docker Desktop).

El objetivo de este documento no es declarar soporte listo. El objetivo es dejar claro:

1. que partes ya son prometedoras;
2. que bloqueos existen hoy en el repo;
3. que cambios tecnicos harian falta para pasar de compatibilidad parcial a soporte operativo real.

Este documento complementa:

- [features/warp-infra.md](/srv2/www/htdocs/66/warp-engine/features/warp-infra.md)
- [features/warp-infra-buildarm.md](/srv2/www/htdocs/66/warp-engine/features/warp-infra-buildarm.md)
- [features/warp-infra-img.md](/srv2/www/htdocs/66/warp-engine/features/warp-infra-img.md)
- [features/warp-infra-img-php.md](/srv2/www/htdocs/66/warp-engine/features/warp-infra-img-php.md)

## 2. Conclusion corta

Hoy Warp no puede considerarse soportado de punta a punta en ARM.

La situacion real al 2026-06-01 es esta:

1. `arm64` en Mac tiene una base mejor porque Docker Desktop puede correr contenedores ARM nativos y emular `amd64` si hace falta.
2. AWS Graviton exige mas rigor: una imagen `amd64` no sirve como estrategia principal y la emulacion destruye parte del beneficio de `c7g`.
3. El repo ya tiene trabajo previo hacia multiarch, pero todavia hay imagenes y templates que siguen anclados a `x86_64`.
4. El bloqueo principal no es Nginx/Redis/MariaDB/OpenSearch; el bloqueo principal esta en deteccion de arquitectura, imagen PHP, Selenium, RabbitMQ/Postgres legacy y algunos defaults historicos.

Conclusion operativa:

1. para `arm64` nativo, Warp necesita una matriz declarativa de arquitectura por servicio;
2. necesita reemplazar o auditar imagenes custom historicas;
3. necesita dejar de tratar ARM como un caso especial de macOS y empezar a tratarlo como arquitectura de primer nivel.

Prioridad operativa pedida para este analisis:

1. stack principal: `nginx`, `php`, `mariadb`, `valkey`, `opensearch`, `mailpit`;
2. segundo nivel: `varnish`, `rabbitmq`;
3. tercer nivel: `selenium`, `postgres`, sandbox y el resto de componentes legacy.

Regla de imagenes deseada:

1. priorizar imagenes oficiales siempre que sea razonable;
2. aceptar imagen propia principalmente para `php`, porque ahi vive la personalizacion Magento/Warp;
3. crear otras imagenes custom solo si una necesidad real no puede resolverse con configuracion, bind mounts, entrypoints chicos o comandos de runtime.
4. tratar `appdata` como pieza base de Warp y no como parte del stack prioritario de este analisis.

Regla de nomenclatura deseada para imagenes ARM/multiarch:

1. usar el mismo repositorio y el mismo tag para `amd64` y `arm64`;
2. no usar sufijos como `-arm`, `-arm64` o variantes por arquitectura en el nombre del tag como estrategia principal;
3. publicar detras de ese mismo tag un manifest list / OCI image index multiarch;
4. dejar que Docker resuelva la plataforma por manifest.

Regla para distinguir imagen oficial vs custom en Warp:

1. `official`: imagen upstream mantenida por su proyecto o por Docker Official Images, por ejemplo `nginx`, `mariadb`, `valkey/valkey`, `opensearchproject/opensearch`, `axllent/mailpit`;
2. `custom`: imagen publicada por Warp o por el equipo para cubrir una necesidad propia, por ejemplo `magtools/php` y, si hiciera falta, `magtools/appdata`;
3. la diferencia no debe expresarse con sufijos de arquitectura, sino por el repositorio propietario;
4. la arquitectura se valida por manifest, no por el nombre.

## 3. Estado actual del repo

### 3.1 Lo que ya apunta en la direccion correcta

1. `php` ya usa `${PHP_IMAGE_REPO:-magtools}/php:${PHP_VERSION}` en [`.warp/setup/php/tpl/php.yml`](/srv2/www/htdocs/66/warp-engine/.warp/setup/php/tpl/php.yml).
2. la DB default del setup actual es `mariadb:10.11`, no `mysql`, en [`.warp/setup/mysql/tpl/database.env`](/srv2/www/htdocs/66/warp-engine/.warp/setup/mysql/tpl/database.env).
3. cache usa `redis:7.2` por defecto en [`.warp/setup/redis/tpl/redis.env`](/srv2/www/htdocs/66/warp-engine/.warp/setup/redis/tpl/redis.env).
4. search usa `opensearchproject/opensearch:2.19.5` por defecto en [`.warp/setup/elasticsearch/tpl/elasticsearch.env`](/srv2/www/htdocs/66/warp-engine/.warp/setup/elasticsearch/tpl/elasticsearch.env).
5. mail ya migro a Mailpit (`axllent/mailpit`) en [`.warp/setup/mailhog/tpl/mailhog.yml`](/srv2/www/htdocs/66/warp-engine/.warp/setup/mailhog/tpl/mailhog.yml).
6. ya existe analisis previo de builds ARM en [features/warp-infra-buildarm.md](/srv2/www/htdocs/66/warp-engine/features/warp-infra-buildarm.md).

### 3.2 Bloqueos concretos detectados

#### a) Deteccion ARM incompleta

Hay checks que usan solo:

```bash
uname -m == 'arm64'
```

Eso aparece en:

1. [`.warp/setup/php/php.sh`](/srv2/www/htdocs/66/warp-engine/.warp/setup/php/php.sh)
2. [`.warp/setup/mysql/database.sh`](/srv2/www/htdocs/66/warp-engine/.warp/setup/mysql/database.sh)
3. [`.warp/setup/varnish/varnish.sh`](/srv2/www/htdocs/66/warp-engine/.warp/setup/varnish/varnish.sh)

Problema:

1. en Apple Silicon suele verse `arm64`;
2. en Linux/Graviton suele verse `aarch64`.

Resultado:

El repo hoy parece tener ramas "ARM" que probablemente solo disparan en macOS y no en EC2 Graviton.

#### b) MySQL en ARM hoy no es nativo

Existe [`.warp/setup/mysql/tpl/database_arm.yml`](/srv2/www/htdocs/66/warp-engine/.warp/setup/mysql/tpl/database_arm.yml) con:

```yaml
platform: linux/x86_64
```

Eso no es soporte ARM real. Es un escape hatch para forzar imagen x86.

En AWS Graviton esto no deberia ser la estrategia default.

#### c) Servicios con imagenes legacy o custom no auditadas para ARM

Persisten referencias a:

1. `summasolutions/rabbitmq:${RABBIT_VERSION}` en [`.warp/setup/rabbit/tpl/rabbit.yml`](/srv2/www/htdocs/66/warp-engine/.warp/setup/rabbit/tpl/rabbit.yml)
2. `summasolutions/postgres:${POSTGRES_VERSION}` en [`.warp/setup/postgres/tpl/postgres.yml`](/srv2/www/htdocs/66/warp-engine/.warp/setup/postgres/tpl/postgres.yml)
3. `summasolutions/selenium:hub` y `selenium/node-chrome` en [`.warp/setup/selenium/tpl/docker-selenium-warp.yml`](/srv2/www/htdocs/66/warp-engine/.warp/setup/selenium/tpl/docker-selenium-warp.yml)
4. versions legacy de Varnish guiadas por [`.warp/setup/varnish/varnish.sh`](/srv2/www/htdocs/66/warp-engine/.warp/setup/varnish/varnish.sh)

Hasta no verificar manifests `linux/arm64` o reemplazarlas, esos servicios siguen siendo bloqueos.

#### d) Inconsistencias de imagen parametrizada

El script de PostgreSQL arma `POSTGRES_DOCKER_IMAGE=postgres:${psql_version}`, pero el template actual usa `summasolutions/postgres:${POSTGRES_VERSION}`.

Eso significa que incluso donde el setup parece querer ir hacia imagen oficial, el compose generado puede seguir anclado a imagen legacy.

#### e) Selenium actual no es apto como baseline ARM

El template actual usa `selenium/node-chrome`.

Para ARM esto es especialmente delicado:

1. Chrome Linux ARM no es el camino estable en Selenium;
2. Chromium/Firefox tienen mejor historia de soporte multiarch;
3. el hub custom `summasolutions/selenium:hub` agrega otro punto de incertidumbre.

## 4. Que haria falta para soportar AWS Graviton

Antes de hablar del stack completo, conviene separar dos objetivos:

1. lograr soporte ARM defendible para el stack principal;
2. extender despues a servicios secundarios y legacy.

Eso baja el riesgo y evita que Selenium o sandbox bloqueen una primera version util de Warp en ARM.

### 4.1 Tratar `arm64` como arquitectura nativa

Primer requisito:

1. crear una funcion comun, por ejemplo `warp_host_arch_normalize`, que devuelva algo estable como `amd64` o `arm64`;
2. mapear `x86_64 -> amd64`;
3. mapear `arm64` y `aarch64 -> arm64`;
4. dejar de usar `uname -m == 'arm64'` directo en subcomandos.

Sin eso, el comportamiento en M1 y en Graviton nunca va a ser consistente.

### 4.2 Definir una matriz de soporte por servicio

Warp necesita declarar, por servicio:

1. imagen default;
2. imagen recomendada para `amd64`;
3. imagen recomendada para `arm64`;
4. si la imagen es `native`, `emulated`, `blocked` o `legacy`;
5. si el servicio requiere override manual.

Eso deberia vivir idealmente en `.warp/variables.sh` y no disperso en ifs.

Esa matriz tambien deberia declarar el tipo de estrategia:

1. `official-first`;
2. `custom-required`;
3. `custom-optional`;
4. `legacy-only`.

### 4.3 Reemplazar defaults x86-only o no auditados

Para Graviton, el minimo defendible seria:

1. `php`: publicar y validar imagen propia `magtools/php` con manifest `linux/amd64,linux/arm64`.
2. `nginx`: fijar tag oficial y validar smoke del frontal principal.
3. `mariadb`: consolidarla como DB principal ARM con imagen oficial y no tratar `mysql` legacy como baseline.
4. `valkey`/`redis`: validar manifiestos y smokes con imagen oficial.
5. `opensearch`: validar imagen oficial, plugin `analysis-phonetic`, heap y persistencia.
6. `mailpit`: mantenerlo como backend mail default y validar smoke simple con imagen oficial.
7. `varnish`: intentar resolverlo con imagen oficial; solo customizar si de verdad hiciera falta algo no cubrible por VCL/config.
8. `rabbitmq`: migrar a imagen oficial multiarch antes de considerar una variante propia.
9. `postgres`: usar imagen oficial multiarch y alinear script/template; no mantener template amarrado a `summasolutions/postgres`.
10. `selenium`: migrar a imagenes oficiales modernas y, en ARM, usar `chromium` o `firefox` en vez de asumir `chrome`.
11. `appdata`: solo confirmar continuidad multiarch como pieza base de Warp, sin abrirlo como frente prioritario.

Verificacion concreta de `appdata` en el estado actual del repo:

1. el setup base escribe `APPDATA_IMAGE_REPO=magtools` y `APPDATA_VERSION=bookworm`;
2. por lo tanto la imagen efectiva a verificar primero es `magtools/appdata:bookworm`;
3. no alcanza con asumir que "appdata es multiarch": hay que inspeccionar el manifest publicado.
4. el resultado observado de `docker manifest inspect magtools/appdata:bookworm` fue un manifest simple `application/vnd.docker.distribution.manifest.v2+json`;
5. eso no es un manifest list / OCI image index multiarch;
6. por lo tanto, hoy `magtools/appdata:bookworm` no puede considerarse publicado como multiarch `linux/amd64,linux/arm64`.
7. la verificacion local adicional con `docker image inspect magtools/appdata:bookworm --format '{{.Os}}/{{.Architecture}}'` devolvio `linux/amd64`;
8. por lo tanto la publicacion actual confirmada de `magtools/appdata:bookworm` es `linux/amd64`.

### 4.4 Evitar emulacion como camino normal

En Graviton, la emulacion `amd64` solo deberia existir para:

1. troubleshooting;
2. compatibilidad temporal;
3. algun servicio auxiliar que no justifique inversion.

No deberia ser el camino default de `warp init`.

### 4.5 Probar datos y plugins reales

Que una imagen arranque no alcanza.

Para declarar soporte Graviton haria falta validar:

1. restore de DB real;
2. indexado OpenSearch real;
3. cron y consumers;
4. Composer con dependencias privadas;
5. extensiones PECL relevantes;
6. `mail()`, supervisor, cron y binds de volumen;
7. tests Selenium si el proyecto usa navegador automatizado.

## 5. Que haria falta para soportar Mac M1/M2/M3

### 5.1 Mantener nativo ARM como primera opcion

El objetivo local en Apple Silicon deberia ser el mismo:

1. usar contenedores `linux/arm64` cuando exista variante nativa;
2. usar emulacion `amd64` solo como compatibilidad, no como baseline.

### 5.2 Tener una degradacion controlada para imagenes legacy

En Mac tiene sentido permitir una capa de compatibilidad mejor que en Graviton, porque Docker Desktop puede emular `amd64`.

Pero Warp deberia decirlo explicitamente:

1. `native`: funciona normal;
2. `emulated`: funciona, pero con peor performance;
3. `blocked`: no se recomienda o no arranca.

Hoy esa informacion no se expone.

### 5.3 Tener en cuenta Docker Desktop actual

Para Apple Silicon hay dos notas importantes:

1. Docker Desktop permite builds multi-platform y emulacion por QEMU;
2. si se usa Docker VMM, Docker documenta que Rosetta no esta soportado ahi y la emulacion `amd64` puede ser lenta.

Eso implica que un stack Warp que dependa demasiado de `amd64` puede "funcionar" en M1 pero dar una experiencia mala o inconsistente.

### 5.4 No mezclar "soporta M1" con "soporta Graviton"

Estos dos escenarios se parecen, pero no son equivalentes:

1. un M1 local puede tolerar algunos servicios emulados;
2. un host EC2 Graviton para correr stack completo no deberia depender de eso.

Warp necesita documentar ambos perfiles por separado.

## 6. Matriz de lectura por servicio

### 6.1 Prioridad 1: stack principal

| Servicio | Estado actual | Lectura ARM | Que haria falta |
| --- | --- | --- | --- |
| `web` | Nginx via imagen oficial | bajo riesgo | fijar tags y validar smoke |
| `php` | `magtools/php` en template; legado `summasolutions` en varios historicos | bloqueo principal hasta validar manifests y extensiones | imagen propia multiarch y smoke real |
| `mariadb` | default moderno | candidato fuerte | mantener imagen oficial y validar restore, charset, perf y volumen |
| `valkey`/`redis` | imagenes modernas | candidato fuerte | mantener imagen oficial, smoke y manifest check |
| `opensearch` | imagen oficial configurable | candidato razonable | mantener imagen oficial y validar plugin `analysis-phonetic`, heap y datos |
| `mail` | Mailpit | bajo riesgo | smoke simple SMTP/UI |

Lectura:

1. este grupo deberia ser el objetivo inmediato de soporte ARM;
2. si este grupo queda estable, Warp ya gana una variante ARM util para muchos proyectos;
3. salvo `php`, este grupo deberia permanecer en enfoque `official-first`;
4. `php` sigue siendo el bloqueo principal del grupo y el candidato natural a imagen propia;
5. `mariadb`, `valkey`, `mailpit` y probablemente `nginx` son los candidatos mas simples;
6. `opensearch` necesita pruebas reales, pero sigue dentro del alcance prioritario.

### 6.2 Prioridad 2: servicios secundarios

| Servicio | Estado actual | Lectura ARM | Que haria falta |
| --- | --- | --- | --- |
| `varnish` | defaults historicos distintos por ARM | incierto | intentar imagen oficial primero; custom solo si la config no alcanza |
| `rabbitmq` | `summasolutions/rabbitmq` | incierto | migrar a imagen oficial multiarch |

Lectura:

1. no deberian bloquear la primera iteracion del stack principal;
2. si un proyecto no usa `varnish` o `rabbitmq`, Warp deberia poder quedar soportado igual para ARM en ese perfil;
3. `rabbitmq` merece atencion antes que Selenium/Postgres porque aparece mas cerca de stacks Magento reales.

### 6.3 Prioridad 3: resto y legacy

| Servicio | Estado actual | Lectura ARM | Que haria falta |
| --- | --- | --- | --- |
| `appdata` | pieza base de Warp, fuera del stack prioritario | imagen publicada hoy sin manifest multiarch observado | construir/publicar variante ARM o manifest multiarch y luego smoke |
| `mysql` | template ARM fuerza `linux/x86_64` | no nativo | preferir MariaDB o marcar MySQL legacy |
| `postgres` | template legacy `summasolutions/postgres` | incierto | migrar a oficial y alinear script/template |
| `selenium` | hub custom + `node-chrome` | bloqueo probable en ARM | migrar a Selenium oficial con `chromium`/`firefox` |

Lectura:

1. `appdata` sigue siendo importante como pieza base de Warp, pero no es parte del stack prioritario funcional pedido;
2. `mysql` legacy puede quedar fuera de la primera declaracion de soporte ARM;
3. `postgres`, `selenium` y sandbox no deberian frenar el avance sobre el core principal;
4. en este grupo tambien conviene agotar primero la opcion de imagen oficial antes de abrir una nueva imagen propia.
5. `appdata` ya no puede quedar solo como supuesto de continuidad porque la publicacion actual no expone manifest multiarch.

Chequeo recomendado para `appdata`:

```bash
docker manifest inspect magtools/appdata:bookworm
```

Resultado esperado:

1. presencia de variantes `linux/amd64` y `linux/arm64`;
2. si existe `linux/arm64`, `appdata` queda como dependencia resuelta y solo requiere smoke;
3. si no existe `linux/arm64`, entonces `appdata` deja de ser solo continuidad y pasa a ser tarea concreta del plan.

Resultado observado:

1. el comando devolvio un manifest simple y no una lista multiarch;
2. `appdata` pasa a ser tarea concreta del plan ARM.
3. la inspeccion local de imagen confirmo `linux/amd64`.

Chequeos recomendados para cualquier imagen futura:

```bash
docker manifest inspect --verbose <repo>:<tag>
docker image inspect <repo>:<tag> --format '{{.Os}}/{{.Architecture}}'
```

Lectura recomendada:

1. si el manifest devuelve `manifest.list.v2+json` u `image.index.v1+json`, tratar la imagen como candidata multiarch;
2. si devuelve `manifest.v2+json`, tratarla como single-platform;
3. usar el repo para distinguir `official` vs `custom`;
4. usar el manifest para distinguir `single-platform` vs `multiarch`.

## 7. Cambios minimos recomendados en Warp

### Fase 1. Higiene de arquitectura

1. normalizar deteccion `amd64`/`arm64`;
2. reemplazar checks `uname -m == 'arm64'`;
3. introducir una ayuda tipo `warp host arch` o `warp doctor arm`;
4. reportar al usuario si un servicio quedara `native`, `emulated` o `blocked`.

### Fase 2. Limpiar defaults que rompen ARM

1. retirar `platform: linux/x86_64` del camino default de ARM;
2. alinear PostgreSQL para que el template use la imagen parametrizada real;
3. revisar RabbitMQ y Selenium como bloqueos de primer orden;
4. documentar que `mysql` legacy y `node-chrome` no son baseline ARM.

### Fase 3. Cerrar stack principal

1. publicar `magtools/php` multiarch;
2. validar `nginx`, `mariadb`, `valkey`, `opensearch` y `mailpit` como perfil ARM principal usando imagenes oficiales;
3. construir/publicar `magtools/appdata:bookworm` con variante `linux/arm64` o manifest multiarch;
4. hacer smoke de continuidad sobre `appdata` ya publicado;
5. validar `linux/amd64` y `linux/arm64` con el mismo compose;
6. definir politica clara para ionCube y binarios legacy x86-only.

### Fase 4. Servicios de segundo nivel

1. cerrar `varnish`;
2. cerrar `rabbitmq`;
3. confirmar que no degradan el perfil principal.

### Fase 5. Validacion de stack real y resto

1. proyecto Magento moderno en M1;
2. proyecto Magento moderno en EC2 Graviton;
3. flujo `warp init`, `warp start`, `warp info`, `warp stop`;
4. restore DB, reindex, cron, cache, search y mail;
5. luego Selenium y servicios legacy si aplica.

## 8. Criterio realista de soporte

Warp podria declarar soporte ARM solo si se cumplen estas condiciones:

1. `warp init` detecta correctamente `arm64` en macOS y `aarch64` en Linux;
2. `warp start` no depende por default de `platform: linux/x86_64`;
3. PHP y appdata tienen imagenes multiarch publicadas;
4. Selenium, RabbitMQ y Postgres dejan de depender de imagenes legacy no auditadas o quedan marcados como no soportados;
5. la ayuda y la documentacion dicen explicitamente que funciona nativo y que queda solo en compatibilidad.

Si esos puntos no se cumplen, la forma correcta de presentarlo es:

```text
Warp tiene compatibilidad parcial en Apple Silicon y soporte experimental/no declarado en AWS Graviton.
```

## 9. Recomendacion practica

La secuencia mas razonable seria:

1. no prometer ARM general todavia;
2. cerrar primero el stack principal `nginx/php/mariadb/valkey/opensearch/mailpit`;
3. corregir deteccion `aarch64`;
4. eliminar defaults x86 forzados;
5. mantener enfoque `official-first` para todo salvo `php`, salvo que aparezca una limitacion real;
6. verificar manifest de `magtools/appdata:bookworm`;
7. si falta `linux/arm64`, agregar creacion/publicacion de imagen ARM para `appdata`;
8. si `appdata` ya es multiarch, mantenerlo solo como pieza base de continuidad;
9. cerrar despues `varnish` y `rabbitmq`;
10. migrar Selenium/Postgres/sandbox fuera del legado cuando el core ya este estable;
11. validar un stack moderno real antes de tocar perfiles legacy.

La mejor apuesta inicial no es "todo Warp en ARM".

La mejor apuesta inicial es:

1. Magento moderno;
2. Nginx;
3. PHP;
4. MariaDB local o externa;
5. Valkey o Redis;
6. OpenSearch;
7. Mailpit;
8. imagenes oficiales en todo lo posible;
9. `appdata` como base de Warp, con verificacion de continuidad pero fuera del stack prioritario;
10. despues `varnish` y `rabbitmq`.

## 10. Fuentes externas consultadas

Fuentes oficiales o primarias usadas para esta investigacion:

1. AWS Graviton containers guide: https://aws.github.io/graviton/containers.html
2. Docker multi-platform builds: https://docs.docker.com/build/building/multi-platform/
3. Docker Desktop settings para Apple Silicon y emulacion `amd64`: https://docs.docker.com/desktop/settings-and-maintenance/settings/
4. Docker Desktop VMM en Mac: https://docs.docker.com/desktop/features/vmm/
5. Docker Desktop install on Mac: https://docs.docker.com/installation/mac/
6. Selenium Docker multi-arch support: https://github.com/SeleniumHQ/docker-selenium
7. Docker Official Images program: https://github.com/docker-library/official-images
8. Docker Official PHP image packaging: https://github.com/docker-library/php

## 11. Resumen final

Si la pregunta es "se puede?", la respuesta es si, pero no con el estado actual del repo como esta hoy.

Si la pregunta es "que hace falta?", la respuesta corta es:

1. deteccion de arquitectura correcta;
2. imagen multiarch real para `php`;
3. enfoque `official-first` para el resto del stack principal;
4. salir de defaults legacy `summasolutions/*`;
5. no depender de emulacion `x86_64` para DB ni Selenium;
6. verificar manifest de `magtools/appdata:bookworm`;
7. si falta `linux/arm64`, incluir creacion/publicacion de imagen ARM para `appdata`;
8. validacion real en M1 y en Graviton antes de declararlo soportado.
