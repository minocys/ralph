# SQLite Data Store

Replace PostgreSQL with a local SQLite database file, eliminating the Docker container dependency while preserving the task data model.

## Overview

Ralph currently stores all task, dependency, and agent data in a PostgreSQL database running inside a Docker container. This spec replaces that with a single SQLite database file on the local filesystem. The data model (three tables: `tasks`, `task_deps`, `agents`) is unchanged. The `psql` CLI is replaced by `sqlite3`, and the connection string is replaced by a file path.

## Requirements

### Database File Location

- The database file path is determined by `RALPH_DB_PATH` environment variable
- Default location when `RALPH_DB_PATH` is unset: `$REPO_ROOT/.ralph/tasks.db` (co-located with the repository, git-ignored)
- `$REPO_ROOT` is resolved from the ralph script's own location (following symlinks), same as existing `$SCRIPT_DIR` resolution
- The `.ralph/` directory and database file are created automatically on first invocation
- `.ralph/` must be added to `.gitignore`

### Schema Translation

The three-table schema translates from PostgreSQL types to SQLite types:

**tasks table:**

| Column | PostgreSQL | SQLite | Notes |
|--------|-----------|--------|-------|
| `id` | `UUID DEFAULT gen_random_uuid()` | `TEXT PRIMARY KEY` | UUID generated in bash via `uuidgen` (macOS) or `cat /proc/sys/kernel/random/uuid` (Linux), lowercased |
| `slug` | `TEXT NOT NULL` | `TEXT NOT NULL` | Unchanged |
| `scope_repo` | `TEXT NOT NULL` | `TEXT NOT NULL` | Unchanged |
| `scope_branch` | `TEXT NOT NULL` | `TEXT NOT NULL` | Unchanged |
| `title` | `TEXT NOT NULL` | `TEXT NOT NULL` | Unchanged |
| `description` | `TEXT` | `TEXT` | Unchanged |
| `category` | `TEXT` | `TEXT` | Unchanged |
| `priority` | `INT DEFAULT 2` | `INTEGER DEFAULT 2` | Unchanged |
| `status` | `TEXT DEFAULT 'open'` | `TEXT DEFAULT 'open'` | Unchanged |
| `spec_ref` | `TEXT` | `TEXT` | Unchanged |
| `ref` | `TEXT` | `TEXT` | Unchanged |
| `result` | `JSONB` | `TEXT` | Stored as JSON string; validated and queried via SQLite json1 extension |
| `assignee` | `TEXT` | `TEXT` | Unchanged |
| `lease_expires_at` | `TIMESTAMPTZ` | `TEXT` | ISO-8601 format in UTC (e.g. `2024-01-15T10:30:00Z`); compared with `datetime('now')` |
| `retry_count` | `INT DEFAULT 0` | `INTEGER DEFAULT 0` | Unchanged |
| `fail_reason` | `TEXT` | `TEXT` | Unchanged |
| `steps` | `TEXT[]` | `TEXT` | Stored as JSON array string (e.g. `["step1","step2"]`); queried via `json_each()` |
| `created_at` | `TIMESTAMPTZ DEFAULT now()` | `TEXT DEFAULT (datetime('now'))` | ISO-8601 UTC |
| `updated_at` | `TIMESTAMPTZ` | `TEXT` | ISO-8601 UTC |
| `deleted_at` | `TIMESTAMPTZ` | `TEXT` | ISO-8601 UTC |

- `UNIQUE(scope_repo, scope_branch, slug)` constraint preserved
- Index `idx_tasks_scope_status ON tasks(scope_repo, scope_branch, status, priority, created_at)` preserved

**task_deps table:** unchanged (TEXT foreign keys, composite primary key, `ON DELETE CASCADE` — SQLite supports cascading deletes when `PRAGMA foreign_keys = ON`)

**agents table:** unchanged (TEXT primary key, INTEGER pid, TEXT hostname/scope fields, TEXT timestamps with `DEFAULT (datetime('now'))`)

### Schema Initialization

- `ensure_schema()` in `lib/task` creates tables with `CREATE TABLE IF NOT EXISTS` (same idempotent pattern)
- `PRAGMA journal_mode=WAL` is set on every connection to enable concurrent readers (see sqlite-concurrency spec)
- `PRAGMA foreign_keys=ON` is set on every connection (SQLite disables foreign keys by default)
- `PRAGMA busy_timeout=5000` is set on every connection (5-second wait before returning SQLITE_BUSY)
- The `db/init/001-schema.sql` file is replaced with a SQLite-dialect equivalent for reference, but the canonical schema lives in `ensure_schema()` (same as current PostgreSQL behavior)

### Database Access

- All queries run via the `sqlite3` CLI: `sqlite3 "$db_path"` replacing `psql "$RALPH_DB_URL" -tAX`
- `sqlite3` output uses the same separator-based parsing as current psql (pipe-delimited with `-separator '|'` or CSV mode as needed)
- Each CLI invocation opens and closes its own connection (same as current pattern — no connection pooling)
- The `sqlite3` CLI must be available on the system PATH; if missing, exit 1 with an actionable error message suggesting installation via the system package manager

### UUID Generation

- UUIDs are generated in bash, not in SQL
- On macOS: `uuidgen | tr '[:upper:]' '[:lower:]'`
- On Linux: `cat /proc/sys/kernel/random/uuid` (already lowercase) with `uuidgen` as fallback
- A `generate_uuid()` shell function encapsulates this with platform detection
- UUIDs are passed as string literals in INSERT statements

## Constraints

- Requires `sqlite3` CLI (version 3.35+ for `RETURNING` support, 3.38+ for built-in json functions)
- macOS ships with sqlite3 3.39+ (Ventura and later); Linux distros ship 3.31+ (Ubuntu 22.04) to 3.40+ (Ubuntu 24.04) — the `RETURNING` clause (3.35) is the binding minimum version
- If the installed sqlite3 version is below 3.35, exit 1 with a message stating the minimum required version
- No Docker, no `psql`, no PostgreSQL server required
- No ORM or application-level connection pooling (unchanged)
- The database file must not be committed to git

## Out of Scope

- Data migration from an existing PostgreSQL database to SQLite
- Remote or networked SQLite access (e.g. LiteFS, Turso)
- Encryption at rest (SQLCipher)
- Schema versioning or migration tooling beyond idempotent `CREATE TABLE IF NOT EXISTS`
- PostgreSQL as a fallback or dual-backend option
