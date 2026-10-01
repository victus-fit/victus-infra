---
id: 005-phoenix-private-observability
title: Use Phoenix for private LLM observability
status: accepted
date: 2026-09-30
---

# Use Phoenix for private LLM observability

## Context

Phoenix is already instrumented by the backend and agent through OpenInference
and stores its data under `/srv/data/app/phoenix`. Langfuse had no application
consumer and duplicated tracing infrastructure, a database, routing, secrets,
and operational setup.

## Decision

Remove Langfuse from the LiteLLM stack, including its callback, database
initialization, private DNS, NGINX route, and deployment secrets. Retain
Phoenix as the sole V1 LLM tracing UI. Attach Phoenix to the shared Docker
network and publish it only through private NGINX at `phoenix.victus.io`, whose
CoreDNS record targets the host's Tailscale IP.

## Consequences

Phoenix remains unreachable from the public listener and does not need a
public DNS record or TLS certificate. Existing Langfuse data is not deleted by
this change; its retention or removal requires an explicit operational action.
