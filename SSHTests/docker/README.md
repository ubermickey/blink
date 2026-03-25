```sh
docker build -t blink-ssh-fixture:local .
```

```sh
docker run --rm --init \
  -p 2222:22 \
  -p 2223:23 \
  --name blink-ssh-fixture \
  -e FIXTURE_RUN_ID=manual \
  -e FIXTURE_LANE=manual \
  -e FIXTURE_REMOTE_ROOT='~/fps-runs/manual/manual' \
  blink-ssh-fixture:local
```

Fixture helper service:

- Runs in-container on `127.0.0.1:${FIXTURE_HELPER_PORT:-18080}`.
- Health check: `curl http://127.0.0.1:18080/healthz` (inside container).
- Metadata: `curl http://127.0.0.1:18080/meta` (inside container).
