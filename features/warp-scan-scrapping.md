# RFC: warp scan scraping

## Estado

Propuesto.

Nota de naming: el archivo conserva `scrapping` por compatibilidad con la
documentacion previa, pero el comando publico recomendado es `scraping`.
`scrapping` puede existir como alias tolerante.

## Objetivo

Agregar un comando de diagnostico para detectar patrones compatibles con
scraping de alto costo sobre logs de Nginx, sin bloquear trafico ni modificar
configuracion.

El comando debe funcionar con:

- logs generados por Warp en `.warp/docker/volumes/nginx/logs`;
- logs externos de servidor, por ejemplo `/var/log/nginx/access.log`;
- logs rotados plain y comprimidos `.gz`.

El resultado debe ser una lectura operativa: clientes sospechosos, paths
calientes y familias de user-agent, con score explicado por senales combinadas.

## No objetivos

- No bloquear IPs.
- No editar reglas de Nginx, WAF, ALB o firewall.
- No recargar servicios.
- No afirmar que una IP es scraper por una unica senal.
- No confiar en user-agent como prueba de bot valido o malicioso.

## Comando propuesto

```bash
warp scan scraping [options] [log_file_or_glob ...]
warp scan scrapping [options] [log_file_or_glob ...]
```

`scraping` es el nombre canonico. `scrapping` queda como alias por tolerancia a
la escritura usada en notas internas previas.

## Ejemplos

Logs de Warp:

```bash
warp scan scraping
warp scan scraping --top 50
warp scan scraping --min-score 5
```

Logs externos:

```bash
warp scan scraping /var/log/nginx/access.log
warp scan scraping /var/log/nginx/access.log /var/log/nginx/access.log.1
warp scan scraping '/var/log/nginx/access.log*'
warp scan scraping '/mnt/fronts/*/access.log*'
```

Salida para automatizacion:

```bash
warp scan scraping --json
warp scan scraping --json --output var/warp-scan/scraping.json
```

## Opciones

```bash
-n, --top N             Maximo de filas por seccion. Default: 25.
-s, --min-score N       Score minimo para listar clientes sospechosos. Default: 4.
--log PATH              Agrega un archivo o glob de log. Repetible.
--format auto|combined|warp
                         Formato de access log. Default: auto.
--request-time-field N  Campo numerico de request_time cuando no pueda detectarse.
--json                  Imprime salida JSON.
--output FILE           Escribe la salida en archivo.
-h, --help              Muestra ayuda.
```

Los argumentos posicionales `log_file_or_glob` son equivalentes a repetir
`--log`.

## Fuente de logs

Si no se reciben logs explicitos, el comando debe usar defaults de Warp:

```bash
.warp/docker/volumes/nginx/logs/access.log
.warp/docker/volumes/nginx/logs/default-access.log
.warp/docker/volumes/nginx/logs/*access*.log
.warp/docker/volumes/nginx/logs/*access*.log.[1-9]
.warp/docker/volumes/nginx/logs/*access*.log.[1-9][0-9]
.warp/docker/volumes/nginx/logs/*access*.log*.gz
```

Si se reciben logs explicitos, no debe mezclar automaticamente los defaults de
Warp, salvo que el usuario tambien los pase.

Los paths externos deben leerse desde el host. El comando no debe asumir que el
log externo existe dentro del contenedor.

`warp scan` debe resolver runtime `host` por defecto, incluso en proyectos que
ya tengan `docker-compose-warp.yml`, porque su unidad de trabajo principal son
archivos de log del filesystem local o montajes externos.

## Formatos soportados

MVP:

- Nginx combined-like con request, referer y user-agent entre comillas.
- Variante que incluya `request_time` al final de la linea.
- Logs sin `request_time`, degradando metricas de costo a `0` o `unknown`.

El parser inicial puede reutilizar el enfoque AWK del prototipo:

- dividir por comillas para extraer request, referer y user-agent;
- usar el primer token como IP;
- leer status desde el bloque posterior al request;
- obtener `path` y `query` desde el target HTTP;
- usar `request_time` solo si el campo final es numerico.

Cuando `--format auto` no pueda reconocer el formato, el comando debe avisar
cuantas lineas fueron descartadas y sugerir `--format` o
`--request-time-field`.

## Senales de scoring

El comando debe sumar score por senales combinadas. Una sola senal no debe
presentarse como evidencia concluyente.

Senales por cliente (`IP + UA family + path`):

- user-agent de libreria HTTP: `axios`, `node-fetch`, `python-httpx`,
  `python-requests`, `curl`, `wget`, `go-http-client`, `okhttp`, `aiohttp`,
  `scrapy`, `httpclient`;
- volumen alto de requests sobre el mismo path;
- muchas query strings unicas en el mismo path;
- paginacion profunda con `p` alto;
- uso repetido de ordenamientos caros como `product_list_order=price` u
  `order=price`;
- suma o promedio alto de `request_time`, cuando el log lo incluya;
- referer vacio en todas las requests;
- cantidad relevante de respuestas 4xx/5xx.

Senales por path:

