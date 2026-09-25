# Warp Stress

Fecha: 2026-09-25

Estado: implementado

`warp stress` ejecuta pruebas HTTP con k6 en un runtime Compose independiente del stack principal. Usa `grafana/k6:0.49.0`, el proyecto Compose `warp-stress` y guarda los resultados bajo `var/warp-stress/`. No inicia ni detiene los servicios normales de Warp.

## Inicio rápido

1. Iniciar el runtime y crear los archivos iniciales:

   ```bash
   warp stress start
   ```

2. Editar `.stresscfg` con un destino real y permitido:

   ```dotenv
   STRESS_BASE_URL=https://uat.example.test
   STRESS_TARGET_CLASS=uat
   STRESS_ALLOWED_HOSTS=uat.example.test
   ```

3. Validar y ejecutar un profile:

   ```bash
   warp stress profiles
   warp stress validate --profile catalog-load
   warp stress run --profile catalog-load --dry-run
   warp stress run --profile catalog-load
   ```

Los destinos `prod` requieren confirmación. `--yes` la omite y debe usarse deliberadamente.

## Comandos

| Comando | Acción |
| --- | --- |
| `warp stress start` | Materializa configuración y arranca el contenedor k6. |
| `warp stress stop [--hard]` | Detiene el runtime; `--hard` también elimina sus contenedores. |
| `warp stress status` / `logs [-f]` | Muestra estado o logs del runtime. |
| `warp stress sitemap [--refresh]` | Descarga y procesa el sitemap del destino. |
| `warp stress datasets` / `profiles` | Informa datasets o lista profiles. |
| `warp stress validate [--profile <nombre>]` | Valida destino, script y datasets de un profile. |
| `warp stress warmup [opciones]` | Ejecuta `catalog-warm`, salvo que se indique otro profile. |
| `warp stress run [opciones]` | Ejecuta un profile k6. |
| `warp stress report [latest\|<directorio>]` | Lee el resumen persistido de una corrida. |

`run` y `warmup` aceptan `--profile`, `--rate`, `--duration`, `--vus`, `--max-vus`, `--stage`, `--yes` y `--dry-run`. Los overrides sólo afectan esa ejecución.

## Archivos y precedencia

| Ruta | Uso | Seguimiento |
| --- | --- | --- |
| `.stresscfg` | Destino y defaults locales. | No trackear. |
| `docker-compose-stress.yml` | Runtime Compose aislado. | No trackear. |
| `.warp/docker/config/stress/` | Profiles y escenarios k6. | Versionar los propios del proyecto. |
| `var/warp-stress/` | Sitemap, datasets, resultados y logs. | No trackear. |

Warp carga primero `.stresscfg` y después el archivo del profile, por lo que el profile prevalece. Los flags de `run` y `warmup` prevalecen para tasa, duración, VUs iniciales, VUs máximas y stages.

## Profiles existentes

Los profiles seed están en `.warp/docker/config/stress/profiles/`: `catalog-warm`, `catalog-baseline`, `catalog-load`, `catalog-load-realistic`, `catalog-stress`, `catalog-stress-realistic`, `catalog-search-load` y `catalog-search-stress`.

Cada uno es un archivo `KEY=VALUE`. Ejemplo:

```dotenv
STRESS_PROFILE_NAME=catalog-load
STRESS_TYPE=load
STRESS_SCENARIO_SCRIPT=scenarios/catalog.js
STRESS_EXECUTOR=constant-arrival-rate
STRESS_RATE=300
STRESS_DURATION=5m
STRESS_TIME_UNIT=1m
STRESS_PRE_ALLOCATED_VUS=25
STRESS_MAX_VUS=120
STRESS_URL_ORDER=random
STRESS_URL_REVISIT_RATE=4
```

Con `ramping-arrival-rate`, `STRESS_STAGES` usa CSV con el formato `tasa:duración`, por ejemplo `100:2m,250:3m,0:2m`.

## Profiles y escenarios personalizados

Un escenario debe ser un script JavaScript de k6 dentro de `.warp/docker/config/stress/scenarios/`. El profile lo selecciona con una ruta relativa a `.warp/docker/config/stress/`.

```dotenv
# .warp/docker/config/stress/profiles/product-detail-load.env
STRESS_PROFILE_NAME=product-detail-load
STRESS_TYPE=load
STRESS_SCENARIO_SCRIPT=scenarios/product-detail.js
STRESS_EXECUTOR=constant-arrival-rate
STRESS_RATE=120
STRESS_DURATION=3m
STRESS_TIME_UNIT=1m
STRESS_PRE_ALLOCATED_VUS=15
STRESS_MAX_VUS=60
```

Crear el script en `.warp/docker/config/stress/scenarios/product-detail.js` y verificarlo antes de ejecutar:

```bash
warp stress validate --profile product-detail-load
warp stress run --profile product-detail-load --dry-run
warp stress run --profile product-detail-load
```

No existe `--script` o `--file`: la selección del escenario pertenece al profile para que la corrida sea reproducible. Warp copia el script, profile y datasets efectivos al directorio de resultados.

### User-Agent y headers

Warp no ofrece `STRESS_USER_AGENT` ni `--user-agent`. Un User-Agent o header específico se define en el escenario k6 personalizado, por ejemplo:

```javascript
http.get(url, { headers: { 'User-Agent': 'MyLoadTest/1.0' } });
```

## Datasets y sitemap

El escenario de catálogo consume una URL por línea desde `STRESS_DATASET_FILE`. Si no se declara, Warp usa el dataset generado desde el sitemap. Una ruta explícita se evalúa en el host y debe existir antes de ejecutar:

```dotenv
STRESS_DATASET_FILE=./fixtures/product-urls.txt
```

Para `catalog-search` se puede definir `STRESS_SEARCH_TERMS_FILE`; si no, se usa la lista CSV `STRESS_SEARCH_TERMS`.

`warp stress sitemap` descarga `STRESS_SITEMAP_URL` o, si está vacío, `<STRESS_BASE_URL>/sitemap.xml`. Usa la caché indicada por `STRESS_SITEMAP_CACHE_DAYS` (7 por defecto); `--refresh` fuerza la descarga. Para `warmup`, Warp prefiere `/media/warmup.csv` si existe, salvo que el profile haya definido `STRESS_DATASET_FILE`.

## Escenarios incluidos

`catalog.js` recorre el dataset en orden aleatorio o secuencial (`STRESS_URL_ORDER`) y controla repeticiones con `STRESS_URL_REVISIT_RATE`. Puede invocar `customer/section/load` mediante `STRESS_CUSTOMER_SECTION_LOAD_MODE=never|always|sampled`, `STRESS_CUSTOMER_SECTION_LOAD_RATIO` y `STRESS_CUSTOMER_SECTION_LOAD_PATH`.

`catalog-search.js` mezcla catálogo y búsqueda con `STRESS_SCENARIOS` (por ejemplo, `catalog=80,search=20`), `STRESS_SEARCH_PATH` y los términos configurados.

Ambos requieren `STRESS_BASE_URL`, aplican thresholds para `http_req_failed` y p95 de `http_req_duration`, y registran HTTP 404 en `http_404s`.

## Resultados

Cada corrida deja artefactos en `var/warp-stress/runs/<año>/<mes>/<profile>-<fecha>/`: `stdout.txt`, `summary.json`, `metadata.json`, `runtime.env`, y las copias de script, profile y datasets efectivos cuando corresponden.

Usar `warp stress report latest` para leer el último resultado.
