# SQL Dialect Migration

Port all PostgreSQL-specific SQL in `lib/task` to SQLite-compatible equivalents, function by function.

## Overview

`lib/task` contains 40+ distinct SQL queries using PostgreSQL-specific syntax: JSON aggregation functions, array types, interval arithmetic, CTE-based updates with `RETURNING`, and type casts. This spec maps every PostgreSQL construct to its SQLite replacement. The CLI interface and output formats are unchanged — only the SQL internals change.

## Requirements

### JSON Functions

| PostgreSQL | SQLite Replacement | Notes |
|-----------|-------------------|-------|
| `json_build_object('key1', val1, 'key2', val2)` | `json_object('key1', val1, 'key2', val2)` | Direct equivalent in json1 extension |
| `json_agg(expression)` | `json_group_array(expression)` | Aggregate into JSON array |
| `json_object_agg(key, value)` | `json_group_object(key, value)` | Aggregate key-value pairs into JSON object |
| `to_json(value)` | `json(value)` for strings; use `json_array()` to convert arrays | `to_json(steps)` for TEXT[] becomes reading the JSON array TEXT column directly |
| `'value'::jsonb` | `json('value')` | Validate and store as JSON text |
| `'[]'::json` / `'{}'::json` | `'[]'` / `'{}'` | Plain text literals (json1 functions accept JSON strings) |

### Array Handling

| PostgreSQL | SQLite Replacement | Notes |
|-----------|-------------------|-------|
| `TEXT[]` column type | `TEXT` column storing JSON array | e.g. `["step1","step2"]` |
| `ARRAY['a','b']::TEXT[]` | `json_array('a','b')` or store pre-built JSON string | Constructed in bash before SQL |
| `unnest(steps)` | `json_each(steps)` as a table-valued function | `SELECT value FROM json_each(steps)` |
| `array_length(steps, 1)` | `json_array_length(steps)` | Count elements |

- The `build_steps_literal()` function must be rewritten to produce a JSON array string (e.g. `["step 1","step 2"]`) instead of a PostgreSQL array literal (e.g. `ARRAY['step 1','step 2']::TEXT[]`)

### Timestamp and Interval Arithmetic

| PostgreSQL | SQLite Replacement | Notes |
|-----------|-------------------|-------|
| `now()` | `datetime('now')` | Returns UTC ISO-8601 string |
| `now() + interval '600 seconds'` | `datetime('now', '+600 seconds')` | SQLite date modifier syntax |
| `lease_expires_at < now()` | `lease_expires_at < datetime('now')` | String comparison works because ISO-8601 is lexicographically sortable |
| `TIMESTAMPTZ DEFAULT now()` | `TEXT DEFAULT (datetime('now'))` | Parentheses required for expression defaults in SQLite |

### UUID Generation

| PostgreSQL | SQLite Replacement | Notes |
|-----------|-------------------|-------|
| `DEFAULT gen_random_uuid()` | No default; UUID passed as a literal from bash | The `generate_uuid()` shell function provides the value before the INSERT |

- Every INSERT into `tasks` or agent collision-retry in `agent register` must call `generate_uuid()` in bash and interpolate the result into the SQL

### Upsert Syntax

| PostgreSQL | SQLite Replacement | Notes |
|-----------|-------------------|-------|
| `INSERT ... ON CONFLICT (cols) DO UPDATE SET col = EXCLUDED.col` | `INSERT ... ON CONFLICT (cols) DO UPDATE SET col = excluded.col` | SQLite uses lowercase `excluded` but is case-insensitive; syntax is otherwise identical since SQLite 3.24 |
| `ON CONFLICT DO NOTHING` | `ON CONFLICT DO NOTHING` | Identical |

- The `plan-sync` upsert and `block` command upsert require no structural change, only type-related adjustments (JSONB → TEXT, array literal → JSON string)

### RETURNING Clause

| PostgreSQL | SQLite Replacement | Notes |
|-----------|-------------------|-------|
| `UPDATE ... RETURNING *` | `UPDATE ... RETURNING *` | Supported since SQLite 3.35 |
| `INSERT ... RETURNING id` | `INSERT ... RETURNING id` | Supported since SQLite 3.35 |

