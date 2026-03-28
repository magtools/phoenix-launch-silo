# Warp Security

Fecha: 2026-03-28
Estado: relevamiento inicial de amenazas y fase 1 funcional para `warp security check`

## Objetivo

Diseñar una capacidad de detección de intrusión orientada a proyectos PHP, con foco operativo en:

1. Magento / Adobe Commerce,
2. Nginx + PHP-FPM,
3. malware de eCommerce reciente,
4. salida resumida por pantalla,
5. evidencia detallada en log para análisis posterior.

La meta no es competir con un EDR ni con un WAF. La meta es detectar temprano señales de:

1. compromiso ya ocurrido,
2. explotación activa,
3. persistencia,
4. skimming/backdoors,
5. configuración peligrosa que vuelve triviales ciertos ataques recientes.

## Principio de diseño

El detector de Warp no debe depender de una sola IOC rígida.

Debe combinar:

1. heurísticas de acceso web,
2. señales de filesystem,
3. señales de procesos/cron/persistencia,
4. artefactos Magento,
5. correlación temporal.

Idea central:

1. CLI: resumen muy corto, tipo semáforo + hallazgos principales.
2. Log: timeline detallado con evidencia, paths, requests, IPs, user-agent, hashes, snippets y scoring.

## 1) Panorama actual de amenazas

Para Magento/PHP/eCommerce, los ataques que más importan hoy no son solo CVEs aislados sino cadenas completas:

1. acceso inicial por bug público o credencial filtrada,
2. upload o escritura de payload,
3. persistencia fuera de la superficie obvia,
4. skimmer o backdoor reutilizable,
5. exfiltración por canales cada vez menos visibles.

La tendencia reciente es clara:

1. campañas masivas automatizadas en horas o días tras disclosure,
2. abuso intensivo de REST API y superficies guest,
3. uso de polyglots y uploads aparentemente benignos,
4. persistencia en DB/config/layout además de archivos,
5. skimmers que evaden CSP y monitoreo HTTP clásico,
6. movimientos desde compromiso Magento hacia persistencia de host.

## 2) Familias de ataques prioritarias

## 2.1 PolyShell (Magento / Adobe Commerce)

Relevancia: critica y muy reciente.

Fecha clave:

1. 2026-03-17: publicación técnica de Sansec.
2. 2026-03-19: primeros ataques observados.
3. 2026-03-24: Sansec ya reporta abuso activo y payloads en stores expuestos.

Qué hace:

1. explota upload no autenticado vía REST API,
2. escribe archivos en `pub/media/custom_options/quote/`,
3. permite subir polyglots GIF/PNG que también contienen PHP,
4. según webserver config deriva en:
   - RCE,
   - stored XSS,
   - o payload dormido listo para activarse luego.

Tretas observadas:

1. filenames como `index.php`, `json-shell.php`, `bypass.phtml`, `rce.php`, `static.php`,
2. uso de nombres unicode escapados,
3. payloads con `GIF89a` + PHP,
4. shell con auth por cookie y `eval(base64_decode())`,
5. shell con password que llama `system()`.

Por qué importa para Warp:

1. es ideal para detección por filesystem,
2. tiene endpoints y rutas concretas de acceso,
3. depende mucho de si Nginx/Apache ejecuta o expone uploads,
4. encaja perfecto con un check de hardening más un scan de artefactos.

Señales detectables:

1. requests a `POST /V1/guest-carts/:cartId/items`
2. requests a `PUT /V1/guest-carts/:cartId/items/:itemId`
3. creación/modificación reciente en `pub/media/custom_options/`
4. archivos con magic bytes de imagen y contenido PHP en el mismo archivo
5. extensiones `.php`, `.phtml`, `.phar`, `.html` sospechosas dentro de uploads
6. presencia de strings como `GIF89a;<?php`, `eval(base64_decode`, `hash_equals(`, `system($_REQUEST`

## 2.2 WebRTC skimmer post-compromiso

Relevancia: alta y muy moderna.

Fecha clave:

1. 2026-03-24: Sansec publica skimmer con exfiltración por WebRTC DataChannels.

Qué cambia respecto del skimmer clásico:

1. ya no depende solo de `fetch`, XHR o beacon HTTP,
2. usa `RTCPeerConnection` y DataChannels,
3. evade controles basados en CSP `connect-src`,
4. evade inspección centrada en tráfico HTTP.

Lectura operativa:

1. no es necesariamente el vector inicial,
2. es un payload de segunda etapa muy compatible con PolyShell o con compromisos previos.

Señales detectables:

1. inyecciones JS que crean `RTCPeerConnection`
2. `createDataChannel`
3. SDP/ICE hardcodeado
4. IPs hardcodeadas en JS ofuscado
5. código que inyecta segundo stage dinámico en checkout

Esto obliga a que el IDS no mire solo PHP y logs de acceso:

1. también debe inspeccionar JS servido o inyectado,
2. especialmente en templates, CMS blocks y header/footer.

## 2.3 SessionReaper (Magento / Adobe Commerce)

Relevancia: critica.

Fechas clave:

1. 2025-08: descubrimiento de la falla.
2. 2025-09-09: hotfix público de Adobe.
3. 2025-10-22: primeros ataques masivos observados por Sansec.
4. inicios de 2025-11: Sansec reporta alcance muy amplio de probing/ataques.

Qué hace:

1. takeover de cuentas y RCE bajo ciertas condiciones,
2. combina sesión maliciosa con bug de deserialización anidada en REST API,
3. en campañas observadas sube backdoors PHP vía `customer/address_file/upload`,
4. Adobe parchó la deserialización, pero Sansec señaló que el upload arbitrario seguía siendo una superficie riesgosa.

Tretas observadas:

1. fake session files,
2. probing de `phpinfo`,
3. webshells PHP en paths de media relacionados a customer address,
4. abuso de endpoints de customer address upload.

Señales detectables:

