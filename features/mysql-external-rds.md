# Feature: MySQL externo / RDS en comandos `warp mysql`

Fecha: 2026-03-16

## 1) Objetivo funcional

Permitir que `warp mysql connect`, `warp mysql dump` y `warp mysql import` funcionen de forma segura cuando no existe servicio `mysql` en `docker-compose-warp.yml` y la base es externa.

## 2) Comportamiento implementado

## 2.1 Detección de escenario

Antes de ejecutar `connect|dump|import`, Warp evalúa:

1. si existe servicio `mysql` en `docker-compose-warp.yml`,
2. si `MYSQL_VERSION` está en modo externo (`rds`).

## 2.2 Bootstrap a modo externo

Si no existe servicio `mysql` y `MYSQL_VERSION != rds`, Warp pregunta:

- si la base es externa (`Y/n`).

Si se confirma:

1. intenta leer `app/etc/env.php`,
2. carga credenciales y host/puerto,
3. persiste configuración en `.env`.

Variables que actualiza en `.env`:

1. `MYSQL_VERSION=rds`
2. `DATABASE_HOST`
3. `DATABASE_BINDED_PORT`
4. `DATABASE_NAME`
5. `DATABASE_USER`
6. `DATABASE_PASSWORD`

## 2.3 Lectura de puerto desde `env.php`

Se soportan ambos formatos:

1. host con puerto embebido: `'host' => '127.0.0.1:3307'`
2. puerto explícito: `'port' => '3307'`

Fallback de puerto: `3306`.

Si no se puede completar desde `env.php`, Warp pide prompt al operador para:

1. `DATABASE_HOST`
2. `DATABASE_BINDED_PORT`
3. `DATABASE_NAME`
4. `DATABASE_USER`
5. `DATABASE_PASSWORD`

## 2.4 Cliente SQL local (host)

En modo `rds`, Warp usa cliente local del sistema (no `docker exec mysql`):

1. si hay binario genérico (`mysql`, `mariadb`, `mysqldump`, `mariadb-dump`), lo usa,
2. si falta, ofrece instalación desatendida por distro sin actualizar repos.

Distros cubiertas:

1. Debian/Ubuntu
2. Amazon Linux / RHEL-like
3. openSUSE / SLES

Si falla instalación automática, imprime guía manual.

Motor preferido según `.env`:

- `MYSQL_DOCKER_IMAGE` (mysql o mariadb).

## 3) Comandos en modo `rds`

1. `warp mysql connect`:
   - conecta al servidor externo con host/puerto/usuario/clave de `.env`.
2. `warp mysql dump <db>`:
   - genera dump desde servidor externo.
3. `warp mysql import <db>`:
   - no ejecuta import sobre externo,
   - imprime comando sugerido con redirección estándar (`< file.sql`) y password aparte.

## 3.1 MySQLTuner en local y `rds`

`warp mysql tuner` reutiliza el mismo criterio de conexión:

1. local (contenedor DB): host `localhost` y puerto mapeado (`DATABASE_BINDED_PORT` o `docker-compose port`),
2. si el puerto efectivo es `3306`, usa `localhost` sin forzar `--port`,
3. `rds`: usa `DATABASE_HOST`, `DATABASE_BINDED_PORT`, `DATABASE_USER`, `DATABASE_PASSWORD`.

## 4) Alcance de cambios

Solo modifica `.env` del servidor actual cuando se confirma modo externo.

No modifica `.env.sample`.
