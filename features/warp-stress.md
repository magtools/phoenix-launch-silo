# Warp Stress

Fecha: 2026-05-03
Estado: RFC sin implementacion

## Objetivo

Definir una capability futura `warp stress` para ejecutar pruebas de performance con `k6` desde un contenedor separado del stack principal de Warp.

El objetivo no es solo "tirar requests", sino operar un flujo ordenado de:

1. `warmup` de caches y rutas criticas;
2. `baseline` para medir comportamiento normal;
3. `load` para validar trafico esperado;
4. `stress` para encontrar limites y degradacion;
5. `spike` opcional para observar recuperacion ante picos.

El caso de uso principal es ejecutar estas corridas desde un server de testing o UAT contra produccion, sin contaminar `warp start/stop` ni meter tooling de carga dentro del stack de aplicacion.

## Resumen ejecutivo

La decision propuesta es:

1. crear un comando separado `warp stress`;
2. usar la imagen oficial `grafana/k6`;
3. correrlo en un runtime Compose independiente del `docker-compose-warp.yml` principal;
4. mantener profiles versionados y overrides locales no trackeados;
5. modelar trafico principalmente con escenarios de `k6`, no con un DSL nuevo de Warp;
6. usar `arrival-rate` como modelo primario para capacidad y trafico esperado;
7. reservar VUs explicitos como modo avanzado, no como contrato principal;
8. separar `warmup`, `baseline`, `load`, `stress` y `spike` como tipos de corrida visibles en CLI y en profiles;
9. persistir resultados y metadata bajo `var/warp-stress`;
10. dejar afuera del MVP los dashboards externos y el checkout transaccional completo.

## Por que `k6`

`k6` encaja con este objetivo mejor que un wrapper casero porque:

1. soporta escenarios, stages y executors nativos para open model y closed model;
2. su imagen oficial en Docker simplifica mucho la operacion desde Warp;
3. permite scriptar HTTP realista con cookies, tokens, `form_key` y datasets externos;
4. entrega resumen util en consola y archivos de salida nativos;
5. es hoy una herramienta ampliamente adoptada para performance testing HTTP moderno.

Para este RFC, la fuente de verdad tecnica debe ser la documentacion oficial de k6 y no ejemplos aislados de terceros.

## Principios de producto

`warp stress` deberia nacer con estos principios:

1. opt-in explicito;
2. runtime aislado;
3. configuracion auditable;
4. resultados persistentes;
5. defaults seguros;
6. semantica clara entre volumen, tasa y concurrencia;
7. foco en capacity planning real, no solo en generar trafico.

## Objetivo operativo real

La pregunta que este feature debe ayudar a responder no es solamente:

1. "cuantas requests puedo mandar"

Sino tambien:

1. "cuanto trafico esperado soporta el sitio con margen aceptable";
2. "a partir de que tasa aparece degradacion de `p95`, errores o backlog";
3. "que warmup necesito antes de medir";
4. "que capacidad extra necesito para el siguiente escalon de trafico";
5. "si escalo horizontal o verticalmente, cuanto cambia el punto de quiebre".

Por lo tanto, la RFC debe tratar a `warp stress` como una capability de observacion y decision operativa, no como un simple generador de requests.

## Desambiguacion clave: requests, iteraciones, VUs y usuarios

Este punto hay que corregirlo con precision para evitar falsas conclusiones.

En `k6`:

1. `VUs` representa actores concurrentes del generador de carga;
2. `iterations` representa ejecuciones de un flujo del script;
3. una iteracion puede hacer una o varias requests HTTP;
4. `arrival-rate` controla el inicio de iteraciones por unidad de tiempo;
5. `constant-vus` o `ramping-vus` controlan concurrencia, no tasa objetivo.

Conclusion operativa:

1. `500 usuarios` no debe reinterpretarse automaticamente como `500 requests`;
2. `500 requests en 1m` tampoco es exactamente igual a `500 iteraciones en 1m` si una iteracion hace varias requests;
3. para un contrato robusto, Warp debe hablar principalmente en terminos de `scenarios` y `iterations` de un flujo definido;
4. si se expone una vista simplificada de "requests por ventana", debe ser solo para perfiles donde 1 iteracion equivale de forma controlada a 1 request principal.

## Decision de modelado

La semantica principal de `warp stress` deberia ser:

