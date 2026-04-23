# Warp Agents

Estado: implementado

Este documento define el comando `warp agents` orientado a consumir un repositorio privado con automatizaciones auxiliares del individuo/organización que opera el proyecto.

## 1) Objetivo

Agregar una superficie simple y predecible para:

- declarar un repositorio Git privado de agents por proyecto,
- clonarlo localmente fuera del árbol trackeado del proyecto,
- ejecutar un `install.sh` inicial,
- ejecutar un `update.sh` bajo demanda,
- y enganchar ese `update` al final de `warp start`.

La intención es que Warp provea el lifecycle mínimo, sin mezclar todavía lógica específica de los agents dentro del core.

## 2) Configuración del proyecto

Se propone un archivo versionado:

- `./.warp/docker/config/agents/config.ini`

Contenido mínimo esperado:

```ini
AGENTS_REPO=
```

Reglas:

1. el archivo debe existir al menos con esa clave;
2. el valor inicial debe quedar vacío;
3. el archivo debe copiarse durante `warp init`;
4. el archivo debe quedar trackeado en el proyecto;
5. si no existe todavía en un proyecto ya inicializado, `warp agents install` debe recrearlo antes de continuar.

## 3) Repositorio local de agents

Se propone clonar el repositorio configurado en:

- `./.agents-md`

Reglas:

1. `./.agents-md` no debe trackearse en Git;
2. `warp agents install` debe añadir `/.agents-md` a `.gitignore` si aún no existe;
3. el repositorio remoto se considera privado y perteneciente al individuo/organización del operador;
4. si el clone falla por acceso/autenticación, Warp debe informar que se debe configurar una clave válida para poder clonarlo;
5. si `./.agents-md` existe y está vacío, `warp agents install` puede clonar allí;
6. si `./.agents-md` existe y no está vacío, `warp agents install` debe informar que agents ya está instalado y no hacer nada.

## 4) Contrato esperado del repo de agents

El repositorio remoto tendrá siempre estos scripts:

- `.agents-md/install.sh`
- `.agents-md/update.sh`

Contrato propuesto:

1. `install.sh` se ejecuta luego de un clone exitoso en `warp agents install`;
2. `update.sh` se ejecuta en `warp agents update`;
3. Warp debe ejecutar los scripts con Bash, sin exigir bit ejecutable:
   - `bash .agents-md/install.sh`
   - `bash .agents-md/update.sh`
4. Warp no necesita heredar un entorno especial propio hacia esos scripts;
5. Warp no asume por ahora más archivos ni estructura adicional;
6. si alguno de esos scripts falta, el comando debe fallar con mensaje claro;
7. los scripts del repo privado son responsables de su propia lógica interna, incluyendo `git pull`, notificaciones, validaciones y manejo detallado de fallos.

## 5) Comando `warp agents`

Se propone una superficie inicial mínima:

- `warp agents install`
- `warp agents update`

### 5.1) `warp agents install`

Comportamiento propuesto:

1. asegurar que exista `./.warp/docker/config/agents/config.ini`;
2. si el archivo no existe, copiarlo desde el template y avisar que debe completarse para continuar;
3. leer `AGENTS_REPO`;
4. si `AGENTS_REPO` está vacío, no intentar clone y mostrar mensaje explícito para completar la URL;
5. si `AGENTS_REPO` tiene una URL Git SSH, intentar clonar en `./.agents-md`;
6. asegurar `/.agents-md` en `.gitignore`;
7. ejecutar `.agents-md/install.sh` como post-install;
8. si `./.agents-md` ya existe y no está vacía, responder:
   - `agents ya esta instalado, nada que hacer`

Notas de UX:

- el mensaje por config faltante o incompleta debe ser accionable;
- el mensaje por falla de clone debe mencionar explícitamente la necesidad de una clave válida.
- solo se soportan URLs SSH, por ejemplo `git@host:org/repo.git` o `ssh://git@host/org/repo.git`; otros esquemas deben rechazarse con mensaje claro.

### 5.2) `warp agents update`

Comportamiento propuesto:

1. verificar que exista `./.agents-md`;
2. verificar que exista `.agents-md/update.sh`;
3. ejecutar `bash .agents-md/update.sh`;
4. si `./.agents-md` no existe, fallar con mensaje claro indicando que primero debe correrse `warp agents install`.

## 6) Integración con `warp init`

Se propone que `warp init` copie un template inicial hacia:

- `./.warp/docker/config/agents/config.ini`

Objetivo:

