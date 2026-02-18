# Task Data Store

PostgreSQL-backed persistent storage for multi-agent task orchestration across ephemeral Docker containers.

## Requirements

- Store task, step, dependency, and agent data in a PostgreSQL database
- Connection via `RALPH_DB_URL` environment variable (e.g. `postgres://ralph:pass@db:5432/ralph`)
- Create schema automatically on first invocation if tables do not exist
- Task table schema:
  - `id` — text primary key, planner-assigned stable ID in `{spec-slug}/{seq}` format (e.g. `task-cli/01`, `task-store/03`)
  - `description` — text, required
  - `category` — text: `bug`, `feat`, `test`, `refactor`, `doc`
  - `priority` — integer, default 2 (0=critical, 1=high, 2=medium, 3=low)
  - `status` — text: `open`, `active`, `done`, `deleted`
  - `spec_ref` — text, the spec filename this task was derived from (e.g. `task-cli.md`)
  - `ref` — text, additional file or line reference
  - `result` — JSONB, structured output from the builder that completed this task (anchored by `commit` key)
  - `assignee` — text, references agent ID (nullable)
  - `lease_expires_at` — timestamptz, set on claim, used for automatic recovery of abandoned tasks
  - `retry_count` — integer, default 0, incremented when reclaiming from an expired lease
  - `created_at` — timestamptz, default `now()`
  - `updated_at` — timestamptz, updated on every write
  - `deleted_at` — timestamptz, set on soft delete
- Task steps table schema:
  - `task_id` — text, references task ID with `ON DELETE CASCADE`
  - `seq` — integer, step sequence number within the task
  - `content` — text, description of the step
  - `status` — text, default `pending`: `pending`, `done`, `skipped`
  - Composite primary key on `(task_id, seq)`
- Dependency table schema:
  - `task_id` — text, references task ID with `ON DELETE CASCADE`
  - `blocked_by` — text, references task ID with `ON DELETE CASCADE`
  - Composite primary key on `(task_id, blocked_by)`
- Agent table schema:
  - `id` — text primary key, 4-char random hex
  - `pid` — integer, OS process ID
  - `hostname` — text, container or machine identifier
  - `started_at` — timestamptz, default `now()`
  - `status` — text: `active`, `stopped`
- All writes must use explicit SQL transactions for atomicity
- Soft delete: setting status to `deleted` must also set `deleted_at` and `updated_at` to current timestamp
- Soft-deleted tasks must be excluded from all list and scheduling queries by default
- The `updated_at` field must be set to current timestamp on every update
- Done tasks are immutable — no update may change a task's status away from `done`

## Constraints

- Requires `psql` CLI for database access
- Connection string provided exclusively via `RALPH_DB_URL` environment variable
- No ORM or application-level connection pooling — each CLI invocation opens and closes a connection
- Schema creation must be idempotent (`CREATE TABLE IF NOT EXISTS`)
- The database server runs as a separate container (e.g. `postgres:17-alpine` in Docker Compose)
- Database data directory should be on a Docker volume for persistence across container restarts

## Out of Scope

- Database migrations or schema versioning
- Replication or remote sync
- Archival or compaction of completed tasks
- Web UI or REST API
- SQLite fallback for local development