1. requests a rutas relacionadas con `customer/address_file/upload`
2. archivos recientes en `pub/media/customer_address/`
3. sesiones o uploads con contenido PHP
4. picos de requests REST seguidos por creación de webshell
5. request patterns con user-agents automatizados y bursts cortos

## 2.4 CosmicSting y fallout de agosto-octubre 2024

Relevancia: critica y probablemente la campaña más definitoria del período.

Fechas clave:

1. 2024-06-11: Adobe publica fix inicial.
2. 2024-06-18: Sansec alerta que 75% de los stores seguían expuestos.
3. 2024-07-12: Sansec ve explotación masiva.
4. 2024-08-27: Sansec reporta escalada con CNEXT para RCE persistente.
5. 2024-10-01: Sansec reporta miles de stores comprometidos por campañas competidoras.

Qué hace:

1. `CVE-2024-34102` permite lectura arbitraria de archivos,
2. robo de crypt key de Magento,
3. abuso posterior de API/admin token y CMS blocks,
4. combinado con `CVE-2024-2961` (CNEXT/iconv/glibc) escala a RCE,
5. luego deja backdoors persistentes y skimmers.

Tretas observadas:

1. cart IDs de prueba heredados como `test-ambio`,
2. requests con `python-requests/2.32.3`,
3. 4xx/5xx que igual pueden corresponder a explotación exitosa,
4. robo de crypt key y posterior modificación remota del store,
5. inyección de JS de skimming por CMS blocks o header/footer.

Persistencia host-level observada por Sansec en esta cadena:

1. drop de `~/.config/htop/defunct` y `defunct.dat`,
2. cronjobs que reviven el proceso,
3. gsocket oculto con nombres tipo kernel thread,
4. WebSocket skimmers hacia dominios efímeros.

Señales detectables:

1. logs REST sobre `estimate-shipping-methods`
2. presencia de `test-ambio`
3. `python-requests` en momentos anómalos
4. cambios en CMS blocks/layout/config tras esos accesos
5. archivos `defunct`, `defunct.dat`
6. entradas de crontab sospechosas con base64
7. procesos disfrazados como `[raid5wq]`, `[kswapd0]`, etc.

## 2.5 Persistencia Magento oculta en XML / DB

Relevancia: alta.

Fecha clave:

1. 2024-04-04: Sansec documenta backdoor persistente en XML.

Qué hace:

1. usa `layout_update` en base de datos para reinyectar malware,
2. aprovecha el parser de layout y componentes presentes por default,
3. hace que archivos regenerados vuelvan a infectarse.

Por qué importa:

1. una limpieza basada solo en filesystem no alcanza,
2. explica reinfecciones “misteriosas” de `Interceptor.php` u otros archivos generados.

Señales detectables:

1. contenido anómalo en `layout_update`
2. XML con fragments incompatibles con uso normal
3. referencias a comandos de sistema, sed, assert, eval, payload encodado
4. correlación entre request a carrito/checkout y reaparición de backdoor

## 2.6 TrojanOrder y template exploits heredados

Relevancia: alta aunque no nueva.

Fechas clave:

1. 2022: disclosure y campañas principales.
2. 2023-2024: sigue habiendo stores comprometidos por reversiones o fixes vencidos.

Qué hace:

1. RCE a través de parsing/template/mail flows,
2. puede instalar backdoor aunque el store “parezca parchado”,
3. en algunos casos el síntoma visible es una orden o customer extraño.

Señales detectables:

1. customer names/addresses extraños tipo `system`, `pwd`,
2. emails/órdenes señuelo,
3. activity rara en pedidos inmediatamente antes de cambios en archivos
4. vendors que reintroducen funcionalidad insegura tras un patch oficial

## 2.7 Compromiso de extensiones y supply chain

Relevancia: alta.

No todo entra por el core:

1. módulos vulnerables o abandonados,
2. vendors comprometidos,
3. secretos expuestos en integraciones,
4. backdoors “de soporte” reutilizables.

Casos relevantes del ecosistema:

1. FishPig comprometido en 2022,
2. ConnectPOS con exposición grave reportada por Sansec en 2026,
3. MGT Varnish con backdoor crítico reportado en 2025.

Señales detectables:

1. archivos vendor/module modificados fuera de release normal,
2. módulos no reconocidos o con timestamps extraños,
3. firmas conocidas de backdoor en extensiones,
4. desvío entre `composer.lock` y código realmente desplegado,
5. credenciales hardcodeadas o llaves expuestas en módulos.

## 2.8 PHP webshells genéricas

Relevancia: muy alta como resultado final de casi cualquier compromiso.

Patrones recurrentes:

1. `eval(base64_decode(...))`
2. `assert`, `preg_replace /e`, `create_function`, `system`, `passthru`, `shell_exec`
3. polyglots GIF/PNG con PHP
4. nombres cortos y neutros: `c.php`, `r.php`, `static.php`, `cache.php`
5. uploads en directorios aparentemente inocentes

Esto no basta para atribuir campaña, pero sí para scoring alto de intrusión.

## 2.9 Malware residente en host: CronRAT / NginRAT / gsocket

Relevancia: alta en incidentes ya avanzados.

Qué aportan:

1. persistencia fuera de la app,
2. exfiltración server-side,
3. camuflaje dentro de procesos del sistema o Nginx,
4. supervivencia a limpieza parcial del código web.

Señales detectables:

1. crons ofuscados/base64
2. uso de `LD_PRELOAD`
3. `LD_L1BRARY_PATH` con typo, indicador histórico de NginRAT
4. binarios/artefactos en `/dev/shm`, `~/.config/htop`, `.cache`, tmp
5. conexiones salientes raras de `nginx` o procesos hijo

## 3) Tretas más comunes, eficaces o modernas

Resumen ejecutivo:

### Más comunes

1. webshell PHP simple,
2. skimmer JS en checkout,
3. credenciales admin filtradas o reutilizadas,
4. módulos/vendor inseguros,
5. reinfección desde DB/layout/config.

### Más eficaces

