# Legacy Backlog (evolutivo)

Fecha inicio: 2026-03-17
Estado: vivo

Objetivo: registrar compatibilidad legacy que se mantiene temporalmente y planificar su retiro sin breaking changes abruptos.

## 1) Politica

1. comandos legacy siguen disponibles via alias durante transicion,
2. ayudas y documentacion priorizan comandos canonicos,
3. retiro solo con fecha/version anunciada,
4. cada item debe tener criterio de salida y riesgos.

## 2) Items actuales

## 2.1 Comandos legacy (alias)

1. `warp mysql` -> canonico `warp db`
2. `warp redis` -> canonico `warp cache`
3. `warp elasticsearch` -> canonico `warp search`
4. `warp valkey` -> alias de compatibilidad de engine para `warp cache`
5. `warp opensearch` -> alias de compatibilidad de engine para `warp search`

Criterio de salida:

1. telemetria/uso legacy por debajo del umbral acordado,
2. documentacion migrada,
3. minimo 1 ciclo de release con warnings visibles.

## 2.2 Variables legacy

1. DB legacy: `DATABASE_*`, `MYSQL_VERSION`, `MYSQL_DOCKER_IMAGE`
2. CACHE legacy: `REDIS_*`
3. SEARCH legacy: `ES_*`

Regla transitoria:

1. fallback lee legacy si canonico falta,
2. nuevas escrituras se hacen en variables canonicas,
3. `warp init` genera ambas durante periodo de transicion.

Criterio de salida:

1. eliminar generacion de variables legacy en `init`,
2. mantener solo read-compat por una ventana corta,
3. retirar read-compat cuando la mayoria de proyectos este migrada.

## 2.3 Mensajes y help

1. ejemplos oficiales solo con comandos canonicos,
2. comandos legacy sin protagonismo pero funcionales,
3. warnings no intrusivos en legacy.

Criterio de salida:

1. retirar referencias legacy del help,
2. mantener solo nota de migracion historica en docs.

## 3) Registro de decisiones

1. 2026-03-17: se adopta arquitectura canonica `db/cache/search`.
2. 2026-03-17: alias se mantienen para comandos y subcomandos.
3. 2026-03-17: `cache flush` y `search flush` en external siempre con confirmacion explicita `y/Y`, sin `--force`.

## 4) Preguntas pendientes

1. definir umbral de uso para retiro de alias legacy,
2. definir version objetivo para eliminar generacion de variables legacy,
3. definir si warnings legacy estaran activos por defecto o por flag de entorno.
