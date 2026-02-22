# Scoped Task Lists

Scope all task and agent data by git repository and branch so that multiple Ralph agents can work on different repos and branches simultaneously without interfering with each other.

## Overview

The current task system uses a single global task list — all tasks, dependencies, and agents share one flat namespace. When multiple Ralph agents run concurrently on different repositories or branches, their tasks collide (same `{spec-slug}/{seq}` IDs), plan-sync deletes the wrong tasks, and peek/claim return tasks from unrelated work.

Scoped task lists add `scope_repo` and `scope_branch` columns to the database. Every query filters by the current scope, derived from the git repository's remote URL and current branch. Each scope operates as an independent task list.

## Requirements

### Schema

- Replace the existing `id TEXT PRIMARY KEY` on the `tasks` table with `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- Add `slug TEXT NOT NULL` column to the `tasks` table — holds the planner-assigned human-readable identifier (e.g. `task-cli/01`), previously stored in `id`
- Add `scope_repo TEXT NOT NULL` column to the `tasks` table
- Add `scope_branch TEXT NOT NULL` column to the `tasks` table
- Add a `UNIQUE` constraint on `(scope_repo, scope_branch, slug)`
- Update `task_deps` foreign keys from `TEXT` to `UUID`:
  - `task_id UUID REFERENCES tasks(id) ON DELETE CASCADE`
  - `blocked_by UUID REFERENCES tasks(id) ON DELETE CASCADE`
- Add `scope_repo TEXT NOT NULL` and `scope_branch TEXT NOT NULL` columns to the `agents` table
- Add an index on `tasks (scope_repo, scope_branch, status, priority, created_at)` for efficient scoped queries
- `ensure_schema()` in the `task` CLI must handle the migration idempotently (add columns if they don't exist)
- `db/init/001-schema.sql` must be updated to reflect the new schema for fresh installs

### Scope Derivation

- The `task` CLI must determine scope from environment variables or git, in this order:
  1. `RALPH_SCOPE_REPO` environment variable (if set)
  2. Derived from `git remote get-url origin` — extract `owner/repo` (strip `.git` suffix, handle both SSH and HTTPS URL formats)
- The `task` CLI must determine branch scope in this order:
  1. `RALPH_SCOPE_BRANCH` environment variable (if set)
  2. Derived from `git branch --show-current`
- The `task` CLI must error if scope cannot be determined:
  - Not inside a git repository → `Error: not inside a git repository. Run: git init`
  - No remote named `origin` → `Error: no git remote "origin" found. Run: git remote add origin <url>`
  - Detached HEAD state (`git branch --show-current` returns empty) → `Error: detached HEAD state. Run: git checkout <branch>`
- `ralph.sh` / `lib/loop.sh` should set `RALPH_SCOPE_REPO` and `RALPH_SCOPE_BRANCH` environment variables explicitly before invoking `task` or `claude`, so that subprocesses inherit the scope

### CLI Behavior

- All CLI commands that accept a task identifier must accept the **slug** (e.g. `task-cli/01`), not the UUID
- The slug is resolved to an internal UUID within the current scope: `WHERE scope_repo = $REPO AND scope_branch = $BRANCH AND slug = $SLUG`
- The UUID is internal only — never exposed to users, planners, or builders
- Commands affected: `claim`, `done`, `fail`, `renew`, `show`, `update`, `delete`, `deps`, `block`, `unblock`
- `task create` must accept the slug as the first positional argument (same ergonomics as today's `id`), and generate the UUID automatically
- `task list` (including `--all`), `task peek`, `task plan-status` must filter results by the current scope
- `task plan-sync` must match incoming tasks to existing DB rows using `(scope_repo, scope_branch, slug)` — the incoming JSONL `id` field maps to the `slug` column
- `task plan-sync` orphan deletion must be scoped: only soft-delete tasks within the current scope's `spec_ref` group
- `task agent register` must record `scope_repo` and `scope_branch` on the agent row
- `task agent list` must filter by the current scope

### Output Format

- Markdown-KV output (`render_task_md`, `list --all --markdown`, `peek`, `claim`, `list --markdown`) must use `slug` where `id` was previously used — the output field name remains `id` for backward compatibility with skills
- The UUID must not appear in any user-facing or skill-facing output

### Hooks

- `hooks/session_end.sh` and `hooks/precompact.sh` must filter active tasks by both `RALPH_AGENT_ID` and the current scope when failing abandoned tasks

## Constraints

- Requires a git repository with an `origin` remote and a checked-out branch — not usable outside of git
- The `psql` CLI remains the only database access mechanism — no ORM or connection pooling
- Schema migration must be idempotent — `ensure_schema()` handles both fresh installs and upgrades from the unscoped schema
- The `slug` column replaces the role of `id` in all external interfaces; the UUID `id` is strictly internal
- Environment variable overrides (`RALPH_SCOPE_REPO`, `RALPH_SCOPE_BRANCH`) take precedence over git auto-detection — this allows testing and non-standard workflows

## Out of Scope

- Cross-scope visibility (e.g. `--all-scopes` flag to see tasks from all repos/branches)
- Migration tooling for existing task data (existing unscoped tasks are orphaned; fresh `plan-sync` repopulates)
- Scope management commands (e.g. `task scope list`, `task scope prune`)
- Web UI or dashboard for multi-scope monitoring
- Scope derived from anything other than git (e.g. arbitrary project names)