1. fallas RCE/XXE sin auth en Magento,
2. robo de crypt key + abuso de API/admin token,
3. uploads arbitrarios en media con ejecución por webserver,
4. persistencia host-level con cron/gsocket/Nginx injection.

### Más modernas o recientes

1. PolyShell con polyglot upload y dependencia del webserver config,
2. WebRTC skimmer que evade CSP y herramientas HTTP,
3. SessionReaper con fake sessions y address upload,
4. cadenas CosmicSting + CNEXT,
5. backdoors DB/XML que sobreviven a limpieza de archivos.

## 4) Qué debería detectar Warp primero

Prioridad 1:

1. PolyShell
2. SessionReaper
3. CosmicSting fallout
4. webshells PHP genéricas

Prioridad 2:

1. persistencia DB/XML
2. skimmers JS
3. persistence host-level tipo gsocket/NginRAT

Prioridad 3:

1. supply chain drift en módulos,
2. hardening gaps de Nginx/Apache/PHP que vuelven explotable un payload ya subido.

## 5) Superficies de detección recomendadas

## 5.1 Access logs

Buscar:

1. guest cart REST abuse,
2. `estimate-shipping-methods`,
3. `customer/address_file/upload`,
4. bursts con `python-requests`, `curl`, user-agents raros,
5. 4xx/5xx correlacionados con escritura en disco,
6. requests a uploads ejecutables en `pub/media/*`.

## 5.2 Filesystem

Buscar:

1. PHP/PHTML/PHAR/HTML sospechoso en `pub/media`, `var`, `generated`, `pub/static`,
2. polyglots imagen+PHP,
3. webshell strings,
4. timestamps recientes en uploads,
5. `.htaccess` o reglas locales alteradas,
6. indicadores `defunct`, `defunct.dat`, `/dev/shm/*`,
7. drift inesperado en `pub/` según `git status`,
8. archivos sin trackear dentro de `pub/` fuera de una allowlist de paths conocidos,
9. presencia de PHP dentro de `pub/media`, `pub/static` o `pub/opt`.

## 5.2.1 Archivo `.known-paths`

Se propone un archivo versionable en root del proyecto:

1. `.known-paths`

Contrato:

1. un path por línea,
2. paths relativos al root del proyecto,
3. comentarios con `#`,
4. pensado para paths requeridos pero no trackeados, por ejemplo:
   - `pub/.well-known`
   - `pub/media/tmp`
   - `var/quarantine`

Regla importante:

1. que un path exista en `.known-paths` evita alertar solo por su existencia o por estar untracked,
2. pero no desactiva reglas de contenido peligroso dentro del path,
3. en particular, si hay PHP dentro de un path conocido bajo `pub/`, sigue siendo hallazgo.

Creación:

1. `warp security scan` y `warp security check` crean `.known-paths` si no existe.

## 5.2.2 Archivo `.known-files`

Se propone un archivo versionable en root del proyecto:

1. `.known-files`

Contrato:

1. un archivo relativo por línea,
2. comentarios con `#`,
3. sin glob patterns,
4. pensado para archivos esperados del proyecto que no deben contar por sí solos como “PHP inesperado”.

Uso inicial:

1. entrypoints core en `pub/`, por ejemplo:
   - `pub/cron.php`
   - `pub/get.php`
   - `pub/health_check.php`
   - `pub/index.php`
   - `pub/static.php`

Regla importante:

1. que un archivo exista en `.known-files` evita marcarlo solo por existir como PHP esperado,
2. no desactiva reglas de IOC o contenido sospechoso,
3. si ese archivo aparece modificado según Git, Warp lo reporta en una verificación separada.

Creación:

1. `warp security scan` y `warp security check` crean `.known-files` si no existe.

## 5.2.3 Archivo `.known-findings`

Se propone un archivo versionable en root del proyecto:

1. `.known-findings`

Contrato:

1. un finding conocido por línea,
2. formato: `path|indicator|class`,
3. comentarios con `#`,
4. pensado para hallazgos aceptables y específicos, sin blanquear todo el archivo.

Ejemplo:

1. `pub/errors/processor.php|$_POST|risky primitive`

Regla importante:

1. `.known-findings` aplica a findings derivados de contenido en `scan` y `check`,
2. no desactiva otros indicadores del mismo archivo,
3. no reemplaza `.known-paths` ni `.known-files`; los complementa.

Creación:

1. `warp security scan` y `warp security check` crean `.known-findings` si no existe.

## 5.3 Magento DB

Buscar:

1. `layout_update` anómalo,
2. CMS blocks/pages con `eval`, `base64`, `WebSocket`, `RTCPeerConnection`,
3. config sospechosa en core_config_data,
4. usuarios admin nuevos o alterados,
5. integraciones/tokens anómalos,
6. newsletter/phishing abuse.

## 5.4 Web assets / JS

Buscar:

1. websocket o WebRTC inyectado,
2. dominios/IPs hardcodeados,
3. nonce stealing,
4. ofuscación XOR/base64 pesada,
5. exfil channels no HTTP.

## 5.5 Host persistence

Buscar:

1. cron sospechoso,
2. procesos con nombres tipo kernel thread falsos,
3. `LD_PRELOAD`,
4. conexiones salientes de `nginx`,
5. binarios o keys escondidos en home/tmp/shm/config dirs.

## 6) Superficie CLI propuesta

Comando raíz:

1. `warp security`
   - muestra ayuda y overview.

Subcomandos iniciales:

1. `warp security check`
   - ejecuta análisis read-only,
   - produce resumen corto en pantalla,
   - escribe log detallado en `var/log`.
2. `warp security toolkit`
   - no analiza ni modifica nada,
   - imprime comandos sugeridos de análisis y limpieza manual,
   - puede filtrar por familia (`--family`) o superficie (`--surface`).

Flags sugeridos para `check`:

