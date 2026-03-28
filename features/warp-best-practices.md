# WARP Shell Best Practices

## Objetivo

Este documento resume problemas reales encontrados en los scripts de `warp`, los anti-patrones que los causaron, las soluciones aplicadas y una guía de buenas prácticas para mantener y escribir mejor código shell en el futuro.

Aplica especialmente a:

- `.warp/bin/scan.sh`
- `.warp/bin/hyva.sh`
- `.warp/bin/mysql.sh`
- `.warp/bin/memory.sh`

No es una guía teórica general de Bash. Está enfocada en fallos y riesgos ya observados en este repositorio.

---

## Resumen ejecutivo

Los problemas más repetidos en `warp` fueron:

- uso extensivo de variables globales implícitas
- pérdida o pisado de códigos de salida
- spinners frágiles que seguían activos aunque el proceso había terminado
- wrappers que mostraban éxito falso aunque el archivo de salida contenía findings
- ejecución de comandos complejos a través de strings con `bash -lc`
- mezcla de flujos de lectura con side effects fuertes
- demasiada duplicación entre comandos parecidos

La mejora más importante no fue “hacer más corto el código”, sino hacerlo más predecible:

- estado local
- códigos de salida confiables
- responsabilidades más separadas
- menos magia implícita
- menos string-shell execution

---

## Problemas reales encontrados

### 1. Variables globales implícitas

#### Síntoma

Funciones distintas reutilizaban nombres como:

- `_status`
- `_pid`
- `_path`
- `_file`
- `key`
- `targets`

sin declararlos como `local`.

#### Impacto real observado

En `scan.sh`, esto causó que:

- un módulo con findings devolviera error
- luego otro módulo limpio devolviera `0`
- el segundo estado pisara el primero
- el wrapper terminara mostrando `audit finished without issues`

aunque el archivo de salida tenía findings reales.

#### Solución aplicada

Localizar variables en funciones críticas:

- runners
- spinners
- helpers de resolución de path
- dispatchers
- funciones de reporting

#### Regla

Toda variable interna de una función debe ser `local`, salvo que:

- sea una constante global intencional
- o sea estado compartido explícito y documentado

#### Patrón recomendado

```bash
my_function() {
    local path="$1"
    local status=0
    local output=""
}
```

---

### 2. Captura incorrecta del exit code

#### Síntoma

Se usaba este patrón:

```bash
if ! wait "$pid"; then
    status=$?
fi
```

#### Impacto real observado

El script perdía el exit code real del proceso y terminaba devolviendo `0` aunque el comando hubiera fallado.

#### Solución aplicada

Capturar el estado inmediatamente después de `wait`:

```bash
wait "$pid"
status=$?
```

#### Regla

Si el resultado del comando importa, capturarlo inmediatamente. No confiar en `$?` después de lógica adicional.

---

### 3. Spinner desacoplado del proceso real

#### Síntoma

El spinner seguía “girando” aunque el análisis ya había terminado, o dejaba basura visual al repintar.

#### Causas detectadas

- PID pisado por variables globales
- `wait` mal manejado
- limpieza fija de 80 columnas cuando el mensaje ocupaba más

#### Impacto real observado

- sensación de loop infinito
- CLI reportando estado confuso
- restos visuales del spinner en pantalla

#### Soluciones aplicadas

- localización de `_pid` y `_status`
- captura correcta de `wait`
- limpieza ampliada a 100 columnas

#### Regla

El spinner debe ser una capa de UX, no una fuente de verdad.

El estado final siempre debe depender del proceso esperado, no del spinner.

---

### 4. PHPMD sobre raíces agregadas daba falso negativo

#### Síntoma

`phpmd analyze app/code ...` no encontraba un finding que sí aparecía al correr sobre el archivo puntual.

#### Impacto real observado

`testPR` y `warp audit pr` daban verde falso mientras el pipeline fallaba.

#### Solución aplicada

Expandir raíces Magento agregadas a targets concretos:

- módulos
- themes

basándose en señales como:

- `registration.php`
- `etc/module.xml`
- `theme.xml`

#### Regla

Cuando una herramienta se comporta distinto sobre una raíz agregada, preferir ejecutar por unidad lógica del proyecto en vez de por árbol masivo.

---

### 5. Reportes sobrescritos en lugar de anexados

#### Síntoma

`scan_run_pr()` corría varias herramientas sobre el mismo output file, pero algunas fases escribían en modo overwrite.

#### Impacto real observado

El bloque de `PHPCompatibility` desaparecía cuando luego corría `PHPCS`.

#### Solución aplicada

Separar claramente:

- primer writer
- writers posteriores en append

y extraer helpers de append para metadata y secciones.

#### Regla

Si un pipeline comparte archivo de salida, definir explícitamente qué pasos:

- inicializan el archivo
- agregan al archivo
- formatean encabezados

Nunca asumir ese comportamiento implícitamente.

---

### 6. Ejecución por string con `bash -lc`

#### Síntoma

