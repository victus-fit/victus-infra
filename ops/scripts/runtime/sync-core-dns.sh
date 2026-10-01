#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/../compose.yml" ]]; then
  PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
  ENV_FILE="${CORE_ENV_FILE:-/srv/secrets/runtime/core.env}"
  COMPOSE_BASE="$PROJECT_DIR/compose.yml"
  COMPOSE_OVERLAY="${CORE_COMPOSE_OVERLAY:-$PROJECT_DIR/compose.prod.yml}"
else
  ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  PROJECT_DIR="$ROOT_DIR/compose/projects/core"
  ENV_FILE="${CORE_ENV_FILE:-$PROJECT_DIR/.env}"
  COMPOSE_BASE="$PROJECT_DIR/compose.yml"
  COMPOSE_OVERLAY="${CORE_COMPOSE_OVERLAY:-$PROJECT_DIR/compose.dev.yml}"
fi

TAILSCALE_INTERFACE="${TAILSCALE_INTERFACE:-tailscale0}"
DNS_ZONE="${DNS_ZONE:-victus.io}"
S3_DOMAIN="${S3_DOMAIN:-s3.$DNS_ZONE}"
POSTGRES_DOMAIN="${POSTGRES_DOMAIN:-pipeline-postgres.$DNS_ZONE}"
REDIS_DOMAIN="${REDIS_DOMAIN:-redis.$DNS_ZONE}"
LITELLM_DOMAIN="${LITELLM_DOMAIN:-litellm.$DNS_ZONE}"
PHOENIX_DOMAIN="${PHOENIX_DOMAIN:-phoenix.$DNS_ZONE}"
ETCD_PREFIX="${ETCD_PREFIX:-/skydns}"
DNS_TTL="${DNS_TTL:-30}"
ETCD_SERVICE_NAME="${ETCD_SERVICE_NAME:-etcd}"
COREDNS_SERVICE_NAME="${COREDNS_SERVICE_NAME:-coredns}"

if [[ "${COMPOSE_OVERLAY##*/}" == "compose.prod.yml" ]]; then
  DEFAULT_COREDNS_DNS_PORT=53
else
  DEFAULT_COREDNS_DNS_PORT=1053
fi

COREDNS_DNS_PORT="${COREDNS_DNS_PORT:-$DEFAULT_COREDNS_DNS_PORT}"

log() { echo "[INFO] $*"; }
err() {
  echo "[ERROR] $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || err "Missing command: $1"
}

require_file() {
  [[ -f "$1" ]] || err "Missing file: $1"
}

ensure_file() {
  local path="$1"

  mkdir -p "$(dirname "$path")"
  touch "$path"
}

env_value() {
  local key="$1"
  local value

  value="$(awk -F= -v key="$key" '
    /^# BEGIN managed: core-private-dns$/ { skip=1; next }
    /^# END managed: core-private-dns$/ { skip=0; next }
    skip == 0 && $1 == key { value = substr($0, length(key) + 2) }
    END { print value }
  ' "$ENV_FILE" 2>/dev/null || true)"
  printf '%s' "$value"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

tailscale_ipv4() {
  ip -4 addr show dev "$TAILSCALE_INTERFACE" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1
}

public_ipv4() {
  ip -4 route get 1.1.1.1 | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}'
}

etcd_put() {
  local key="$1"
  local value="$2"

  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_BASE" -f "$COMPOSE_OVERLAY" \
    exec -T "$ETCD_SERVICE_NAME" \
    etcdctl --endpoints=http://127.0.0.1:2379 put "$key" "$value"
}

etcd_healthy() {
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_BASE" -f "$COMPOSE_OVERLAY" \
    exec -T "$ETCD_SERVICE_NAME" \
    etcdctl --endpoints=http://127.0.0.1:2379 endpoint health >/dev/null 2>&1
}

