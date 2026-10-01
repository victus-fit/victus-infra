#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

command -v ansible-playbook >/dev/null 2>&1 || {
  echo "Missing ansible-playbook in PATH" >&2
  exit 1
}

bash "$ROOT_DIR/tests/ansible/deploy-syntax-check.sh"
bash "$ROOT_DIR/tests/ansible/deploy-observability-syntax-check.sh"
bash "$ROOT_DIR/tests/ansible/deploy-llm-syntax-check.sh"
bash "$ROOT_DIR/tests/ansible/deploy-wiki-syntax-check.sh"
bash "$ROOT_DIR/tests/ansible/deploy-app-syntax-check.sh"
bash "$ROOT_DIR/tests/ansible/preflight-syntax-check.sh"
bash "$ROOT_DIR/tests/ansible/review-syntax-check.sh"

echo "Infra-Victus Ansible integrity checks OK"