En `hyva.sh` se construían comandos completos como string:

```bash
bash -lc "$npm_cmd"
```

#### Riesgo

- quoting frágil
- debugging más difícil
- mayor superficie para inyección si el input crece
- comportamiento menos predecible

#### Solución aplicada

Reemplazar ejecución por string por ejecución por argumentos:

```bash
docker exec ... npm --prefix "$tailwind_path" run build
```

Para mantener control, se introdujo un mapper explícito de acciones soportadas:

- `install`
- `run generate`
- `run build`
- `run watch`

#### Regla

Evitar `bash -lc "$cmd"` salvo cuando sea estrictamente necesario y esté muy justificado.

Preferir argv real:

```bash
command arg1 arg2 arg3
```

---

### 7. Side effects fuertes mezclados con comandos de soporte

#### Síntoma

En `mysql.sh` había comandos que:

- imprimían secretos
- instalaban paquetes del host
- descargaban herramientas
- destruían volúmenes
- reescribían `.env`

dentro del mismo helper.

#### Riesgo

- radio de impacto muy alto
- operaciones peligrosas demasiado accesibles
- debugging más difícil
- automatismos difíciles de revisar

#### Decisión tomada

No se cambió todo porque varios flujos siguen siendo operativos para el equipo.

Sí se anuló `mysql_switch()` como ejecución automática y se lo dejó en modo guía/manual.

#### Regla

Separar siempre:

- lectura / diagnóstico
- mutación de archivos
- acciones destructivas
- instalación de dependencias del host

Si una operación destruye datos, no debe convivir silenciosamente con tareas de relevamiento.

---

### 8. Salida demasiado ruidosa o poco informativa

#### Síntoma

En PHPMD:

- se imprimía `TARGET: ...` para módulos sin findings
- el spinner no mostraba el ruleset actual

#### Impacto

- ruido innecesario
- difícil correlación entre salida y causa real

#### Soluciones aplicadas

- imprimir `TARGET: ...` solo cuando hay findings
- agregar separación entre bloques de distintos módulos
- mostrar el ruleset actual en el spinner
- quitar `.xml` del label para hacerlo legible

#### Regla

La salida de consola debe responder tres preguntas:

1. qué está corriendo
2. sobre qué target
3. qué falló

Todo lo que no ayude a eso debe minimizarse.

---

## Anti-patrones a evitar

### Variables globales por default

Anti-patrón:

```bash
my_func() {
    status=0
    path="$1"
}
```

Mejor:

```bash
my_func() {
    local status=0
    local path="$1"
}
```

---

### `echo "$var" | command` cuando no hace falta

Anti-patrón:

```bash
echo "$value" | sed '...'
cat "$file" | php -r '...'
```

Mejor:

```bash
printf '%s' "$value" | sed '...'
php -r '...' < "$file"
```

Excepción:

si la tubería realmente mejora claridad o el comando necesita ese flujo.

---

### Construir comandos largos como string

Anti-patrón:

```bash
cmd="npm --prefix \"$path\" run build"
bash -lc "$cmd"
```

Mejor:

```bash
npm --prefix "$path" run build
```

o bien arrays si hace falta componer:

```bash
local -a cmd=(npm --prefix "$path" run build)
"${cmd[@]}"
```

---

### Duplicar pipelines casi iguales

Anti-patrón:

- una función para `scan pr`
- otra para `testPR on path`
- ambas con la misma secuencia base copiada y editada

#### Riesgo

Un fix entra en una, pero no en la otra.

#### Mejor

Extraer un helper común y parametrizar:

- suffix de output
- path de código
- path de design

---

### Mostrar secretos completos

Anti-patrón:

- passwords en `info`
- credenciales en comandos imprimibles

#### Mejor

Mostrar:

- host
- usuario
- puerto
- estado

y si se necesita identificar el secreto:

- enmascarar
- o indicar solo si está configurado

Ejemplo:

```bash
Password: ******** (configured)
```

---

### Hacer demasiado en una función

Anti-patrón:

una sola función que:

- pregunta
- modifica `.env`
- borra volúmenes
- descarga imágenes
- recrea config
- imprime siguientes pasos

#### Mejor

Separar:

- validación previa
- plan de acciones
- ejecución destructiva
- post pasos

Si la acción es riesgosa, incluso mejor:

- solo generar guía manual
- o exigir confirmaciones más explícitas

---

## Buenas prácticas recomendadas

### 1. Diseñar funciones pequeñas y monotarea

Cada función debería hacer una sola cosa:

- resolver targets
- correr una herramienta
- imprimir reporte
- formatear output

Si una función necesita más de una pantalla para entender qué hace, probablemente está haciendo demasiado.

---

### 2. Mantener separación entre “resolver”, “ejecutar” y “reportar”

Patrón recomendado:

1. resolver input
2. ejecutar proceso
3. capturar estado
4. reportar resultado

No mezclar esas responsabilidades sin necesidad.

---

### 3. Mantener flujos append/overwrite explícitos