skydns_key_for_name() {
  local name="${1%.}"
  local IFS=.
  local -a labels
  local key="$ETCD_PREFIX"
  local i

  read -r -a labels <<< "$name"
  for ((i = ${#labels[@]} - 1; i >= 0; i--)); do
    key="$key/${labels[$i]}"
  done

  printf '%s/x1' "$key"
}

wait_for_etcd() {
  local attempts=30
  local delay=2
  local i

  for ((i = 1; i <= attempts; i++)); do
    if etcd_healthy; then
      return 0
    fi
    sleep "$delay"
  done

  err "etcd did not become healthy after $((attempts * delay)) seconds"
}

compose_up() {
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_BASE" -f "$COMPOSE_OVERLAY" up -d "$@"
}

write_managed_env_block() {
  local target="$1"
  local tmp_file

  tmp_file="$(mktemp)"
  awk '
    BEGIN { skip=0 }
    /^# BEGIN managed: core-private-dns$/ { skip=1; next }
    /^# END managed: core-private-dns$/ { skip=0; next }
    $1 ~ /^(TAILSCALE_INTERFACE|TAILSCALE_IPV4|DNS_ZONE|ETCD_PREFIX|DNS_TTL|COREDNS_BIND_IP|COREDNS_DNS_PORT|NGINX_BIND_IP|NGINX_HTTP_PORT|NGINX_PUBLIC_BIND_IP|NGINX_PUBLIC_HTTP_PORT|NGINX_PUBLIC_HTTPS_PORT|S3_DOMAIN|POSTGRES_DOMAIN|POSTGRES_BIND_IP|POSTGRES_PORT|REDIS_DOMAIN|REDIS_BIND_IP|REDIS_PORT|LITELLM_DOMAIN|PHOENIX_DOMAIN)=/ { next }
    skip == 0 { print }
  ' "$target" > "$tmp_file"

  cat >> "$tmp_file" <<EOF
# BEGIN managed: core-private-dns
TAILSCALE_INTERFACE=$TAILSCALE_INTERFACE
TAILSCALE_IPV4=$TAILSCALE_IP
DNS_ZONE=$DNS_ZONE
ETCD_PREFIX=$ETCD_PREFIX
DNS_TTL=$DNS_TTL
COREDNS_BIND_IP=$TAILSCALE_IP
COREDNS_DNS_PORT=$COREDNS_DNS_PORT
NGINX_BIND_IP=${NGINX_BIND_IP:-$TAILSCALE_IP}
NGINX_HTTP_PORT=${NGINX_HTTP_PORT:-8080}
NGINX_PUBLIC_BIND_IP=${NGINX_PUBLIC_BIND_IP:-$PUBLIC_IP}
NGINX_PUBLIC_HTTP_PORT=${NGINX_PUBLIC_HTTP_PORT:-80}
NGINX_PUBLIC_HTTPS_PORT=${NGINX_PUBLIC_HTTPS_PORT:-443}
S3_DOMAIN=$S3_DOMAIN
POSTGRES_DOMAIN=$POSTGRES_DOMAIN
POSTGRES_BIND_IP=${POSTGRES_BIND_IP:-$TAILSCALE_IP}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
REDIS_DOMAIN=$REDIS_DOMAIN
REDIS_BIND_IP=${REDIS_BIND_IP:-$TAILSCALE_IP}
REDIS_PORT=${REDIS_PORT:-6379}
LITELLM_DOMAIN=$LITELLM_DOMAIN
PHOENIX_DOMAIN=$PHOENIX_DOMAIN
# END managed: core-private-dns
EOF

  mv "$tmp_file" "$target"
  chmod 600 "$target"
}

require_cmd docker
require_cmd ip
require_file "$COMPOSE_BASE"
require_file "$COMPOSE_OVERLAY"
ensure_file "$ENV_FILE"

NGINX_BIND_IP="${NGINX_BIND_IP:-$(env_value NGINX_BIND_IP)}"
NGINX_HTTP_PORT="${NGINX_HTTP_PORT:-$(env_value NGINX_HTTP_PORT)}"
NGINX_PUBLIC_BIND_IP="${NGINX_PUBLIC_BIND_IP:-$(env_value NGINX_PUBLIC_BIND_IP)}"
NGINX_PUBLIC_HTTP_PORT="${NGINX_PUBLIC_HTTP_PORT:-$(env_value NGINX_PUBLIC_HTTP_PORT)}"
NGINX_PUBLIC_HTTPS_PORT="${NGINX_PUBLIC_HTTPS_PORT:-$(env_value NGINX_PUBLIC_HTTPS_PORT)}"

TAILSCALE_IP="${TAILSCALE_IPV4:-}"
if [[ -z "$TAILSCALE_IP" ]]; then
  TAILSCALE_IP="$(tailscale_ipv4)"
fi
[[ -n "$TAILSCALE_IP" ]] || err "No IPv4 found on interface $TAILSCALE_INTERFACE"

PUBLIC_IP="${NGINX_PUBLIC_BIND_IP:-}"
if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "0.0.0.0" ]]; then
  PUBLIC_IP="$(public_ipv4)"
fi
[[ -n "$PUBLIC_IP" ]] || err "No public IPv4 could be derived for nginx-public"

write_managed_env_block "$ENV_FILE"

STORAGE_KEY="$(skydns_key_for_name "$S3_DOMAIN")"
POSTGRES_KEY="$(skydns_key_for_name "$POSTGRES_DOMAIN")"
REDIS_KEY="$(skydns_key_for_name "$REDIS_DOMAIN")"
LITELLM_KEY="$(skydns_key_for_name "$LITELLM_DOMAIN")"
PHOENIX_KEY="$(skydns_key_for_name "$PHOENIX_DOMAIN")"

# TTL low on purpose. Tailscale IP can change on node/network events; 30s keeps
# client-side cache short without creating extreme DNS churn.
STORAGE_VALUE="$(printf '{"host":"%s","ttl":%s}' "$(json_escape "$TAILSCALE_IP")" "$(json_escape "$DNS_TTL")")"
POSTGRES_VALUE="$STORAGE_VALUE"
REDIS_VALUE="$STORAGE_VALUE"
LITELLM_VALUE="$STORAGE_VALUE"
PHOENIX_VALUE="$STORAGE_VALUE"

log "Detected Tailscale IPv4: $TAILSCALE_IP"
log "Detected public IPv4: $PUBLIC_IP"
log "Updated runtime env file: $ENV_FILE"
log "Ensuring DNS services are running with current bind IP"
compose_up "$ETCD_SERVICE_NAME"
wait_for_etcd
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_BASE" -f "$COMPOSE_OVERLAY" up -d --force-recreate "$COREDNS_SERVICE_NAME"
log "Syncing SkyDNS records under $ETCD_PREFIX for zone $DNS_ZONE"

etcd_put "$STORAGE_KEY" "$STORAGE_VALUE"
etcd_put "$POSTGRES_KEY" "$POSTGRES_VALUE"
etcd_put "$REDIS_KEY" "$REDIS_VALUE"
etcd_put "$LITELLM_KEY" "$LITELLM_VALUE"
etcd_put "$PHOENIX_KEY" "$PHOENIX_VALUE"

log "Updated records:"
log "  $S3_DOMAIN -> $TAILSCALE_IP"
log "  *.$S3_DOMAIN -> $TAILSCALE_IP (CoreDNS template)"
log "  $POSTGRES_DOMAIN -> $TAILSCALE_IP"
log "  $REDIS_DOMAIN -> $TAILSCALE_IP"
log "  $LITELLM_DOMAIN -> $TAILSCALE_IP"
log "  $PHOENIX_DOMAIN -> $TAILSCALE_IP"
