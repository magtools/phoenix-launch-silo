# Warp Infra: estrategia multiarch x86/arm

Fecha: 2026-04-16

## 1. Objetivo

Analizar la posibilidad de hacer que el stack Docker Compose generado por Warp pueda operar de forma confiable en hosts `linux/amd64` y `linux/arm64`, con foco en una migracion de servidores chicos desde instancias EC2 `m5`/`c5` hacia `c7i` o `c7g`.

Este documento es una fase de analisis para decidir si el costo/beneficio justifica avanzar. No asume que Warp deba implementar soporte Arm, ni que convenga crear imagenes propias multiarch. Una conclusion valida del analisis puede ser:

1. no implementar soporte `arm64` por ahora;
2. usar `c7i` como modernizacion conservadora;
3. soportar `c7g` solo para un perfil reducido;
4. soportar `c7g` con imagenes oficiales donde alcance;
5. crear imagenes propias multiarch solo para los gaps que tengan ROI claro.

Contexto operativo actual:

1. sitios chicos con todos los servicios en una instancia suelen correr en `m5`;
2. sitios con MariaDB/MySQL externo suelen correr en `c5`;
3. la nueva decision es si conviene saltar a `c7i` x86 o invertir en soporte real para `c7g` Arm/Graviton.

La pregunta no es solo si Docker puede correr en Arm. La pregunta real para Warp es si el conjunto de imagenes, templates, defaults, comandos auxiliares y compatibilidad legacy puede funcionar sin sorpresas en ambas arquitecturas.

## 2. Resumen ejecutivo

La migracion a `c7i` es de baja complejidad para Warp porque conserva `x86_64`. Es el camino conservador: mejora generacional, menor riesgo de imagenes incompatibles y casi nulo cambio en `warp init/start/stop`.

La migracion a `c7g` es tecnicamente viable, pero requiere tratar multiarch como hipotesis de ROI y no como objetivo asumido. El upside economico/performance puede justificarlo si el ahorro recurrente supera el costo inicial y el costo de mantenimiento de imagenes. El riesgo sube cuando el stack usa imagenes custom historicas, PHP viejo, extensiones PECL no validadas en Arm, Selenium/browser, RabbitMQ/Postgres propios o motores DB legacy.

Hipotesis inicial:

1. `c7i` probablemente gane en tiempo de adopcion y riesgo bajo;
2. `c7g` probablemente gane en costo/performance si el stack corre nativo Arm;
3. usar emulacion `amd64` en `c7g` reduce o destruye el beneficio esperado;
4. el analisis debe separar servicios cubiertos por imagenes oficiales de servicios que obligan a mantener imagenes propias;
5. si solo hay pocos servidores o el ahorro absoluto mensual es bajo, el ROI puede no justificar crear y mantener imagenes Arm.

Estado de PoC al 2026-04-16:

1. se crearon Dockerfiles PoC para `appdata` y PHP 8.4;
2. ambos builds `linux/amd64` funcionaron localmente;
3. el build `linux/arm64` quedo bloqueado por falta de soporte Arm en el builder Docker local (`exec format error`);
4. antes de estimar esfuerzo real de `c7g`, falta validar en builder Arm/QEMU que PHP 8.4 compile todas las extensiones en `arm64`;
5. el reemplazo de mail local propuesto es Mailpit + `msmtp`, evitando `mhsendmail_linux_amd64`.

## 3. Datos externos relevantes

AWS posiciona Graviton como una familia con hasta 40% mejor relacion precio/performance para muchas cargas frente a x86 comparables. En C7 especificamente, `c7g` usa Graviton3 y AWS declara hasta 25% mejor performance frente a `c6g`; `c7i` usa Intel Xeon Sapphire Rapids y AWS declara hasta 15% mejor precio/performance frente a `c6i`.

Fuentes:

1. AWS Graviton getting started: https://aws.amazon.com/ec2/graviton/getting-started/
2. AWS C7g: https://aws.amazon.com/ec2/instance-types/c7g/
3. AWS C7i: https://aws.amazon.com/ec2/instance-types/c7i/
4. Docker multi-platform builds: https://docs.docker.com/build/building/multi-platform/
5. AWS Graviton containers guide: https://aws.github.io/graviton/containers.html

Nota de lectura:

Los porcentajes de AWS son referencias generales, no garantias para Magento/Oro/PHP. En este analisis se toma como supuesto operativo que `c7g` puede ser aproximadamente 15% mas barato y hasta 40% mas performante, pero el ROI debe calcularse con precios reales por region, Savings Plans/Reserved Instances, tipo de EBS y carga medida. En Warp hay que medir por sitio porque las cargas reales combinan CPU PHP, latencia de Redis, I/O EBS, OpenSearch, cron, cola, compresion, TLS y picos de admin.

