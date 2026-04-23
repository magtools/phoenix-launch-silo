# Warp Latest: functional improvements from the last year

Date: 2026-03-24

This document summarizes Warp's recent improvements from a functional, day-to-day team usage perspective.

Repository continuity note:

- this fork is maintained as a compatibility and historical bridge,
- active project evolution continues at `https://github.com/magtools/phoenix-launch-silo`.

## Unified environment-aware deploy (`warp deploy`)

Warp now includes a native deploy flow for `local` and `prod`, with per-project configuration in `.deploy`.

What it brings to the team:

- a standard deploy command (`warp deploy run`),
- preflight validation with `warp deploy doctor`,
- detection of an outdated global `warp` versus a valid delegating PATH wrapper,
- visible configuration with `warp deploy show`,
- guided `.deploy` generation with `warp deploy set`,
- recipe simulation without execution (`--dry-run`),
- frontend/static-only execution with `warp deploy static`.

Commands:

- `warp deploy`: shows deploy help (informational entrypoint).
- `warp deploy run`: executes the full deploy according to `.deploy`.
- `warp deploy static`: runs only static/frontend steps.
- `warp deploy set`: creates or updates `.deploy`.
- `warp deploy show`: shows the active configuration.
- `warp deploy doctor`: validates prerequisites.

Functional impact:

- fewer ad-hoc scripts per project,
- more predictable step ordering,
- better operational safety in production (confirmations and gates),
- OPcache handling at the end of deploy:
  - in `local`, if managed OPcache is active, it is disabled and PHP-FPM is reloaded;
  - in `prod`, PHP-FPM is reloaded only when managed OPcache is active.

## Stable Container Status (`warp ps`)

`warp ps` now avoids depending on the native Compose v1/v2 table format for its primary output.

What it brings to the team:

- stable columns (`IMAGE`, `CONTAINER`, `STATUS`, `PORTS`) across environments using `docker-compose` v1 or `docker compose` v2,
- `IMAGE` uses the short name (`img:version`) to avoid namespace/provider differences,
- native Compose output remains available with `warp ps --raw`,
- script-friendly formats:
  - `warp ps --services`,
  - `warp ps -q`,
  - `warp ps --format json`,
  - `warp ps --format names`.

## Integrated Hyva frontend flows (`warp hyva`)

A dedicated command for Hyva workflows has been consolidated:

- theme discovery,
- dependency installation,
- generate/build/watch,
- per-theme or batch execution.

What it brings to the team:

- simpler onboarding in Hyva projects,
- less manual npm work inside containers,
- repeatable local and production build flows.

Commands:

- `warp hyva discover`: detects themes and generates configuration.
- `warp hyva setup[:theme]`: installs dependencies and prepares theme(s).
- `warp hyva prepare[:theme]`: runs generation only.
- `warp hyva build[:theme]`: compiles assets.
- `warp hyva watch[:theme]`: watch mode for development.
- `warp hyva list`: shows detected themes.

## More complete Magento code quality coverage (`warp audit`)

`warp audit` is now the canonical name for the Magento code quality helper, replacing `warp scan`, and it covers more of the daily technical workflow.

What it brings to the team:

- direct execution per tool or through a menu,
- the same UX for `phpcs`, `phpcbf`, `phpmd`, `phpcompat`, `risky`, and `phpstan`,
- support for a specific path with `--path <path>` without prompting for the path again,
- `PHPCompatibility` integration to validate PHP version compatibility,
- a focused `risky primitive` audit for quick review of potentially dangerous PHP patterns,
- `PHPStan` integration using the project's base configuration,
- cleaner and more readable CLI and log output,
- more useful PR checks by adding PHP compatibility checks on `app/code`,
- a stronger `integrity` flow by adding risky primitive review and `PHPStan --level 1` on `app/code`.

Commands:

- `warp audit`: main audit menu.
- `warp audit --path <path>`: tool menu for a specific path.
- `warp audit pr`: opens a PR scope menu (`custom path`, `default`, or vendor-level paths).
- `warp audit --pr`: non-interactive PR checks on the project's default paths.
- `warp audit integrity` / `warp audit -i`: `setup:di:compile` + PR checks.
- `warp audit phpcs --path <path>`: direct PHPCS on a path.
- `warp audit phpcbf --path <path>`: direct PHPCBF on a path.
- `warp audit phpmd --path <path>`: direct PHPMD on a path.
- `warp audit phpcompat --path <path>`: direct PHPCompatibility on a path.
- `warp audit risky --path <path>`: direct risky primitive audit on a path.
- `warp audit phpstan`: PHPStan on the default scope from `phpstan.neon.dist`.
- `warp audit phpstan --path <path>`: PHPStan on a specific path.
- `warp audit phpstan --level <n>`: one-off level override for a run.
- `warp audit phpstan --level <n> --path <path>`: one-off level override on a specific path.
- `warp audit integrity`: now also runs risky primitive audit on `app/code` and `phpstan --level 1` on `app/code`.