Cuando un comando genera archivo de salida:

- definir si inicializa
- definir si agrega
- definir si reescribe

No usar el mismo helper para ambos modos sin dejarlo explícito.

---

### 4. Centralizar dispatch y helpers comunes

Si menú y CLI llaman las mismas acciones, ambos deben pasar por el mismo dispatcher.

Beneficios:

- menos divergencia
- menos ramas duplicadas
- menor costo de mantenimiento

---

### 5. Validar por unidad lógica del proyecto

Para herramientas estáticas, preferir:

- módulo por módulo
- theme por theme

antes que grandes raíces agregadas, si eso mejora confiabilidad y trazabilidad.

---

### 6. Tratar el spinner como opcional

El spinner nunca debe ser obligatorio para que el comando funcione bien.

Debe poder quitarse sin afectar:

- exit code
- archivos de salida
- reporting final

---

### 7. Reducir side effects sorpresa

Un comando llamado `info`, `scan`, `discover` o `report` no debería:

- editar `.gitignore`
- cambiar `.env`
- instalar paquetes del host
- descargar ejecutables
- borrar volúmenes

si no está claramente documentado y delimitado.

Si por compatibilidad se mantiene, debe ser muy visible en la ayuda y salida.

---

### 8. Mantener mensajes cortos y accionables

Un buen mensaje operativo:

- dice qué pasó
- dice dónde
- dice qué hacer ahora

Ejemplo:

```text
phpmd found issues in app/code/Ecommerce66/Gtm
output: var/static/scan_testpr_20260325-201409.txt
next: review ProductList.php and rerun warp audit pr
```

---

### 9. Documentar decisiones no obvias

Ejemplos de cosas que conviene dejar comentadas:

- por qué un tool se ejecuta por módulo y no por raíz
- por qué cierto ruleset va antes que otro
- por qué cierto spinner width se fijó en 100
- por qué cierta acción quedó manual y no automática

No comentar lo obvio. Comentar decisiones y tradeoffs.

---

### 10. Priorizar seguridad en helpers operativos

Checklist mínimo:

- no imprimir secretos completos
- no usar passwords en argumentos si puede evitarse
- no desactivar validación TLS salvo caso muy acotado y documentado
- no descargar/ejecutar herramientas externas sin dejarlo muy claro
- no correr acciones destructivas como side effect de comandos ambiguos

---

## Reglas concretas para nuevos scripts `warp`

### Estructura recomendada

```bash
#!/bin/bash

. "$PROJECTPATH/.warp/bin/tool_help.sh"

tool_helper_a() {
    local path="$1"
}

tool_helper_b() {
    local status=0
}

tool_run_action() {
    local target="$1"
    local output_file="$2"
}

tool_main() {
    case "$1" in
        action)
            shift
            tool_run_action "$@"
        ;;
        -h|--help|"")
            tool_help_usage
        ;;
        *)
            warp_message_error "unknown command: $1"
            tool_help_usage
            return 1
        ;;
    esac
}
```

### Reglas de estilo

- usar `local` por default
- quote siempre variables con paths o texto
- capturar status inmediatamente
- preferir `printf` sobre `echo` cuando importe exactitud
- evitar subshells y pipes innecesarios
- extraer helpers cuando haya duplicación real
- no ocultar side effects

---

## Priorización sugerida de deuda técnica actual

### Prioridad alta

- `mysql.sh`
  - ocultar secretos en `info`
  - revisar uso de passwords en CLI
  - separar aún más flujos destructivos / install / download

### Prioridad media

- `hyva.sh`
  - seguir localizando variables
  - revisar si `.gitignore` debe pasar a modo opt-in
  - revisar si conviene helper común de logs y spinner

### Prioridad media-baja

- `memory.sh`
  - seguir higiene de variables
  - revisar fallback TLS y supuestos de localhost

### Prioridad continua

- mantener `scan.sh` como referencia positiva de lo ya corregido
- no reintroducir helpers que mezclen:
  - ejecución
  - estado global
  - UX
  - reporting

---

## Criterio de aceptación para futuros cambios en `warp`

Antes de dar por bueno un cambio en shell, validar:

1. ¿usa variables `local` en la función nueva?
2. ¿el exit code real del proceso se conserva?
3. ¿el spinner puede romper el resultado si falla?
4. ¿la salida final coincide con el archivo de salida?
5. ¿hay side effects inesperados?
6. ¿el mismo fix quedó replicado en menú y CLI?
7. ¿hay secretos impresos o expuestos?
8. ¿el flujo puede entenderse rápido sin leer todo el archivo?

Si una respuesta importante es “no”, el cambio no está suficientemente sólido.

---

## Cierre

La lección principal de esta pasada es simple:

los problemas más costosos no vinieron de lógica compleja del negocio, sino de shell glue frágil.

En `warp`, la robustez depende más de:

- estado explícito
- responsabilidades pequeñas
- reporting fiel
- side effects controlados

que de agregar más features o más automatismos.