## 4. Estado actual observado en Warp

Warp ya tiene una base parcial para este camino:

1. la matriz declarativa de servicios vive en `.warp/variables.sh`;
2. DB ya permite `mariadb` como default y `mysql` como opcion explicita;
3. existe `.warp/setup/mysql/tpl/database_arm.yml`;
4. Redis usa imagen oficial configurable con `${CACHE_IMAGE_REPO:-redis}`;
5. Search usa `${SEARCH_IMAGE:-opensearchproject/opensearch:${ES_VERSION}}`.

Pero el soporte no es multiarch completo:

1. PHP usa `summasolutions/php:${PHP_VERSION}`;
2. RabbitMQ usa `summasolutions/rabbitmq:${RABBIT_VERSION}`;
3. Postgres usa `summasolutions/postgres:${POSTGRES_VERSION}`;
4. sandbox usa varias imagenes `summasolutions/*`;
5. Selenium mezcla imagenes legacy y oficiales;
6. `database_arm.yml` fuerza `platform: linux/x86_64`, lo que no da soporte Arm nativo sino ejecucion x86 emulada o forzada;
7. el flujo de DB solo cae en `database_arm.yml` para `mysql` sobre `arm64`; `mariadb` usa `database.yml` sin `platform`, lo cual es mejor si la imagen oficial soporta Arm.

Implicacion:

Warp no parte de cero, pero hoy no puede prometer que un `warp init && warp start` sea portable entre `amd64` y `arm64` para todos los perfiles.

## 4.1 Caso de referencia: `example`

Se reviso `example` como muestra de un proyecto Magento real generado con Warp. La lectura fue estructural, no funcional: compose, `.env`, `composer.json` y `app/etc/env.php`. No se toman credenciales ni valores sensibles para este analisis.

Stack observado:

1. Magento Open Source `2.4.8-p4`;
2. PHP `8.4-fpm`;
3. MariaDB `11.4` local;
4. OpenSearch `2.12.0`;
5. Redis `7.2` separado en cache, session y FPC;
6. Nginx oficial;
7. servicio local de mail para desarrollo;
8. Hyva y ElasticSuite;
9. varios modulos comerciales y patches de compatibilidad PHP 8.4.

Imagenes efectivas del compose:

| Servicio | Imagen | Lectura multiarch preliminar |
| --- | --- | --- |
| `web` | `nginx:latest` | Probable soporte Arm por imagen oficial. Conviene fijar tag para reproducibilidad. |
| `php` | `summasolutions/php:8.4-fpm` | Principal bloqueo. Hay que verificar manifest o reemplazar/crear imagen propia. |
| `appdata` | `summasolutions/appdata:latest` | Bloqueo secundario. Probablemente reemplazable por imagen simple multiarch. |
| `mysql` | `mariadb:11.4` | Buen candidato Arm por imagen oficial moderna, sujeto a prueba de datos y tuning. |
| `elasticsearch` | `opensearchproject/opensearch:2.12.0` | Candidato razonable, pero hay que validar tag, plugin `analysis-phonetic`, heap y volumen. |
| `redis-*` | `redis:7.2` | Buen candidato Arm por imagen oficial moderna. |
| `mail` | servicio legacy de captura de mail en el caso observado | Reemplazable. Para PoC multiarch se prefiere evaluar Mailpit por imagen multiarch y autenticacion UI/API. |

Lectura del caso:

1. `example` no representa el peor caso legacy; usa versiones modernas.
2. La mayor parte del stack ya usa imagenes oficiales modernas.
3. El cuello de botella de decision esta en PHP/appdata y no tanto en DB/cache/search.
4. Al tener DB local y OpenSearch local, el riesgo operativo es mayor que en un perfil con DB externa.
5. Si un proyecto de este tipo no justifica ROI, probablemente los proyectos mas chicos tampoco justifiquen una inversion amplia.
6. Si este proyecto justifica ROI, conviene probar primero una variante con DB externa o con restore controlado, no moviendo volumenes crudos.

Conclusion preliminar para `example`:

Tecnologicamente parece un candidato medio/bueno para `c7g` por versiones modernas, pero no es un candidato "gratis". Para que el caso sea defendible, el analisis debe demostrar que:

1. `summasolutions/php:8.4-fpm` puede ser reemplazada por una imagen oficial/custom Arm sin perder extensiones;
2. `summasolutions/appdata` puede eliminarse o reconstruirse multiarch con bajo costo;
3. MariaDB 11.4 y OpenSearch 2.12 corren nativos y estables;
4. los patches y modulos de Composer no introducen binarios x86-only;
5. el ahorro mensual compensa build, pruebas, mantenimiento y riesgo.