Functional impact:

- less need for project-specific helper scripts,
- broader quality/compatibility coverage without leaving Warp,
- more consistency between interactive and direct checks,
- less noise in analysis logs.

## Explicit PHP runtime diagnostics (`warp php --version`)

A direct way to query the real PHP runtime version was added.

What it brings to the team:

- quickly confirms drift between `.env` and the real container,
- supports troubleshooting and the target version used by `PHPCompatibility`,
- avoids entering the container just to validate the PHP version.

Command:

- `warp php --version`: prints the real PHP runtime version.

## Broader Compose compatibility and mixed-runtime support

Warp improved its tolerance for environments that do not fit the classic `full warp` case exactly.

What it brings to the team:

- real support for the `docker compose` v2 plugin in addition to `docker-compose`,
- less friction on hosts where there is no global `docker-compose` binary,
- better support for commands that can operate without local compose,
- fewer unnecessary blocks in projects with partial or external infrastructure.

Functional impact:

- if `docker-compose` is missing but `docker compose` exists, Warp can operate through an internal fallback,
- compatible commands such as `warp magento`, `warp php`, `warp telemetry`, `warp info`, and other fallback-aware flows are no longer tied to the same rigid precheck,
- the experience improves in mixed-topology projects: local + external services or even fully external infrastructure with Warp present.

## Canonical capability-based commands (`warp db`, `warp cache`, `warp search`)

During this cycle, a clearer direction for naming and operational responsibility was consolidated.

What it brings to the team:

- a canonical capability-oriented layer instead of historical technology names,
- lower naming debt in commands and help output,
- a better base to operate local or external services through the same functional command.

Commands and compatibility:

- `warp db` as the canonical database surface.
- `warp cache` as the canonical cache surface.
- `warp search` as the canonical search surface.
- legacy aliases remain available:
  - `warp mysql`
  - `warp redis`
  - `warp valkey`
  - `warp elasticsearch`
  - `warp opensearch`

Functional impact:

- operators can think first in terms of capability (`db`, `cache`, `search`) instead of the historical container name,
- backward compatibility is preserved without forcing an abrupt command migration.

## Operational fallback for external services

Warp moved forward with a more explicit context and fallback layer for environments with services outside local Docker.

What it brings to the team:

- better external DB support,
- a common base for cache/search in `external` mode,
- less duplication of detection and validation logic across commands.

Functional impact:

- `warp db` / `warp mysql` now handle RDS/external scenarios better,
- `warp cache` and `warp search` are moving toward consistent behavior across local and external modes,
- `warp cache` can now bootstrap remote cache/fpc/session settings from `app/etc/env.php` and resolve DB per scope,
- `warp search` can now bootstrap `SEARCH_*` from `app/etc/env.php` when the local service is missing,
- guards for sensitive operations were hardened in external mode, especially `flush`.

Practical result:

- fewer ambiguous failures when a service is missing in `docker-compose-warp.yml`,
- better separation between local container operations and operations against external endpoints.

## More consistent version selection and defaults in `warp init`

The base logic behind `warp init` was strengthened so infrastructure engines/versions are resolved with a more coherent strategy.

What it brings to the team:

- fewer inconsistencies between the wizard, templates, and real defaults,
- better alignment between canonical service, engine, and version,
- a clearer base for current, verifiable defaults.

Functional impact:

- improved predictability when choosing the DB/cache/search stack,
- fewer historical misalignments between legacy naming and the real engine,
- better groundwork for Magento and supporting service upgrades.

## Memory diagnostics and suggestions (`warp telemetry scan`)

A memory report focused on analysis was added:

- memory usage by key services (`php`, `mysql`, `elasticsearch`, `redis-*`),
- reading the current configuration when present,
- automatic threshold suggestions based on RAM and real usage.

Recent functional evolution:

- Redis and Elasticsearch recommendations now use `used_memory` as the base.
- A `used_memory_peak` guardrail was added to propose a “safe minimum”.
- Operational alerts for memory pressure were added:
  - `>=75%` warning
  - `>=90%` critical
- PHP-FPM moved to RAM-based extrapolation with optimistic rounding for `pm.max_children`
  (including an additional adjustment on medium/large servers).

What it brings to the team:

- capacity/tuning decisions based on data,
- quick visibility into drift between real usage and configuration,
- clear separation between container usage and internal service usage,
- text and JSON output for troubleshooting and documentation,

## Access-log scraping diagnostics (`warp scan scraping`)

Warp adds a read-only scanner to detect patterns compatible with expensive
scraping over local or external access logs.

What it brings to the team:

- analyzes plain and `.gz` Nginx/PHP-FPM logs without changing configuration,
- supports `--path`, `--since`, `--window`, `--page-gap`, `--json`, `--save`,
  `--output`, and `--output-dir`,
- reports suspicious clients, hot paths, user-agent families, and signatures by
  `path + normalized query + ua_family`,
- shows interactive pv-like progress on `stderr` with current stage, ingested
  bytes, seen lines, and parsed lines,
- keeps `stdout` clean for human reports, JSON, and redirection,
- allows disabling progress with `--no-progress`.

Functional impact:

- helps investigate IP-rotating scrapers by grouping repeated signatures,
- avoids the appearance of a hung command during ingestion, final metrics, and
  report rendering,
- reduces analysis finalization cost by computing pagination metrics per client
  without scanning all global pages for every client.

Commands:

- `warp scan scraping --path /var/log/nginx/access.log --top 20`
- `warp scan scraping --since 24h --window 5m`
- `warp scan scraping --json --output var/log/warp-scan-scraping.json`
- `warp scan scraping --no-progress`

## More useful security scan and check (`warp security`)

`warp security` continued tightening the balance between real signal and operational noise.

What it brings to the team:

- `warp security scan` now explains more clearly why a file was flagged (`path - indicator [class]`),
- `warp security check` keeps detailed output in `var/log/warp-security.log` plus a rotated historical copy,
- an incorrect discard of lines with inline comments (`// phpcs:ignore`) was fixed, which had been hiding real signals such as `base64_decode()` in `app/code`,
- a generic `new WebSocket` inside known `pub/static` libraries such as `jquery/uppy` is no longer treated as a skimmer by itself,
- `warp security scan` also adds a fast PHP-under-`pub` check excluding `pub/errors` and Magento core entrypoints, plus a separate verification to detect whether those core entrypoints were modified,
- `warp security scan` and `warp security check` now create `.known-paths`, `.known-files`, and `.known-findings` when missing, so expected paths/files and accepted findings live in project files instead of hardcoded scanner logic,
- that exclusion does not silence stronger signals: if `wss://`, `RTCPeerConnection`, `createDataChannel`, or `new Function(event.data)` appear, the finding remains.

Functional impact:

- fewer false positives in legitimate frontend assets,
- better visibility into risky primitives outside `pub`,
- more confidence in the score and `attention paths` shown by `scan`.
- better signals to prevent saturation before business impact.

Commands:

- `warp telemetry` / `warp telemetry scan`: functional report for usage/configuration/suggestions.
- `warp telemetry scan --no-suggest`: shows usage + current config without recommendations.
- `warp telemetry scan --json`: structured output for automation.
- `warp telemetry config`: quick guide showing where to configure memory per service (Redis, Search, PHP-FPM) plus MySQL/MariaDB reference through MySQLTuner.

## Initial operational security base (`warp security`)

Warp now includes an initial surface for security triage:

- `warp security`: main entrypoint and help
- `warp security scan`: quick heuristic pass to decide whether `check` is worth running
- `warp security check`: runs a read-only scan over filesystem, IOC, logs and host; writes `var/log/warp-security.log` plus a rotated copy
- `warp security toolkit`: prints manual analysis and cleanup commands by family/surface

What it brings to the team:

- a consistent base to investigate signs of compromise,
- explicit separation between read-only analysis and manual cleanup,
- short operational output with score, severity/suspicion and status line,
- operational guidance for recent families such as PolyShell, SessionReaper, and CosmicSting.

Functional impact:

- Warp does not execute destructive cleanup in this feature,
- `toolkit` prioritizes safer inspection and quarantine-oriented commands,
- `.known-paths` lets teams document expected untracked paths without whitelisting dangerous PHP inside `pub/`.

## More configurable Redis per environment

Warp moved from an “implicit” Redis configuration to a more controlled one:

- effective use of `redis.conf` inside containers,
- memory/policy parameters per service through `.env`,
- functional separation of cache/fpc vs session,
- compatibility with Magento operational recommendations.

What it brings to the team:

- safer tuning in production,
- faster per-environment adjustments without rebuilding images,
- lower risk of degradation caused by incorrect memory policies.

Commands:

- `warp redis info`: shows information about configured Redis services.
- `warp redis cli <cache|session|fpc>`: access to `redis-cli` per service.
- `warp redis monitor <cache|session|fpc>`: real-time command monitoring.
- `warp redis flush <cache|session|fpc|--all>`: data cleanup per service.

## Warp self-maintenance and update flow (`warp update`)

The framework update flow was hardened:

- integrity verification (checksum) before replacement,
- pending update state tracking,
- automatic version checks without interrupting critical commands,
- non-destructive creation of empty `ext-xdebug.ini` and `zz-warp-opcache.ini` files when missing,
- `.gitignore` verification for those local effective INI files,
- clear separation between Warp updates and Docker image updates.

Current remote sources for runtime update:

- `https://raw.githubusercontent.com/magtools/phoenix-launch-silo/refs/heads/master/dist/version.md`
- `https://raw.githubusercontent.com/magtools/phoenix-launch-silo/refs/heads/master/dist/sha256sum.md`
- `https://raw.githubusercontent.com/magtools/phoenix-launch-silo/refs/heads/master/dist/warp`

What it brings to the team:

- more reliable upgrades,
- better visibility when a new version exists or when connectivity fails,
- lower risk of surprising project configuration changes,
- a clear operational recommendation to install a delegating `warp` wrapper in PATH when the global binary becomes stale.

Commands:

- `warp update`: updates the Warp binary/framework.
- `warp update --images`: updates project Docker images.
- `warp update self` / `warp update --self`: applies a local self-update for development flows; if the remote is newer, it leaves the normal pending update marker.

## Quick MySQL diagnostics with MySQLTuner (`warp mysql tuner`)

An operational shortcut was added to run MySQLTuner against the project's DB service.

What it brings to the team:

- avoids manual steps to download the script,
- uses a standard working directory (`./var` or `/tmp`),
- detects missing Perl and attempts distro-specific installation with prior confirmation,
- runs MySQLTuner using connection data aligned with the project's `.env` (local or external).

Connection behavior:

- local environment with DB container: uses `localhost` and the mapped port (`DATABASE_BINDED_PORT` or `docker-compose port`).
- if the effective port is `3306`, connects to `localhost` without forcing `--port`.
- external environment (`MYSQL_VERSION=rds`): uses `DATABASE_HOST`, `DATABASE_BINDED_PORT`, `DATABASE_USER`, `DATABASE_PASSWORD`.
- server log output is filtered by default to reduce noise; use `warp mysql tuner -vvv` to include it completely.
- color is enabled by default (except with `--nocolor`).

Command:

- `warp mysql tuner`: downloads/validates dependencies and runs MySQLTuner.

## Per-application dev dumps (`warp mysql devdump`)

A lightweight development dump flow based on per-app exclusion profiles was added.

What it brings to the team:

- avoids maintaining ad-hoc scripts per project,
- allows generating smaller dumps without sensitive/voluminous data,
- enables simple extension by adding profile files without touching the core,
- supports selecting one profile or combining all profiles for the same app.

Commands:

- `warp mysql devdump`: helper with description and available apps.
- `warp mysql devdump:magento`: runs Magento devdump with profile selection.

## External database support for `warp mysql` (`rds` mode)

MySQL commands now handle scenarios where there is no `mysql` service in Docker and the database is external.

What it brings to the team:

- avoids ambiguous failures when the `mysql` service is not present in `docker-compose-warp.yml`,
- allows switching to external mode with operator confirmation,
- autocompletes credentials from `app/etc/env.php` when available,
- uses a local client for `connect` and `dump`, with assisted installation when missing,
- allows cleaning `DEFINER` clauses from the dump stream with a native option.

Affected commands:

- `warp mysql connect`: in `rds`, connects to the external host.
- `warp mysql dump <db>`: in `rds`, dumps against the external host.
- `warp mysql dump -s <db>` / `warp mysql dump --strip-definers <db>`: removes `DEFINER` clauses from the streamed dump before writing it.
- `warp mysql import <db>`: in `rds`, does not import; it prints a suggested command and the password.

## More guided Grunt setup (`warp grunt setup`)

In addition to the classic execution command, there is now a dedicated setup flow for Grunt:

- prepares base files when missing,
- installs npm dependencies inside the container,
- normalizes permissions to avoid later blockers.

What it brings to the team:

- less friction in legacy/classic frontend projects,
- fewer permission errors when installing as root,
- better compatibility with different PHP containers.

Commands:

- `warp grunt setup`: prepares base files and installs Grunt dependencies.
- `warp grunt exec`: republishes frontend symlinks/artifacts.
- `warp grunt less`: compiles LESS/CSS.
- `WARP_GRUNT_PHP_CONTAINER=<container> warp grunt ...`: runs against a specific PHP container.

## Platform and version compatibility (Magento/OpenSearch)

Over the last year, compatibility adjustments were also added to reduce friction during upgrades and environment bootstrap.

What it brings to the team:

- better operational support for Magento projects on recent branches (including 2.4.7/2.4.8 adjustments),
- fixes in OpenSearch/Elasticsearch setup and related variables,
- alignment of setup defaults for PHP/MySQL and supporting components,
- lower risk of bootstrap failures caused by version combinations.

Functional impact:

- more stable `warp init` runs,
- fewer manual corrections after setup,
- greater consistency across projects when migrating stack versions.

## Overall result for the team

Taken together, these improvements aim to:

- standardize repetitive operations,
- reduce variability across projects,
- improve operational safety in deploy/update flows,
- shorten diagnosis and setup times.
