# Shared Environment Configuration

## Overview

Ralph's database credentials are currently passed via the `RALPH_DB_URL` environment variable, which users must manually export in their shell. The `docker-compose.yml` duplicates the same credentials as hardcoded values. This spec introduces a single `.env` file as the shared source of truth for database configuration across `docker-compose.yml`, `ralph.sh`, and the `task` CLI.

## Requirements

- A `.env.example` file is tracked in git with default values: `POSTGRES_USER=ralph`, `POSTGRES_PASSWORD=ralph`, `POSTGRES_DB=ralph`, `POSTGRES_PORT=5499`, `RALPH_DB_URL=postgres://ralph:ralph@localhost:5499/ralph`.
- The actual `.env` file is git-ignored (added to `.gitignore`).
- If `.env` does not exist when `ralph.sh` runs, it is auto-copied from `.env.example` with an informational message. If `.env.example` is also missing, a warning is printed but execution continues (the user may have set `RALPH_DB_URL` manually).
- `docker-compose.yml` references the `.env` file via `env_file: .env` and uses `${POSTGRES_PORT:-5499}` interpolation for the port mapping so compose works even without `.env`.
- `ralph.sh` sources `$SCRIPT_DIR/.env` after ensuring it exists, which sets `RALPH_DB_URL` and `POSTGRES_*` variables.
- The `task` script's `db_check()` function attempts to source `$script_dir/.env` as a fallback when `RALPH_DB_URL` is not already set. If `RALPH_DB_URL` is already set in the environment, the `.env` file is not sourced (backwards compatible).
- The `task` script resolves its own directory following symlinks (for `~/.local/bin/task`) to locate `.env` relative to the repo root.
- The error message in `task` `db_check()` is updated to suggest `cp .env.example .env` as the fix.

## Constraints

- `.env` must never be committed to git — it is excluded via `.gitignore`.
- `.env.example` must always be committed so new clones have a working template.
- Existing workflows that set `RALPH_DB_URL` directly in the shell must continue to work without changes (the `.env` sourcing is a fallback, not a requirement).
- The `.env` file uses simple `KEY=VALUE` syntax compatible with both `source` (bash) and docker-compose `env_file`.

## Out of Scope

- Secrets management, encryption, or vault integration.
- Multiple environment profiles (dev, staging, production).
- Non-database configuration in `.env` (model selection, backend flags, etc. remain in their current locations).
