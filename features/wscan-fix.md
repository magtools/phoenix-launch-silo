# Warp Scan Fixes

## Objetivo

Documentar los cambios aplicados sobre `warp scan` y `codeanalyzer.sh`, indicando:

- que problema se detecto
- por que ocurria
- que cambio se hizo
- que comportamiento se espera ahora

## Contexto del problema

Se detectaron discrepancias entre:

- `bitbucket-pipelines`
- `codeanalyzer.sh` (`testPR`)
- `warp scan pr`
- `warp scan` opcion `phpmd`

Caso visible:

- el pipeline detectaba `NPathComplexity` en `app/code/Ecommerce66/Gtm/ViewModel/ProductList.php`
- `testPR` y `warp scan pr` inicialmente no lo reflejaban correctamente
- `warp scan phpmd` podia generar reportes invalidos o marcar exito falso

## 1. PHPMD sobre roots agregados daba falso negativo

### Sintoma

El pipeline ejecutaba:

```bash
php ./vendor/phpmd/phpmd/bin/phpmd analyze app/code --format text --ruleset app/devops/TestPR.xml --no-progress
```

y reportaba:

- `app/code/Ecommerce66/Gtm/ViewModel/ProductList.php`
- `NPathComplexity`

Pero:

- `codeanalyzer.sh` con `testPR`
- `warp scan pr`

al analizar `app/code` completo podian no reflejar ese finding.

### Causa

`PHPMD` sobre una raiz agregada grande como `app/code` no estaba devolviendo de forma consistente los findings esperados para ciertos casos, mientras que sobre targets concretos si los devolvia.

### Cambio aplicado

Se agrego expansion de targets Magento concretos:

- modulos detectados por `registration.php` o `etc/module.xml`
- themes detectados por `theme.xml`

En lugar de correr `PHPMD` una sola vez sobre `app/code`, ahora:

- se expande a modulos / themes hijos
- se ejecuta `PHPMD` por target concreto

### Archivos tocados

- `codeanalyzer.sh`
- `.warp/bin/scan.sh`

### Resultado esperado

- `testPR` detecta findings que antes quedaban ocultos
- `warp scan pr` detecta findings reales por modulo

## 2. `warp scan pr` detectaba findings pero mostraba exito falso

### Sintoma

El archivo de salida de `warp scan pr` contenia findings reales, pero la consola mostraba:

```text
scan finished without issues
```

### Causa

Habia colision de variables globales shell, especialmente `_status`, entre:

- `scan_run_phpmd_compat()`
- `scan_run_phpmd_compat_targets()`

El ultimo target limpio podia pisar el estado de un target previo con error.

### Cambio aplicado

Se pasaron variables a `local` en varias funciones relacionadas con PHPMD:

- `scan_run_phpmd_compat()`
- `scan_is_phpmd_project_target()`
- `scan_resolve_phpmd_targets()`
- `scan_run_phpmd_compat_targets()`

### Resultado esperado

- si algun target falla, `warp scan pr` debe terminar con estado de error
- la salida de consola debe coincidir con el contenido del archivo

## 3. El spinner podia quedar colgado o dejar basura visual

### Sintoma

En algunos casos:

- el spinner parecia seguir corriendo aunque el analisis habia terminado
- quedaban restos visuales del spinner en la consola

### Causa

Los helpers del spinner usaban variables globales y gestionaban mal el `wait`:

- `scan_spinner_wait()`
- `scan_run_to_file_with_spinner()`
- `scan_run_capture_with_spinner()`

Ademas, el borrado final usaba ancho fijo corto.

### Cambio aplicado

1. Se pasaron variables a `local` en funciones de spinner.
2. Se corrigio la captura del exit code real:

```bash
wait "$_pid"
_status=$?
```

en vez de usar patrones con `if ! wait ...` que perdian el exit code real.

3. Se aumento el ancho de limpieza final del spinner de `80` a `100` columnas.

### Resultado esperado

- menos riesgo de spinner colgado por colision de variables
- el estado final debe reflejar el retorno real del proceso
- menos restos visuales en consola

