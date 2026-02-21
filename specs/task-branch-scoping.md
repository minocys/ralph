# Task Branch Scoping

Route each task CLI invocation to a DoltgreSQL branch that mirrors the current git branch, so tasks are automatically scoped to the branch being worked on.

## Requirements

### Git Branch Detection

- A `get_git_branch()` helper must return the current git branch name via `git branch --show-current`
- If not inside a git repository (or git is unavailable), fall back to `"main"`
- The helper must be called by `psql_cmd()` on every invocation — no caching

### URL-Based Branch Routing

- `psql_cmd()` must append `/${branch}` to `RALPH_DB_URL` when connecting to DoltgreSQL
- Example: if `RALPH_DB_URL=postgres://ralph:pass@db:5432/ralph` and the git branch is `feature-x`, `psql_cmd` connects to `postgres://ralph:pass@db:5432/ralph/feature-x`
- DoltgreSQL resolves the path suffix as a database branch — no `SELECT DOLT_CHECKOUT()` needed
- Read-only queries and write queries both route through the same URL-based mechanism

### Automatic Branch Creation

- An `ensure_branch()` helper must run on every CLI invocation, before `ensure_schema()`
- `ensure_branch()` connects to the base `RALPH_DB_URL` (no branch suffix) and queries `SELECT 1 FROM dolt.branches WHERE name = '${branch}'`
- If the branch does not exist, create it from `main`: `SELECT DOLT_BRANCH('${branch}', 'main')`
- If `main` does not exist either (fresh database), skip branch creation — the default branch is used as-is
- The branch name must be SQL-escaped via `sql_esc()` before interpolation

### Inline DOLT_COMMIT After Mutations

- Every command that writes to the database must include a `SELECT DOLT_COMMIT('-A', '-m', '${message}')` in the same `psql` session as the write
- For commands that use `psql_cmd -c`, append the `DOLT_COMMIT` call to the SQL string with a semicolon separator
- For commands that pipe SQL to `psql_cmd` (e.g., `plan-sync`, `create`), append the `DOLT_COMMIT` call after `COMMIT;` in the SQL blob
- The commit message must include the command name and task ID for traceability (e.g., `done task-cli/01`, `plan-sync: 3 inserted, 1 updated, 0 deleted`)
- DOLT_COMMIT output must be suppressed — it must not appear in the command's stdout
- Commands that require inline DOLT_COMMIT:
  - `plan-sync` — after the transaction commits
  - `claim` — after the CTE update
  - `renew` — after the lease extension
  - `done` — after marking task done
  - `fail` — after releasing task to open
  - `create` — after the transaction commits
  - `update` — after the transaction commits
  - `delete` — after the soft delete
  - `block` — after inserting the dependency
  - `unblock` — after deleting the dependency
  - `step-done` — after marking the step done

### Read-Only Commands

- Read-only commands (`list`, `show`, `peek`, `plan-export`, `plan-status`, `deps`) do not need DOLT_COMMIT
- They still route through the branch-scoped URL and see committed data on that branch

### Main Dispatch Update

- The `main()` dispatch must call `ensure_branch()` before `ensure_schema()` for every command
- The call order is: `db_check` → `ensure_branch` → `ensure_schema` → `cmd_<name>`

## Constraints

- Branch names come from git and may contain characters that need SQL escaping (e.g., slashes in `ryan/oto-226-feature`)
- DoltgreSQL's URL-based branch routing treats the path segment after the database name as the branch — `RALPH_DB_URL` must not already contain a trailing slash
- `ensure_branch()` adds one extra query per CLI invocation; this is acceptable given the CLI runs infrequently
- DOLT_COMMIT requires that changes exist in the working set — calling it with no changes may error or no-op depending on DoltgreSQL version; mutation commands must handle this gracefully
- Each `psql` invocation is a separate session — DOLT_COMMIT must be in the same session as the writes it commits

## Out of Scope

- Merging DoltgreSQL branches (future enhancement)
- Diffing task state across branches
- Querying tasks from other branches (cross-branch `AS OF` queries)
- Garbage collection or pruning of old DoltgreSQL branches
- Branch deletion when git branches are deleted