1. `--family <polyshell|sessionreaper|cosmicsting|webshell|xml|skimmer|host>`
2. `--surface <logs|fs|db|js|host|all>`
3. `--logs <ruta>`
4. `--since <date|relative>`
5. `--json`
6. `--log-file <ruta>`

Flags sugeridos para `toolkit`:

1. `--family <...>`
2. `--surface <...>`
3. `--format <text|json>`
4. `--with-cleanup`

Regla operativa obligatoria:

1. `warp security check` solo ejecuta comandos no destructivos.
2. `warp security toolkit` puede listar comandos destructivos, pero Warp no los ejecuta.
3. cualquier cleanup debe quedar explícitamente en manos del operador.

## 7) Toolkit inicial de comandos

El toolkit debe separar dos grupos:

1. análisis (`read-only`)
2. limpieza (`manual/destructiva`)

Formato deseado:

```text
[TOOLKIT]
FAMILY: polyshell

[ANALYSIS]
find pub/media/custom_options -type f
find pub/media/custom_options -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" \)
grep -RInE "GIF89a|<\?php|eval\(base64_decode|system\(" pub/media/custom_options

[CLEANUP - MANUAL]
find pub/media/custom_options -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" \) -delete
```

## 7.1 Toolkit por superficie

### Filesystem

Análisis:

1. `find pub/media -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" -o -name "*.html" \)`
2. `find pub/media/custom_options -type f`
3. `find pub/media/customer_address -type f`
4. `find var generated pub/static -type f \( -name "*.php" -o -name "*.phtml" \)`
5. `find . -type f -mtime -7`
6. `grep -RInE "eval\\(base64_decode|assert\\(|system\\(|shell_exec\\(|passthru\\(" pub/media var generated pub/static app vendor`
7. `grep -RIl "<?php" pub/media`
8. `grep -RInE "RTCPeerConnection|createDataChannel|new WebSocket|wss://" app pub vendor`
9. `git status --porcelain --untracked-files=all -- pub`
10. `find pub/media pub/static pub/opt -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" \) 2>/dev/null`
11. `cat .known-paths`
12. `grep -RInE "<\\?php|base64_decode\\(|passthru\\(|system\\(|shell_exec\\(|assert\\(|proc_open\\(" pub/media pub/opt`
13. `grep -RInE "<\\?php|md5\\(\\$_COOKIE\\[\"d\"\\]\\)|md5\\(\\$_COOKIE\\['d'\\]\\)|new Function\\(event\\.data\\)|RTCPeerConnection|createDataChannel|new WebSocket|wss://" pub/static`
13. `grep -R --line-number 'md5($_COOKIE\\["d"\\])' .`
14. `grep -RInE 'md5\\(\\$_COOKIE\\["d"\\]\\)|md5\\(\\$_COOKIE\\['\''d'\''\\]\\)|new Function\\(event\\.data\\)|preg_replace\\s*\\(.*/e|(^|[^[:alnum:]_])create_function\\s*\\(|hash_equals\\(md5\\(|\\$_REQUEST\\["password"\\]' app pub var generated`

Limpieza manual:

1. `find pub/media -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" \) -delete`
2. `find pub/media/custom_options -type f -delete`
3. `find pub/media/customer_address -type f -delete`
4. `rm -f <path-sospechoso>`
5. `mv <path-sospechoso> var/quarantine/`

Nota:

1. para Warp conviene preferir `mv ... var/quarantine/` como cleanup sugerido más seguro antes que `-delete`.

### Access logs

Análisis:

1. `grep -RIn "estimate-shipping-methods" /var/log/nginx /var/log/httpd`
2. `grep -RIn "customer/address_file/upload" /var/log/nginx /var/log/httpd`
3. `grep -RInE "guest-carts/.*/items" /var/log/nginx /var/log/httpd`
4. `grep -RInE "python-requests|curl|Go-http-client" /var/log/nginx /var/log/httpd`
5. `grep -RIn "test-ambio" /var/log/nginx /var/log/httpd`
6. `awk '$9 ~ /404|500|502|503|504/' /var/log/nginx/access.log`

Limpieza manual:

1. no aplica limpieza directa sobre logs
2. como acción sugerida: rotar, preservar copia y extraer evidencia antes de cualquier cleanup

### Magento DB

Análisis:

1. `./warp db connect` y luego queries read-only sobre:
2. `layout_update`
3. `cms_block`
4. `cms_page`
5. `core_config_data`
6. `admin_user`
7. `integration`

Ejemplos de queries a emitir en toolkit:

1. `SELECT layout_update_id, handle, xml FROM layout_update WHERE xml REGEXP 'eval|base64|WebSocket|RTCPeerConnection|system\\(';`
2. `SELECT block_id, title, identifier FROM cms_block WHERE content REGEXP 'eval|base64|wss://|WebSocket|RTCPeerConnection';`
3. `SELECT config_id, path FROM core_config_data WHERE value REGEXP 'eval|base64|wss://|WebSocket';`
4. `SELECT user_id, username, created, modified FROM admin_user ORDER BY modified DESC;`

Limpieza manual:

1. `UPDATE ...` o `DELETE ...` específicos contra rows confirmadas como maliciosas
2. deshabilitar usuarios/admin tokens sospechosos
3. restaurar contenido legítimo desde backup conocido

Regla:

1. Warp no debe emitir `DELETE FROM ...` genérico sin identificación previa de row concreta.

### Host / persistence

Análisis:

1. `crontab -l`
2. `grep -RInE "defunct|base64|LD_PRELOAD|gsocket" /etc/cron* /var/spool/cron /var/spool/cron/crontabs`
3. `ps auxww | grep -E "\\[raid5wq\\]|\\[kswapd0\\]|defunct|gsocket|nginx: worker process"`
4. `grep -al LD_L1BRARY_PATH /proc/*/environ 2>/dev/null`
5. `find /dev/shm ~/.config ~/.cache -maxdepth 3 -type f`

Limpieza manual:

