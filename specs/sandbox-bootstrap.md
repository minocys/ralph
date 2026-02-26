# Sandbox Bootstrap

## Overview

When a Docker sandbox is created for the first time, it needs ralph installed, PostgreSQL running, and environment configured before any ralph command can execute. This one-time bootstrap runs after sandbox creation and persists across stop/start cycles.

## Requirements

### Sandbox creation

- The sandbox is created with `docker sandbox create -t docker/sandbox-templates:claude-code --name <name> shell <target-repo-dir> <ralph-docker-dir>:ro`.
- `<target-repo-dir>` is the absolute path to the user's git working directory (the repo ralph will work on). This is mounted read-write with bidirectional file sync.
- `<ralph-docker-dir>` is the absolute path to the ralph-docker repository on the host. This is mounted read-only (`:ro` suffix).
- The `shell` agent type is used because ralph orchestrates Claude Code itself.
- The `docker/sandbox-templates:claude-code` template provides Claude Code, Docker CLI, Node.js, Python 3, Git, and other development tools.

### Ralph installation

- After creation, the sandbox is started with `docker sandbox run <name>`.
- Ralph is installed via `docker sandbox exec <name> bash -c '<install commands>'`.
- The install commands must:
  1. Copy `ralph.sh` from the read-only mount to `/usr/local/bin/ralph` and make it executable.
  2. Copy the `lib/` directory to a writable location (e.g., `/opt/ralph/lib/`).
  3. Copy `models.json` to the same writable location.
  4. Copy the `skills/` directory to `~/.claude/skills/`.
  5. Copy the `hooks/` directory to a writable location and configure Claude Code hooks.
  6. Install `jq` if not already present (the claude-code template may include it; install as fallback).
  7. Install `psql` client for database access (`postgresql-client` package).
- The install must adapt `ralph.sh`'s `SCRIPT_DIR` resolution so it points to the writable copy location, not the read-only mount.

### PostgreSQL setup

- A Docker Compose file is generated at `~/.ralph/docker-compose.yml` inside the sandbox during bootstrap.
- The compose file defines a `ralph-task-db` service using `postgres:17-alpine` with the same configuration as the host compose file: port 5499, credentials `ralph/ralph/ralph`, healthcheck, and a data volume.
- The compose file includes an `init` volume mount that points to the schema SQL file copied during installation.
- The `.env` file is generated at `~/.ralph/.env` inside the sandbox with the same defaults as `.env.example`.
- PostgreSQL is started via `docker compose -f ~/.ralph/docker-compose.yml up -d` inside the sandbox.
- The bootstrap waits for PostgreSQL to be healthy before completing (same healthcheck polling as the host's `ensure_postgres()`).

### Bootstrap marker

- A marker file is written at `~/.ralph/.bootstrapped` after successful bootstrap completion.
- Before running bootstrap, the dispatch code checks for this marker via `docker sandbox exec <name> test -f ~/.ralph/.bootstrapped`.
- If the marker exists, bootstrap is skipped entirely (idempotent re-entry).
- This allows `docker sandbox run` to restart a stopped sandbox without re-running bootstrap.

### PostgreSQL lifecycle on restart

- When a stopped sandbox is restarted, the internal Docker daemon resumes. Containers that were running inside the sandbox when it stopped are restarted automatically by Docker.
- The dispatch code does not need to explicitly restart PostgreSQL after a sandbox restart — Docker's restart policy handles this.
- The `ensure_postgres()` function called by ralph inside the sandbox provides a secondary healthcheck before proceeding.

### RALPH_SKIP_DOCKER passthrough

- When ralph runs inside the sandbox, it should NOT try to manage an external Docker container for PostgreSQL via the host's `docker-compose.yml`. The sandbox has its own compose setup.
- The internal ralph installation must be configured so that `ensure_postgres()` uses the sandbox-local compose file (`~/.ralph/docker-compose.yml`), not the read-only mount's compose file.

## Constraints

- Bootstrap must complete in a single `docker sandbox exec` session (or a small number of sequential execs). Each exec is a separate process invocation.
- The sandbox's internal Docker daemon starts automatically with the sandbox VM — no manual daemon startup is needed.
- The `postgres:17-alpine` image must be pulled inside the sandbox (the sandbox has its own image registry, separate from the host).
- The first PostgreSQL start inside a sandbox may be slow due to image pull. This is a one-time cost.
- The `claude-code` template runs as non-root `agent` user with `sudo` access. Installation commands that need root (e.g., `apt-get install`) must use `sudo`.

## Out of Scope

- Upgrading ralph inside an existing sandbox (user recreates the sandbox for updates).
- Custom PostgreSQL configuration (tuning, extensions).
- Persisting the PostgreSQL data volume across sandbox removal (sandbox removal deletes everything).
- Building custom sandbox templates with ralph pre-baked.
