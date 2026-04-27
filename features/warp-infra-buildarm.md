# Warp Infra: build Arm en instancia Graviton temporal

Fecha: 2026-04-16

## 1. Objetivo

Definir un runbook para validar los Dockerfiles PoC de Warp en `linux/arm64` usando una instancia EC2 Graviton temporal.

Este documento complementa:

- [warp-infra.md](/srv2/www/htdocs/66/warp-engine/features/warp-infra.md)
- [warp-infra-img.md](/srv2/www/htdocs/66/warp-engine/features/warp-infra-img.md)
- [warp-infra-img-appdata.md](/srv2/www/htdocs/66/warp-engine/features/warp-infra-img-appdata.md)
- [warp-infra-img-php.md](/srv2/www/htdocs/66/warp-engine/features/warp-infra-img-php.md)

El objetivo no es dejar infraestructura permanente. La instancia se usa para responder una pregunta puntual:

```text
Los Dockerfiles PoC de appdata y PHP 8.4 buildan y corren nativos en arm64?
```

## 2. Instancia recomendada

Perfil minimo recomendado:

```text
familia: c7g, m7g o t4g
tamano: xlarge
arquitectura: arm64 / aarch64
disco: gp3 100 GB
SO: Ubuntu 24.04 LTS arm64 o Amazon Linux 2023 arm64
```

Notas:

1. `xlarge` mantiene la comparacion alineada con el analisis de costos.
2. PHP compila muchas extensiones; usar menos CPU hace que la prueba tarde mas y puede ocultar problemas de timeout.
3. `gp3 100 GB` evita fallos por espacio durante capas Docker, PECL, Node y cache de build.
4. Para una prueba rapida alcanza una instancia temporal sin servicios expuestos, salvo SSH.

## 3. Seguridad minima

Security group:

```text
inbound:
  SSH 22 solo desde IP propia
outbound:
  HTTPS/HTTP/DNS permitido para apt, Docker Hub, PECL, NodeSource y Composer
```

No montar secretos productivos. Si se prueba push a un registry, usar token temporal con permisos minimos.

## 4. Preparacion del host

### 4.1 Confirmar arquitectura

```bash
uname -m
dpkg --print-architecture 2>/dev/null || true
```

Resultado esperado:

```text
aarch64
arm64
```

### 4.2 Ubuntu 24.04 LTS

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git make rsync
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"
```

Cerrar y volver a abrir la sesion SSH, o ejecutar:

```bash
newgrp docker
```

### 4.3 Amazon Linux 2023

```bash
sudo dnf update -y
sudo dnf install -y docker git make rsync
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

Cerrar y volver a abrir la sesion SSH, o ejecutar:

```bash
newgrp docker
```

Validar Docker:

```bash
docker version
docker buildx version
docker run --rm hello-world
```

## 5. Llevar el repo a la instancia

Opcion A: clonar desde remoto:

```bash
git clone <repo-url> warp-engine
cd warp-engine
git checkout <branch-o-sha-de-prueba>
```

Opcion B: copiar el working tree actual desde la maquina local:

```bash
rsync -av --exclude .git --exclude var --exclude .warp/docker/volumes ./ <user>@<graviton-host>:~/warp-engine/
ssh <user>@<graviton-host>
cd ~/warp-engine
```

Validar que esten los archivos PoC:

```bash
test -f images/appdata-poc/Dockerfile
test -f images/php/8.4-fpm-poc/Dockerfile
test -f images/php/8.4-fpm-poc/msmtprc
test -f images/php/8.4-fpm-poc/docker-php-mail.ini
```

## 6. Build arm64 local

En una instancia Graviton no hace falta QEMU para `arm64`; el build corre nativo.

Confirmar builder:

```bash
docker buildx ls
```

Debe aparecer soporte para `linux/arm64` o el build nativo debe reportar `aarch64` en los smokes.

### 6.1 Appdata

