#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$ROOT_DIR/ansible"
ansible-playbook -i inventories/production/syntax-check.yml --syntax-check playbooks/deploy-app.yml
