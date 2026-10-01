# Plans

## 2026-10-01 - Stabilize core apt install during deploy

Goal: prevent the core deploy from losing SSH while apt/dpkg locks are held by
host background package jobs.

Scope:
- Add an explicit, short-interval apt lock wait before installing certbot.
- Add Ansible SSH keepalive settings for long-running remote tasks.
- Document the apt lock failure mode in the deployment runbook.

Assumptions:
- The server may run `apt-daily`, `apt-daily-upgrade`, or another package job
  during the GitHub Actions deploy.
- We should wait for the package manager instead of deleting lock files.

Steps:
1. Make the core role wait for apt/dpkg locks with visible retries.
2. Keep the certbot package install idempotent and reduce its silent lock wait.
3. Enable SSH keepalive in Ansible.
4. Validate Ansible syntax.

Validation:
- `make ansible-check`

Risks:
- If the remote package job hangs indefinitely, the deploy will still fail, but
  it should fail with a clearer lock diagnosis instead of an unreachable SSH
  error.
