# RFC: soporte Warp para Mailpit con auth nativa, reutilizando la capa historica `mailhog`

## Decision propuesta

**Si, conviene desacoplar la RFC de cualquier proyecto puntual y mantener el contrato historico de Warp**, igual que en otros cambios donde se reusa naming existente y se cambia el engine real por detras.

La recomendacion es:

- mantener el nombre de servicio `mailhog`
- mantener el comando `warp mailhog`
- mantener compatibilidad con variables legacy `MAILHOG_*`
- cambiar la imagen real a Mailpit
- agregar configuracion y auth en `./.warp/docker/config/mail`
- usar auth nativa de Mailpit para UI/API
- dejar SMTP interno y sin auth en la primera etapa

En otras palabras: **no hace falta renombrar la capa "mailhog" a "mailpit"**. Lo correcto para Warp es conservar el contrato externo y cambiar contenido/comportamiento interno cuando el engine nuevo lo requiera.

## Alcance funcional

Este RFC **no esta atado a un proyecto puntual**.

El objetivo es mejorar el mail catcher local de Warp para cualquier stack PHP soportado por el framework:

- Magento
- Oro
- PHP generico

La mejora buscada es:

- mantener el flujo SMTP local ya conocido por PHP
- proteger la UI/API HTTP con auth
- bajar exposicion innecesaria al host
- evitar una migracion transversal de nombres, comandos y variables

## Contexto actual

### Servicio Docker

Actualmente Warp expone un servicio `mailhog` y la UI web se publica con `MAILHOG_BINDED_PORT`.

El servicio actual mantiene dos caracteristicas relevantes:

- SMTP para red interna del compose
- UI web publicada al host

### PHP

La configuracion historica de PHP apunta a:

- `SMTP = mailhog`
- `smtp_port = 1025`
- `sendmail_path = "/usr/local/bin/mhsendmail --smtp-addr=mailhog:1025"`

Ese contrato no conviene romper en esta RFC.

### CLI y setup

Superficies actuales:

- `.warp/bin/mailhog.sh`
- `.warp/bin/mailhog_help.sh`
- `.warp/setup/mailhog/mailhog.sh`
- `.warp/setup/mailhog/tpl/mailhog.yml`
- `.warp/setup/init/developer.sh`
- `.warp/setup/init/autoload.sh`
- `.warp/setup/init/gandalf.sh`
- `.warp/bin/init.sh`

Hoy Warp ya tiene una capa establecida alrededor del nombre `mailhog`. Esa capa no deberia renombrarse si el objetivo real es cambiar el engine del mail catcher.

## Capacidades relevantes de Mailpit

Mailpit aporta lo que hace falta para este caso:

- mantiene `1025` para SMTP
- mantiene `8025` para UI/API
- soporta auth HTTP nativa para UI/API
- permite montar archivo de auth

Eso encaja bien con Warp porque permite reemplazar el engine sin rediseñar el flujo SMTP local.

## Problema con la RFC actual

La version anterior de esta RFC proponia una migracion en dos etapas:

1. reemplazo funcional
2. rename completo a `mailpit`

Ese enfoque **no sigue el patron historico de Warp**.

En este repo conviene hacer lo mismo que en otros cambios:

- reusar nombre de servicio
- reusar comando existente
- reusar variables legacy
- reusar paths esperables
- cambiar imagen, auth y archivos de configuracion por debajo

Si el servicio ya se llama `mailhog` y PHP ya habla con `mailhog:1025`, renombrarlo a `mailpit` agrega costo, ruido y mas superficie de rotura sin beneficio operativo claro.

## Decision de naming y compatibilidad

### Mantener el nombre de servicio `mailhog`

Se recomienda **mantener**:

- servicio Docker `mailhog`
- hostname `mailhog`
- comando `warp mailhog`
- variables `MAILHOG_*`

Motivo:

- PHP ya apunta a `mailhog:1025`
- setup, ayudas y tooling ya dependen de ese nombre
- evita tocar superficies innecesarias
- sigue el estilo de Warp: reusar naming historico y cambiar engine interno