## 4. `warp scan` opcion `phpmd` usaba una invocacion incorrecta de PHPMD

### Sintoma

El archivo de la opcion `phpmd` podia llenarse con errores como:

```text
Command "app/code/Ecommerce66/Gtm" is not defined.
```

### Causa

El wrapper estaba entrando por una sintaxis legacy no compatible con el binario actual de `PHPMD`.

### Cambio aplicado

Se corrigio el orden de fallback en `scan_run_phpmd_compat()`:

1. intentar primero:

```bash
phpmd analyze ...
```

2. si no aplica, fallback a:

```bash
phpmd check ...
```

3. luego sintaxis legacy si realmente hiciera falta

### Resultado esperado

- la opcion `warp scan -> phpmd` genera reportes validos
- deja de escribir `Command "... is not defined."` como salida principal

## 5. El menu interactivo de `warp scan` podia pisar variables

### Sintoma

En flujos interactivos se observo comportamiento raro:

- reimpresion de listas
- sensacion de loop
- transiciones inconsistentes entre menu de paths y acciones

### Causa

Las funciones del menu usaban muchas variables globales:

- `scan_path_option_add()`
- `scan_path_option_add_children()`
- `scan_select_path_menu()`
- `scan_menu_tools_for_path()`
- `scan_menu_path()`

### Cambio aplicado

Se migraron variables locales en esas funciones para aislar estados del menu.

### Resultado esperado

- menos riesgo de que opciones del menu se pisen entre si
- flujo interactivo mas estable

## 6. El spinner de PHPMD ahora informa el ruleset activo

### Motivo

La opcion `phpmd` hace una pasada por cada ruleset:

- `cleancode`
- `codesize`
- `controversial`
- `design`
- `naming`
- `unusedcode`

Sin mostrar el ruleset, el spinner era ambiguo.

### Cambio aplicado

Se agrego el nombre del ruleset al texto del spinner, sin la extension `.xml`.

Ejemplo:

```text
running phpmd analyze [codesize] on app/code/Ecommerce66/Gtm
```

### Resultado esperado

- mas claridad durante ejecucion
- el operador puede entender en que pasada esta el analisis

## 7. `TARGET:` solo se imprime cuando un modulo tiene salida

### Problema previo

Al expandir `PHPMD` por modulo, el log podia llenarse con muchas lineas:

```text
TARGET: app/code/Modulo
```

incluso cuando ese modulo no tenia findings.

### Cambio aplicado

Se cambio el comportamiento para que:

- `TARGET: ...` solo se imprima si ese target devuelve salida
- se deje una separacion simple entre bloques con findings

### Resultado esperado

- menos ruido en el reporte
- mejor legibilidad

## 8. `warp scan pr` ahora incorpora PHPCompatibility

### Situacion previa

El pipeline ejecutaba `PHPCompatibility`, pero `warp scan pr` no.

Pipeline:

```bash
php ./vendor/squizlabs/php_codesniffer/bin/phpcs --standard=PHPCompatibility --runtime-set testVersion 8.4 --extensions=php,phtml app/code
```

### Cambio aplicado

`warp scan pr` ahora corre:

1. `PHPCompatibility`
2. `PHPCS`
3. `PHPMD`

Y `PHPCompatibility` reutiliza la deteccion de version PHP ya existente en:

- `scan_phpcompat_target_version()`

No queda hardcodeado `8.4`; toma la version del runtime / `.env`.

### Alcance

Se mantiene alineado al flujo ya existente:

- extensiones: `php,phtml`
- path: `app/code`

Tambien se aplico lo mismo a:

- `scan_run_testpr_on_path()`

### Resultado esperado

- `warp scan pr` mas alineado con `bitbucket-pipelines`
- menos diferencias entre analisis local y pipeline

## 9. El reporte de `warp scan pr` podia perder secciones por overwrite

### Sintoma

Luego de agregar `PHPCompatibility` a `warp scan pr`, el archivo de salida podia quedar incompleto.

Caso tipico:

- se ejecutaba `PHPCompatibility`
- luego se ejecutaba `PHPCS`
- el archivo final podia quedar con la salida del ultimo paso y sin la del primero

