# Docker Removal

Remove Docker, docker-compose, and PostgreSQL infrastructure from Ralph, replacing it with zero-dependency SQLite initialization.

## Overview

Ralph currently depends on Docker to run a PostgreSQL container (`ralph-task-db-dev`). With the move to SQLite, Docker is no longer needed. This spec covers deleting Docker-related files, removing Docker checks from `ralph.sh`, simplifying environment configuration, and updating the install script.

## Requirements

### Files to Delete

- `docker-compose.yml` — no longer needed; the database is a local file
- `lib/docker.sh` — `ensure_postgres()`, `check_docker_installed()`, `is_container_running()`, `wait_for_healthy()` are all PostgreSQL/Docker-specific
- `db/init/001-schema.sql` — the PostgreSQL-dialect schema; replaced by `ensure_schema()` in `lib/task` using SQLite syntax (a reference copy may be kept as `db/schema.sql` for documentation, but is not operationally used)

### ralph.sh Changes

- Remove the `source "$SCRIPT_DIR/lib/docker.sh"` line
- Remove all calls to `ensure_postgres()` in the plan and build loop setup
- Remove Docker prerequisite checks (`check_docker_installed`, `is_container_running`, `wait_for_healthy`)
- Add `sqlite3` availability check: if `sqlite3` is not on PATH, exit 1 with message `"Error: sqlite3 is required but not installed."` and platform-specific install instructions
- The `load_env()` function in `ralph.sh` is simplified: it sources `.env` for `RALPH_DB_PATH` (if set), but the database works without `.env` using the default path

### Environment Configuration

- `.env.example` is updated — remove all `POSTGRES_*` variables and `RALPH_DB_URL`; add `RALPH_DB_PATH` with a comment noting it is optional (defaults to `.ralph/tasks.db`):
  ```
  # Optional: override the default database location (.ralph/tasks.db)
  # RALPH_DB_PATH=/path/to/custom/tasks.db
  ```
- `.env` remains git-ignored
- `RALPH_DB_URL` is no longer read or referenced anywhere
- `RALPH_SKIP_DOCKER` environment variable is removed (no Docker to skip)
- `DOCKER_HEALTH_TIMEOUT` environment variable is removed

### install.sh Changes

- Remove the `jq` dependency check — `jq` was only needed for editing `~/.claude/settings.json` with hooks; if hooks configuration still uses `jq`, keep it; otherwise remove
- Add a `sqlite3` availability check with version verification (minimum 3.35 for `RETURNING` support)
- The install script no longer needs to handle any Docker setup

### Database Initialization

- Replace `ensure_postgres()` (Docker startup) with `ensure_db()` (SQLite file creation):
  1. Resolve `RALPH_DB_PATH` (from env or default `$REPO_ROOT/.ralph/tasks.db`)
  2. Create parent directory if it does not exist (`mkdir -p`)
  3. Call `ensure_schema()` which runs `CREATE TABLE IF NOT EXISTS` statements via `sqlite3`
- `ensure_db()` is called at the start of every `ralph task` invocation (same as current `ensure_schema()` pattern)
- No health checks, no polling, no timeouts — SQLite is immediately available

### .gitignore Update

- Add `.ralph/` to `.gitignore` (the database directory)
- The existing `.env` ignore entry remains

### Test Infrastructure

- BATS test helpers that stub Docker commands (`STUB_DIR` with fake `docker` and `pg_isready`) are removed
- BATS tests that start/stop PostgreSQL containers are replaced with tests that create/destroy temporary SQLite database files
- Test setup creates a temp directory, sets `RALPH_DB_PATH` to a file in that directory, and test teardown deletes it
- No network, no containers, no port binding — tests run faster and with no external dependencies

## Constraints

- `sqlite3` CLI must be present on the system PATH — Ralph cannot bundle or install it
- macOS ships sqlite3 with the OS (Xcode CLT); Linux provides it via `sqlite3` or `libsqlite3-dev` packages
- The `.ralph/` directory is per-repository (created inside the repo root), not global — this matches the current scoping model where each repo has its own task state
- Removing Docker support is permanent — there is no fallback to PostgreSQL

## Out of Scope

- Providing a Docker-based SQLite setup (defeats the purpose)
- Migrating existing PostgreSQL data to SQLite
- Supporting both PostgreSQL and SQLite simultaneously
- Bundling or auto-installing sqlite3