1. dejar visible desde el arranque que el proyecto puede usar agents;
2. permitir que el archivo se complete y se versione junto al resto del proyecto;
3. evitar que `warp agents install` tenga que inferir defaults ocultos.

Regla adicional:

1. el mismo template debe poder copiarse desde `warp agents install` cuando el proyecto ya existe y todavía no tiene `./.warp/docker/config/agents/config.ini`.

## 7) Integración con `warp start`

Se propone que `warp start` intente mantener actualizado el repo auxiliar sólo cuando ya exista:

```bash
./.agents-md/update.sh
```

Momento de ejecución:

1. después de terminar de levantar contenedores;
2. no antes del `compose up`;
3. como paso posterior del lifecycle normal de arranque.

Contrato del hook:

1. si `./.agents-md/update.sh` no existe, `warp start` no debe llamar a `warp agents update`;
2. si `./.agents-md/update.sh` existe, `warp start` debe ejecutar `bash .agents-md/update.sh` de forma silenciosa;
3. si el script falla, `warp start` debe mostrar un aviso indicando que no se pudo actualizar agents;
4. el fallo del update de agents no debe bloquear `warp start` ni cambiar su exit code a error;
5. el manejo detallado de errores y notificaciones queda en `warp agents update` y/o en el propio `.agents-md/update.sh`;
6. si `AGENTS_REPO` esta configurado pero `./.agents-md` no existe o esta vacio, `warp start` debe mostrar un cuadro informativo indicando que falta correr `warp agents install`, sin bloquear el arranque.
7. si el proyecto Magento esta en `MAGE_MODE=production`, `warp start` / `warp restart` no deben mostrar ese cuadro ni ejecutar el hook automatico de agents post-start.

Intención:

- mantener actualizado el repo auxiliar de agents en cada arranque del entorno.

## 8) Reglas de Git y tracking

Se propone distinguir claramente dos superficies:

| Ruta | Tracking esperado |
| --- | --- |
| `./.warp/docker/config/agents/config.ini` | versionado |
| `./.agents-md` | ignorado |

Esto preserva:

1. configuración declarativa del proyecto dentro del repo;
2. artefactos operativos externos fuera del árbol trackeado.

## 9) Manejo de errores esperado

Casos mínimos a cubrir:

1. falta `config.ini`:
   - copiar template y avisar que debe completarse;
2. `AGENTS_REPO` vacío:
   - abortar sin clone y pedir completar la URL;
3. clone fallido:
   - abortar e indicar que debe agregarse una clave válida para clonar el repo privado;
4. falta `install.sh` o `update.sh`:
   - abortar con mensaje explícito;
5. instalación ya presente:
   - informar `agents ya esta instalado, nada que hacer`.

Nota para `warp start`:

1. el hook post-start es best-effort;
2. no debe fallar si agents no está instalado;
3. no debe fallar si el update de agents falla.

## 10) Alcance de esta RFC

Incluido en esta propuesta:

1. nuevo comando `warp agents`;
2. config mínima por proyecto;
3. clone SSH a `./.agents-md`;
4. ejecución de `install.sh` y `update.sh`;
5. hook post-start para `update`.

Fuera de alcance por ahora:

1. múltiples repositorios de agents;
2. branches, tags o revisiones fijadas en config;
3. soporte HTTPS/token;
4. gestión avanzada de errores/reintentos;
5. contratos adicionales dentro del repo de agents;
6. sincronización/desinstalación.

Consideraciones de runtime:

1. `warp agents` debe funcionar en modo host-compatible, sin requerir Docker ni `docker-compose`;
2. `agents` debe agregarse al listado de comandos que pueden arrancar sin runtime Docker cuando no existe `docker-compose-warp.yml`;
3. Warp sólo orquesta la ejecución; el repositorio privado de agents se considera código confiable bajo responsabilidad del operador.

## 11) Resumen funcional propuesto

Flujo esperado:

1. `warp init` copia `./.warp/docker/config/agents/config.ini`;
2. el operador completa `AGENTS_REPO` con una URL SSH válida;
3. `warp agents install` clona `./.agents-md`, lo ignora en Git y ejecuta `install.sh`;
4. `warp agents update` ejecuta `update.sh`;
5. `warp start` ejecuta silenciosamente `bash .agents-md/update.sh` al finalizar el arranque de contenedores sólo si ese archivo existe.

Este RFC define una primera iteración deliberadamente simple, con foco en bootstrap, claridad operativa y separación entre configuración versionada del proyecto y automatización privada externa.
