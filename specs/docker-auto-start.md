# Docker Auto-Start

## Overview

Ralph plan and build both require a running PostgreSQL server, but currently users must start the Docker container manually before invoking `ralph`. This spec adds automatic container lifecycle management to `ralph.sh` so that the database is guaranteed to be running and healthy before any iteration begins.

## Requirements

- `ralph.sh` checks that `docker` CLI and `docker compose` (V2 plugin) are available before proceeding. If either is missing, it exits 1 with an actionable error message naming what is missing.
- If the `ralph-task-db` container is not running, `ralph.sh` starts it via `docker compose up -d` using `$SCRIPT_DIR/docker-compose.yml` with `--project-directory "$SCRIPT_DIR"` so the command works regardless of the caller's working directory.
- If the container is already running, `ralph.sh` skips the startup step.
- After startup (or when already running), `ralph.sh` waits for the container to be healthy using both `docker inspect` health status AND `pg_isready` (belt-and-suspenders).
- The health check polls with a configurable timeout (default 30 seconds, overridable via `DOCKER_HEALTH_TIMEOUT` for tests). If the timeout expires, `ralph.sh` exits 1 with a timeout error.
- The PostgreSQL container listens on host port **5499** (not the default 5499) to avoid conflicts with any local PostgreSQL instance.
- The Docker service is named `ralph-task-db` with `container_name: ralph-task-db`.
- The data volume is named `ralph-task-data` and persists between runs (not ephemeral).
- The `docker-compose.yml` mounts `./db/init/` to `/docker-entrypoint-initdb.d/:ro` for schema initialization on first boot.
- The database schema SQL file lives at `db/init/001-schema.sql`, extracted from the `task` script's `ensure_schema()` function. It uses `CREATE TABLE IF NOT EXISTS` for idempotency.
- The `task` script retains its own `ensure_schema()` call for backwards compatibility with databases not initialized via Docker entrypoint.
- BATS tests bypass Docker checks by prepending a `STUB_DIR` to `PATH` containing fake `docker` and `pg_isready` scripts (same PATH-stub pattern used for other external commands). This exercises the real code paths in `ensure_postgres()` without requiring a running Docker daemon.

## Constraints

- Must use `docker compose` V2 (plugin), not the legacy `docker-compose` standalone binary.
- The `--project-directory "$SCRIPT_DIR"` flag is required on all `docker compose` invocations because `ralph.sh` may be invoked from any working directory (especially via the `~/.local/bin/ralph` symlink).
- macOS `readlink` does not support `-f`; symlink resolution must use a portable `while [ -L ... ]` loop.
- Image is `postgres:17-alpine` (already in use).
- Database credentials are `ralph/ralph/ralph` (user/password/database).

## Out of Scope

- Remote database connections or cloud-managed PostgreSQL.
- Docker image builds or custom Dockerfiles.
- Database migration tooling beyond the idempotent `CREATE TABLE IF NOT EXISTS` pattern.
- Container orchestration (Kubernetes, ECS, etc.).
- A `--reset-db` flag or data migration from the old `ralph_pgdata` volume.
