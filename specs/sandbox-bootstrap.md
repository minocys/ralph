# Sandbox Bootstrap

## Overview

When a Docker sandbox is created for the first time, it needs ralph installed, `sqlite3` available, and environment configured before any ralph command can execute. This one-time bootstrap runs after sandbox creation and persists across stop/start cycles.

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
  7. Install `sqlite3` if not already present (`sudo apt-get update && sudo apt-get install -y sqlite3`). Verify version >= 3.35 (required for `RETURNING` clause support).
- The install must adapt `ralph.sh`'s `SCRIPT_DIR` resolution so it points to the writable copy location, not the read-only mount.

### SQLite verification

- After installing `sqlite3`, the bootstrap must verify the version meets the minimum requirement (3.35) using the same check as `install.sh` on the host: `sqlite3 --version` and parse the major.minor version.
- If the installed version is below 3.35, the bootstrap must exit 1 with an error message stating the minimum required version.
- No database file is created during bootstrap — SQLite databases are created on-demand by `ensure_db()` when ralph runs its first command inside the sandbox.
- No healthcheck, no polling, no compose files — SQLite is immediately available once the binary is on PATH.

### Bootstrap marker

- A marker file is written at `~/.ralph/.bootstrapped` after successful bootstrap completion.
- Before running bootstrap, the dispatch code checks for this marker via `docker sandbox exec <name> test -f ~/.ralph/.bootstrapped`.
- If the marker exists, bootstrap is skipped entirely (idempotent re-entry).
- This allows `docker sandbox run` to restart a stopped sandbox without re-running bootstrap.

### SQLite persistence on restart

- When a stopped sandbox is restarted, the sandbox filesystem is preserved. The SQLite database file (`.ralph/tasks.db` inside the target repo directory) persists across stop/start cycles automatically.
- No explicit database startup or recovery is needed after a sandbox restart — SQLite is a file, not a server.
- The `ensure_db()` function called by ralph inside the sandbox creates the database and schema if the file does not yet exist, and is a no-op if it already exists.

## Constraints

- Bootstrap must complete in a single `docker sandbox exec` session (or a small number of sequential execs). Each exec is a separate process invocation.
- The `claude-code` template runs as non-root `agent` user with `sudo` access. Installation commands that need root (e.g., `apt-get install`) must use `sudo`.
- The sandbox's internal Docker daemon starts automatically with the sandbox VM but is not used by ralph itself (ralph uses SQLite, not a containerized database).

## Out of Scope

- Upgrading ralph inside an existing sandbox (user recreates the sandbox for updates).
- Building custom sandbox templates with ralph pre-baked.
- Pre-creating or seeding the SQLite database during bootstrap (it is created on first use by ralph).