### Introducir `config/mail` como carpeta canonica del capability

Se recomienda **agregar y usar**:

- `./.warp/docker/config/mail`
- `./.warp/setup/mailhog/config/mail`

Dentro de esa carpeta vivirian archivos como:

- `ui-auth.txt`
- `ui-auth.txt.sample`
- futuros archivos de config mail-related si hacen falta

Motivo:

- la auth ya no pertenece a nginx sino al capability mail
- `config/mail` es mas neutral que `config/mailpit`
- permite reusar la misma ruta aunque en el futuro cambie el engine del mail catcher otra vez

### Mantener variables legacy `MAILHOG_*`

Conviene **mantener**:

- `MAILHOG_BINDED_PORT`

Y sumar, si hace falta, variables compatibles y especificas del nuevo runtime, por ejemplo:

- `MAILPIT_VERSION`

No recomiendo una migracion obligatoria a `MAILPIT_BINDED_PORT` si el binded port ya esta estable y funcional bajo `MAILHOG_BINDED_PORT`.

El criterio deberia ser:

- reusar variables historicas cuando describen el slot funcional
- agregar variables nuevas solo donde describen algo especifico del engine real

## Propuesta tecnica

### 1. Reemplazar imagen, no el contrato externo

El servicio debe seguir llamandose `mailhog`, pero usar Mailpit como imagen real.

Ejemplo de direccion esperada:

```yaml
mailhog:
  image: axllent/mailpit:${MAILPIT_VERSION}
  env_file: .env
  hostname: "mailhog"
  environment:
    MP_UI_AUTH_FILE: /mail-config/ui-auth.txt
    MP_DISABLE_VERSION_CHECK: 1
  volumes:
    - ./.warp/docker/config/mail:/mail-config:ro
  expose:
    - "1025"
  ports:
    - "127.0.0.1:${MAILHOG_BINDED_PORT}:8025"
  networks:
    - back
```

Con esto:

- PHP sigue hablando con `mailhog:1025`
- la UI sigue siendo accesible con el puerto historico de Warp
- la auth y config viven en una carpeta neutral del capability

### 2. No publicar SMTP al host

El SMTP no necesita publicarse al host si el uso esperado es interno al compose.

Por eso la recomendacion es:

- mantener `1025` solo en red interna
- publicar solo `8025` hacia el host
- preferir bind en loopback `127.0.0.1`

Esto baja exposicion sin romper el flujo historico.

### 3. Auth nativa de Mailpit para UI/API

La autenticacion recomendada es **solo para UI/API HTTP**.

No recomiendo activar auth SMTP en esta RFC porque:

- el flujo actual de PHP es simple y ya conocido
- agrega complejidad innecesaria
- no aporta tanto valor como proteger la superficie web

### 4. Archivo de auth en `config/mail`

En lugar de persistir usuario/password en `.env`, conviene montar un archivo:

- host: `./.warp/docker/config/mail/ui-auth.txt`
- sample: `./.warp/docker/config/mail/ui-auth.txt.sample`
- container: `/mail-config/ui-auth.txt`

Eso deja el secreto:

- fuera de variables de entorno
- mas facil de ignorar en git
- alineado a la idea de config por archivo que Warp ya usa en otros servicios

## Impacto en superficies existentes

### PHP

No deberia cambiar.

Mientras el servicio siga llamandose `mailhog`, esta configuracion puede permanecer:

```ini
smtp_port = 1025
SMTP = mailhog
sendmail_path = "/usr/local/bin/mhsendmail --smtp-addr=mailhog:1025"
```

### CLI de Warp

No hace falta crear `warp mailpit`.

La recomendacion es:

- mantener `warp mailhog`
- actualizar su ayuda para aclarar que el backend real puede ser Mailpit
- si hace falta, exponer en `info` que el engine actual es Mailpit

### Setup / bootstrap

Los setup scripts deben:

- seguir usando la capa `mailhog`
- cambiar el template Docker a Mailpit
- crear o copiar `config/mail`
- seguir escribiendo `MAILHOG_BINDED_PORT`
- escribir `MAILPIT_VERSION` si se quiere versionar la imagen

### Nginx

No es obligatorio tocar nginx.

La auth recomendada para esta RFC vive en Mailpit, no en reverse proxy.

## Estructura de config recomendada

Archivos propuestos:

- `./.warp/docker/config/mail/ui-auth.txt`
- `./.warp/docker/config/mail/ui-auth.txt.sample`
- `./.warp/setup/mailhog/config/mail/ui-auth.txt.sample`

Si luego aparece algun ajuste adicional del runtime mail, `config/mail` ya queda como carpeta canonica para ese capability.

## Variables de entorno recomendadas

### Mantener

- `MAILHOG_BINDED_PORT`

### Agregar si hace falta

```dotenv
MAILPIT_VERSION=v1.29
```

No recomiendo mover el binded port a `MAILPIT_BINDED_PORT` porque el puerto publicado sigue perteneciendo al contrato historico `mailhog` de Warp, aunque el engine real sea Mailpit.

## Implementacion recomendada

### Fase unica recomendada

1. Cambiar imagen `mailhog/mailhog` por `axllent/mailpit:${MAILPIT_VERSION}`
2. Mantener servicio y hostname `mailhog`
3. Montar `./.warp/docker/config/mail` como carpeta de config/auth
4. Configurar `MP_UI_AUTH_FILE`
5. Publicar la UI en `127.0.0.1:${MAILHOG_BINDED_PORT}:8025`
6. Dejar SMTP solo interno
7. Mantener `warp mailhog` y `MAILHOG_BINDED_PORT`
8. Ajustar docs y help para aclarar backend Mailpit

No veo valor en una segunda fase obligatoria de rename global.

## Riesgos y consideraciones

1. **API protegida por auth:** cualquier consumo HTTP de la API va a requerir credenciales.
2. **SMTP auth fuera de alcance inicial:** si luego se quiere auth SMTP, eso merece RFC separada.
3. **Cambio de engine interno:** aunque el contrato externo no cambie, hay que validar comandos `ssh/info` porque la imagen ya no es MailHog.
4. **Archivo de auth:** si cambia el archivo mientras el contenedor corre, puede requerirse reinicio del servicio.

## Validacion propuesta

### Mail capability

1. `warp start`
2. abrir `http://127.0.0.1:${MAILHOG_BINDED_PORT}` y confirmar challenge basic auth
3. validar acceso con credenciales correctas
4. validar rechazo con credenciales invalidas
5. enviar un mail de prueba desde PHP/Magento y confirmar recepcion
6. confirmar que `curl -u user:pass http://127.0.0.1:${MAILHOG_BINDED_PORT}/api/v1/messages` responde OK
7. confirmar que sin credenciales la API responde `401`

### Smoke core de Warp

1. `./warp --help`
2. `./warp init --help`
3. `./warp start --help`
4. `./warp stop --help`
5. `./warp info --help`
6. `./warp docker ps`

## Recomendacion final

La forma correcta de incorporar Mailpit en Warp no es renombrar todo a `mailpit`, sino **mantener la capa historica `mailhog` como contrato externo y reemplazar el engine por debajo**.

Ese enfoque:

- desacopla la RFC de un proyecto concreto
- respeta como Warp ya se viene moviendo
- evita romper PHP, setup y comandos existentes
- agrega auth donde corresponde
- introduce `config/mail` como carpeta neutral y reutilizable del capability

## Archivos relevados

- `.warp/bin/mailhog.sh`
- `.warp/bin/mailhog_help.sh`
- `.warp/setup/mailhog/mailhog.sh`
- `.warp/setup/mailhog/tpl/mailhog.yml`
- `.warp/setup/init/developer.sh`
- `.warp/setup/init/autoload.sh`
- `.warp/setup/init/gandalf.sh`
- `.warp/bin/init.sh`
- `.warp/setup/php/config/php/php.ini`
- `.warp/docker/config/php/php.ini`