1. `crontab -e`
2. `kill -9 <pid>`
3. `rm -f ~/.config/htop/defunct ~/.config/htop/defunct.dat`
4. `rm -f /dev/shm/php-shared`

### Nginx / webserver hardening

Análisis:

1. `grep -RIn "location" /etc/nginx /usr/local/nginx/conf`
2. `grep -RIn "php" /etc/nginx /usr/local/nginx/conf`
3. `grep -RIn "custom_options" /etc/nginx /usr/local/nginx/conf`
4. `nginx -T | grep -n "custom_options"`

Limpieza manual:

1. editar config para impedir ejecución PHP en uploads
2. reload manual de nginx luego de validar config

Regla:

1. Warp puede sugerir `nginx -t` y el diff deseado, pero no recargar ni tocar config automáticamente en esta feature.

## 7.2 Toolkit por familia

### PolyShell

Análisis:

1. `find pub/media/custom_options -type f`
2. `find pub/media/custom_options -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" -o -name "*.html" \)`
3. `grep -RInE "GIF89a|<\\?php|eval\\(base64_decode|system\\(" pub/media/custom_options`
4. `grep -RInE "guest-carts/.*/items" <access-log>`

Limpieza manual:

1. `mv pub/media/custom_options/<file> var/quarantine/`
2. `find pub/media/custom_options -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" \) -delete`

### SessionReaper

Análisis:

1. `find pub/media/customer_address -type f`
2. `grep -RIn "customer/address_file/upload" <access-log>`
3. `grep -RIl "<?php" pub/media/customer_address`

Limpieza manual:

1. `mv pub/media/customer_address/<file> var/quarantine/`
2. `find pub/media/customer_address -type f -delete`

### CosmicSting / CNEXT fallout

Análisis:

1. `grep -RIn "estimate-shipping-methods" <access-log>`
2. `grep -RIn "test-ambio" <access-log>`
3. `find ~/.config/htop -maxdepth 2 -type f`
4. `crontab -l | grep -n "defunct"`
5. `ps auxww | grep -E "raid5wq|kswapd0|defunct"`

Limpieza manual:

1. `crontab -e`
2. `kill -9 <pid>`
3. `rm -f ~/.config/htop/defunct ~/.config/htop/defunct.dat`

### XML / DB persistence

Análisis:

1. queries sobre `layout_update`
2. export puntual de rows sospechosas
3. comparación con backup sano

Limpieza manual:

1. `UPDATE layout_update SET xml=<clean> WHERE layout_update_id=<id>;`
2. `DELETE FROM layout_update WHERE layout_update_id=<id>;`

### JS skimmer / WebSocket / WebRTC

Análisis:

1. `grep -RInE "new WebSocket|wss://|RTCPeerConnection|createDataChannel" app pub vendor`
2. `grep -RInE "sellerstat|statsseo|inspectdlet|iconstaff" app pub vendor`
3. queries sobre `cms_block` y `cms_page`

Limpieza manual:

1. restaurar template/CMS block limpio
2. remover referencia a dominio o payload ofuscado

## 8) Especificación ejecutable de `warp security check`

## 7.5 `warp security scan`

`warp security scan` es el paso rápido y heurístico.

Objetivo:

1. dar una señal breve al operador,
2. decidir si conviene correr `warp security check`,
3. reutilizar `.known-paths` para bajar ruido en drift no trackeado esperado.

Contrato:

1. no escribe log detallado,
2. imprime solo un resumen corto por pantalla,
3. usa `git status --porcelain --untracked-files=all` sobre `pub`, `app`, `bin`, `generated`, `var`,
4. usa `.known-paths` solo para suavizar `??` conocidos,
5. no suaviza `M`, `D`, `R` aunque el path esté en `.known-paths`,
6. corre un grep heurístico relajado sobre funciones de ejecución/ofuscación en código PHP,
7. suma una señal JS liviana para `WebSocket` / `WebRTC`.
8. excluye señales genéricas de `new WebSocket` en librerías conocidas de `pub/static`, como `jquery/uppy`, pero mantiene alertas si aparece `wss://`, `RTCPeerConnection`, `createDataChannel` o `new Function(event.data)`.
9. suma un check rápido de PHP bajo `pub/` excluyendo `pub/errors` y cualquier archivo listado en `.known-files`; ese check solo eleva score y marca `[FOUND]`, sin listar paths en `attention paths`.
10. suma además un check rápido para detectar si archivos listados en `.known-files` fueron modificados según Git; también eleva score sin listar paths.

Salida esperada:

1. `suspicion: none|low|medium|high`
2. `status: <frase operativa>`
3. `score: N`
4. `drift signals: N`
5. `code signals: N`
6. hasta `30` attention paths
7. si hay más, agrega `showing 30/N`
8. si el umbral es `medium` o `high`, sugerir `warp security check`

## 8.1 Pipeline de ejecución

`warp security check` fase 1 corre hoy en este orden:

1. resolver contexto del proyecto
   - root path
   - tipo de app detectada
   - fecha/hora de corrida
   - rutas de logs disponibles
2. inicializar log detallado en `var/log/warp-security.log`
3. ejecutar reglas read-only por superficie:
   - git drift en `pub/`
   - drift específico de archivos listados en `.known-files`
   - filesystem en `pub/media`, `pub/static`, `pub/opt`
   - señales JS modernas en `app` y `pub` (`WebSocket`, `WebRTC`)
   - firmas IOC en `app`, `pub`, `var`, `generated`
   - access logs legibles en rutas típicas
   - persistencia básica de host (`crontab`, `~/.config/htop`, `/dev/shm`, `ps`)
   - db queda para la siguiente iteración
4. normalizar hallazgos
5. asignar score por regla y por familia
6. colapsar hallazgos duplicados
7. calcular severity global
8. imprimir resumen corto
9. sugerir `warp security toolkit --family ...` según las familias detectadas
10. exponer `score`, `severity` y una línea `status` global

Formato actual del log:

