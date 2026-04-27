# RFC: capability `mail` en Warp con backend Mailpit y compatibilidad legacy `mailhog`

## Decision final

Warp adopta un contrato nuevo y mas generico para mail:

- capability/documentacion: `mail`
- backend actual: `Mailpit`
- comando CLI legacy conservado: `warp mailhog`
- servicio y hostname de compatibilidad: `mailhog`
- carpeta canonica de config: `./.warp/docker/config/mail`
- auth HTTP obligatoria por archivo: `./.warp/docker/config/mail/ui-auth.txt`
- storage persistente local: `./.warp/docker/volumes/mail`

Compatibilidad de variables:

- variable canonica nueva: `MAIL_BINDED_PORT`
- alias legacy aceptado: `MAILHOG_BINDED_PORT`
- engine canonico: `MAIL_ENGINE=mailpit`
- version canonica: `MAIL_VERSION=<tag>`
- retencion canonica: `MAIL_MAX_MESSAGES=100`

`MAILHOG_BINDED_PORT` queda solo como alias de lectura/fallback. Desde ahora Warp crea y mantiene `MAIL_BINDED_PORT`.

## Alcance

Esta RFC aplica al core de Warp y no a un proyecto puntual.

Objetivos:

- mantener SMTP interno conocido por PHP
- proteger UI/API HTTP con auth nativa
- bajar exposicion al host
- introducir naming generico `mail`
- preservar compatibilidad con la capa legacy `mailhog`

## Contrato operativo

### Superficie externa

Se mantiene:

- comando `warp mailhog`
- hostname `mailhog`
- `SMTP = mailhog`
- `smtp_port = 1025`
- `sendmail_path = "/usr/local/bin/mhsendmail --smtp-addr=mailhog:1025"`

Motivo:

- evita romper setup, PHP y tooling historico
- el rename visible no agrega valor operativo hoy

### Superficie canonica nueva

Se adopta como naming oficial de ahora en mas:

- capability: `mail`
- config: `./.warp/docker/config/mail`
- variable de puerto: `MAIL_BINDED_PORT`
- variable de engine: `MAIL_ENGINE`
- variable de version: `MAIL_VERSION`

## Runtime elegido

Warp usa Mailpit por detras del contrato legacy `mailhog`.

Requisitos funcionales cubiertos:

- SMTP en `1025`
- UI/API en `8025`
- auth HTTP nativa por archivo
- imagen Docker multiarch

## Compose esperado

```yaml
mailhog:
  image: axllent/mailpit:${MAIL_VERSION}
  env_file: .env
  hostname: "mailhog"
  environment:
    MP_UI_AUTH_FILE: /mail-config/ui-auth.txt
    MP_DATABASE: /mail-data/mailpit.db
    MP_MAX_MESSAGES: ${MAIL_MAX_MESSAGES}
    MP_DISABLE_VERSION_CHECK: 1
  volumes:
    - ./.warp/docker/config/mail:/mail-config:ro
    - ./.warp/docker/volumes/mail:/mail-data
  expose:
    - "1025"
  ports:
    - "127.0.0.1:${MAIL_BINDED_PORT}:8025"
  networks:
    - back
```

Decisiones:

- SMTP no se publica al host
- UI/API se publica solo en loopback
- la auth vive en Mailpit, no en nginx

## Auth y config

Archivos canonicos:

- `./.warp/docker/config/mail/ui-auth.txt`
- `./.warp/docker/config/mail/ui-auth.txt.sample`
- `./.warp/docker/volumes/mail`
- `./.warp/setup/mailhog/config/mail/ui-auth.txt`
- `./.warp/setup/mailhog/config/mail/ui-auth.txt.sample`

Contrato:

- `ui-auth.txt` es obligatorio
- contenido default: `warp:warp`
- el archivo se versiona junto con otras configs del proyecto
- no se trata como secreto fuerte; es una barrera minima
- los mensajes se persisten en SQLite local usando `./.warp/docker/volumes/mail`
- Warp mantiene por default solo los ultimos `100` mensajes

Bootstrap:

- `warp init` debe crear/copiar `ui-auth.txt` si no existe
- `warp update` y `warp update --self` deben crear/copiar `ui-auth.txt` si no existe
- si falta el directorio `config/mail`, debe crearse
- si falta `./.warp/docker/volumes/mail`, debe crearse

## Compatibilidad

### Variables

Regla:

1. usar `MAIL_BINDED_PORT` como variable canonica
2. si no existe, aceptar `MAILHOG_BINDED_PORT`
3. si existe el alias legacy, tratarlo como alias del valor canonico

En la practica:

- nuevos proyectos escriben `MAIL_BINDED_PORT`
- proyectos legacy pueden seguir trayendo `MAILHOG_BINDED_PORT`
- cuando Warp materializa defaults, debe escribir la forma canonica

### CLI

`warp mailhog` se conserva por compatibilidad.

La ayuda y la documentacion deben hablar de `mail` como capability y aclarar que `warp mailhog` es el nombre legacy del comando.

### Shell dentro del contenedor

Mailpit corre en la imagen oficial sin un usuario dedicado tipo `mailhog`.

Por eso:

- `warp mailhog ssh`
- `warp mailhog ssh --root`
- `warp mailhog ssh --mailhog`

pueden resolver a shell como `root` dentro del contenedor.

## Casos documentales

Para evitar ambiguedad, la documentacion debe separarse asi:

1. **Capability docs**
   Usar naming `mail`.

2. **Compat docs**
   Aclarar que `warp mailhog` y `mailhog:1025` siguen vigentes.

3. **Config docs**
   Usar `config/mail`, nunca `config/mailpit`.

4. **Env docs**
   Usar `MAIL_BINDED_PORT`, `MAIL_ENGINE`, `MAIL_VERSION`, `MAIL_MAX_MESSAGES`.
   Mencionar `MAILHOG_BINDED_PORT` solo como alias legacy.

5. **Engine docs**
   Hablar de Mailpit como backend actual.

## Implementacion acordada

1. cambiar imagen a `axllent/mailpit:${MAIL_VERSION}`
2. mantener servicio y hostname `mailhog`
3. montar `./.warp/docker/config/mail`
4. configurar `MP_UI_AUTH_FILE=/mail-config/ui-auth.txt`
5. persistir mensajes en `./.warp/docker/volumes/mail` usando `MP_DATABASE=/mail-data/mailpit.db`
6. limitar retencion por defecto con `MAIL_MAX_MESSAGES=100`
7. publicar UI en `127.0.0.1:${MAIL_BINDED_PORT}:8025`
8. dejar SMTP solo interno
9. mantener `warp mailhog`
10. crear/copiar `ui-auth.txt` con default `warp:warp`
11. aceptar `MAILHOG_BINDED_PORT` como alias legacy

## Validacion

### Mail

1. `warp start`
2. abrir `http://127.0.0.1:${MAIL_BINDED_PORT}`
3. confirmar challenge basic auth
4. validar acceso con `warp:warp`
5. validar rechazo sin credenciales o con credenciales invalidas
6. enviar un mail de prueba desde PHP
7. confirmar recepcion en UI
8. confirmar que `curl -u warp:warp http://127.0.0.1:${MAIL_BINDED_PORT}/api/v1/messages` responde OK

### Smoke core

1. `./warp --help`
2. `./warp init --help`
3. `./warp start --help`
4. `./warp stop --help`
5. `./warp info --help`
6. `./warp docker ps`
