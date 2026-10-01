---
id: victus-infra-local-runtime
title: Local Runtime Operations
status: active
updated_at: 2026-05-27
owners:
  - CarlosGebard/victus-infra
---

# Local Runtime Operations

## Purpose

This runbook describes local validation and local execution for the shared
Victus infrastructure runtime.

## Requirements

- Docker
- Docker Compose
- Python 3.12+
- `uv`
- Ansible for validation and deployment checks

## Configuration

Committed examples:

```text
compose/env/core.env.example
compose/env/observability.env.example
compose/env/llm.env.example
compose/env/app.env.example
```

Local runtime env files:

```text
compose/projects/core/.env
compose/projects/observability/.env
compose/projects/llm/.env
compose/projects/app/.env
```

Local `.env` files are not committed.

## Validate

Run from the repository root:

```bash
make ansible-check
make compose-validate
```

## Start Core

```bash
make core-up
```

This workflow:

- creates the shared Docker network `infra_shared_backend`.
- starts the `core` stack.
- syncs local private DNS.
- applies the S3 bucket and prefix contract idempotently.

## Inspect Core

```bash
docker compose \
  --env-file compose/projects/core/.env \
  -f compose/projects/core/compose.yml \
  -f compose/projects/core/compose.dev.yml \
  ps
```

## Logs

```bash
make core-logs
```

## Stop Core

```bash
make core-down
```

## Run LLM Stack

Start the stack:

```bash
make llm-up
```

Local endpoints:

```text
LiteLLM    http://127.0.0.1:4000
Postgres   127.0.0.1:55432
```

Production does not publish LiteLLM ports directly. Access goes through
private NGINX on the Tailscale IP.

Private DNS endpoints:

```text
LiteLLM    http://litellm.victus.io
Phoenix    http://phoenix.victus.io
MCP        http://mcp.victus.io
```

Local NGINX aliases:

```text
LiteLLM    http://litellm.localhost:8080
Phoenix    http://phoenix.localhost:8080
MCP        http://mcp.localhost:8080
```

## Run Application Stack

The application stack consumes released image references. Copy
`compose/env/app.env.example` to `compose/projects/app/.env`, replace all
`change-me` values and image tags, then run:

```bash
make app-up
```

Local ports bind to loopback by default. Production mounts the application's
durable Postgres, Qdrant, and Phoenix data under `/srv/data/app`; only the
frontend is exposed publicly through central NGINX at `app.victus.fit`.
Phoenix and MCP are available only on the Tailscale private edge at
`http://phoenix.victus.io` and `http://mcp.victus.io`.

Check startup and service health with:

```bash
docker compose --env-file compose/projects/app/.env \
  -f compose/projects/app/compose.yml \
  -f compose/projects/app/compose.dev.yml ps
curl --fail http://127.0.0.1:8000/health
curl --fail http://127.0.0.1:8766/health
curl --fail http://127.0.0.1:8765/health
```

Provider API keys are added through the LiteLLM UI and persisted in the
LiteLLM Postgres database. They should not be committed to git.

## Bridge Smoke Check

```bash
cd ops/bridge
UV_PROJECT_ENVIRONMENT=/tmp/victus-bridge-uv-env uv run victus-ingest --help
```

Expected local bridge variables:

```text
VICTUS_PG_DSN=postgresql://victus:<password>@pipeline-postgres:5432/victus_registry
VICTUS_REDIS_URL=redis://:<password>@redis:6379/0
VICTUS_S3_ENDPOINT=http://seaweedfs:8333
VICTUS_S3_ACCESS_KEY=<access-key>
VICTUS_S3_SECRET_KEY=<secret-key>
VICTUS_S3_BUCKET=victus-corpus
VICTUS_AWS_REGION=us-east-1
```

Expected variables from other hosts in the private network:

```text
VICTUS_PG_DSN=postgresql://victus:<password>@pipeline-postgres.victus.io:5432/victus_registry
VICTUS_REDIS_URL=redis://:<password>@redis.victus.io:6379/0
VICTUS_S3_ENDPOINT=http://s3.victus.io
```
