#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENV_FILE="$ROOT_DIR/compose/projects/app/.env"
COMPOSE_BASE="$ROOT_DIR/compose/projects/app/compose.yml"
COMPOSE_OVERLAY="$ROOT_DIR/compose/projects/app/compose.dev.yml"

[[ -f "$ENV_FILE" ]] || {
  echo "Missing $ENV_FILE. Copy compose/env/app.env.example and set real values." >&2
  exit 1
}

"$ROOT_DIR/ops/scripts/local/ensure-shared-network.sh"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_BASE" -f "$COMPOSE_OVERLAY" up -d "$@"