- The CTE-based `WITH ... AS (UPDATE ... RETURNING ...) SELECT ...` pattern used in PostgreSQL claims **is not supported in SQLite** — SQLite does not allow UPDATE inside a CTE
- Claim must be restructured: separate SELECT (find eligible task) → UPDATE (claim it) → SELECT (return full row with blocker results), all within a single `BEGIN IMMEDIATE` transaction

### CTE Restructuring for Claims

The PostgreSQL claim uses a single CTE chain: `WITH eligible AS (SELECT ... FOR UPDATE SKIP LOCKED), claimed AS (UPDATE ... FROM eligible RETURNING *) SELECT json_build_object(...) FROM claimed`. In SQLite this becomes:

1. `BEGIN IMMEDIATE`
2. `SELECT id, slug, ... FROM tasks WHERE <eligibility conditions> ORDER BY priority, created_at LIMIT 1` — find the candidate
3. Capture the task ID in a bash variable
4. `UPDATE tasks SET status='active', assignee=..., lease_expires_at=..., updated_at=... WHERE id = '<captured_id>' AND status IN ('open','active') RETURNING *` — claim it, with a WHERE guard to prevent stale updates
5. Build the JSON output including blocker results via a separate SELECT
6. `COMMIT`

- The `WHERE id = ... AND status IN ('open','active')` guard on the UPDATE prevents claiming a task that was concurrently claimed between the SELECT and UPDATE (belt-and-suspenders with `BEGIN IMMEDIATE`)

### Recursive CTEs

- `WITH RECURSIVE dep_tree AS (...)` is supported in SQLite 3.8.3+ — no structural change needed
- The `ralph task deps` query can remain as-is with only type adjustments

### Temporary Tables

| PostgreSQL | SQLite Replacement | Notes |
|-----------|-------------------|-------|
| `CREATE TEMP TABLE _sync_pre ON COMMIT DROP AS SELECT ...` | `CREATE TEMP TABLE _sync_pre AS SELECT ...` | SQLite temp tables are connection-scoped and auto-dropped when the connection closes; `ON COMMIT DROP` is not supported but not needed since each CLI invocation is a fresh connection |

### psql Client Flags → sqlite3 Equivalents

| psql | sqlite3 | Notes |
|------|---------|-------|
| `psql "$URL" -tAX` | `sqlite3 "$db_path"` | Base invocation |
| `-t` (tuples only) | Default (no headers unless `.headers on`) | sqlite3 omits headers by default |
| `-A` (unaligned) | `-separator '|'` for pipe-delimited output | Or use `.mode list` |
| `-X` (no .psqlrc) | `-batch` to suppress interactive features | Also suppresses prompts |
| `--set ON_ERROR_STOP=1` | Wrap in a function that checks `$?` after each statement | sqlite3 does not stop on error by default in piped input; use `.bail on` pragma |

- The `psql_cmd()` function is replaced with a `sqlite_cmd()` function: `sqlite3 -batch -separator '|' "$RALPH_DB_PATH"` piped SQL from stdin
- For multi-statement transactions, use `.bail on` as the first line to stop on first error (equivalent to `ON_ERROR_STOP`)

### SET client_min_messages

- `SET client_min_messages TO WARNING` (PostgreSQL-specific) is removed — SQLite has no equivalent and does not emit notices for `IF NOT EXISTS`

## Constraints

- Every SQL query in `lib/task` must be ported — no PostgreSQL syntax may remain
- The CLI interface, exit codes, and output formats must be identical before and after migration
- All existing BATS tests must be updated to work with `sqlite3` instead of `psql` — test assertions about output remain unchanged where possible
- The `sqlite3` CLI must be invoked with `.bail on` for multi-statement batches to preserve fail-fast behavior

## Out of Scope

- Optimizing SQLite queries with custom indexes beyond the existing index
- Full-text search (FTS5) for task descriptions
- SQLite extensions beyond the built-in json1
- Query performance benchmarking or profiling
