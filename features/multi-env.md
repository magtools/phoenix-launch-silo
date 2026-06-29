# RFC: multi-env expuesto hacia afuera con Traefik

## Decision operativa

Si se quieren correr dos o mas entornos Warp en el mismo server y visitarlos desde fuera usando un solo IP publico, el patron recomendado es:

1. cada proyecto Warp en modo multi-project
2. cada proyecto con `HTTP_HOST_IP` propio dentro de la red Docker
3. un Traefik frontal unico publicado en `80` y `443`
4. routing por hostname hacia la IP Docker de cada `web`

Warp por si solo no resuelve ese routing externo.

El modo multi-project actual de Warp esta pensado para dar una IP fija al contenedor web y permitir convivencia de varios proyectos en paralelo, pero no para publicar directamente varios sitios externos por hostname sin un proxy frontal.

## Por que en local si funciona y en server no

En local el patron historico funciona porque:

- Warp asigna una IP Docker fija al `web`
- el desarrollador agrega esa IP al `/etc/hosts`
- el navegador local resuelve el hostname hacia esa IP

En un server accesible desde Internet, ese enfoque no alcanza:

- el cliente remoto no tiene ruta a la red Docker `172.x`
- todos los dominios suelen resolver al mismo IP publico del server
- con un solo IP publico, la seleccion del backend debe hacerse por `Host` o SNI, no por IP destino Docker

Por eso hace falta un reverse proxy frontal.

## Comportamiento real de Warp hoy

En Linux, `warp init` ofrece configurar una IP fija para soportar mas de un proyecto en paralelo.

Cuando se elige ese modo:

- `HTTP_HOST_IP` toma una IP Docker dedicada
- `HTTP_BINDED_PORT` y `HTTPS_BINDED_PORT` quedan en `80` y `443`
- el `web` deja de bindear `80:80` y `443:443` en el host
- el compose usa puertos internos y `ipv4_address` fija en la red bridge

Eso sirve para convivencia interna entre proyectos, pero no expone esos sitios hacia clientes externos por si solo.

Referencias de codigo:

- [`.warp/setup/init/developer.sh`](../.warp/setup/init/developer.sh)
- [`.warp/lib/net.sh`](../.warp/lib/net.sh)
- [`.warp/setup/webserver/tpl/webserver_ports_multi.yml`](../.warp/setup/webserver/tpl/webserver_ports_multi.yml)
- [`.warp/setup/webserver/tpl/webserver_network_multi.yml`](../.warp/setup/webserver/tpl/webserver_network_multi.yml)

## Topologia recomendada

Ejemplo con dos proyectos:

- `project-a`
  - `VIRTUAL_HOST=shop-a.example.com`
  - `HTTP_HOST_IP=172.50.0.10`
- `project-b`
  - `VIRTUAL_HOST=shop-b.example.com`
  - `HTTP_HOST_IP=172.50.0.11`
- `traefik`
  - publicado en `0.0.0.0:80` y `0.0.0.0:443`
  - conectado a una red Docker que tenga alcance a los backends Warp

Flujo:

1. DNS publico apunta `shop-a.example.com` y `shop-b.example.com` al mismo server
2. Traefik recibe ambas requests en `80/443`
3. Traefik inspecciona el hostname
4. Traefik reenvia a `172.50.0.10:80` o `172.50.0.11:80`

## Requisitos de red

Hay dos formas razonables de cablear Traefik con los proyectos Warp.

### Opcion A: Traefik en la misma red Docker de cada proyecto

Es la opcion mas limpia si se controla bien la topologia de redes.

Requiere:

- conectar Traefik a la red `back` de cada proyecto, o
- mover los `web` Warp a una red externa comun accesible por Traefik

Ventaja:

- Traefik resuelve por nombre de contenedor o por IP interna sin publicar puertos extra

Tradeoff:

- requiere mas coordinacion entre redes Compose de proyectos distintos

### Opcion B: publicar puertos altos por proyecto y usar Traefik hacia host ports

Es mas simple de operar pero ya no usa el modo multi-project puro de Warp.

Ejemplo:

- `project-a` publica `8081 -> 80`
- `project-b` publica `8082 -> 80`
- Traefik enruta a `http://127.0.0.1:8081` y `http://127.0.0.1:8082`

Ventaja:

- evita meter Traefik dentro de redes Docker por proyecto

Tradeoff:

- cada proyecto consume puertos del host
- se parece mas a modo mono con puertos distintos

## Recomendacion para este repo

Para mantener el contrato actual de Warp y no meter una dependencia transversal fuerte en el core, la recomendacion es:

1. dejar que Warp siga resolviendo cada proyecto y su `web`
2. usar `warp init` en modo multi-project para asignar IP fija por proyecto
3. montar Traefik por fuera de Warp como proxy de infraestructura del server
4. apuntar Traefik a la IP `HTTP_HOST_IP` de cada entorno