## 4.2 Base local en `images/`

La carpeta `images/` contiene una base util para analizar imagenes propias, pero no conviene interpretarla como soporte Arm listo.

Inventario relevante:

1. `images/appdata`: imagen simple basada en Debian Jessie con `rsync` y entrypoint propio.
2. `images/php`: wrappers actuales sobre `summasolutions/php:<version>`.
3. `images/php/common`: entrypoint y helper para instalar extensiones extra por `PHP_EXTRA_LIBS`.
4. `images/php/old`: Dockerfiles historicos construidos desde `php:<version>-fpm`.
5. `images/elasticsearch`, `images/postgres`, `images/rabbitmq`, `images/selenium`, `images/varnish`: imagenes legacy o auxiliares.

Lectura:

1. `appdata` es un buen candidato para imagen propia multiarch porque su funcion es chica y estable.
2. PHP es el candidato principal para imagen propia porque concentra el runtime Magento y las extensiones.
3. DB/cache/search/web deberian quedarse con imagenes oficiales mientras sea posible.
4. No conviene migrar todo `images/` a multiarch: Elasticsearch legacy, Magento samples, Varnish viejo y sandbox aumentan costo sin aportar al caso inicial.

### 4.2.1 `appdata`

Estado actual:

1. `FROM debian:jessie`;
2. instala `rsync`;
3. expone puerto `873`;
4. genera `/etc/rsyncd.conf` si no existe;
5. monta `/var/www/html` como volumen compartido por otros servicios.

Problemas para multiarch:

1. Debian Jessie esta EOL;
2. la imagen es simple, pero heredada;
3. no hay razon fuerte para mantener una base vieja si se reconstruye.

Hipotesis:

`appdata` puede reconstruirse como imagen propia multiarch con bajo costo usando `debian:bookworm-slim`, `debian:trixie-slim`, `alpine` o incluso una imagen minima con `rsync`. El ROI tecnico es bueno porque reemplaza `summasolutions/appdata:latest` y elimina un bloqueo con poco mantenimiento.

### 4.2.2 PHP

Estado actual:

1. el template de Warp usa `summasolutions/php:${PHP_VERSION}`;
2. los Dockerfiles actuales en `images/php/<version>` solo agregan entrypoint/helper sobre `summasolutions/php`;
3. los Dockerfiles historicos en `images/php/old` muestran como se construian las extensiones desde `php:<version>-fpm`;
4. `PHP_EXTRA_LIBS` instala extensiones en runtime mediante `mlocati/docker-php-extension-installer`.

Base util:

1. lista de paquetes Debian necesarios para extensiones Magento;
2. patron de usuarios/grupos (`www-data`, `warp`, etc.);
3. logs de PHP-FPM;
4. Composer;
5. Node/Yarn/Grunt/Gulp para tooling frontend legacy;
6. cron y supervisor;
7. entrypoint que instala extensiones extra.

Problemas para multiarch:

1. hay referencias explicitas x86 como `lib/x86_64-linux-gnu`;
2. hay binarios `mhsendmail_linux_amd64`, reemplazables por alternativas multiarch o por envio SMTP directo al servicio local de mail;
3. varias imagenes viejas descargan `ioncube_loaders_lin_x86-64`;
4. NodeSource viejo (`setup_11.x`, `setup_12.x`) y Debian stretch/jessie son deuda tecnica;
5. instalar extensiones en runtime con `PHP_EXTRA_LIBS` puede volver el arranque lento y dependiente de red;
6. no hay Dockerfiles locales para PHP `8.2`, `8.3` o `8.4`, aunque Warp ya acepta esas versiones.

Hipotesis:

La carpeta `images/php/old` es una buena base documental para reconstruir una imagen PHP propia, pero no debe copiarse literalmente. El camino razonable seria crear una imagen nueva solo para PHP vigente, empezando por `8.4-fpm` para cubrir el caso `example`, y usar build multiarch desde una base oficial `php:8.4-fpm`.

### 4.2.3 Alcance inicial recomendado para imagenes

Para el analisis de ROI, el alcance mas defendible es:

1. imagen propia `appdata`;
2. imagen propia `php`;
3. oficiales para `nginx`, `mariadb`, `opensearch`, `redis` y mail/testing si aplica.

Esto evita convertir Warp en mantenedor de una distribucion completa de infraestructura. El esfuerzo propio queda concentrado donde realmente hay valor:

1. compatibilidad del runtime PHP con Magento;
2. extensiones y herramientas necesarias;
3. control de tags;
4. soporte `linux/amd64` y `linux/arm64`.

## 5. Lectura por servicio

### 5.1 PHP

Es el componente mas critico.

Riesgos:

