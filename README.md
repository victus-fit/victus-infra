# Victus Infra

Reproducible infrastructure for the private Victus runtime.

This repository does not contain application source code. It provides the shared runtime and deploys released Victus application images:

- object storage and artifacts in SeaweedFS S3
- durable paper state in Postgres
- live events in Redis
- private DNS with CoreDNS
- private and public edge routing with NGINX
- observability with Grafana, Prometheus, and Loki
- Wiki.js for central, browser-managed documentation
- deployment with Ansible and GitHub Actions

[Leer en español](docs/README.es.md)

## Quick View

```text
compose/        Docker Compose source of truth
ansible/        VPS deployment
ops/            scripts and reusable bridge
docs/           essential documentation
tests/          Ansible validation
```

Stacks:

```text
core            nginx, seaweedfs, pipeline-postgres, redis, etcd, coredns
observability   grafana, prometheus, loki
llm             LiteLLM, Postgres
wiki            Wiki.js, Postgres, browser-managed documentation
app             Victus web app, agent, RAG, Qdrant, Phoenix, two Postgres services
```

## Local Use

Validate:

```bash
make ansible-check
make compose-validate
```

Start `core`:

```bash
make core-up
```

This also applies local S3 buckets idempotently.

Logs:

```bash
make core-logs
```

Stop:

```bash
make core-down
```

## Reusable Bridge

The shared SDK/CLI lives in:

```text
ops/bridge
```

Example:

```bash
cd ops/bridge
uv run victus-ingest --help
```

The bridge only talks to shared infrastructure. It does not implement Docling, claims, embeddings, Qdrant, or app-specific logic.

## Deployment

Production deploy runs through:

```text
.github/workflows/deploy-all.yml
```

Secrets come from Infisical through GitHub OIDC.

## Documentation

- [Documentation Index](docs/README.md)
- [System Context](docs/000-SYSTEM-CONTEXT.md)
- [Architecture](docs/100-ARCHITECTURE.md)
- [Networking Architecture](docs/architecture/101-NETWORKING.md)
- [Compute Runtimes](docs/architecture/102-COMPUTE-RUNTIMES.md)
- [Data Storage](docs/architecture/103-DATA-STORAGE.md)
- [Observability Architecture](docs/architecture/104-OBSERVABILITY.md)
- [Operations](docs/200-OPERATIONS.md)
- [Contracts](docs/300-CONTRACTS.md)
- [Local Runtime](docs/operations/201-LOCAL-RUNTIME.md)
- [Deployment](docs/operations/202-DEPLOYMENT.md)
- [Security Operations](docs/operations/203-SECURITY.md)
- [Troubleshooting](docs/operations/204-TROUBLESHOOTING.md)
