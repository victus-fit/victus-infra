# Victus Infra

Infraestructura reproducible para el runtime privado de Victus.

Este repo no contiene la app. Provee la base compartida usada por otros repositorios Victus:

- objetos y artefactos en SeaweedFS S3
- estado durable de papers en Postgres
- eventos live en Redis
- DNS privado con CoreDNS
- edge privado y publico con NGINX
- observabilidad con Prometheus y Loki
- Wiki.js para documentación central administrada desde el navegador
- deploy con Ansible y GitHub Actions

[Read in English](../README.md)

## Vista Rápida

```text
compose/        Docker Compose source of truth
ansible/        deploy al VPS
ops/            scripts y bridge reusable
docs/           documentación esencial
tests/          validaciones Ansible
```

Stacks:

```text
core            nginx, seaweedfs, pipeline-postgres, redis, etcd, coredns
observability   prometheus, loki
llm             LiteLLM, Postgres
wiki            Wiki.js, Postgres, documentación administrada desde el navegador
```

## Uso Local

Validar:

```bash
make ansible-check
make compose-validate
```

Levantar `core`:

```bash
make core-up
```

Esto también aplica buckets S3 locales de forma idempotente.

Ver logs:

```bash
make core-logs
```

Bajar:

```bash
make core-down
```

## Bridge Reusable

El SDK/CLI común vive en:

```text
ops/bridge
```

Ejemplo:

```bash
cd ops/bridge
uv run victus-ingest --help
```

El bridge solo comunica con infraestructura común. No implementa Docling, claims, embeddings, Qdrant ni lógica interna de otros repos.

## Deploy

El deploy productivo ocurre desde:

```text
.github/workflows/deploy-all.yml
```

Los secretos vienen desde Infisical vía GitHub OIDC.

## Documentación

- [Índice de documentación](README.md)
- [Contexto del sistema](000-SYSTEM-CONTEXT.md)
- [Arquitectura](100-ARCHITECTURE.md)
- [Networking](architecture/101-NETWORKING.md)
- [Compute runtimes](architecture/102-COMPUTE-RUNTIMES.md)
- [Data storage](architecture/103-DATA-STORAGE.md)
- [Observabilidad](architecture/104-OBSERVABILITY.md)
- [Operación](200-OPERATIONS.md)
- [Contratos](300-CONTRACTS.md)
- [Runtime local](operations/201-LOCAL-RUNTIME.md)
- [Deploy](operations/202-DEPLOYMENT.md)
- [Seguridad operativa](operations/203-SECURITY.md)
- [Troubleshooting](operations/204-TROUBLESHOOTING.md)
