# warp nginx

## Runtime commands

`warp nginx version` and `warp nginx --version` print only the effective Nginx
version line:

```bash
nginx version: nginx/1.23.3
```

Resolution order:

- if the `web` container is running, Warp resolves its container id with
  `docker-compose ps -q web` and runs `docker exec -i <container> nginx -v`
- if the `web` container is not running, Warp resolves the configured image for
  the `web` service from `docker-compose config`
- if the compose file or image cannot be resolved, Warp falls back to
  `nginx:latest`

Because `nginx -v` can emit auxiliary text depending on the runtime, Warp
extracts and prints only the last line that matches `nginx version: ...`.

If the detected version is lower than `1.25.1`, Warp prints a red warning and
the suggested remediation:

```bash
docker pull nginx:latest
```

`warp nginx check` builds on the same runtime resolution logic, then queries the
published `nginx` tags on Docker Hub and prints a compact status report:

```bash
Image reference: nginx:latest
Local nginx version: 1.29.6
Latest remote version: 1.30.0
Released versions behind: 3
Newer versions: 1.29.7 , 1.29.8 , 1.30.0
Status: still a valid version
```

Decision rules:

- if the detected version is lower than `1.25.1`, Warp prints a red `must be updated` warning
- if `Released versions behind` is `0`, Warp prints `Status: up to date` in green
- if `Released versions behind` is between `1` and `10`, Warp prints `Status: still a valid version` in green
- if `Released versions behind` is greater than `10`, Warp prints `Status: outdated` in yellow plus:
  - `Recommendation: update nginx to a newer released version.`
  - `Suggested action: docker pull nginx:latest`

This check is intended for official Docker Hub style image references. If the
configured `web` image points to a custom registry, Warp aborts with an
explicit message instead of guessing a remote comparison target.

`warp nginx -t`, `warp nginx --test`, and `warp nginx test` validate the Nginx
configuration inside the `web` container as `root`:

```bash
docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root web nginx -t
```

`warp nginx -r`, `warp nginx --reload`, and `warp nginx reload` validate the
configuration first and only reload Nginx if the test succeeds:

```bash
docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root web nginx -t
docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root web nginx -s reload
```

Before sending the reload signal, Warp compares known single-file Nginx bind
mounts on the host with their paths inside the `web` container using `cksum`.
This catches stale file mounts, usually caused by an editor or deploy process
replacing a config file with an atomic rename. In that case, Nginx cannot reload
the new file because Docker is still exposing the old inode inside the
container.

The checked files are:

- `NGINX_CONFIG_FILE` -> `/etc/nginx/sites-enabled/default.conf`
- `.warp/docker/config/nginx/nginx.conf` -> `/etc/nginx/nginx.conf`
- `.warp/docker/config/nginx/m2-cors.conf` -> `/etc/nginx/m2-cors.conf`
- `.warp/docker/config/nginx/bad-bot-blocker/globalblacklist.conf` -> `/etc/nginx/conf.d/globalblacklist.conf`

Before using the restart fallback, Warp streams the current host vhost into
`/etc/nginx/sites-enabled/warp-vhost-test.conf` inside the container. It also
copies current host versions of optional file-mounted configs such as
`nginx.conf`, `m2-cors.conf`, and `globalblacklist.conf` into temporary paths
under `/etc/nginx`, rewrites the temporary config to reference those files, and
runs `nginx -t -c` against the temporary config. The temporary files live under
`/etc/nginx` so relative includes such as `fastcgi_params` resolve the same way
as the real vhost. Warp restarts only the `web` container as the last resort
when that validation succeeds, so Docker remounts the current host files.

If the explicit reload command fails after a successful config test, Warp also
restarts only the `web` container as a fallback.

Both commands require Warp containers to be running. If they are stopped, Warp
aborts with the same message used by `warp nginx ssh`.

Unknown `warp nginx` subcommands must return a non-zero exit code after showing
the help output, so a mistyped reload command is not reported as a successful
operation.
