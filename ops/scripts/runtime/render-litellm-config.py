#!/usr/bin/env python3
"""Render LiteLLM runtime config from environment metadata."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"render-litellm-config: {message}", file=sys.stderr)
    raise SystemExit(1)


def quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def load_env_file(path: Path) -> None:
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            fail(f"{path}:{line_number}: expected KEY=VALUE")
        key, value = line.split("=", 1)
        key = key.strip()
        if not key:
            fail(f"{path}:{line_number}: empty key")
        os.environ[key] = value


def positive_int(value: object, field: str, index: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        fail(f"deployment {index}: {field} must be a positive integer")
    return value


def required_string(deployment: dict[str, object], field: str, index: int) -> str:
    value = deployment.get(field)
    if not isinstance(value, str) or not value.strip():
        fail(f"deployment {index}: {field} is required")
    return value.strip()


def load_deployments() -> list[dict[str, object]]:
    raw = os.environ.get("LITELLM_DEPLOYMENTS_JSON")
    if not raw:
        fail("LITELLM_DEPLOYMENTS_JSON is required")

    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"LITELLM_DEPLOYMENTS_JSON is invalid JSON: {exc}")

    if not isinstance(parsed, list):
        fail("LITELLM_DEPLOYMENTS_JSON must be a JSON list")
    if not parsed:
        fail("LITELLM_DEPLOYMENTS_JSON must not be empty")

    deployments: list[dict[str, object]] = []
    for index, item in enumerate(parsed):
        if not isinstance(item, dict):
            fail(f"deployment {index}: must be an object")

        model_name = required_string(item, "model_name", index)
        model = required_string(item, "model", index)
        api_key_env = required_string(item, "api_key_env", index)

        if not api_key_env.startswith("KEY_"):
            fail(f"deployment {index}: api_key_env must start with KEY_")
        if api_key_env not in os.environ:
            fail(f"deployment {index}: api_key_env {api_key_env} is not set")

        deployment: dict[str, object] = {
            "model_name": model_name,
            "model": model,
            "api_key_env": api_key_env,
        }

        for field in ("rpm", "tpm"):
            if field in item:
                deployment[field] = positive_int(item[field], field, index)

        deployments.append(deployment)

    return deployments


def render(deployments: list[dict[str, object]]) -> str:
    lines = ["model_list:"]
    for deployment in deployments:
        lines.extend(
            [
                f"  - model_name: {quote(str(deployment['model_name']))}",
                "    litellm_params:",
                f"      model: {quote(str(deployment['model']))}",
                f"      api_key: os.environ/{deployment['api_key_env']}",
            ]
        )
        if "rpm" in deployment:
            lines.append(f"    rpm: {deployment['rpm']}")
        if "tpm" in deployment:
            lines.append(f"    tpm: {deployment['tpm']}")

    lines.extend(
        [
            "",
            "router_settings:",
            "  routing_strategy: simple-shuffle",
            "  num_retries: 3",
            "  timeout: 180",
            "  enable_pre_call_checks: true",
            "",
            "general_settings:",
            "  master_key: os.environ/LITELLM_MASTER_KEY",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file")
    parser.add_argument("output", nargs="?")
    args = parser.parse_args()

    if args.env_file:
        load_env_file(Path(args.env_file))

    rendered = render(load_deployments())

    if args.output:
        path = Path(args.output)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