1. profile;
2. tipo de corrida;
3. stages o tasa objetivo;
4. thresholds de aceptacion;
5. dataset/fixtures requeridos.

La semantica secundaria y opcional puede incluir:

1. `--rate`;
2. `--duration`;
3. `--vus`;
4. `--max-vus`;
5. `--stage`.

No se recomienda que el contrato principal del operador sea "requests por ventana" para todos los casos, porque:

1. sirve para sitemap o GET simples;
2. se vuelve ambiguo en search, login, cart o checkout;
3. complica la interpretacion del resultado cuando una iteracion deja de equivaler a una request.

## Open model vs closed model

Para capacity planning hacia produccion, la recomendacion de este RFC es:

1. usar `constant-arrival-rate` o `ramping-arrival-rate` como modelo primario;
2. usar `constant-vus` o `ramping-vus` solo cuando se quiera estudiar concurrencia cerrada o comportamiento de sesion;
3. documentar explicitamente que el modelo open es el default porque se parece mas a trafico externo real.

Justificacion:

1. con `arrival-rate`, las iteraciones empiezan independientemente del tiempo de respuesta del sistema;
2. eso permite observar mejor si el sistema deja de sostener una tasa objetivo;
3. cuando el sitio se degrada, k6 necesita suficientes VUs para intentar mantener esa tasa;
4. por eso `preAllocatedVUs` y `maxVUs` pasan a ser parametros de soporte del generador, no el objetivo del test.

## Tipos de corrida soportados

El RFC deberia definir tipos de prueba con semantica operativa clara.

### 1. `warmup`

Objetivo:

1. precalentar caches, FPC, bloques, query paths y paginas de mayor trafico;
2. reducir ruido del "primer hit" antes de medir.

Caracteristicas:

1. recorrido secuencial o pseudoaleatorio controlado;
2. sin thresholds de capacidad;
3. con output persistente igual que cualquier corrida;
4. preferentemente sobre subset conocido de URLs calientes.

### 2. `baseline`

Objetivo:

1. medir un nivel estable y bajo o medio de carga;
2. obtener referencia comparativa antes de escalar.

Caracteristicas:

1. tasa fija;
2. duracion breve a media;
3. thresholds moderados;
4. se ejecuta idealmente luego de warmup.

### 3. `load`

Objetivo:

1. validar el trafico esperado del negocio;
2. confirmar si la plataforma soporta el target normal con margen.

Caracteristicas:

1. arrival rate constante o por stages moderados;
2. thresholds de SLO visibles;
3. foco en `p95`, errores y estabilidad.

### 4. `stress`

Objetivo:

1. llevar el sistema mas alla del trafico esperado;
2. identificar punto de degradacion y punto de quiebre.

Caracteristicas:

1. `ramping-arrival-rate`;
2. varias etapas ascendentes;
3. posible etapa de sostenimiento en el escalon alto;
4. bajada controlada para observar recuperacion.

### 5. `spike`

Objetivo:

1. observar comportamiento ante suba brusca;
2. medir recuperacion cuando el pico termina.

Caracteristicas:

1. subida agresiva;
2. duracion corta;
3. foco en errores, colas y recuperacion.

### 6. `soak`

Fuera de alcance inicial, pero conviene dejarlo nombrado para futuro:

1. carga sostenida por tiempo largo;
2. util para memory leaks, colas, degradacion acumulativa y efectos de cache.

## Contrato CLI propuesto

Comandos del MVP:

1. `warp stress start`
2. `warp stress stop`
3. `warp stress status`
4. `warp stress logs`
5. `warp stress sitemap`
6. `warp stress warmup`
7. `warp stress run`

Comandos posteriores:

1. `warp stress report`
2. `warp stress profiles`
3. `warp stress validate`

Se recomienda usar `run` en lugar de `test` porque:

1. evita ambiguedad con tests de aplicacion;
2. permite expresar mejor el tipo de corrida;
3. queda mas natural para `baseline`, `load` o `stress`.

Ejemplos:

```bash
warp stress start
warp stress sitemap
warp stress warmup --profile catalog-warm
warp stress run --profile catalog-baseline
warp stress run --profile catalog-load
warp stress run --profile catalog-stress
warp stress run --profile catalog-stress --stage 100:2m,250:3m,500:5m,0:2m
warp stress run --profile catalog-load --rate 300 --duration 5m
warp stress status
warp stress logs
warp stress stop
```