1. `summasolutions/php` puede no tener manifest multiarch;
2. extensiones como `ioncube`, `imagick`, `sodium`, `amqp`, `redis`, `xdebug`, `grpc` o `mongodb` pueden tener diferencias de build;
3. versiones viejas de PHP y extensiones legacy suelen ser el punto que rompe Arm;
4. Composer puede exponer dependencias con binarios nativos o checks de plataforma.

Complejidad estimada: alta si se mantienen imagenes propias historicas; media si se migra a una familia nueva de imagenes PHP multiarch y se limita el soporte a PHP vigente.

Hipotesis a evaluar:

1. crear una familia `magtools/php` o reemplazo equivalente multiarch;
2. publicar manifest `linux/amd64,linux/arm64`;
3. validar primero PHP 8.1+ o la version minima real vigente para los sitios actuales;
4. dejar PHP legacy x86-only como modo compatibilidad, no como camino recomendado.

### 5.2 Webserver

`nginx:latest` suele ser multiarch. El riesgo es bajo.

Complejidad estimada: baja.

Riesgos:

1. evitar `latest` a mediano plazo por reproducibilidad;
2. validar modulos o configuraciones custom si aparecen imagenes propias.

### 5.3 DB local

MariaDB oficial es el camino mas prometedor para Arm. MySQL legacy es mas delicado, especialmente si se requieren tags viejos.

Estado actual:

1. default actual de DB: `mariadb:10.11`;
2. `mysql` queda como opcion explicita;
3. en `arm64`, si el motor elegido es `mysql`, Warp usa una plantilla con `platform: linux/x86_64`.

Lectura:

Ese `platform` sirve como escape hatch para compatibilidad, pero no deberia considerarse soporte nativo `c7g`. En produccion, emular DB x86 dentro de un host Arm puede destruir buena parte del beneficio de Graviton y agrega riesgo operacional.

Complejidad estimada:

1. baja para `mariadb` moderno;
2. media/alta para `mysql` viejo;
3. baja si la DB es externa/RDS y Warp solo necesita cliente local.

Hipotesis a evaluar:

1. priorizar `DB_ENGINE=mariadb` para `arm64`;
2. tratar `mysql` sobre Arm como `compatibility/manual`;
3. si `MYSQL_VERSION=rds`, hacer foco en clientes `mysql`/`mariadb` del host o en un contenedor cliente multiarch liviano.

### 5.4 Redis / Valkey

Redis oficial tiene buen encaje multiarch para tags modernos. Valkey tambien es buen candidato cuando pase de preparado a operativo.

Complejidad estimada: baja.

Riesgos:

1. tags muy viejos de Redis pueden no tener variantes Arm;
2. cualquier `redis.conf` custom debe seguir siendo portable;
3. si se usa `docker exec redis-cli`, el binario dentro de la imagen debe existir igual en ambas arquitecturas.

### 5.5 Search: OpenSearch / Elasticsearch

OpenSearch moderno es el camino mas razonable. Elasticsearch legacy es el riesgo.

Complejidad estimada:

1. media para OpenSearch 2.x;
2. alta para Elasticsearch legacy.

Riesgos:

1. plugins instalados en arranque deben existir para Arm;
2. heap y consumo de memoria deben recalibrarse por instancia;
3. `vm.max_map_count` sigue siendo requisito del host;
4. volumenes existentes no deben moverse entre arquitecturas sin backup y prueba de restore;
5. indices grandes pueden mostrar diferencias de latencia por EBS, no solo por CPU.

Hipotesis a evaluar:

1. validar `opensearchproject/opensearch` tag por tag con `docker manifest inspect`;
2. no prometer Elasticsearch viejo en Arm salvo caso puntual probado;
3. para sitios chicos, considerar search externo si el host Arm queda muy ajustado de memoria.

### 5.6 RabbitMQ, Postgres, Selenium y sandbox

Estos servicios son el bloque de compatibilidad secundaria.

Riesgos:

1. imagenes `summasolutions/*` probablemente son x86-only hasta que se pruebe lo contrario;
2. Selenium/browser en Arm tiene historial de diferencias por imagen y version;
3. sandbox usa imagenes de demo viejas y puede no justificar soporte Arm completo.

Complejidad estimada: media/alta si se declaran soportados en `arm64`.

Hipotesis a evaluar:

1. excluir sandbox del primer alcance multiarch;
2. validar RabbitMQ/Postgres solo si hay sitios productivos que los usen con Warp;
3. evitar que un servicio opcional bloquee el soporte Arm del stack PHP+Nginx+Redis+DB externa.

## 6. Comparacion operativa: c7i vs c7g

### 6.1 c7i

Ventajas:

1. continuidad x86;
2. menor riesgo de imagenes rotas;
3. mejor para stacks legacy;
4. compatible con imagenes privadas actuales si ya son amd64;
5. permite migrar rapido desde `c5`.

Costos:

1. menor upside economico que Graviton;
2. no fuerza limpiar deuda de imagenes;
3. si la carga es CPU-bound en PHP, puede dejar ahorro sobre la mesa.

Uso recomendado:

1. sitios productivos donde el downtime de migracion debe ser minimo;
2. proyectos con PHP viejo o extensiones no auditadas;
3. servidores con todos los servicios locales y poca ventana de prueba;
4. migracion inmediata desde `c5`.

### 6.2 c7g

Ventajas:

1. mejor potencial de precio/performance;
2. buena opcion cuando DB es externa;
3. buen encaje con servicios oficiales multiarch modernos;
4. puede bajar costo recurrente si el stack queda nativo Arm.

Costos:

1. requiere auditoria de imagenes;
2. requiere build multiarch de imagenes propias;
3. el soporte a PHP/extensiones legacy puede ser caro;
4. la emulacion x86 debe evitarse en servicios calientes;
5. los incidentes son mas probables al inicio porque cambia arquitectura, no solo generacion.

Uso recomendado:

1. sitios chicos con DB externa;
2. stacks Magento/Oro/PHP en versiones actuales;
3. servicios donde Redis/OpenSearch sean tags modernos;
4. nuevos servidores con smoke test previo y rollback claro.

## 7. Dificultad y complejidad estimada

| Area | Dificultad | Motivo |
| --- | --- | --- |
| `c7i` como target | Baja | Misma arquitectura `amd64`; casi todo es cambio de instancia/AMI. |
| DB externa en `c7g` | Baja/media | Evita el servicio mas sensible; quedan PHP, web, cache y search. |
| MariaDB local moderno en `c7g` | Media | Probable soporte de imagen, pero requiere prueba de datos, tuning y backup/restore. |
| PHP multiarch | Media/alta | Depende de imagen propia, extensiones y versiones. |
| OpenSearch moderno | Media | Imagen probable, pero plugins, heap y volumenes requieren validacion. |
| MySQL/Elasticsearch/PHP legacy | Alta | Alta probabilidad de tags o binarios x86-only. |
| Sandbox legacy | Alta | No parece justificar soporte inicial completo. |

## 7.1 Modelo de ROI

La decision debe calcularse por ahorro anualizado, no por porcentaje teorico.

Variables:

1. `S`: cantidad de servidores candidatos.
2. `C_x86`: costo mensual actual o costo mensual estimado en `c7i`.
3. `C_arm`: costo mensual estimado en `c7g`.
4. `P`: ganancia de performance real utilizable.
5. `D`: factor de downsizing posible por performance, si aplica.
6. `H_init`: horas de analisis, PoC, build de imagenes y pruebas.
7. `H_maint`: horas mensuales de mantenimiento de imagenes y soporte.
8. `R`: costo estimado del riesgo operativo, aunque sea cualitativo.

Formula simple:

```text
ahorro_mensual_base = S * (C_x86 - C_arm)
ahorro_mensual_downsize = ahorro adicional si P permite bajar size sin perder SLA
costo_inicial = H_init * costo_hora
costo_mensual_mantenimiento = H_maint * costo_hora
break_even_meses = costo_inicial / (ahorro_mensual_base + ahorro_mensual_downsize - costo_mensual_mantenimiento)
```

Lectura practica:

1. si `c7g` solo ahorra 15% y no permite bajar size, el ahorro absoluto puede ser bajo en flotas chicas;
2. si el 40% de performance permite bajar de size, el ROI mejora mucho;
3. si hay que crear y mantener varias imagenes propias, el costo fijo puede comerse el ahorro;
4. si solo hay que reemplazar una imagen PHP y el resto son oficiales, el ROI puede ser razonable;
5. si hay muchas tiendas parecidas, el costo inicial se amortiza mejor.

Ejemplo conceptual sin precios reales:

| Escenario | Lectura |
| --- | --- |
| 1 servidor chico, solo 15% menos costo | Probablemente no justifica crear imagenes propias. |
| 5-10 servidores chicos, sin downsizing | Depende mucho del costo/hora y mantenimiento. |
| 10+ servidores o varios medianos | Empieza a justificar PoC formal. |
| Performance permite bajar un size | Puede justificar aun con menos servidores. |
| Hay que mantener PHP legacy multiarch | ROI probablemente malo salvo flota grande. |

Gate recomendado:

No avanzar a implementacion si el break-even estimado supera 6-12 meses o si el soporte obliga a mantener imagenes legacy para pocos sitios.

## 7.1.1 Perfil base de costos: xlarge + gp3 100 GB