1. ruta fija: `var/log/warp-security.log`
2. copia histórica por corrida: `var/log/warp-security-yyyymmdd-hhmm.log`
3. retención de históricos: últimos `10`
4. cada sección comienza con:
   - nombre de sección
   - `discovery: <comando>`
   - `cleanup: <comando manual>`
5. luego deja un salto de línea y lista hallazgos, o `No findings.`
6. entre secciones inserta:
   - un salto de línea
   - una línea de `=` de 100 columnas
   - otro salto de línea

## 8.2 Reglas iniciales de fase 1

Cada regla debe definir:

1. `id`
2. `family`
3. `surface`
4. `command`
5. `match logic`
6. `score`
7. `evidence formatter`
8. `toolkit mapping`

### Regla FS-001: PHP en `pub/media`

Objetivo:

1. detectar shells o uploads ejecutables donde no deberían existir.

Comando base:

1. `find pub/media -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" \)`

Match:

1. cada path encontrado genera hallazgo.

Score:

1. `70` base
2. `+20` si está en `pub/media/custom_options`
3. `+15` si está en `pub/media/customer_address`

Toolkit:

1. `polyshell`
2. `sessionreaper`
3. `webshell`

### Regla FS-002: Polyglot imagen + PHP

Comando base:

1. `grep -RInE "GIF89a|<\\?php" pub/media/custom_options pub/media/customer_address`

Match:

1. archivo con marca de imagen y tag PHP cercano.

Score:

1. `90`

Toolkit:

1. `polyshell`
2. `sessionreaper`

### Regla FS-003: Strings típicos de webshell

Comando base:

1. `grep -RInE "eval\\(base64_decode|assert\\(|system\\(|shell_exec\\(|passthru\\(" pub/media var generated pub/static app`

Match:

1. ocurrencia en archivo no vendor-core conocido.

Score:

1. `85`

Toolkit:

1. `webshell`

### Regla FS-004: drift en `pub/` según Git

Objetivo:

1. detectar cambios o archivos no trackeados dentro de `pub/` que no estén explicados por el proyecto.

Comando base:

1. `git status --porcelain --untracked-files=all -- pub`

Match:

1. archivo modificado, agregado o untracked dentro de `pub/`,
2. excluyendo paths que matcheen `.known-paths`.

Score:

1. `20` base para drift no explicado
2. `+20` si el path está bajo `pub/media`, `pub/static` o `pub/opt`
3. `+40` si además la extensión es `.php`, `.phtml` o `.phar`

Toolkit:

1. `webshell`
2. `polyshell`

### Regla FS-008: firmas IOC conocidas

Objetivo:

1. detectar backdoors o webshells que coinciden con firmas específicas de alta señal.

Comando base:

1. `grep -RInE 'md5\\(\\$_COOKIE\\["d"\\]\\)|md5\\(\\$_COOKIE\\['\''d'\''\\]\\)|new Function\\(event\\.data\\)|preg_replace\\s*\\(.*/e|(^|[^[:alnum:]_])create_function\\s*\\(|hash_equals\\(md5\\(|\\$_REQUEST\\["password"\\]' app pub var generated`

Match:

1. cualquier ocurrencia de estas firmas fuera de vendor permitido.
2. esta regla debe ignorar superficies de build/log de bajo valor operativo para IOC, por ejemplo `*/node_modules/*`, `var/log/*` y `var/hyva*/*`.

Score:

1. `90`
2. `+10` si está bajo `pub/`
3. `+10` si además el archivo está untracked o modificado según Git

Toolkit:

1. `webshell`
2. `skimmer`

### Regla FS-005: PHP en `pub/static` o `pub/opt`

Objetivo:

1. detectar código ejecutable en superficies públicas donde no debería existir.

Comando base:

1. `find pub/static pub/opt -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" \) 2>/dev/null`

Match:

1. cada path encontrado genera hallazgo.

Score:

1. `80`

Toolkit:

1. `webshell`
2. `hardening`

### Regla FS-006: path conocido con PHP ejecutable

Objetivo:

1. evitar falsos negativos en paths permitidos como `pub/.well-known`.

Comando base:

1. `find <known-path> -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" \)`

Match:

1. path listado en `.known-paths` que contiene PHP ejecutable.

Score:

1. `85`

Toolkit:

1. `webshell`

### Regla FS-007: tretas PHP-like en archivos no PHP dentro de `pub/`

Objetivo:

1. detectar payloads camuflados en archivos con extensiones no PHP dentro de superficies públicas.

Comando base:

1. `grep -RInE "<\\?php|base64_decode\\(|passthru\\(|system\\(|shell_exec\\(|assert\\(|proc_open\\(" pub/media pub/opt`
2. en `pub/static`, evitar firmas genéricas de JS como `assert(`; limitarse a PHP real o IOCs conocidas de webshell/skimmer

Match:

1. ocurrencia de estas tretas en archivos que no terminan en `.php`, `.phtml` o `.phar`.

Score:

1. `75`
2. `+15` si el archivo está en `pub/media/custom_options` o `pub/media/customer_address`
3. `+10` si además hay drift por Git en `pub/`

Nota:

1. `eval(` solo no se usa como patrón principal en esta regla para evitar ruido con JS minificado, especialmente en `pub/static`.

Toolkit:

1. `webshell`
2. `polyshell`

### Regla LOG-001: actividad `guest-carts` sospechosa

Comando base:

1. `grep -RInE "guest-carts/.*/items" <access-log>`

Match:

1. requests sobre rutas asociadas a PolyShell.

Score:

1. `25`
2. `+15` si user-agent contiene `python-requests`, `curl` o similar
3. `+15` si hay correlación temporal con FS-001/FS-002

Toolkit:

1. `polyshell`

### Regla LOG-002: `estimate-shipping-methods` / `test-ambio`

Comando base:

1. `grep -RInE "estimate-shipping-methods|test-ambio" <access-log>`

Match:

1. request o burst compatible con CosmicSting.

Score:

1. `35`
2. `+25` si hay correlación con cambios en DB/CMS o artefactos host-level

