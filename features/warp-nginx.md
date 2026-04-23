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

Both commands require Warp containers to be running. If they are stopped, Warp
aborts with the same message used by `warp nginx ssh`.

Unknown `warp nginx` subcommands must return a non-zero exit code after showing
the help output, so a mistyped reload command is not reported as a successful
operation.