Flags utiles:

1. `--profile <name>`
2. `--rate <n>`
3. `--duration <dur>`
4. `--stage <csv>`
5. `--yes`
6. `--dry-run`
7. `--vus <n>`
8. `--max-vus <n>`
9. `-f` para follow de logs

## Relacion con `warp start` y `warp stop`

La asimetria propuesta sigue siendo razonable y conviene conservarla.

1. `warp start` no debe iniciar `warp stress`;
2. `warp stress start` debe ser siempre explicito;
3. `warp stop` puede hacer best-effort stop del runtime de stress administrado por Warp;
4. `warp stop --hard` tambien puede limpiarlo;
5. Warp solo debe tocar el runtime que el propio comando materializo;
6. este contrato debe quedar visible en la ayuda y en la documentacion funcional.

Motivo:

1. generar carga hacia produccion nunca debe ocurrir por accidente;
2. detener el runtime auxiliar durante cleanup es razonable;
3. preserva la separacion entre stack de aplicacion y tooling de performance.

## Runtime y aislacion

La recomendacion es usar Compose independiente y versionado por Warp.

Decision propuesta:

1. materializar `docker-compose-stress.yml` si no existe;
2. mantenerlo separado de `docker-compose-warp.yml`;
3. alojar sus templates en `.warp/setup`;
4. no trackear el archivo runtime generado;
5. montar un workspace de stress dedicado;
6. guardar resultados bajo `var/warp-stress`.

Servicios iniciales:

1. `k6`

Servicios opcionales futuros:

1. `xk6` personalizado;
2. sidecar de proxy o captura si alguna vez hiciera falta;
3. exportadores o outputs adicionales.

No se recomienda arrancar con `docker run` largo y mutable, porque:

1. empeora la ergonomia;
2. dificulta mounts y overrides;
3. rompe el patron de Warp de materializar runtime claro y auditable.

## Modelo de configuracion

Se mantienen tres capas, con un ajuste importante.

1. `.stresscfg` para configuracion local no trackeada;
2. `.warp/docker/config/stress` para scripts y profiles versionados;
3. `var/warp-stress` para artefactos runtime.

### 1. `.stresscfg`

Debe ser estilo `KEY=VALUE`, alineado con `.deploy`.

Uso recomendado:

1. `STRESS_BASE_URL`
2. `STRESS_ENV`
3. `STRESS_PROFILE`
4. `STRESS_SITEMAP_URL`
5. `STRESS_FIXTURES_FILE`
6. `STRESS_ACCOUNTS_FILE`
7. `STRESS_ALLOWED_HOSTS`
8. cualquier secreto o referencia a secretos

Claves interpretativas recomendadas:

1. `STRESS_URL_REVISIT_RATE=1|3|4` para repetir cada URL de sitemap varias veces antes de avanzar y aproximar el sesgo cacheado real.
2. `STRESS_CUSTOMER_SECTION_LOAD=1` para agregar `GET /customer/section/load` a cada page view de catalogo basada en sitemap.
3. `STRESS_CUSTOMER_SECTION_LOAD_PATH=/customer/section/load` para override del endpoint complementario.
4. `STRESS_GA4_SESSION_SECONDS` para duracion media de sesion.
5. `STRESS_GA4_PAGEVIEWS_PER_SESSION` para page views medias por sesion.

`STRESS_CUSTOMER_SECTION_LOAD*` no deberia vivir como default global en `.stresscfg`, sino activarse por profile cuando la corrida quiera simular navegacion Magento mas real. `warmup` deberia mantenerlo apagado para no mezclar precalentamiento con trafico interpretativo.

Modelo recomendado:

1. `STRESS_URL_REVISIT_RATE=1` en warmup.
2. `STRESS_URL_REVISIT_RATE=3` para aproximar un mix 66/33.
3. `STRESS_URL_REVISIT_RATE=4` para aproximar un mix 80/20.
4. `STRESS_CUSTOMER_SECTION_LOAD_MODE=never|always|sampled`.
5. `STRESS_CUSTOMER_SECTION_LOAD_RATIO=0.15` cuando el modo sea `sampled`.

Esto permite diferenciar entre:

1. `warmup` sin `section/load`;
2. profiles sinteticos que fuerzan `section/load` siempre;
3. profiles mas realistas para comparar contra APM, donde solo una fraccion de page views dispara ese endpoint.

