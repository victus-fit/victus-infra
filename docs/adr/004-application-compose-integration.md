---
id: 004-application-compose-integration
title: Deploy released application images as an infra app stack
status: accepted
date: 2026-09-28
---

# Deploy released application images as an infra app stack

## Context

The application was operated from a workspace-level Compose file with local
build contexts, named volumes, and host ports. That arrangement cannot be
reproduced by the production Ansible deployment, which only stages
`victus-infra` files onto the server.

## Decision

`victus-infra` owns an `app` Compose project that runs released backend,
frontend, agent, and RAG images. It owns application Postgres, agent Postgres,
Qdrant, and Phoenix persistence under `/srv/data/app`. The stack connects to
`infra_shared_backend` for LiteLLM and core NGINX; NGINX publishes only the
frontend at `victus.fit`.

## Consequences

Image publication precedes infrastructure deployment and all four immutable
image references must be staged as separate secrets under
`/Hetzner-Server/app`. The deploy workflow materializes those app secrets into
the runtime env file used by Compose. Application code remains in its component
repositories. State rollback must restore the corresponding `/srv/data/app`
directories; an image rollback alone does not reverse a schema migration. The
legacy root-level Compose stack and this `app` stack use the same container
names and must not run at the same time.