Toolkit:

1. `cosmicsting`

### Regla LOG-003: `customer/address_file/upload`

Comando base:

1. `grep -RIn "customer/address_file/upload" <access-log>`

Match:

1. request a surface conocida de SessionReaper.

Score:

1. `35`
2. `+25` si hay artefactos en `pub/media/customer_address`

Toolkit:

1. `sessionreaper`

### Regla JS-001: WebSocket/WebRTC sospechoso

Comando base:

1. `grep -RInE "new WebSocket|wss://|RTCPeerConnection|createDataChannel" app pub vendor`

Match:

1. ocurrencia en templates, CMS export, JS custom o static assets del proyecto.
2. `new WebSocket` aislado en librerías conocidas de `pub/static` como `jquery/uppy` no se trata como hallazgo por sí solo.
3. si esa misma librería contiene además `wss://`, `RTCPeerConnection`, `createDataChannel` o `new Function(event.data)`, la señal se mantiene.

Nota:

1. `event.data` genérico ya no se usa como finding por sí solo en `scan`/`check`, porque produce demasiado ruido legítimo en módulos custom y de terceros.

Score:

1. `60`
2. `+20` si aparece en checkout/cart/payment templates
3. `+20` si coincide con dominios IOC conocidos

Toolkit:

1. `skimmer`

### Regla HOST-001: artefactos `defunct` / `gsocket`

Comando base:

1. `find ~/.config/htop /dev/shm -maxdepth 3 -type f`
2. `crontab -l`
3. `ps auxww`

Match:

1. `defunct`, `defunct.dat`, `php-shared`
2. crons con base64 o relanzado persistente
3. procesos disfrazados con nombres tipo kernel thread
4. nombres como `[kswapd0]` o `[raid5wq]` no deben contar por sí solos; solo se consideran hallazgo si ya hay otros indicios host-level en la misma sección.

Score:

1. `95`

Toolkit:

1. `cosmicsting`
2. `host`

### Regla DB-001: `layout_update` sospechoso

Comando base:

1. query regex sobre `layout_update`

Match:

1. filas con `eval`, `base64`, `WebSocket`, `RTCPeerConnection`, `system(`

Score:

1. `90`

Toolkit:

1. `xml`

### Regla DB-002: CMS/content skimmer

Comando base:

1. query regex sobre `cms_block`, `cms_page`, `core_config_data`

Match:

1. `wss://`, `WebSocket`, `RTCPeerConnection`, dominios IOC, ofuscación fuerte

Score:

1. `80`

Toolkit:

1. `skimmer`
2. `xml`

## 8.3 Reglas de correlación

No alcanza con reglas sueltas. Fase 1 debería sumar correlación simple:

1. si `LOG-001` + `FS-001/002` ocurren juntos:
   - elevar familia `polyshell` a `high/critical`
2. si `FS-004` + `FS-001` o `FS-005` ocurren juntos:
   - elevar `webshell` o `polyshell` porque hay drift confirmado en `pub/`
3. si `FS-004` + `FS-007` ocurren juntos:
   - elevar `webshell` porque hay drift y tretas PHP-like camufladas en archivos no PHP
4. si `FS-008` + `FS-004` ocurren juntos:
   - elevar a `critical` porque hay IOC específica conocida más drift real
5. si `FS-006` ocurre:
   - elevar a `high` aunque el path esté permitido en `.known-paths`
6. si `LOG-003` + artefacto en `pub/media/customer_address`:
   - elevar `sessionreaper`
7. si `LOG-002` + `HOST-001`:
   - elevar `cosmicsting`
8. si `DB-001` + `FS-003`:
   - elevar `db-persistence`
9. si `JS-001` + dominio IOC:
   - elevar `skimmer`

## 8.4 Modelo de scoring global

Cada hallazgo debe tener:

1. `rule_score`
2. `family_score`
3. `global_score_contribution`

Propuesta inicial:

1. score global = máximo score correlacionado de familia + bonus por diversidad de superficies
2. bonus:
   - `+10` si hay evidencia en 2 superficies
   - `+20` si hay evidencia en 3 o más superficies
   - `+15` si hay correlación temporal fuerte

Severidad resultante:

1. `0-24` => `low`
2. `25-49` => `medium`
3. `50-79` => `high`
4. `80-100` => `critical`

## 8.5 Salida corta de `check`

Debe incluir:

1. severity global
2. cantidad de hallazgos
3. familias probables
4. conteos por superficie
5. path del log
6. hint de toolkit contextual

Ejemplo:

```text
[SECURITY]
SEVERITY: critical
FINDINGS: 6
LIKELY_FAMILIES: polyshell, php-webshell
SURFACES: fs=3 logs=2 js=0 db=0 host=1
LOG: var/log/warp-security-2026-03-28_191500.log

- suspicious PHP file in pub/media/custom_options/quote/...
- guest-carts/items requests match PolyShell pattern
- image/PHP polyglot markers found

Toolkit:
warp security toolkit --family polyshell --with-cleanup
```

## 8.6 Log detallado de `check`

Secciones sugeridas:

1. metadata
2. inputs y rutas usadas
3. reglas ejecutadas
4. hallazgos crudos
5. correlaciones
6. scoring final
7. toolkit sugerido

Formato sugerido:

```text
[RULE FS-002]
family=polyshell
score=90
path=pub/media/custom_options/quote/7/rce.php
sha256=<hash>
snippet=GIF89a...<?php ...
mtime=2026-03-28 18:51:02

[RULE LOG-001]
family=polyshell
score=40
request=POST /rest/default/V1/guest-carts/.../items
ip=193.93.193.74
ua=python-requests/2.32.3
status=500
time=2026-03-28T18:49:10-03:00

[CORRELATION]
family=polyshell
score=100
reason=guest-carts abuse + executable upload + polyglot markers
```

## 8.7 Selección contextual de `toolkit`

`warp security toolkit` puede funcionar en dos modos:

1. estático
   - imprime todos los comandos de una familia o superficie.
2. contextual
   - lee el log indicado por `--from-log`
   - imprime solo los comandos relevantes a los hallazgos detectados.

Contrato sugerido:

1. `warp security toolkit --family polyshell`
2. `warp security toolkit --surface fs`
3. `warp security toolkit --from-log var/log/warp-security.log`

Regla:

1. si existe correlación `polyshell`, mostrar primero análisis y cleanup de `pub/media/custom_options` y logs `guest-carts`.
2. si existe correlación `sessionreaper`, mostrar primero análisis y cleanup de `pub/media/customer_address`.
3. si existe `FS-004`, mostrar primero `git status --porcelain -- pub`, `git diff -- pub` y comandos de cuarentena.
4. si existe `FS-008`, mostrar primero los `grep` IOC específicos y el path exacto a cuarentenar.
5. si el log muestra `guest-carts` o `customer/address_file/upload`, priorizar `polyshell` y `sessionreaper`.
6. si el log muestra `estimate-shipping-methods`, `test-ambio` o persistencia de host, priorizar `cosmicsting`.
5. si existe `host`, mostrar toolkit de cron/process antes que limpieza de app.
6. si existe `db/xml`, mostrar queries de export antes que cualquier `UPDATE/DELETE`.

## 8.8 Scope de fase 1 vs fase 2

Fase 1:

1. filesystem
2. logs
3. js
4. host
5. toolkit estático
6. soporte de `.known-paths` para reducir falsos positivos en `pub/`
7. regla explícita: PHP en `pub/media`, `pub/static`, `pub/opt` o dentro de un path conocido bajo `pub/` sigue siendo hallazgo

Fase 2:

1. db online
2. toolkit contextual desde log
3. IOC packs versionados
4. baseline para diff entre corridas
5. allowlist por proyecto

## 9) Propuesta de salida futura para Warp

## 9.1 Resumen por pantalla

Debe ser breve.

Ejemplo conceptual:

```text
[SECURITY]
SEVERITY: high
FINDINGS: 4
LIKELY_FAMILIES: polyshell, php-webshell, db-persistence
SUSPICIOUS_REQUESTS: 18
SUSPICIOUS_FILES: 3
SUSPICIOUS_DB_ITEMS: 2
LOG: var/log/warp-security-2026-03-28_143200.log
```

Y debajo, solo 3 a 5 bullets de hallazgo principal:

1. archivo PHP detectado en `pub/media/custom_options/...`
2. requests REST guest compatibles con PolyShell
3. `layout_update` con contenido ejecutable

## 9.2 Log detallado

Debe incluir:

1. timestamp de ejecución,
2. contexto host/app,
3. versión Magento/PHP/Nginx si se pudo detectar,
4. timeline de requests sospechosos,
5. paths y hashes de archivos,
6. snippets seguros y truncados,
7. queries/artefactos DB,
8. scoring por familia,
9. remediaciones sugeridas.

## 10) Criterios de scoring sugeridos

### Critical

1. webshell confirmado,
2. PolyShell payload en `pub/media/custom_options`,
3. persistence host-level confirmada,
4. JS skimmer activo en checkout,
5. `layout_update` claramente ejecutable.

### High

1. access log compatible + archivo sospechoso,
2. request pattern de campaña conocida + cambio en CMS/DB,
3. proceso o cron muy compatible con IOC conocida.

### Medium

1. hardening roto pero sin payload hallado,
2. requests de probing sin evidencia de persistencia,
3. obfuscación sospechosa aislada.

### Low

1. configuración riesgosa,
2. versión vulnerable sin evidencia de abuso,
3. artefacto ambiguo sin correlación.

## 11) Implicancias para implementación

La primera versión útil de Warp IDS debería:

1. no depender de root,
2. funcionar aunque Magento no esté corriendo en Docker,
3. tolerar host-mode,
4. poder leer logs Nginx/Apache si se indica ruta,
5. operar en modo read-only,
6. escribir evidencia en `var/log`.

## 12) Fase 1 recomendada

Construir detección para:

1. PolyShell,
2. SessionReaper,
3. CosmicSting/CNEXT fallout,
4. PHP webshells genéricas,
5. XML/DB persistence básica,
6. JS skimmer con WebSocket/WebRTC.

Con eso ya se cubre una parte muy alta del riesgo práctico actual en Magento.

## 13) Fuentes base del relevamiento

Magento / Adobe / campañas:

1. Sansec research index: `https://sansec.io/research`
2. Sansec SessionReaper: `https://sansec.io/research/sessionreaper`
3. Sansec CosmicSting persistent backdoor: `https://sansec.io/research/cosmicsting-cnext-persistent-backdoor`
4. Sansec CosmicSting fallout: `https://sansec.io/research/cosmicsting-fallout`
5. Sansec persistent XML backdoor: `https://sansec.io/research/magento-xml-backdoor`
6. Sansec menu injection / admin takeover: `https://sansec.io/research/magento-menu-bar-hack`
7. Sansec TrojanOrder background: `https://sansec.io/research/trojanorder-magento`
8. Adobe security bulletins, KBs y hotfixes oficiales para `CVE-2024-34102`
9. Adobe security bulletins, KBs y hotfixes oficiales para `CVE-2025-54236`

PHP / host malware:

1. Huntress PHP webshell overview: `https://www.huntress.com/threat-library/malware/php-webshell`
2. Sansec NginRAT: `https://sansec.io/research/nginrat`

## 14) Conclusión operativa

Para Warp, el mejor retorno no está en “detectar cualquier malware del universo”.

Está en detectar muy bien estas familias:

1. uploads ejecutables y polyglots,
2. abuse de REST guest/customer endpoints,
3. persistence en DB/layout/CMS,
4. skimmers JS modernos,
5. persistencia host-level típica de compromisos eCommerce.

Ese recorte es defendible, útil y directamente accionable para equipos que operan Magento sobre PHP/Nginx.