Con estas claves, `warp stress report` puede traducir `iterations/s` a `pageviews/min`, `usuarios GA4 por minuto` y una concurrencia estimada, sin depender de un factor fijo externo de requests por page view.

Reglas:

1. no debe trackearse;
2. debe quedar en `.gitignore`;
3. si falta un dato obligatorio, el comando debe fallar explicitamente;
4. si el target parece productivo y no hay marca de confirmacion local, el comando debe pedir confirmacion explicita.

Clave de seguridad recomendada:

1. `STRESS_TARGET_CLASS=prod|uat|test`

Esto permite endurecer mensajes y confirmaciones cuando el destino es productivo.

### 2. `.warp/docker/config/stress`

Esta carpeta debe contener material versionado y legible.

Contenido recomendado:

1. scripts JS de `k6`;
2. profiles bootstrap en formato `KEY=VALUE`;
3. fixtures no sensibles;
4. helpers compartidos;
5. thresholds por tipo de corrida;
6. subsets de warmup;
7. listas base de endpoints si aplica.

La decision mas alineada con la comunidad es:

1. no inventar un DSL completo de Warp en el MVP;
2. usar scripts `k6` reales mas profiles de datos declarativos;
3. dejar que Warp resuelva variables, paths, datasets y defaults.

Decision de bootstrap:

1. la primera implementacion puede usar profiles `KEY=VALUE` porque Warp ya opera bien con ese formato;
2. eso evita depender de `jq` o de parsers extra en Bash;
3. si mas adelante hace falta, Warp puede migrar esos profiles a JSON o YAML sin romper el contrato alto nivel del comando.

Eso da dos ventajas:

1. el equipo puede aprender `k6` de forma nativa y no un lenguaje intermedio;
2. el proyecto conserva portabilidad fuera de Warp si alguna vez la necesita.

### 3. `var/warp-stress`

Debe alojar:

1. sitemaps descargados;
2. listas procesadas de URLs;
3. datasets resueltos para una corrida;
4. reportes y metadata;
5. logs del runtime;
6. archivos renderizados efectivos para reproducibilidad.

## Profiles

El profile debe ser la unidad principal de operacion.

Un profile deberia declarar como minimo:

1. nombre;
2. tipo de corrida;
3. script `k6` a ejecutar;
4. target funcional;
5. stages o tasa;
6. thresholds;
7. datasets requeridos;
8. tags;
9. precondiciones.

Ejemplo conceptual:

```json
{
  "name": "catalog-stress",
  "type": "stress",
  "script": "scenarios/catalog.js",
  "executor": "ramping-arrival-rate",
  "startRate": 50,
  "timeUnit": "1m",
  "preAllocatedVUs": 20,
  "maxVUs": 200,
  "stages": [
    { "target": 100, "duration": "2m" },
    { "target": 250, "duration": "3m" },
    { "target": 500, "duration": "5m" },
    { "target": 0, "duration": "2m" }
  ],
  "thresholds": {
    "http_req_failed": ["rate<0.02"],
    "http_req_duration{scenario:catalog}": ["p(95)<1200"]
  }
}
```

Esta aproximacion es mejor que esconder todo atras de `-r/-t` porque:

1. expresa el objetivo del test;
2. deja trazabilidad;
3. permite versionar capacidad objetivo por escenario;
4. facilita repetir corridas comparables.

## Mezcla funcional

La idea del draft original es valida, pero conviene implementarla distinto.

Recomendacion:

1. no modelar la mezcla principal con un `Math.random()` unico dentro de un solo flujo;
2. usar escenarios separados por flujo siempre que la trazabilidad lo justifique;
3. etiquetar cada escenario con su nombre funcional;
4. asignar cuota o tasa por escenario;
5. reservar mezclas aleatorias simples solo para un MVP muy acotado.

Motivo:

1. mejora la lectura de resultados;
2. permite thresholds por flujo;
3. evita que un flujo raro quede oculto por el volumen del sitemap;
4. alinea mejor con buenas practicas de k6 sobre `scenarios`.

Ejemplo para la mezcla inicial:

1. `sitemap` o `catalog` como escenario principal;
2. `search` como escenario separado;
3. `login` separado y con fixtures reales;
4. `add-to-cart` separado;
5. `cart` separado;
6. `checkout-landing` separado.

## Warmup

