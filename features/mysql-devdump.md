# Feature: `warp mysql devdump`

Fecha: 2026-03-16

## 1) Objetivo funcional

Generar dumps livianos para desarrollo, preservando estructura completa y excluyendo datos de tablas sensibles/voluminosas según perfil por aplicación.

## 2) Comandos

```bash
warp mysql devdump
warp mysql devdump:magento
```

## 3) Diseño operativo

1. `warp mysql devdump` funciona como helper de la feature:
   - muestra descripción,
   - lista apps disponibles detectadas por perfiles.
2. `warp mysql devdump:<app>` ejecuta el devdump de esa app.
3. La lógica está desacoplada en módulo propio (`.warp/bin/mysql_devdump.sh`).
4. Los perfiles de exclusión están desacoplados en archivos, para extender sin tocar core.

## 4) Perfiles por app

Directorio:

`/.warp/bin/mysql/devdump/profiles`

Formato:

`<app>.<perfil>.tables.txt`

Ejemplo Magento:

1. `magento.base.tables.txt`
2. `magento.compact.tables.txt`

Selección:

1. si existe solo un perfil para la app, se ejecuta directo,
2. si hay varios perfiles, Warp muestra menú numerado:
   - opción por perfil,
   - opción `0` para combinar todos los perfiles.

## 5) Fuente de conexión

No pide datos extra: usa `.env`.

1. si `MYSQL_VERSION=rds`, ejecuta contra DB externa,
2. si no, usa el contenedor `mysql` del stack.

## 6) Salida de archivos

Nombre:

`<db>_devdump_<YYYYmmdd_HHMM>.sql`

También genera:

`<db>_devdump_<YYYYmmdd_HHMM>.sql.gz`

Ubicación:

1. app `magento`: `./var`
2. otras apps: directorio actual

Warp informa en pantalla ambos paths de salida.

## 7) Proceso del dump

1. dump de estructura (`--no-data`),
2. dump de datos excluyendo tablas de perfil,
3. limpieza de `DEFINER`,
4. compresión a `.gz`.

## 8) Extensión futura (nuevas apps)

Para añadir una app nueva no hace falta editar el core:

1. crear archivo(s) de perfil en `/.warp/bin/mysql/devdump/profiles`,
2. ejecutar `warp mysql devdump:<nueva-app>`.
