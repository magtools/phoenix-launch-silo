# warp nginx

## Runtime commands

`warp nginx -t` and `warp nginx test` validate the Nginx configuration inside
the `web` container as `root`:

```bash
docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root web nginx -t
```

`warp nginx reload` validates the configuration first and only reloads Nginx if
the test succeeds:

```bash
docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root web nginx -t
docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root web nginx -s reload
```

Both commands require Warp containers to be running. If they are stopped, Warp
aborts with the same message used by `warp nginx ssh`.
