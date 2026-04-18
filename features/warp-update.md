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

## 4.1) `update self` / `update --self` (modo desarrollo/publicacion local)

Se agrega:

- `warp update self`
- `warp update --self`

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
7. Al finalizar el comando, el chequeo remoto normal sigue activo.
8. Si el remoto es mas nuevo, deja la marca de update pendiente en `.pending-update`.
9. Si el remoto es mas viejo, no degrada el binario local aplicado por `--self`.

Nota:

- este modo es para pruebas/flujo local de desarrollo del binario antes de publicar artefactos remotos.
- si el `./warp` fisico local es mas nuevo que la version publicada, `--self` conserva y aplica ese payload local; no degrada al remoto.
- si la version publicada resulta mas nueva, `--self` igual aplica el payload local y deja visible el aviso de update pendiente para una corrida posterior de `warp update`.

## 4.2) Binario `warp` en PATH: wrapper delegador recomendado

Warp ahora distingue entre dos casos para `warp` encontrado en el equipo via `type -a warp`:

1. un binario/script Warp real instalado en PATH,
2. un wrapper delegador que reenvia al `./warp` del proyecto actual.

Wrapper canónico versionado:

- `.warp/setup/bin/warp-wrapper.sh`

Comportamiento esperado del chequeo:

1. si existe un wrapper delegador en PATH, Warp lo considera un estado valido y no alerta.
2. si no existe wrapper y hay un `warp` de PATH mas viejo que `./warp`, Warp alerta.
3. si puede leer `WARP_BINARY_VERSION`, compara version.
4. si no puede leer version, compara tamaño en bytes.

Remediación sugerida actual:

- pisar/reemplazar el `warp` de sistema desincronizado con el wrapper delegador canónico versionado en `.warp/setup/bin/warp-wrapper.sh`, por ejemplo:

```bash
sudo cp ".warp/setup/bin/warp-wrapper.sh" "/ruta/del/warp" && sudo chmod 755 "/ruta/del/warp"
```

Motivo:

1. evita drift entre binario global y `.warp`,
2. permite que `warp` use siempre `./warp` del proyecto,
3. evita copiar el binario `./warp` del proyecto a rutas globales del host.

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

## 8) Desalineado entre ejecutable y `.warp` instalado

Warp compara la version embebida en el ejecutable fisico con la version instalada en:

- `.warp/lib/version.sh`

Si no coinciden:

1. muestra advertencia explicita,
2. informa ambas versiones (`binary` e `installed framework`),
3. recomienda ejecutar:

```bash
./warp update --self
```

Objetivo:

1. detectar cuando se actualizo/commiteo el ejecutable pero no se aplico su payload local,
2. evitar errores por comandos nuevos en `./warp` con librerias/scripts viejos en `.warp`.

## 9) Integración del chequeo en deploy doctor y update

Estado actual:

1. `warp deploy doctor` imprime el estado de `warp` encontrado en PATH.
2. si detecta wrapper delegador, informa `[ok]`.
3. si detecta binario viejo real y no hay wrapper, informa `[warn]` y muestra como reemplazar esa ruta con el wrapper canónico.
4. al finalizar `warp update` y `warp update --self`, Warp vuelve a mostrar esta sugerencia si detecta un `warp` viejo en PATH y no existe wrapper delegador.