```bash
docker build --platform linux/arm64 \
  -t warp/appdata:bookworm-poc-arm64 \
  -f images/appdata-poc/Dockerfile \
  images/appdata-poc
```

Smoke:

```bash
docker run --rm --entrypoint sh warp/appdata:bookworm-poc-arm64 -lc 'cat /etc/os-release; uname -m; rsync --version | head -n2'
```

Resultado esperado:

```text
Debian GNU/Linux 12 (bookworm)
aarch64
rsync version 3.2.7 protocol version 32
```

Validar entrypoint:

```bash
docker run --rm warp/appdata:bookworm-poc-arm64 sh -lc 'test -f /etc/rsyncd.conf && test -d /var/www/html && rsync --version | head -n1'
```

### 6.2 PHP 8.4

```bash
docker build --platform linux/arm64 \
  -t warp/php:8.4-fpm-poc-arm64 \
  -f images/php/8.4-fpm-poc/Dockerfile \
  images/php/8.4-fpm-poc
```

Este build puede tardar varios minutos porque compila extensiones core y PECL.

Smoke:

```bash
docker run --rm --entrypoint sh warp/php:8.4-fpm-poc-arm64 -lc 'uname -m; php -v | head -n1; composer --version; node --version; npm --version; yarn --version; msmtp --version | head -n1'
```

Extensiones:

```bash
docker run --rm --entrypoint sh warp/php:8.4-fpm-poc-arm64 -lc 'php -m | sort | grep -E "^(apcu|bcmath|gd|imagick|intl|mongodb|opcache|pdo_mysql|redis|soap|ssh2|xdebug|xsl|zip)$"'
```

Resultado minimo esperado:

```text
apcu
bcmath
gd
imagick
intl
mongodb
opcache
pdo_mysql
redis
soap
ssh2
xdebug
xsl
zip
```

Validar FPM:

```bash
docker run --rm --entrypoint php-fpm warp/php:8.4-fpm-poc-arm64 -t
```

## 7. Smoke mail local

Crear red temporal:

```bash
docker network create warp-poc
```

Levantar Mailpit para el capability `mail` de Warp:

```bash
docker run -d --rm \
  --name warp-poc-mail \
  --network warp-poc \
  -v "$PWD/.tmp-mail-config:/mail-config:ro" \
  -e MP_UI_AUTH_FILE="/mail-config/ui-auth.txt" \
  axllent/mailpit:latest
```

Enviar mail desde PHP:

```bash
docker run --rm --network warp-poc --entrypoint php warp/php:8.4-fpm-poc-arm64 -r 'var_dump(mail("dev@example.local", "warp arm test", "ok"));'
```

Validar por API interna:

```bash
docker run --rm --network warp-poc curlimages/curl:latest -s -u warp:warp http://warp-poc-mail:8025/api/v1/messages
```

Limpiar:

```bash
docker stop warp-poc-mail
docker network rm warp-poc
```

Nota:

1. para una PoC local, crear antes `mkdir -p .tmp-mail-config && printf 'warp:warp\n' > .tmp-mail-config/ui-auth.txt`.
2. el contrato final de Warp prefiere `MP_UI_AUTH_FILE` y `config/mail/ui-auth.txt`.
3. aunque el capability/documentacion sea `mail`, Warp mantiene compatibilidad legacy con `warp mailhog` y hostname `mailhog`.

## 8. Publicar/verificar manifest multiarch

Tags modernos esperados en DockerHub:

```text
magtools/appdata:bookworm
magtools/php:8.4.20-fpm
```

Los tags PoC con sufijo de arquitectura quedan como historial o fallback de diagnostico. Si se quiere publicar imagenes de prueba, usar tags temporales:

```bash
docker login <registry>
docker tag warp/appdata:bookworm-poc-arm64 magtools/appdata:bookworm-poc-arm64
docker tag warp/php:8.4-fpm-poc-arm64 magtools/php:8.4-fpm-poc-arm64
docker push magtools/appdata:bookworm-poc-arm64
docker push magtools/php:8.4-fpm-poc-arm64
```

