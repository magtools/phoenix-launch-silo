# warp nginx

## Runtime commands

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