### Causa

`scan_run_pr()` y `scan_run_testpr_on_path()` usaban varias veces `scan_run_to_file_with_spinner()` sobre el mismo archivo, y ese helper redirige con overwrite:

```bash
> "$_outfile"
```

### Cambio aplicado

Se dejo de reutilizar ese helper para los pasos encadenados del `test PR`.

Ahora:

- se crea el archivo una vez
- cada herramienta escribe primero a `SCAN_LAST_CAPTURED_OUTPUT`
- luego el wrapper hace append manual al archivo final

Se extrajeron helpers:

- `scan_append_phpcompat_metadata()`
- `scan_append_phpmd_output()`
- `scan_run_testpr_suite()`

### Resultado esperado

- el archivo final conserva las secciones de:
  - `PHPCompatibility`
  - `PHPCS`
  - `PHPMD`
- menor duplicacion entre `scan_run_pr()` y `scan_run_testpr_on_path()`

## 10. Se redujo duplicacion en runners simples

### Problema previo

Los runners de herramientas simples repetian el mismo patron:

- construir suffix seguro
- construir nombre de archivo
- correr con spinner
- reportar resultado

Esto aparecia en:

- `phpcs`
- `phpcbf`
- `phpcompat`
- `phpstan`

### Cambio aplicado

Se extrajeron helpers:

- `scan_build_safe_suffix()`
- `scan_run_simple_tool_to_file()`

### Resultado esperado

- menos codigo repetido
- menos riesgo de divergencia entre runners
- mantenimiento mas simple

## 11. Se centralizo parte del dispatch de acciones

### Problema previo

La seleccion de acciones estaba repetida en varios lugares:

- `scan_menu_main()`
- `scan_menu_tools_for_path()`
- `scan_command()`

Eso aumentaba el riesgo de que una accion se comportara distinto segun se ejecutara por menu o por CLI.

### Cambio aplicado

Se agrego:

- `scan_run_selected_action()`

Este helper centraliza la ejecucion de:

- `phpcs`
- `phpcbf`
- `phpmd`
- `phpcompat`
- `phpstan`
- `test PR`

### Resultado esperado

- menos branching repetido
- menor riesgo de inconsistencias entre menu y CLI

## 12. Se corrigio una pequena regresion en el nombre del output file de `test PR`

### Sintoma

Al extraer `scan_run_testpr_suite()`, el modo por path podia generar siempre:

```text
scan_testpr_<timestamp>.txt
```

en lugar de conservar el sufijo del path.

### Cambio aplicado

`scan_run_testpr_suite()` ahora recibe el suffix de output como argumento.

Con esto:

- `warp scan pr` sigue generando `scan_testpr_<timestamp>.txt`
- `warp scan` por path vuelve a generar `scan_testpr_<path>_<timestamp>.txt`

### Resultado esperado

- se mantiene la trazabilidad esperada en los reportes por path

## 13. Estado actual y riesgo residual

### Estado actual

Luego de estas rondas:

- no queda identificado un bug funcional claro comparable a los ya corregidos
- el archivo sigue siendo grande, pero bastante menos fragil que al inicio

### Riesgo residual

Todavia quedan funciones antiguas con variables globales implicitas.

Esto ya no aparece como un bug inmediato, pero si como deuda tecnica de mantenimiento.

La recomendacion es:

- no seguir agregando features grandes sin antes considerar una separacion mas clara entre:
  - runtime / wrappers
  - tool runners
  - menu interactivo
  - dispatch CLI

En el estado actual, el script ya deberia ser mucho mas confiable que antes para uso operativo diario.

## Archivos modificados

- `.warp/bin/scan.sh`
- `codeanalyzer.sh`

## Siguiente recomendacion

Aunque el tooling ahora refleja mejor los findings reales, sigue siendo recomendable corregir el codigo reportado por pipeline, por ejemplo:

- `app/code/Ecommerce66/Gtm/ViewModel/ProductList.php`

El objetivo de estos cambios fue:

- alinear mejor `warp scan` con el pipeline
- evitar falsos verdes
- mejorar la experiencia operativa del wrapper