Supuesto de comparacion:

1. region: `us-east-1`;
2. sistema operativo: Linux;
3. tenancy: shared;
4. modalidad: On-Demand;
5. horas mensuales: `730`;
6. disco: `gp3` de 100 GB;
7. sin IOPS/throughput extra sobre baseline gp3.

Fuente de precios:

AWS Price List API para `AmazonEC2`, region `us-east-1`, publicacion `2026-04-15T20:36:45Z`.

URL de referencia:

https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/us-east-1/index.json

Referencia gp3:

AWS documenta que gp3 incluye baseline de 3,000 IOPS y 125 MiB/s en el precio de storage; IOPS/throughput extra se cobran aparte.

https://docs.aws.amazon.com/whitepapers/latest/optimizing-mysql-on-ec2-using-amazon-ebs/ebs-volume-types.html

Precios detectados:

| Recurso | vCPU | RAM | USD/h | Compute/mes | gp3 100 GB/mes | Total/mes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `m5.xlarge` | 4 | 16 GiB | 0.1920 | 140.16 | 8.00 | 148.16 |
| `c5.xlarge` | 4 | 8 GiB | 0.1700 | 124.10 | 8.00 | 132.10 |
| `c7i.xlarge` | 4 | 8 GiB | 0.1785 | 130.31 | 8.00 | 138.31 |
| `c7g.xlarge` | 4 | 8 GiB | 0.1450 | 105.85 | 8.00 | 113.85 |

Lectura:

1. `c7g.xlarge` es 18.8% mas barato que `c7i.xlarge` en compute puro.
2. Incluyendo `gp3` 100 GB, `c7g.xlarge` queda 17.7% mas barato que `c7i.xlarge`.
3. Frente a `c5.xlarge`, `c7g.xlarge` ahorra 18.25 USD/mes con 100 GB gp3.
4. Frente a `m5.xlarge`, `c7g.xlarge` ahorra 34.31 USD/mes con 100 GB gp3, pero tambien baja RAM de 16 GiB a 8 GiB si se compara literalmente `m5.xlarge` contra `c7g.xlarge`.
5. `c7i.xlarge` es mas caro que `c5.xlarge` en este perfil On-Demand, aunque puede traer mejora generacional de CPU.

Impacto sobre ROI:

Con este perfil, el ahorro directo por servidor entre `c7i.xlarge` y `c7g.xlarge` es aproximadamente 24.46 USD/mes. Eso significa:

| Servidores | Ahorro mensual aproximado vs `c7i.xlarge` | Ahorro anual aproximado |
| ---: | ---: | ---: |
| 1 | 24.46 | 293.46 |
| 5 | 122.28 | 1,467.30 |
| 10 | 244.55 | 2,934.60 |
| 20 | 489.10 | 5,869.20 |

Esta tabla vuelve importante el costo fijo de construir y mantener imagenes. Si la flota candidata es chica, solo se justifica avanzar si:

1. `c7g` permite bajar un size adicional;
2. la imagen PHP propia sirve para muchos proyectos;
3. el costo de mantenimiento mensual es bajo;
4. el cambio reduce tambien tiempo de respuesta o capacidad necesaria, no solo factura.

## 7.2 Imagenes oficiales vs imagenes propias

Hay tres caminos posibles, de menor a mayor inversion.

### Camino A: solo imagenes oficiales

Objetivo:

Usar imagenes oficiales multiarch para todo lo posible.

Ventajas:

1. menor costo de mantenimiento;
2. mejor probabilidad de recibir updates de seguridad;
3. menos responsabilidad operativa propia;
4. mas facil justificar ROI.

Riesgos:

1. la imagen oficial PHP no trae todas las extensiones que Magento necesita;
2. algunas extensiones requieren compilacion;
3. se pierde compatibilidad con convenciones actuales de `summasolutions/php`;
4. `appdata` debe reemplazarse por una imagen minima o por otro patron.

Lectura:

Es el mejor camino para la fase de analisis. Si no se puede armar un stack Magento funcional con oficiales + configuracion ligera, recien ahi conviene evaluar imagenes propias.

### Camino B: imagen propia solo para PHP

Objetivo:

Mantener DB/cache/search/web oficiales y crear una imagen PHP multiarch controlada por Warp.

Ventajas:

1. reduce el scope de mantenimiento propio;
2. ataca el bloqueo principal;
3. permite estandarizar extensiones;
4. puede amortizarse entre varios proyectos.

Riesgos:

1. hay que mantener builds por version PHP;
2. hay que validar extensiones PECL por arquitectura;
3. hay que definir politica de tags y seguridad;
4. puede duplicar esfuerzo si ya existe otra linea activa en `phoenix-launch-silo`.

Lectura:

Probablemente es el camino con mejor balance si `c7g` pasa el filtro de ROI.

### Camino C: familia completa de imagenes propias

Objetivo:

Crear imagenes propias multiarch para PHP, appdata, RabbitMQ, Postgres, Selenium y cualquier servicio legacy.

Ventajas:

1. control total;
2. compatibilidad mas parecida al stack actual;
3. menos dependencia de cambios externos.

Riesgos:

1. mayor costo inicial;
2. mayor mantenimiento recurrente;
3. mas superficie de seguridad;
4. peor ROI si la flota es chica.

Lectura:

No deberia ser el primer camino salvo que exista una flota suficiente o una necesidad fuerte de compatibilidad.

## 8. Riesgos principales

### 8.1 Riesgo de imagen sin manifest Arm

Sintoma:

`docker compose pull` o `docker compose up` falla porque la imagen no tiene variante `linux/arm64`.

Mitigacion:

1. agregar un comando de auditoria: `warp infra scan` o extender `warp scan`;
2. ejecutar `docker manifest inspect <image>` por cada imagen efectiva;
3. clasificar resultado como `native`, `x86-only`, `unknown` o `forced-platform`.

### 8.2 Riesgo de emulacion accidental

Sintoma:

El contenedor corre, pero con `platform: linux/amd64` en host Arm. Funciona lento, consume mas CPU y puede ocultar incompatibilidades.

Mitigacion:

1. no generar `platform: linux/amd64` por defecto;
2. permitirlo solo con variable explicita, por ejemplo `WARP_ALLOW_AMD64_EMULATION=1`;
3. mostrar warning visible en `warp info` y `warp start`.

### 8.3 Riesgo de extensiones PHP

Sintoma:

PHP arranca, pero falta una extension, una extension carga con error o Composer instala dependencias distintas.

Mitigacion:

1. smoke test de `php -m`;
2. smoke test de `composer check-platform-reqs`;
3. smoke test de Magento/Oro CLI si aplica;
4. matriz de extensiones por version PHP y arquitectura.

### 8.4 Riesgo de datos y volumenes

Sintoma:

Se intenta reutilizar un volumen DB/search creado con otra imagen/version/arquitectura y aparecen errores de arranque o corrupcion logica.

Mitigacion:

1. migrar DB por dump/restore, no moviendo volumen crudo;
2. recrear indices de search cuando sea posible;
3. hacer backup verificable antes de cambiar arquitectura;
4. documentar rollback por snapshot/AMI.

### 8.5 Riesgo de performance mal atribuido

Sintoma:

Se atribuye un resultado a Arm vs x86 cuando en realidad cambio EBS, kernel, AMI, Docker, PHP-FPM workers, OPcache, Redis maxmemory o heap de OpenSearch.

Mitigacion:

1. medir baseline en instancia actual;
2. correr mismo sitio, misma AMI base equivalente, mismo tipo de volumen y mismos limites;
3. separar pruebas con DB externa de pruebas con DB local;
4. guardar metricas antes/despues con `warp memory`, logs y APM si existe.

## 9. Cambios posibles en Warp

Estos cambios no son una recomendacion de implementacion inmediata. Son el mapa de trabajo si el analisis economico y tecnico supera los gates de ROI.

### 9.1 Fase 0: decision economica antes de codigo

Antes de tocar Warp:

1. listar servidores candidatos;
2. calcular costo actual, costo `c7i` y costo `c7g` por region;
3. separar sitios con DB externa y DB local;
4. estimar si el 40% de performance permite downsizing real o solo headroom;
5. estimar horas de PoC, build, pruebas y mantenimiento;
6. decidir un umbral de break-even aceptable.

Salida esperada:

1. `go`: hay ROI y se justifica PoC;
2. `limited-go`: probar solo un perfil reducido;
3. `no-go`: usar `c7i` o mantener estado actual.

### 9.2 Fase 1: auditoria sin cambiar comportamiento

Agregar documentacion y comandos informativos:

1. detectar arquitectura del host: `uname -m` y `docker info`;
2. listar imagenes efectivas del compose;
3. inspeccionar manifests multiarch;
4. marcar `platform:` forzado en compose;
5. mostrar recomendacion: `amd64 ok`, `arm64 native`, `arm64 blocked`, `arm64 emulated`.

Esto no modifica `.env`, `docker-compose-warp.yml` ni volumenes.

### 9.3 Fase 2: matriz de soporte por servicio

Extender la fuente de verdad de `.warp/variables.sh` con metadata de arquitectura:

1. `native`: soportado y recomendado;
2. `compatibility`: funciona con restricciones;
3. `legacy`: no recomendado;
4. `blocked`: no soportado.

Ejemplo conceptual:

```bash
WARP_DB_MARIADB_ARCHES=("linux/amd64" "linux/arm64")
WARP_DB_MYSQL_ARCH_POLICY="version-dependent"
WARP_SEARCH_OPENSEARCH_ARCHES=("linux/amd64" "linux/arm64")
WARP_PHP_SUMMASOLUTIONS_ARCH_POLICY="amd64-only-until-verified"
```

### 9.4 Fase 3: imagenes PHP multiarch

Publicar imagenes propias con manifest multiarch:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag magtools/php:8.2 \
  --push .
```

Regla:

No declarar soporte `c7g` productivo hasta que PHP sea nativo Arm para las versiones usadas por los sitios objetivo.

### 9.5 Fase 4: UX de `warp init`

Agregar decision de arquitectura solo como capacidad, no como pregunta obligatoria para todos:

1. si host es `amd64`, generar compose normal;
2. si host es `arm64`, preferir imagenes nativas;
3. si un servicio no tiene soporte Arm, abortar con mensaje claro o pedir confirmacion para emulacion;
4. si DB es externa, reducir matriz requerida.

La pregunta debe ser explicita:

```text
This host is arm64. Service mysql:5.7 is x86-only.
Use amd64 emulation for this service? [y/N]
```

### 9.6 Fase 5: smokes por arquitectura

Validaciones minimas:

1. `bash ./warp.sh --help`;
2. `bash ./warp.sh init --help`;
3. `bash ./warp.sh docker ps`;
4. `docker compose config`;
5. `docker compose pull`;
6. `docker compose up -d`;
7. `docker exec php php -m`;
8. `docker exec php php -v`;
9. `docker exec redis-cache redis-cli PING`;
10. `curl` a Nginx/PHP-FPM segun stack;
11. smoke de DB local o conexion externa;
12. smoke de OpenSearch si aplica.

## 10. Politica recomendada para produccion

### 10.1 Regla de decision rapida

Elegir `c7i` cuando:

1. el sitio usa PHP viejo;
2. hay imagenes privadas no auditadas;
3. hay DB/search local con volumen grande;
4. no hay ventana de benchmark;
5. el objetivo es solo modernizar instancia con riesgo bajo.

Elegir `c7g` cuando:

1. la DB es externa;
2. PHP y extensiones estan en versiones actuales;
3. todas las imagenes tienen manifest `linux/arm64`;
4. se puede hacer prueba paralela con trafico real o replay;
5. hay rollback por DNS/AMI/snapshot.

### 10.2 Orden sugerido de adopcion

1. Laboratorio: sitio chico sin DB local.
2. Staging real: DB externa, Redis local, sin search pesado.
3. Produccion chica: bajo trafico, rollback rapido.
4. Sitios con todos los servicios locales.
5. Sitios legacy o con imagenes privadas.

### 10.3 Criterio de exito

No alcanza con que `docker compose up` funcione.

El soporte `c7g` deberia considerarse aceptado cuando:

1. todos los contenedores calientes corren nativos `arm64`;
2. no hay `platform: linux/amd64` salvo excepcion documentada;
3. TTFB, CPU steal, load, memoria y errores 5xx mejoran o quedan iguales;
4. cron y colas no empeoran;
5. dumps/restores y rollback fueron probados;
6. el costo real mensual baja en la cuenta/regiones usadas.

## 11. Decision propuesta

No conviene decidir `c7i` vs `c7g` solo por la ficha de AWS.

Decision pragmatica para esta fase:

1. no implementar nada todavia;
2. medir ROI con una muestra real de proyectos;
3. usar `example` como caso tecnico de referencia moderno;
4. comparar tres caminos: `c7i`, `c7g` con oficiales, `c7g` con PHP propia;
5. considerar `no-go` como resultado aceptable si el ahorro no paga la complejidad.

Si el analisis da `go`, entonces el camino de menor riesgo seria:

1. PoC `c7g` con DB externa o restore controlado;
2. intentar primero imagenes oficiales;
3. crear imagen propia solo para PHP si es el unico gap serio;
4. dejar familia completa de imagenes propias como ultima opcion;
5. no declarar soporte productivo hasta tener smokes y benchmark.

## 12. Proximos pasos concretos

1. Crear inventario de servidores candidatos, costos actuales y tipo de instancia objetivo.
2. Estimar ahorro mensual con `c7i` y `c7g` por region.
3. Clasificar proyectos por perfil: DB externa, DB local, search local, PHP version, imagenes privadas.
4. Para `example`, verificar manifests de las imagenes efectivas sin cambiar el proyecto.
5. Calcular costo de PoC e imagen PHP multiarch minima.
6. Decidir `go / limited-go / no-go` antes de tocar codigo de Warp.