Para manifest multiarch real hay dos opciones:

1. construir y pushear `amd64` desde host x86 y `arm64` desde Graviton, luego crear manifest;
2. usar un builder remoto/buildx que tenga nodos `amd64` y `arm64`.

Ejemplo con manifest manual:

```bash
docker manifest create magtools/appdata:bookworm \
  --amend magtools/appdata:bookworm-poc-amd64 \
  --amend magtools/appdata:bookworm-poc-arm64

docker manifest create magtools/php:8.4.20-fpm \
  --amend magtools/php:8.4-fpm-poc-amd64 \
  --amend magtools/php:8.4-fpm-poc-arm64

docker manifest push magtools/appdata:bookworm
docker manifest push magtools/php:8.4.20-fpm
```

Inspeccionar:

```bash
docker manifest inspect magtools/appdata:bookworm
docker manifest inspect magtools/php:8.4.20-fpm
```

## 9. Captura de resultados

Guardar estos datos en `features/warp-infra-img-appdata.md` y `features/warp-infra-img-php.md`:

```text
fecha:
instancia:
SO:
kernel:
docker:
buildx:
imagen:
resultado build:
tiempo aproximado:
smoke runtime:
extensiones faltantes:
errores:
decision:
```

Comandos utiles:

```bash
date -Is
uname -a
cat /etc/os-release
docker version
docker buildx ls
docker image ls 'warp/*'
```

## 10. Criterios de aceptacion

Para considerar validado el hito Arm:

1. `appdata` builda en `linux/arm64`.
2. `appdata` ejecuta `rsync` y genera `/etc/rsyncd.conf`.
3. PHP builda en `linux/arm64`.
4. PHP reporta `aarch64`.
5. Composer, Node, npm, Yarn y `msmtp` responden.
6. Todas las extensiones minimas esperadas cargan.
7. `php-fpm -t` pasa.
8. `mail()` envia al capability `mail` usando Mailpit como backend.
9. No aparece ningun binario `*_amd64` requerido en runtime.

## 11. Fallos esperables

| Sintoma | Lectura | Accion |
| --- | --- | --- |
| `exec format error` | No se esta corriendo nativo Arm o falta binfmt. | Confirmar `uname -m`; usar Graviton real o arreglar builder. |
| Falla `pecl install imagick` | Dependencias de ImageMagick o version PECL. | Revisar headers `libmagickwand-dev` y version PECL. |
| Falla `ssh2-1.3.1` | Incompatibilidad con libssh2/PHP. | Probar version PECL mas nueva o parchear dependencia. |
| Falla NodeSource | Repo no entrega paquete para arm64 o problema temporal. | Verificar repo, usar Node oficial o paquete Debian si alcanza. |
| `mail()` devuelve false | `sendmail_path` o red con Mailpit. | Probar `msmtp --debug`, revisar host `mailhog` y red Docker. |
| Imagen demasiado grande | Build deps quedan en runtime. | Separar build/runtime en una version posterior; no bloquear PoC inicial. |

## 12. Limpieza

En la instancia:

```bash
docker ps -a
docker image ls
docker system df
docker system prune -a
```

En AWS:

1. terminar la instancia;
2. borrar volumen EBS si no se borra automaticamente;
3. borrar security group temporal si fue creado solo para esta prueba;
4. revocar tokens de registry si se usaron credenciales temporales.

## 13. Decision posterior

Si la prueba Arm pasa, el siguiente paso no es migrar automaticamente a `c7g`.

El siguiente paso correcto es:

1. publicar tags PoC multiarch;
2. probar un compose aislado con `example`;
3. correr Magento CLI, `composer check-platform-reqs`, cache/indexers y un smoke HTTP;
4. medir tiempos de build, consumo y estabilidad;
5. recien despues comparar ROI contra `c7i`.