Eso evita tocar `warp start/stop` y mantiene cambios pequenos y reversibles.

## Ejemplo de configuracion

### Proyecto A

`.env`

```dotenv
VIRTUAL_HOST=shop-a.example.com
HTTP_HOST_IP=172.50.0.10
HTTP_BINDED_PORT=80
HTTPS_BINDED_PORT=443
NETWORK_SUBNET=172.50.0.0/24
NETWORK_GATEWAY=172.50.0.1
```

### Proyecto B

`.env`

```dotenv
VIRTUAL_HOST=shop-b.example.com
HTTP_HOST_IP=172.50.0.11
HTTP_BINDED_PORT=80
HTTPS_BINDED_PORT=443
NETWORK_SUBNET=172.50.0.0/24
NETWORK_GATEWAY=172.50.0.1
```

Nota:

- ambos proyectos no pueden compartir la misma `HTTP_HOST_IP`
- tampoco conviene superponer redes si ya existe otra stack usando ese rango

### Traefik

Ejemplo minimo de `docker-compose.yml` para Traefik:

```yaml
services:
  traefik:
    image: traefik:v3.0
    command:
      - --api.dashboard=true
      - --providers.file.directory=/etc/traefik/dynamic
      - --providers.file.watch=true
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./dynamic:/etc/traefik/dynamic:ro
```

Archivo dinamico `dynamic/warp.yml`:

```yaml
http:
  routers:
    project-a:
      rule: Host(`shop-a.example.com`)
      service: project-a
      entryPoints:
        - web

    project-b:
      rule: Host(`shop-b.example.com`)
      service: project-b
      entryPoints:
        - web

  services:
    project-a:
      loadBalancer:
        servers:
          - url: http://172.50.0.10:80

    project-b:
      loadBalancer:
        servers:
          - url: http://172.50.0.11:80
```

Si se quiere TLS real, hay que sumar:

- certificados estaticos, o
- ACME/Let's Encrypt, o
- un terminador TLS aguas arriba

## Importante sobre HTTPS interno de Warp

Aunque Warp pueda exponer `443` dentro del proyecto, con Traefik frontal normalmente conviene:

- terminar TLS en Traefik
- hablar HTTP plano desde Traefik al `web` Warp en puerto `80`

Eso simplifica certificados y evita duplicar terminacion TLS por proyecto.

Si el sitio necesita saber que la request original fue HTTPS, Traefik debe reenviar headers como:

- `X-Forwarded-Proto: https`
- `X-Forwarded-Host`

Y la app debe confiar en ese proxy si su framework lo requiere.

## DNS

Requisito minimo:

- `shop-a.example.com -> IP_PUBLICO_DEL_SERVER`
- `shop-b.example.com -> IP_PUBLICO_DEL_SERVER`

No hay que apuntar DNS publico a `172.50.0.x`.

Esas IPs son internas de Docker.

## Riesgos y tradeoffs

1. Si Docker recrea redes y alguien cambia manualmente `HTTP_HOST_IP`, Traefik puede quedar apuntando a una IP vieja.
2. Si dos proyectos usan el mismo rango y la misma IP, la colision es inevitable.
3. Si el firewall del server no abre `80/443`, Traefik no sera accesible aunque Warp este sano.
4. Si se quiere TLS por Let's Encrypt, hay que validar reachabilidad publica real y puertos abiertos.
5. Si la aplicacion genera URLs absolutas, `VIRTUAL_HOST` y base URLs deben coincidir con el hostname publico final.

## Lo que no hace Warp hoy

Warp hoy no hace automaticamente:

- levantar Traefik
- registrar routers por proyecto
- publicar varios vhosts externos en un solo `80/443`
- coordinar DNS publico
- regenerar dinamicamente config de Traefik al crear o borrar entornos

Todo eso queda hoy fuera del core.

## Validacion minima

1. inicializar cada proyecto con `warp init` en modo multi-project
2. verificar `HTTP_HOST_IP` distinto en cada `.env`
3. levantar ambos con `warp start`
4. desde el server, validar reachabilidad interna:
   - `curl http://172.50.0.10`
   - `curl http://172.50.0.11`
5. levantar Traefik frontal
6. validar desde fuera:
   - `curl -H 'Host: shop-a.example.com' http://IP_PUBLICO`
   - `curl -H 'Host: shop-b.example.com' http://IP_PUBLICO`
7. validar navegacion real por:
   - `http://shop-a.example.com`
   - `http://shop-b.example.com`

## Resultado esperado

Con este patron, un mismo server puede servir multiples entornos Warp hacia Internet usando:

- un solo IP publico
- un solo Traefik frontal
- una IP Docker fija por entorno Warp
- routing por hostname

Es la forma mas cercana a `multi-env` externo sin forzar cambios profundos en `warp`.