El comando `warp stress warmup` deberia existir como primer ciudadano.

Contrato propuesto:

1. usa una lista de URLs derivada del sitemap o un subset explicitamente declarado;
2. recorre en orden deterministico o pseudoaleatorio estable;
3. puede aceptar varias pasadas;
4. no busca saturar, sino preparar el terreno para medir;
5. deja artefactos y resumen como cualquier otra corrida.

Flags utiles:

1. `--profile`
2. `--passes <n>`
3. `--subset <name>`
4. `--rate <n>`

## Flujos stateful y alcance inicial

No todos los flujos tienen el mismo costo ni la misma seguridad operacional.

### In scope del primer corte

1. warmup por sitemap o listas de URLs;
2. baseline/load de navegacion catalogo;
3. search si el endpoint y los terminos estan claros;
4. checkout landing, no checkout completo;
5. reporting basico y thresholds.

### Condicionales del primer corte

1. login real, solo si existen fixtures validos;
2. add-to-cart real, solo si el proyecto define bien `form_key`, SKUs y validaciones;
3. cart view, si el flujo anonimo o autenticado esta claro.

### Fuera de alcance inicial

1. compra end-to-end productiva;
2. integraciones de pago reales;
3. flujos distribuidos multi-region;
4. cargas multi-node coordinadas.

## Sitemaps y datasets

`warp stress sitemap` deberia preparar el dataset principal de navegacion.

Contrato:

1. reutilizar cache hasta `7` dias salvo override;
2. refrescar si no existe o expiro;
3. persistir XML original y lista plana derivada;
4. dejar metadata de fecha y fuente;
5. fallar explicitamente si no puede descargar o procesar.

Salidas esperadas:

1. `var/warp-stress/sitemaps/*.xml`
2. `var/warp-stress/datasets/sitemap-urls.json`
3. `var/warp-stress/datasets/warmup-urls.json` si aplica

Esto sirve para dos cosas:

1. no recalcular el dataset en cada corrida;
2. tener input reproducible para comparar runs.

## Thresholds y criterio de aceptacion

Si el objetivo es capacity planning, la RFC debe incorporar thresholds desde el inicio.

Minimo recomendado:

1. `http_req_failed`
2. `http_req_duration` por escenario
3. `checks`
4. algun indicador de tiempo de iteracion o flujo si aplica

Ejemplo de criterio operativo:

1. `baseline` pasa si `p95` y tasa de error quedan dentro de SLO;
2. `load` pasa si sostiene el trafico esperado durante toda la ventana sin degradacion material;
3. `stress` no necesariamente "pasa" o "falla": se usa para identificar el escalon donde rompe el SLO;
4. `spike` se interpreta por errores y tiempo de recuperacion.

Esto es mas util que medir solo `avg` o volumen total.

## VU allocation

Warp puede ofrecer una heuristica inicial para `preAllocatedVUs` y `maxVUs`, pero no debe presentar esa formula como verdad fuerte.

Regla propuesta:

1. si el profile define `preAllocatedVUs` y `maxVUs`, Warp los respeta;
2. si no los define, Warp calcula un default conservador y lo deja visible en `--dry-run`;
3. la documentacion debe aclarar que estos valores pueden necesitar calibracion real segun latencia del flujo.

Importante:

1. una formula fija tipo `req_per_sec * 2` puede ser util como bootstrap;
2. no debe venderse como garantia de que la tasa se sostendra;
3. el verdadero ajuste sale de corridas de prueba y observacion del generador.

## Observabilidad y artefactos

Toda corrida debe dejar evidencia reproducible.

Ubicacion:

1. `var/warp-stress/<year>/<month>/<profile>-<day>-<hourminute>/`

Artefactos minimos:

1. `stdout.txt`
2. `summary.json`
3. `metadata.json`
4. script efectivo renderizado
5. datasets resueltos usados por la corrida

La metadata deberia incluir:

1. fecha y hora;
2. profile;
3. tipo de corrida;
4. target efectivo;
5. base URL;
6. executor;
7. stages;
8. thresholds;
9. datasets utilizados;
10. commit o version de Warp si es facil de obtener.

## Reporte en pantalla

El resumen final visible por consola deberia mostrar:

1. profile;
2. tipo de corrida;
3. target;
4. executor;
5. requests o iteraciones ejecutadas;
6. tasa de error;
7. `avg`, `p90`, `p95`, `max`;
8. thresholds incumplidos;
9. ruta del reporte persistido.

