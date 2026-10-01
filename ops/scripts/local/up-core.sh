#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENV_FILE="$ROOT_DIR/compose/projects/core/.env"
COMPOSE_BASE="$ROOT_DIR/compose/projects/core/compose.yml"
COMPOSE_OVERLAY="$ROOT_DIR/compose/projects/core/compose.dev.yml"
S3_BUCKETS_SCRIPT="$ROOT_DIR/ops/scripts/runtime/apply-s3-buckets.py"
S3_BUCKETS_CONTRACT="$ROOT_DIR/compose/configs/seaweedfs/buckets.json"
SEAWEED_S3_CONFIG="$ROOT_DIR/compose/configs/seaweedfs/s3.json.example"
LOCAL_DNS_BIND="${LOCAL_DNS_BIND:-loopback}"
COMPOSE_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tailscale)
      LOCAL_DNS_BIND="tailscale"
      shift
      ;;
    --localhost|--loopback)
      LOCAL_DNS_BIND="loopback"
      shift
      ;;
    --)
      shift
      COMPOSE_ARGS+=("$@")
      break
      ;;
    *)
      COMPOSE_ARGS+=("$1")
      shift
      ;;
  esac
done

tailscale_ipv4() {
  ip -4 addr show dev "$TAILSCALE_INTERFACE" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1
}

write_managed_env_block() {
  local tmp_file

  tmp_file="$(mktemp)"
  awk '
    BEGIN { skip=0 }
    /^# BEGIN managed: core-private-dns$/ { skip=1; next }
    /^# END managed: core-private-dns$/ { skip=0; next }
    $1 ~ /^(TAILSCALE_INTERFACE|TAILSCALE_IPV4|DNS_ZONE|ETCD_PREFIX|DNS_TTL|COREDNS_BIND_IP|COREDNS_DNS_PORT|NGINX_BIND_IP|NGINX_HTTP_PORT|S3_DOMAIN|POSTGRES_DOMAIN|POSTGRES_BIND_IP|POSTGRES_PORT|REDIS_DOMAIN|REDIS_BIND_IP|REDIS_PORT|LITELLM_DOMAIN|PHOENIX_DOMAIN|MCP_DOMAIN)=/ { next }
    skip == 0 { print }
  ' "$ENV_FILE" > "$tmp_file"

  cat >> "$tmp_file" <<EOF
# BEGIN managed: core-private-dns
TAILSCALE_INTERFACE=$TAILSCALE_INTERFACE
TAILSCALE_IPV4=$TAILSCALE_IPV4
DNS_ZONE=${DNS_ZONE:-victus.io}
ETCD_PREFIX=${ETCD_PREFIX:-/skydns}
DNS_TTL=${DNS_TTL:-30}
COREDNS_BIND_IP=$COREDNS_BIND_IP
COREDNS_DNS_PORT=$COREDNS_DNS_PORT
NGINX_BIND_IP=$NGINX_BIND_IP
NGINX_HTTP_PORT=$NGINX_HTTP_PORT
S3_DOMAIN=${S3_DOMAIN:-s3.${DNS_ZONE:-victus.io}}
POSTGRES_DOMAIN=${POSTGRES_DOMAIN:-pipeline-postgres.${DNS_ZONE:-victus.io}}
POSTGRES_BIND_IP=$POSTGRES_BIND_IP
POSTGRES_PORT=${POSTGRES_PORT:-5432}
REDIS_DOMAIN=${REDIS_DOMAIN:-redis.${DNS_ZONE:-victus.io}}
REDIS_BIND_IP=$REDIS_BIND_IP
REDIS_PORT=${REDIS_PORT:-6379}
LITELLM_DOMAIN=${LITELLM_DOMAIN:-litellm.${DNS_ZONE:-victus.io}}
PHOENIX_DOMAIN=${PHOENIX_DOMAIN:-phoenix.${DNS_ZONE:-victus.io}}
MCP_DOMAIN=${MCP_DOMAIN:-mcp.${DNS_ZONE:-victus.io}}
# END managed: core-private-dns
EOF

  mv "$tmp_file" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

"$ROOT_DIR/ops/scripts/local/ensure-shared-network.sh"

if [[ "$LOCAL_DNS_BIND" == "tailscale" ]]; then
  export TAILSCALE_INTERFACE="${TAILSCALE_INTERFACE:-tailscale0}"
  export TAILSCALE_IPV4="${TAILSCALE_IPV4:-$(tailscale_ipv4)}"
  if [[ -z "$TAILSCALE_IPV4" ]]; then
    echo "[ERROR] No IPv4 found on interface $TAILSCALE_INTERFACE" >&2
    exit 1
  fi
  export COREDNS_DNS_PORT="${COREDNS_DNS_PORT:-53}"
  export COREDNS_BIND_IP="${COREDNS_BIND_IP:-$TAILSCALE_IPV4}"
  export NGINX_BIND_IP="${NGINX_BIND_IP:-$TAILSCALE_IPV4}"
  export NGINX_HTTP_PORT="${NGINX_HTTP_PORT:-8080}"
  export POSTGRES_BIND_IP="${POSTGRES_BIND_IP:-$TAILSCALE_IPV4}"
  export REDIS_BIND_IP="${REDIS_BIND_IP:-$TAILSCALE_IPV4}"
  RECREATE_BOUND_SERVICES=1
else
  export TAILSCALE_INTERFACE="${TAILSCALE_INTERFACE:-lo}"
  export TAILSCALE_IPV4="${TAILSCALE_IPV4:-127.0.0.1}"
  export COREDNS_DNS_PORT="${COREDNS_DNS_PORT:-1053}"
  export COREDNS_BIND_IP="${COREDNS_BIND_IP:-127.0.0.1}"
  export NGINX_BIND_IP="${NGINX_BIND_IP:-127.0.0.1}"
  export NGINX_HTTP_PORT="${NGINX_HTTP_PORT:-8080}"
  export POSTGRES_BIND_IP="${POSTGRES_BIND_IP:-127.0.0.1}"
  export REDIS_BIND_IP="${REDIS_BIND_IP:-127.0.0.1}"
  RECREATE_BOUND_SERVICES=0
fi

write_managed_env_block

if [[ "$RECREATE_BOUND_SERVICES" -eq 1 ]]; then
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_BASE" -f "$COMPOSE_OVERLAY" up -d --force-recreate nginx-private coredns pipeline-postgres redis "${COMPOSE_ARGS[@]}"
else
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_BASE" -f "$COMPOSE_OVERLAY" up -d "${COMPOSE_ARGS[@]}"
fi

CORE_ENV_FILE="$ENV_FILE" \
CORE_COMPOSE_OVERLAY="$COMPOSE_OVERLAY" \
"$ROOT_DIR/ops/scripts/runtime/sync-core-dns.sh"

docker run --rm \
  --network core_core_backend \
  -v "$S3_BUCKETS_SCRIPT:/apply-s3-buckets.py:ro" \
  -v "$S3_BUCKETS_CONTRACT:/buckets.json:ro" \
  -v "$SEAWEED_S3_CONFIG:/seaweed-s3.json:ro" \
  python:3.12-alpine \
  python /apply-s3-buckets.py \
    --contract /buckets.json \
    --seaweed-s3-config /seaweed-s3.json \
    --endpoint http://seaweedfs:8333 \
    --wait-timeout 120 \
    --wait-interval 3
