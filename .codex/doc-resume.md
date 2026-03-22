# resume.md

## Objetivo

Este documento describe el script [`/.codex/resume.sh`](./resume.sh), su intención y cómo funciona.

La intención principal es reanudar sesiones de Codex del proyecto actual sin tener que recordar manualmente el `session_id`.

---

## Qué hace

1. Detecta `PROJECT_ROOT` y `$CODEX_HOME` (por defecto `~/.codex`).
2. Recorre `$CODEX_HOME/sessions` de forma recursiva.
3. Filtra solo sesiones cuyo `session_meta.payload.cwd` coincide con el proyecto actual.
   - Si la sesión guardó el path físico y el repo fue abierto por un symlink/path lógico, también considera equivalencia por ruta canónica (`pwd -P`).
4. Ordena por más recientes y muestra hasta 9.
5. Permite elegir `1..9` o `0` para salir.
6. Si se elige una sesión válida, obtiene su `session_id` y ejecuta:
   - `/.codex/init.sh -r <session_id>`

---

## Formato del menú

Columnas:

1. `No.`: opción de menú
2. `Size`: tamaño legible (`B`, `KB`, `MB`) alineado a la derecha
3. `Created At`: fecha/hora de creación (o `mtime` como fallback)
4. `Last Access`: fecha/hora de último acceso

Después de la tabla:

1. línea en blanco
2. `0. Exit`

---

## Resolución de session_id

`resume.sh` usa una estrategia robusta:

1. Extrae `payload.id` desde la primera línea del archivo (`head -n 1`).
2. Si falla, busca `session_meta` con `rg -a` y vuelve a extraer `payload.id`.
3. Si sigue fallando, usa UUID parseado desde el nombre del archivo (`rollout-...-<uuid>.jsonl`).

Esto evita fallos con archivos grandes o contenido no estándar.

---

## Modo debug (sin ejecutar resume real)

Para validar qué sesión/ID está resolviendo:

```bash
RESUME_PRINT_ONLY=1 ./.codex/resume.sh
```

Comportamiento:

1. Muestra el mismo menú.
2. Al elegir una opción, imprime:
   - `Session file: ...`
   - `Session id: ...`
3. No ejecuta `init.sh`.

---

## Dependencias

Herramientas usadas por el script:

1. `find`
2. `sort`
3. `cut`
4. `head`
5. `grep`
6. `rg`
7. `sed`
8. `stat`
9. `date`
10. `awk`

---

## Troubleshooting rápido

1. Error `No sessions found for project ...`:
   - revisar que existan sesiones con `payload.cwd` igual al path del proyecto.
   - si el repo fue abierto por symlink, confirmar la ruta física con `pwd -P`; `resume.sh` compara tanto ruta lógica como física.
2. Error `Could not read session id ...`:
   - validar contenido del archivo `.jsonl`.
   - correr en debug para confirmar extracción:
     - `printf 'N\n' | RESUME_PRINT_ONLY=1 ./.codex/resume.sh`
3. Si `codex resume` falla por ID no encontrado:
   - validar que `Session id` impreso en debug exista realmente en `session_meta.payload.id`.