Para `stress`, conviene agregar:

1. primer stage con degradacion material;
2. primer stage con error rate fuera de objetivo;
3. stage maximo sostenible segun thresholds declarados.

## Seguridad operativa

Como este feature puede apuntar a produccion, la RFC debe endurecer mas este aspecto.

Reglas recomendadas:

1. si `STRESS_TARGET_CLASS=prod`, pedir confirmacion explicita salvo `--no-interaction` con flag de aceptacion dedicado;
2. mostrar base URL y tipo de corrida antes de arrancar;
3. impedir por default un target no permitido por `STRESS_ALLOWED_HOSTS`;
4. no ejecutar warmup o stress accidentalmente desde `warp start`;
5. fallar si faltan fixtures requeridos para flujos stateful en vez de simularlos.

## Alcance inicial propuesto

### In scope

1. runtime `k6` separado con Compose propio;
2. `start`, `stop`, `status`, `logs`, `sitemap`, `warmup`, `run`;
3. profiles versionados;
4. `.stresscfg` como override local;
5. datasets por sitemap;
6. profiles `catalog-warm`, `catalog-baseline`, `catalog-load`, `catalog-stress`, `catalog-search-load`, `catalog-search-stress`;
7. artefactos persistidos;
8. thresholds basicos;
9. ayuda clara y consistente con Warp.

### Fuera de alcance inicial

1. dashboards externos;
2. Grafana Cloud o Prometheus;
3. checkout completo;
4. runner distribuido;
5. generacion automatica de reportes historicos comparativos;
6. DSL propio de Warp para reemplazar scripts `k6`.

## Plan propuesto

### Fase 1. Contrato y runtime

1. definir contrato CLI de `warp stress`;
2. materializar `docker-compose-stress.yml` desde `.warp/setup`;
3. definir labels, nombre de servicio y lifecycle con `warp stop`;
4. asegurar `.gitignore` de artefactos y runtime.

### Fase 2. Configuracion y profiles

1. definir estructura de `.stresscfg`;
2. definir layout de `.warp/docker/config/stress`;
3. crear primer script `k6` de catalogo;
4. crear profiles `warmup`, `baseline`, `load` y `stress`.

### Fase 3. Datasets y warmup

1. implementar `warp stress sitemap`;
2. generar dataset reutilizable;
3. implementar warmup deterministico;
4. persistir metadata de inputs.

### Fase 4. Reporting y thresholds

1. guardar `summary.json` y metadata;
2. mostrar resumen humano;
3. marcar thresholds incumplidos;
4. dejar el run reproducible.

### Fase 5. Flujos stateful

1. agregar search con dataset;
2. agregar login solo con fixtures reales;
3. agregar cart y checkout landing;
4. postergar checkout transaccional real.

## Recomendacion final

`warp stress` deberia diseñarse como una capability de performance separada, orientada a capacity planning y basada en `k6` nativo, no como un simple wrapper de requests.

La direccion recomendada para esta RFC es:

1. runtime independiente y opt-in;
2. profiles versionados;
3. `arrival-rate` como default para trafico esperado y stress;
4. `warmup`, `baseline`, `load` y `stress` como tipos de corrida de primer nivel;
5. thresholds y artefactos persistentes desde el MVP;
6. foco inicial en catalogo/search y checkout landing, no en compra completa.

Con este enfoque, Warp queda alineado con buenas practicas de k6, preserva su arquitectura, y te da una base util para responder la pregunta que importa: que capacidad real tiene la plataforma y donde conviene escalar antes de llegar al trafico esperado.

## Referencias

Referencias oficiales de k6 que respaldan el enfoque de esta RFC:

1. `Scenarios`: https://grafana.com/docs/k6/latest/using-k6/scenarios/
2. `Executors`: https://grafana.com/docs/k6/latest/using-k6/scenarios/executors/
3. `Constant arrival rate`: https://grafana.com/docs/k6/latest/using-k6/scenarios/executors/constant-arrival-rate/
4. `Ramping arrival rate`: https://grafana.com/docs/k6/latest/using-k6/scenarios/executors/ramping-arrival-rate/
5. `Arrival-rate VU allocation`: https://grafana.com/docs/k6/latest/using-k6/scenarios/concepts/arrival-rate-vu-allocation/
