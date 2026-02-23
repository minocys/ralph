# Container Entrypoint & Setup

## Overview

The `ralph-worker` container needs a setup phase before it can run ralph loops. The entrypoint script bootstraps the container environment — installing skills, configuring hooks, and preparing the ralph tooling — so the container is self-contained and does not require pre-configuration on the host.

## Requirements

- The entrypoint script is located at `docker/entrypoint.sh` in the ralph repository and is copied into the image at build time.
- On container start, the entrypoint runs `install.sh` (or an equivalent subset) to:
  - Symlink ralph skills into `~/.claude/skills/` inside the container.
  - Symlink `ralph.sh` and `task` into a directory on `$PATH` (e.g., `/usr/local/bin/`).
  - Configure Claude Code hooks (`PreCompact`, `SessionEnd`) in the container's `~/.claude/settings.json`, merging with any settings from the bind-mounted `~/.claude`.
- After setup, the entrypoint keeps the container running (e.g., via `exec tail -f /dev/null` or `exec sleep infinity`) so the user can `docker exec` into it to start ralph loops for different projects.
- The entrypoint validates that required environment variables are present (`RALPH_DB_URL` or individual `POSTGRES_*` vars). If missing, it prints an actionable error and exits 1.
- The entrypoint sources the `.env` file from the ralph installation directory to set database connection defaults.
- The entrypoint sets `RALPH_DB_URL` to use the internal Docker network address (`postgres://ralph:ralph@ralph-task-db:5432/ralph`) unless `RALPH_DB_URL` is already set in the environment.
- If the `/workspace` directory is empty (no project mounted), the entrypoint prints a warning but does not exit — the user may mount projects later via `docker exec`.

## Constraints

- The entrypoint must be idempotent — running it multiple times (e.g., container restart) must not duplicate symlinks or corrupt settings.
- The entrypoint must complete in under 5 seconds on a warm container (no network fetches or package installs at runtime).
- The entrypoint must not modify the bind-mounted `~/.claude` directory on the host (read-only mount). It should copy or merge settings into a container-local path if modifications are needed.
- The entrypoint must work with the `ralph` non-root user (UID 1000).

## Out of Scope

- Automatic project detection or discovery inside `/workspace`.
- Running ralph loops automatically on container start (the container is long-lived; loops are started via `docker exec`).
- Health check endpoints or readiness probes for the worker container.
- Log aggregation or structured logging from the entrypoint.
