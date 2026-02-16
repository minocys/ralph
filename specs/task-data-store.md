# Task Data Store

SQLite-backed persistent storage for multi-agent task orchestration, local to the working directory.

## Requirements

- Store task and agent data in a SQLite database at `.ralph/tasks.db`
- Enable WAL (Write-Ahead Logging) mode on database creation for concurrent read access
- Create `.ralph/` directory automatically on first use if it does not exist
- Task table schema:
  - `id` — text primary key, auto-generated short ID (e.g. `t01`, `t02`)
  - `priority` — integer, default 2 (0=critical, 1=high, 2=medium, 3=low)
  - `status` — text: `open`, `active`, `done`, `deleted`
  - `assignee` — text, references agent ID (nullable)
  - `category` — text: `bug`, `feat`, `test`, `refactor`, `doc`
  - `title` — text, required
  - `description` — text, optional
  - `steps` — text, JSON array of strings
  - `ref` — text, spec or file reference
  - `created_at` — text, ISO timestamp, default now
  - `updated_at` — text, ISO timestamp, updated on every write
  - `deleted_at` — text, ISO timestamp, set on soft delete
- Agent table schema:
  - `id` — text primary key, 4-char random hex
  - `pid` — integer, OS process ID
  - `started_at` — text, ISO timestamp
  - `heartbeat` — text, ISO timestamp
  - `status` — text: `active`, `stopped`
- Dependency table schema:
  - `task_id` — text, references task ID
  - `blocked_by` — text, references task ID
  - Composite primary key on (task_id, blocked_by)
- All writes must use explicit SQL transactions for atomicity
- Soft delete: setting status to `deleted` must also set `deleted_at` to current timestamp
- Soft-deleted tasks must be excluded from all list and scheduling queries by default
- The `updated_at` field must be set to current timestamp on every update

## Constraints

- Requires `sqlite3` CLI (pre-installed on macOS and most Linux distributions)
- No external database servers or additional binary dependencies
- Database file must be gitignored (`.ralph/` directory added to `.gitignore`)
- ID generation must avoid collisions across concurrent agents — use monotonic counter from `max(id)` within a transaction

## Out of Scope

- Database migrations or schema versioning
- Replication or remote sync
- Archival or compaction of completed tasks
- Web UI or REST API