- requests totales;
- IPs unicas;
- query strings unicas;
- maximo `p`;
- cantidad de requests con ordenamiento por precio;
- suma y promedio de `request_time`.

Senales por familia de user-agent:

- requests totales;
- IPs unicas;
- familia: `http-lib`, `search-bot`, `meta-bot`, `other-bot`, `browser`,
  `other`.

## Bots validos

El MVP no debe confiar en user-agent para validar bots. Si una request declara
Googlebot, Bingbot o Meta, la salida debe indicarlo como `claimed`, no como
verificado.

Fase posterior:

```bash
warp scan scraping --verify-bots
```

Ese modo puede resolver reverse DNS y confirmar forward lookup para dominios
esperados:

- `googlebot.com`
- `google.com`
- `search.msn.com`
- `facebook.com`
- `meta.com`

Sin `--verify-bots`, el score puede restar poco peso a `search-bot` o
`meta-bot`, pero el reporte debe aclarar que no hay validacion DNS.

## Salida humana

Salida propuesta:

```text
Files scanned:
  - .warp/docker/volumes/nginx/logs/access.log

Parser:
  parsed_lines=102391 skipped_lines=42 request_time=detected

Suspicious clients (score >= 4)
score count unique_q max_p price_sort sum_rt avg_rt errors ip|ua_family|path
...

Hot paths
count unique_ips unique_q max_p price_sort sum_rt avg_rt path
...

User-agent families
count unique_ips family
...

Notes:
  - Bot user-agents are not DNS-verified in this run.
  - Scores are heuristics for investigation, not automatic blocking decisions.
```

La salida debe ser estable para que se pueda copiar a tickets o incidentes.

## Salida JSON

`--json` debe emitir un objeto con secciones estables:

```json
{
  "files": [],
  "parser": {
    "parsed_lines": 0,
    "skipped_lines": 0,
    "request_time": "detected"
  },
  "clients": [],
  "paths": [],
  "user_agent_families": [],
  "notes": []
}
```

`--output FILE` escribe la misma salida seleccionada por el usuario. Si no se
usa `--json`, escribe el reporte humano.

## Exit codes

```text
0  Analisis completado.
1  No se encontraron logs o no se pudo leer ningun archivo.
2  Argumentos invalidos.
3  Formato de log no reconocido o demasiadas lineas descartadas.
```

El comando no debe devolver error solo porque encontro clientes sospechosos. Es
un comando de diagnostico.

## Integracion en Warp

Archivos esperados:

- `.warp/bin/scan.sh`
- `.warp/bin/scan_help.sh`
- `features/warp-scan-scrapping.md`

`scan` queda reservado para diagnosticos operativos y lectura de senales. Las
herramientas de lint y auditoria de codigo viven en `warp audit`, implementadas
por `.warp/bin/audit.sh`.

Este cambio debe agregarse como subcomando:

```bash
warp scan scraping
```

Si la logica crece, conviene aislarla en funciones dentro de `scan.sh` con
prefijo `scan_scraping_`. No debe mezclarse con helpers de auditoria de codigo.

Variables internas sugeridas:

```bash
local top_n
local min_score
local output_format
local output_file
local log_patterns
local log_files
local summary_file
```

Todas las variables internas deben declararse `local` dentro de funciones Bash,
salvo estado global intencional.

## Seguridad operacional

El comando solo debe leer archivos. No debe ejecutar acciones destructivas ni
pedir permisos masivos.

Para logs externos sin permiso de lectura, debe mostrar un aviso por archivo y
continuar con los que si sean legibles. Si ninguno es legible, exit code `1`.

No debe usar `sudo` automaticamente.

## Consideraciones para cluster

En entornos con multiples fronts detras de ALB, un log local puede ocultar el
patron:

- el RPM por IP baja en cada nodo;
- las secuencias de paginas aparecen incompletas;
- el costo agregado queda repartido.

Por eso el comando debe aceptar multiples logs externos o globs consolidados.
La documentacion debe recomendar ejecutar sobre logs agregados cuando existan
varios fronts.

El score por path y por firma agregada debe tener mas valor operativo que el
RPM local por IP cuando el input contiene logs de varios nodos.

## MVP recomendado

1. Agregar `warp scan scraping` y alias `scrapping`.
2. Usar defaults de logs Warp si no se pasan archivos.
3. Aceptar logs externos como argumentos o `--log`.
4. Leer plain y `.gz`.
5. Reportar:
   - clientes sospechosos;
   - paths calientes;
   - familias de user-agent;
   - metricas de parser.
6. Soportar `--top`, `--min-score`, `--json` y `--output`.
7. Documentar que no verifica bots por DNS en MVP.

## Futuras mejoras

- `--verify-bots` con reverse DNS y forward lookup.
- `--since` para filtrar por ventana temporal cuando el formato de fecha sea
  reconocible.
- `--window 5m` para score por ventanas.
- deteccion de secuencias de paginacion con gaps tolerados;
- normalizacion de query strings para agrupar firmas;
- reporte por subnet o ASN si hay herramienta disponible;
- sugerencias de mitigacion no destructivas;
- export SARIF o NDJSON para pipelines.
