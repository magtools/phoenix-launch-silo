# RFC: migracion de MailHog a Mailpit con autenticacion en warp

## Resumen

`warp` hoy expone un servicio `mailhog` y lo conecta con PHP/Magento usando `mailhog:1025`. Mailpit es compatible con el mismo esquema de puertos (`1025` SMTP y `8025` UI/API) y soporta autenticacion HTTP nativa para UI y API mediante **basic auth**.

La recomendacion es migrar a Mailpit usando **autenticacion nativa de Mailpit para UI/API** y **sin activar autenticacion SMTP en la primera etapa**. Eso permite proteger el acceso web sin romper el flujo actual de envio de correo local desde PHP/Magento.

## Estado actual relevado

### Servicio Docker

- `docker-compose-warp.yml`
- `docker-compose-warp.yml.sample`

Actualmente existe:

```yaml
mailhog:
  image: mailhog/mailhog
  hostname: "mailhog"
  ports:
    - 1025
    - "${MAILHOG_BINDED_PORT}:8025"
```

Hallazgos:

1. La UI se publica en host con `MAILHOG_BINDED_PORT`.
2. SMTP usa `1025`.
3. El puerto SMTP esta publicado via `ports`, aunque PHP ya habla por red interna del compose.

### PHP / Magento

- `.warp/docker/config/php/php.ini`
- `.warp/setup/php/config/php/php.ini`

Actualmente PHP apunta a MailHog:

```ini
smtp_port = 1025
SMTP = mailhog
sendmail_path = "/usr/local/bin/mhsendmail --smtp-addr=mailhog:1025"
```

### CLI y setup de warp

Superficies detectadas:

- `warp`
- `.warp/bin/mailhog.sh`
- `.warp/bin/mailhog_help.sh`
- `.warp/setup/mailhog/mailhog.sh`
- `.warp/setup/mailhog/tpl/mailhog.yml`
- `.warp/setup/init/developer.sh`
- `.warp/setup/init/autoload.sh`
- `.warp/setup/init/gandalf.sh`
- `.warp/bin/init.sh`

Hoy `warp` tiene un comando dedicado `warp mailhog` y el wizard de setup genera el bloque MailHog y la variable `MAILHOG_BINDED_PORT`.

### Nginx

- `docker-compose-warp.yml` monta `./.warp/docker/config/nginx/auth:/etc/nginx/auth`
- varios vhosts ya contemplan `auth_basic`, aunque en local esta comentado

Esto significa que existe una alternativa por reverse proxy con auth en nginx, pero **no es necesaria** para este cambio porque Mailpit ya resuelve auth de UI/API de forma nativa.

## Capacidades relevantes de Mailpit

Segun la documentacion oficial:

1. Mantiene puertos por defecto `1025` (SMTP) y `8025` (UI/API).
2. Soporta **basic auth** para UI/API con `MP_UI_AUTH_FILE` o `MP_UI_AUTH`.
3. Soporta auth SMTP, pero eso exige TLS o `MP_SMTP_AUTH_ALLOW_INSECURE=true`.
4. Si se usa reverse proxy, hay que preservar `Host` y websocket headers.

## Decision recomendada

### Recomendacion principal

Implementar la migracion en **dos etapas**:

1. **Etapa 1: reemplazo funcional**
   - Cambiar la imagen MailHog por Mailpit.
   - Activar auth solo en UI/API.
   - Mantener SMTP local sin auth.
   - Dejar el acceso web publicado solo en loopback del host.
   - Evitar publicar SMTP al host.

2. **Etapa 2: limpieza de naming**
   - Renombrar comando `warp mailhog` a `warp mailpit`.
   - Renombrar variables `MAILHOG_*` a `MAILPIT_*`.
   - Actualizar ayudas, wizard y templates.
   - Mantener alias backward-compatible temporal si se quiere evitar romper habitos del equipo.

## Por que no activar auth SMTP ahora

El flujo actual de PHP/Magento usa un relay local simple:

```ini
sendmail_path = "/usr/local/bin/mhsendmail --smtp-addr=mailhog:1025"
```

Si se activa auth SMTP en Mailpit:

1. hay que confirmar que el binario/flujo actual soporta autenticacion de la forma esperada;
2. si se exige auth sin TLS, Mailpit requiere `MP_SMTP_AUTH_ALLOW_INSECURE=true`;
3. se agrega complejidad a un caso donde el trafico ya vive dentro de la red Docker del proyecto.

Para un entorno de desarrollo, la mejor practica aca es:

- **proteger UI/API**, que son las superficies expuestas al operador;
- **dejar SMTP solo interno**, sin exposicion innecesaria al host.

## Cambios necesarios

## 1. Docker Compose

Archivos:

- `docker-compose-warp.yml`
- `docker-compose-warp.yml.sample`

### Cambio minimo para reemplazo funcional

Opcion conservadora:

- mantener el nombre del servicio `mailhog` en la etapa 1;
- cambiar solo la imagen a Mailpit;
- agregar configuracion de auth de Mailpit;
- no tocar aun PHP.

Ejemplo:

```yaml
mailhog:
  image: axllent/mailpit:${MAILPIT_VERSION}
  env_file: .env
  hostname: "mailhog"
  environment:
    MP_UI_AUTH_FILE: /mailpit-config/ui-auth.txt
    MP_DISABLE_VERSION_CHECK: 1
  volumes:
    - ./.warp/docker/config/mailpit:/mailpit-config:ro
  expose:
    - "1025"
  ports:
    - "127.0.0.1:${MAILPIT_BINDED_PORT}:8025"
  networks:
    - back
```

Notas:

1. `expose` alcanza para SMTP interno; no hace falta publicarlo al host.
2. `127.0.0.1:${MAILPIT_BINDED_PORT}:8025` reduce exposicion innecesaria.
3. `MP_UI_AUTH_FILE` protege UI y API con el mismo mecanismo.

### Cambio completo de naming

En etapa 2, el bloque deberia pasar a `mailpit` y el hostname tambien:

```yaml
mailpit:
  image: axllent/mailpit:${MAILPIT_VERSION}
  env_file: .env
  hostname: "mailpit"
  environment:
    MP_UI_AUTH_FILE: /mailpit-config/ui-auth.txt
    MP_DISABLE_VERSION_CHECK: 1
  volumes:
    - ./.warp/docker/config/mailpit:/mailpit-config:ro
  expose:
    - "1025"
  ports:
    - "127.0.0.1:${MAILPIT_BINDED_PORT}:8025"
  networks:
    - back
```

## 2. Variables de entorno

Archivos:

- `.env`
- `.env.sample`

### Variables nuevas recomendadas

```dotenv
# Config Mailpit
MAILPIT_VERSION=v1.29
MAILPIT_BINDED_PORT=8050
```

### Decision sobre credenciales

**Recomendado:** no guardar usuario/password en `.env`.

Usar archivo montado:

- host: `./.warp/docker/config/mailpit/ui-auth.txt`
- container: `/mailpit-config/ui-auth.txt`

Formato soportado por Mailpit:

```text
user1:password1
```

o con password hasheado.

Esto es preferible a `MP_UI_AUTH="user:pass"` porque evita mover credenciales por variables de entorno.

## 3. PHP

Archivos:

- `.warp/docker/config/php/php.ini`
- `.warp/setup/php/config/php/php.ini`

### Si se hace reemplazo funcional sin renombrar servicio

No hace falta cambiar nada en etapa 1, porque PHP seguira apuntando a `mailhog:1025` y el servicio puede conservar ese nombre mientras la imagen ya es Mailpit.

### Si se hace rename completo a mailpit

Hay que actualizar:

```ini
smtp_port = 1025
SMTP = mailpit
sendmail_path = "/usr/local/bin/mhsendmail --smtp-addr=mailpit:1025"
```

## 4. Comando CLI de warp

Archivos:

- `warp`
- `.warp/bin/mailhog.sh`
- `.warp/bin/mailhog_help.sh`

### Requerido para cambio completo

1. Agregar comando `warp mailpit`.
2. Cambiar textos de ayuda, `info` y `ssh`.
3. Decidir si `warp mailhog` queda como alias deprecated por una o dos versiones internas.

### Recomendacion

