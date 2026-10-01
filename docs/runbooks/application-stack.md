---
id: application-stack
title: Application Stack Operations
status: active
---

# Application Stack Operations

## Deploy prerequisites

- Publish compatible backend, frontend, agent, and RAG images.
- Set their immutable references, `APP_PUBLIC_ORIGIN`, database credentials and
  application secrets in Infisical as the multiline `APP_RUNTIME_ENV` value at
  `/Hetzner-Server/app`.
- Create DNS for `app.victus.fit` before the first deploy so the core HTTP-01
  certificate step can succeed.

## Deploy and verify

Run the standard **Deploy All Stacks** workflow. It deploys core before app,
so the shared network and public NGINX are ready.

On the host:

```bash
docker compose --env-file /srv/secrets/runtime/app.env \
  -f /srv/apps/app/compose.yml -f /srv/apps/app/compose.prod.yml ps
curl --fail --resolve app.victus.fit:443:127.0.0.1 https://app.victus.fit/health
docker exec victus-agent-chat python -c "import urllib.request; urllib.request.urlopen('http://rag:8080/healthz').read()"
```

Inspect tracing through the Tailscale-only endpoint:

```bash
curl --fail http://phoenix.victus.io/healthz
```

The public health URL is served by the frontend; use `docker exec victus-backend`
with `/health` when verifying the backend directly.

## Roll back

Set `VICTUS_BACKEND_IMAGE`, `VICTUS_FRONTEND_IMAGE`, `VICTUS_AGENT_IMAGE`, and
`VICTUS_RAG_IMAGE` to the prior compatible image set in `APP_RUNTIME_ENV`, then
rerun the workflow. Do not delete `/srv/data/app`. If a release changed either
Postgres schema, restore the matching database backup before starting the older
image set.
