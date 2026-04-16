# Warp Infra Images: PoC Appdata Multiarch

Fecha: 2026-04-16

## 1. Objetivo

Definir una PoC de imagen `appdata` propia, multiarch, para reemplazar `summasolutions/appdata:latest` en stacks Warp modernos.

Este archivo complementa:

- [warp-infra.md](/srv2/www/htdocs/66/warp-engine/features/warp-infra.md)
- [warp-infra-img.md](/srv2/www/htdocs/66/warp-engine/features/warp-infra-img.md)

La PoC debe probar primero `linux/amd64` y despues `linux/arm64`.

## 2. Diagnostico

La imagen actual observada:

```text
summasolutions/appdata:latest
OS: Debian 8 Jessie
arch: amd64
rsync: 3.1.1
runtime user: root
entrypoint: /docker-entrypoint.sh
cmd del proyecto: /bin/sh /startup.sh
```

Funciones reales:

1. exponer un volumen compartido en `/var/www/html`;
2. ejecutar `rsync --daemon`;
3. generar `/etc/rsyncd.conf` si no existe;
4. ejecutar `/startup.sh` montado por Warp;
5. permitir que `/startup.sh` ajuste permisos de proyecto periodicamente.

Conclusion:

`appdata` es de bajo riesgo para multiarch. No tiene logica compleja ni dependencias especificas de CPU. El unico motivo fuerte para rehacerla es salir de Debian Jessie y publicar manifest `linux/amd64,linux/arm64`.

## 3. Dockerfile PoC

Archivo propuesto:

```text
images/appdata-poc/Dockerfile
```

Contenido:

```dockerfile
FROM debian:bookworm-slim

LABEL maintainer="Warp"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        iproute2 \
        iputils-ping \
        rsync \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

EXPOSE 873

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 755 /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/bin/sh", "/startup.sh"]
```

Notas:

1. `iproute2` e `iputils-ping` aparecen en la imagen runtime actual y se mantienen para compatibilidad operativa.
2. Si el smoke demuestra que no se usan, pueden salir para reducir superficie.
3. `CMD` replica el uso real del compose observado; `/startup.sh` sigue siendo bind mount de Warp.

## 4. Entrypoint PoC

Archivo propuesto:

```text
images/appdata-poc/docker-entrypoint.sh
```

Contenido:

```bash
#!/bin/sh
set -eu

if [ ! -f /etc/rsyncd.conf ]; then
    cat > /etc/rsyncd.conf <<'EOF'
uid = root
gid = root
use chroot = yes
log file = /dev/stdout
reverse lookup = no
[warp]
    hosts allow = *
    read only = false
    path = /var/www/html
    comment = docker volume
EOF
fi

if [ ! -d /var/www/html ]; then
    mkdir -p /var/www/html
fi

rsync --daemon --config /etc/rsyncd.conf

exec "$@"
```

## 5. Build multiarch

Primero local `amd64`:

```bash
docker build --platform linux/amd64 \
  -t warp/appdata:bookworm-poc-amd64 \
  -f images/appdata-poc/Dockerfile \
  images/appdata-poc
```

Resultado local del 2026-04-16:

```text
OK: warp/appdata:bookworm-poc-amd64
OS: Debian 12 bookworm
arch runtime: x86_64
rsync: 3.2.7
```

Luego buildx multiarch:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t magtools/appdata:bookworm-poc \
  -f images/appdata-poc/Dockerfile \
  images/appdata-poc \
  --push
```

Resultado local `arm64` del 2026-04-16:

```text
FAIL: exec /bin/sh: exec format error
builder: default/docker
platforms: linux/amd64 (+3)
```

Lectura:

1. el Dockerfile no llego a fallar por dependencias;
2. fallo porque el host/builder local no puede ejecutar capas `arm64` durante instrucciones `RUN`;
3. para validar `linux/arm64` hace falta un builder con binfmt/QEMU registrado o un builder nativo Arm;
4. este bloqueo aplica tambien a la imagen PHP mientras use `RUN` para instalar paquetes/extensiones.

## 6. Smoke tests

### 6.1 Imagen

```bash
docker run --rm --entrypoint sh warp/appdata:bookworm-poc-amd64 -lc 'cat /etc/os-release && uname -m && rsync --version | head -n2'
docker run --rm magtools/appdata:bookworm-poc sh -lc 'cat /etc/os-release && uname -m && rsync --version | head -n2'
```

Smoke local `amd64` ejecutado:

```text
Debian GNU/Linux 12 (bookworm)
x86_64
rsync version 3.2.7 protocol version 32
```

### 6.2 Compose

Reemplazar temporalmente solo en un compose de prueba:

```yaml
appdata:
  image: magtools/appdata:bookworm-poc
```

Validar:

```bash
docker compose config
docker compose up -d appdata
docker compose logs appdata
docker exec example-appdata-1 rsync --version
docker exec example-appdata-1 sh -lc 'test -f /etc/rsyncd.conf && test -d /var/www/html'
```

### 6.3 Permisos

Validar que el `startup.sh` montado sigue funcionando:

```bash
docker exec example-appdata-1 sh -lc 'ls -ld /var/www/html && test -x /var/www/html/bin/magento'
```

## 7. Criterios de aceptacion

1. La imagen builda en `linux/amd64`.
2. La imagen builda en `linux/arm64`.
3. `rsync --daemon` arranca.
4. `/etc/rsyncd.conf` se genera cuando falta.
5. `/startup.sh` montado se ejecuta sin cambios.
6. PHP y web pueden seguir usando `volumes_from: appdata`.
7. No hay regresion visible de permisos en `bin/magento`, `vendor`, `pub`, `generated` o `var`.

## 8. Riesgos

1. Debian Bookworm puede traer diferencias de coreutils/permisos frente a Jessie.
2. El loop de permisos de `/startup.sh` sigue siendo costoso para proyectos grandes.
3. `volumes_from` es legacy en Compose; no se cambia en esta PoC para mantener alcance bajo.

## 9. Decision esperada

Si esta PoC funciona en `amd64` y `arm64`, `appdata` deja de ser bloqueo para `c7g`.

No hace falta esperar a la imagen PHP para validar esta pieza.
