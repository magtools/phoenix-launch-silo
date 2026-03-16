# Warp Update (estado actual)

Este documento resume los cambios implementados en el flujo de `warp update` y en el chequeo automatico de version, segun el comportamiento real del codigo.

## 1) Fuente remota y artefactos

`warp` usa como origen remoto:

- `https://raw.githubusercontent.com/magtools/phoenix-launch-silo/refs/heads/master/dist/version.md`
- `https://raw.githubusercontent.com/magtools/phoenix-launch-silo/refs/heads/master/dist/sha256sum.md`
- `https://raw.githubusercontent.com/magtools/phoenix-launch-silo/refs/heads/master/dist/warp`

## 2) Directorio temporal y estado persistente

Se usa:

- temporal: `./var/warp-update/`
- estado persistente: `./var/warp-update/.pending-update`

Regla de limpieza:

- `warp_update_tmp_clean` elimina contenido temporal dentro de `var/warp-update`.
- preserva siempre `.pending-update`.

## 3) Update runtime seguro (`warp update`)

El flujo actual de `warp update`:

1. Descarga `version.md`.
2. Compara version local vs remota (`yyyy.mm.dd` convertido a entero sin puntos).
3. Si ya esta actualizado (sin `--force`), limpia pending y termina.
4. Descarga `sha256sum.md` y `warp`.
5. Valida SHA-256 del binario descargado.
6. Extrae payload `__ARCHIVE__` en temporal.
7. Actualiza `.warp` desde payload, excluyendo:
   - `.warp/docker/config`
8. Reemplaza `./warp` y aplica `chmod 755`.
9. Limpia temporal y limpia `.pending-update`.

Importante:

- `warp update` no dispara wizard ni `init`.
- no usa rutas legacy de setup para update.

## 4) `update --images`

`warp update --images` mantiene comportamiento separado:

- ejecuta `docker-compose -f $DOCKERCOMPOSEFILE pull`
- no participa del flujo de checksum/binario de `warp`.

## 4.1) `update self` (modo desarrollo/publicacion local)

Se agrega:

- `warp update self`

Objetivo:

- permitir aplicar update cuando ya copiaste un nuevo `./warp` localmente (sin publicar todavia en remoto).

Comportamiento:

1. No descarga `version.md`, `sha256sum.md` ni `warp`.
2. Toma el payload `__ARCHIVE__` del `./warp` actual.
3. Extrae en `var/warp-update/extracted`.
4. Aplica exactamente el mismo bloque de copia de `.warp` que el update remoto:
   - copia `.warp` desde payload
   - excluye `.warp/docker/config`
5. Ajusta permisos ejecutables del `./warp` actual (`chmod 755`).
6. Limpia temporales y limpia `.pending-update`.

Nota:

- este modo es para pruebas/flujo local de desarrollo del binario antes de publicar artefactos remotos.

## 5) Chequeo automatico post-comando

Se ejecuta al final de cada comando via `trap` (`warp_post_command_hook`), no al inicio.

Exclusiones:

- `mysql`
- `start`
- `stop`

Frecuencia:

- controlada por `.self-update-warp`
- default: cada 7 dias (`CHECK_FREQUENCY_DAYS=7`)

Si el check remoto falla:

- escribe mensaje de error en `.pending-update`
- programa reintento en 1 dia (no 7)

Si hay version nueva:

- escribe caja de aviso en `.pending-update` con:
  - ultima version estable
  - estado desactualizado
  - sugerencia `./warp update`

Si no hay update:

- limpia `.pending-update`

El contenido de `.pending-update` se muestra al final de cada comando no excluido.

## 6) Integracion con comando `update`

`.warp/bin/update.sh` delega en el updater seguro de `warp.sh`:

- `warp_update $*`

Esto evita caminos legacy tipo `warp_setup update` que podian alterar configuracion.

## 7) Compatibilidad y seguridad

Cambios clave garantizados por el flujo actual:

- checksum obligatorio antes de reemplazar `./warp`
- no sobrescribir `.warp/docker/config`
- no ejecutar setup/wizard durante update
- conservar estado de aviso/error en `.pending-update`
- limpieza de temporales al finalizar