Mantener compatibilidad temporal:

- `warp mailpit` como comando principal nuevo
- `warp mailhog` como alias que delega al mismo handler y muestra aviso de deprecacion

Eso baja el costo de adopcion para el equipo.

## 5. Setup / bootstrap

Archivos:

- `.warp/setup/mailhog/mailhog.sh`
- `.warp/setup/mailhog/tpl/mailhog.yml`
- `.warp/setup/init/developer.sh`
- `.warp/setup/init/autoload.sh`
- `.warp/setup/init/gandalf.sh`
- `.warp/bin/init.sh`

### Que hay que adaptar

1. Renombrar prompts y mensajes de MailHog a Mailpit.
2. Cambiar template del servicio Docker.
3. Emitir `MAILPIT_BINDED_PORT` y `MAILPIT_VERSION`.
4. Si se adopta auth file por convencion, documentar en el setup la ruta esperada del archivo.

### Decision importante

No recomiendo pedir usuario/password en el wizard para persistirlos en `.env`.

Es mejor:

1. que el setup cree o espere un archivo `ui-auth.txt`;
2. que exista un `ui-auth.txt.sample` con formato de ejemplo;
3. que el operador cree el archivo real con credenciales locales.

## 6. Nginx

No es obligatorio tocar nginx para este RFC.

### Solo haria falta tocar nginx si:

1. se quiere exponer Mailpit bajo un path del sitio, por ejemplo `/mailpit/`;
2. se quiere unificar acceso por dominio en lugar de usar `127.0.0.1:8050`;
3. se decide mover la auth al reverse proxy en vez de usar la auth nativa de Mailpit.

### Si algun dia se proxyea por nginx

Habra que:

1. preservar `Host`;
2. configurar websocket headers (`Upgrade` / `Connection`);
3. definir `MP_WEBROOT` si se publica bajo subpath.

## Superficie final esperada

## Etapa 1 recomendada

- servicio sigue llamandose `mailhog` internamente;
- imagen pasa a `axllent/mailpit`;
- UI/API protegidas por basic auth nativa;
- SMTP queda interno y sin auth;
- `warp mailhog` sigue funcionando;
- PHP no cambia;
- riesgo operativo bajo.

## Etapa 2 recomendada

- servicio, hostname, comando CLI y variables pasan a `mailpit`;
- PHP cambia de `mailhog` a `mailpit`;
- setup y ayudas quedan alineados al nuevo nombre;
- `warp mailhog` queda solo como alias temporal o se elimina.

## Riesgos y consideraciones

1. **API protegida por auth:** cualquier script o prueba que consuma la API HTTP de Mailpit va a necesitar credenciales.
2. **SMTP auth fuera de alcance inicial:** si luego se quiere auth SMTP, hay que rediseñar el envio local de PHP.
3. **Cambio de nombre del servicio:** si se hace rename completo en una sola etapa, hay mas puntos de rotura.
4. **Auth file:** si cambia el archivo mientras Mailpit corre, hay que reiniciar el servicio para que relea credenciales.

## Validacion propuesta

1. `warp start`
2. abrir `http://127.0.0.1:${MAILPIT_BINDED_PORT}` y confirmar challenge basic auth
3. validar acceso con credenciales correctas
4. validar rechazo con credenciales invalidas
5. enviar un mail de prueba desde Magento/PHP y confirmar recepcion
6. confirmar que `curl -u user:pass http://127.0.0.1:${MAILPIT_BINDED_PORT}/api/v1/messages` responde OK
7. confirmar que sin credenciales la API responde `401`

## Recomendacion final

La migracion debe hacerse con **Mailpit auth nativo para UI/API** y **sin auth SMTP en la primera version**.

Si el objetivo es bajar riesgo, la secuencia correcta es:

1. reemplazar MailHog por Mailpit manteniendo naming interno `mailhog`;
2. cerrar exposicion SMTP al host;
3. publicar la UI solo en loopback con basic auth;
4. en una segunda pasada, renombrar `warp mailhog` / `MAILHOG_*` / `mailhog` a `mailpit`.

Ese camino cubre el requerimiento funcional, mejora seguridad y evita romper el envio de correo local de Magento.
