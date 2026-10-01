#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log() { echo "[INFO] $*"; }
err() {
	echo "[ERROR] $*" >&2
	exit 1
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || err "Missing command: $1"
}

require_file() {
	local path="$1"
	[[ -f "$path" ]] || err "Missing file: $path"
}

require_dir() {
	local path="$1"
	[[ -d "$path" ]] || err "Missing dir: $path"
}

validate_stack() {
	local stack="$1"
	local stack_dir="$ROOT_DIR/compose/projects/$stack"
	local env_file="$stack_dir/.env"
	local env_example="$ROOT_DIR/compose/env/${stack}.env.example"
	local compose_base="$stack_dir/compose.yml"
	local compose_overlay="$stack_dir/compose.dev.yml"

	log "Validating stack: $stack"

	if [[ ! -f "$env_file" ]]; then
		env_file="$env_example"
	fi
	require_file "$env_file"
	require_file "$compose_base"
	require_file "$compose_overlay"

	log "$stack: docker compose config"
	if [[ "$stack" == "app" ]]; then
		APP_RUNTIME_ENV_FILE=/dev/null docker compose --env-file "$env_file" -f "$compose_base" -f "$compose_overlay" config >/dev/null
	else
		docker compose --env-file "$env_file" -f "$compose_base" -f "$compose_overlay" config >/dev/null
	fi

	log "$stack: compose rendered OK"
}

validate_nginx() {
	local nginx_conf="$ROOT_DIR/compose/configs/nginx/nginx.conf"
	local nginx_private_conf_dir="$ROOT_DIR/compose/configs/nginx/conf.d"
	local nginx_public_conf_dir="$ROOT_DIR/compose/configs/nginx/public/conf.d"
	local nginx_snippets_dir="$ROOT_DIR/compose/configs/nginx/snippets"

	require_file "$nginx_conf"
	require_dir "$nginx_private_conf_dir"
	require_dir "$nginx_public_conf_dir"
	require_dir "$nginx_snippets_dir"

	log "Validating private nginx config"
	docker run --rm \
		--add-host seaweedfs:127.0.0.1 \
		--add-host prometheus:127.0.0.1 \
		--add-host loki:127.0.0.1 \
		-v "$nginx_conf:/etc/nginx/nginx.conf:ro" \
		-v "$nginx_private_conf_dir:/etc/nginx/conf.d:ro" \
		-v "$nginx_snippets_dir:/etc/nginx/snippets:ro" \
		nginx:1.28.3-alpine nginx -t

	log "Validating public nginx config"
	docker run --rm \
		-v "$nginx_conf:/etc/nginx/nginx.conf:ro" \
		-v "$nginx_public_conf_dir:/etc/nginx/conf.d:ro" \
		-v "$nginx_snippets_dir:/etc/nginx/snippets:ro" \
		nginx:1.28.3-alpine nginx -t
}

validate_coredns() {
	local coredns_corefile="$ROOT_DIR/compose/configs/coredns/Corefile"
	local status=0

	require_file "$coredns_corefile"

	log "Validating CoreDNS Corefile"
	timeout 3s docker run --rm \
		-v "$coredns_corefile:/etc/coredns/Corefile:ro" \
		coredns/coredns:1.14.2 -conf /etc/coredns/Corefile -dns.port 1053 >/dev/null 2>&1 || status=$?
	[[ "$status" -eq 124 ]] || err "CoreDNS Corefile validation failed"
}

validate_seaweed_s3_config() {
	local s3_config="$ROOT_DIR/compose/configs/seaweedfs/s3.json.example"
	local buckets_config="$ROOT_DIR/compose/configs/seaweedfs/buckets.json"

	require_file "$s3_config"
	require_file "$buckets_config"

	log "Validating SeaweedFS S3 config example"
	python3 -m json.tool "$s3_config" >/dev/null

	log "Validating SeaweedFS bucket contract"
	python3 -m json.tool "$buckets_config" >/dev/null
	python3 -m py_compile "$ROOT_DIR/ops/scripts/runtime/apply-s3-buckets.py"
}

validate_litellm_config_renderer() {
	local renderer="$ROOT_DIR/ops/scripts/runtime/render-litellm-config.py"
	local env_file
	local rendered_config

	require_file "$renderer"
	python3 -m py_compile "$renderer"

	env_file="$(mktemp)"
	rendered_config="$(mktemp)"
	trap 'rm -f "$env_file" "$rendered_config"; trap - RETURN' RETURN

	cat >"$env_file" <<'EOF'
LITELLM_MASTER_KEY=sk-test
KEY_GEMINI_FLASH_LITE_01=dummy-key-1
KEY_GEMINI_FLASH_LITE_02=dummy-key-2
LITELLM_DEPLOYMENTS_JSON=[{"model_name":"gemini-flash-lite","model":"gemini/gemini-3.1-flash-lite","api_key_env":"KEY_GEMINI_FLASH_LITE_01","rpm":15,"tpm":100000},{"model_name":"gemini-flash-lite","model":"gemini/gemini-3.1-flash-lite","api_key_env":"KEY_GEMINI_FLASH_LITE_02","rpm":15,"tpm":100000}]
EOF

	log "Validating LiteLLM multi-key routing render"
	"$renderer" --env-file "$env_file" "$rendered_config"
	[[ "$(grep -c 'model_name: "gemini-flash-lite"' "$rendered_config")" -eq 2 ]] || err "LiteLLM renderer did not emit two deployments for the shared model_name"
	grep -q "api_key: os.environ/KEY_GEMINI_FLASH_LITE_01" "$rendered_config" || err "LiteLLM renderer missing first provider key reference"
	grep -q "api_key: os.environ/KEY_GEMINI_FLASH_LITE_02" "$rendered_config" || err "LiteLLM renderer missing second provider key reference"
	grep -q "routing_strategy: simple-shuffle" "$rendered_config" || err "LiteLLM renderer missing simple-shuffle routing"
}

validate_required_dirs() {
	local dirs=(
		"$ROOT_DIR/compose/.tmp/core/nginx-private/logs"
		"$ROOT_DIR/compose/.tmp/core/nginx-public/logs"
		"$ROOT_DIR/compose/.tmp/core/seaweedfs/data"
		"$ROOT_DIR/compose/.tmp/core/etcd/data"
		"$ROOT_DIR/compose/.tmp/core/pipeline-postgres/data"
		"$ROOT_DIR/compose/.tmp/core/redis/data"
		"$ROOT_DIR/compose/.tmp/observability/loki"
		"$ROOT_DIR/compose/.tmp/observability/prometheus"
		"$ROOT_DIR/compose/.tmp/llm/postgres/data"
		"$ROOT_DIR/compose/.tmp/wiki/postgres"
		"$ROOT_DIR/compose/.tmp/app/app-postgres"
		"$ROOT_DIR/compose/.tmp/app/agent-postgres"
		"$ROOT_DIR/compose/.tmp/app/qdrant"
		"$ROOT_DIR/compose/.tmp/app/phoenix"
	)

	for dir in "${dirs[@]}"; do
		mkdir -p "$dir"
		require_dir "$dir"
	done
}

require_cmd docker
require_cmd python3
require_cmd timeout
validate_stack core
validate_stack observability
validate_stack llm
validate_stack wiki
validate_stack app
validate_required_dirs
validate_seaweed_s3_config
validate_litellm_config_renderer
validate_nginx
validate_coredns

log "Local validation OK"
