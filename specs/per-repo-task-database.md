# Per-Repository Task Database

Store each repository's task database inside that repository, not inside the Ralph repository.

## Overview

The task database (`tasks.db`) is currently stored at `<ralph-repo>/.ralph/tasks.db`, resolved from the `lib/task` script's own filesystem location. This means all task data for every target repository lives inside Ralph's directory tree. This spec moves the database into the target repository being worked on, so each repo carries its own `.ralph/tasks.db`. The path is derived from the current working directory's git root via `git rev-parse --show-toplevel`.

## Requirements

### Database Path Derivation

- The database path is `<target-repo-git-root>/.ralph/tasks.db`, where `<target-repo-git-root>` is the output of `git rev-parse --show-toplevel` run from the current working directory
- `db_check()` in `lib/task` must use `git rev-parse --show-toplevel` instead of resolving the script's own directory
- If the current working directory is not inside a git repository, `db_check()` must exit with code 1 and the message: `Error: not inside a git repository. Run: git init`
- The `.ralph/` directory must be created automatically via `mkdir -p` if it does not exist
- The database file is created automatically by `ensure_schema()` on first invocation (unchanged behavior)

### Remove RALPH_DB_PATH

- The `RALPH_DB_PATH` environment variable is removed entirely — there is no override mechanism for the database path
- `db_check()` must not read `RALPH_DB_PATH` from the environment
- `db_check()` must not source `.env` for database path resolution
- The `.env` sourcing block in `db_check()` (lines 42-49 of current `lib/task`) is removed
- `load_env()` in `lib/config.sh` is removed or simplified — it currently exists solely to source `.env` for `RALPH_DB_PATH`
- `RALPH_DB_PATH` is no longer exported — the resolved path is stored in a local variable or a script-scoped global, but not propagated to child processes via env var
- `.env.example` is updated to remove the `RALPH_DB_PATH` comment

### Auto-Gitignore

- After creating the `.ralph/` directory, `db_check()` must create a `.ralph/.gitignore` file inside the target repository containing a single line: `*`
- This file is only created if it does not already exist (idempotent)
- This approach is self-contained — it does not modify the target repository's root `.gitignore`

### Self-Hosting

- When Ralph works on itself (the target repo is the Ralph repository), the database is stored at `<ralph-repo>/.ralph/tasks.db` — the same physical location as before, but derived via `git rev-parse` instead of script-dir resolution
- No special-casing is needed

### Scoping Columns

- The `scope_repo` and `scope_branch` columns remain in the schema — they continue to scope tasks by branch within a single repository's database
- `scope_repo` is retained for consistency and future-proofing (e.g., if a repo has multiple remotes or forks sharing the same `.ralph/` directory)
- No schema changes are required

### Test Infrastructure

- All BATS tests that set `RALPH_DB_PATH` directly must be updated to use the new derivation mechanism
- Tests should create a temporary git repository (with `git init` and a configured `origin` remote), then run commands from within that directory so `git rev-parse --show-toplevel` resolves correctly
- The `test_helper.bash` setup must be updated to reflect the new path derivation

## Constraints

- Requires the current working directory to be inside a git repository — `lib/task` cannot operate outside of git
- The `sqlite3` version requirement (>= 3.35) is unchanged
- The symlink-following logic for `$_script_dir` resolution in `db_check()` is no longer needed for DB path derivation, but may still be used for other purposes (e.g., locating sibling files) — remove only the DB-path-specific usage

## Out of Scope

- Migration of existing task data from the Ralph repo's `.ralph/tasks.db` to target repos
- A `RALPH_DB_PATH` override for custom database locations
- Storing the database outside the target repository's `.ralph/` directory
- Per-branch database files (one DB per branch) — branches are scoped via columns, not files

## Supersedes

This spec updates the following existing specs:

- **sqlite-data-store.md** — "Database File Location" section: replace `$REPO_ROOT` resolution from script directory with `git rev-parse --show-toplevel`; remove `RALPH_DB_PATH` env var; remove `.env` sourcing for DB path
- **task-cli.md** — line 8: remove "Read database path from `RALPH_DB_PATH` environment variable"; replace with "Derive database path from `git rev-parse --show-toplevel`"
- **docker-removal.md** — "Environment Configuration" section: remove `RALPH_DB_PATH` from `.env.example`; "Database Initialization" section: replace `RALPH_DB_PATH` resolution with git-rev-parse derivation
- **scoped-task-lists.md** — no structural changes, but the relationship between scoping and DB location is clarified: one DB per repo (at git root), scoped by branch within
- **sql-dialect-migration.md** — line 103: replace `$RALPH_DB_PATH` reference in `sqlite_cmd()` description with the git-root-derived path variable
