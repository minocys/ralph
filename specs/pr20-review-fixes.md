# PR #20 Review Fixes

Address 9 issues identified during code review of the PostgreSQL-to-SQLite migration PR (#20).

## Overview

The SQLite migration (58 tasks across `sqlite-data-store`, `sqlite-concurrency`, `sql-dialect-migration`, and `docker-removal` specs) is functionally complete. During PR review, 7 issues were identified ranging from a SQL injection vector to missing concurrency guards to code duplication. This spec documents each issue and its fix.

## Issues

### HIGH PRIORITY

**Issue #1: SQL injection via unvalidated numeric parameters**

- Location: `lib/task` -- `cmd_claim`, `cmd_renew`, `cmd_create`
- `--lease` in `cmd_claim`/`cmd_renew` and `-p` (priority) in `cmd_create` are interpolated directly into SQL without integer validation
- `cmd_plan_sync` already validates priority with `^[0-9]+$` regex -- the same pattern should be applied to these functions
- Fix: Add `^[0-9]+$` regex validation after option parsing in each affected function

**Issue #2: `cmd_plan_sync` lacks retry-on-BUSY**

- Location: `lib/task` -- `cmd_plan_sync`
- The function builds a single SQL transaction and passes it to `sqlite_cmd` directly
- The concurrency spec (`sqlite-concurrency.md`) requires all write operations to use retry-on-BUSY logic
- Fix: Wrap the `sqlite_cmd` execution in a retry-on-exit-5 loop matching the `sql_write` pattern, or pipe through `sql_write`

### MEDIUM PRIORITY

**Issue #3: `db_check()` duplicates symlink resolution block**

- Location: `lib/task` -- `db_check()` function
- An identical 8-line `BASH_SOURCE` symlink-resolution block appears twice
- Fix: Resolve `_script_dir` once at the top of the function and reuse

**Issue #4: `cmd_update --steps` executes a separate UPDATE**

- Location: `lib/task` -- `cmd_update`
- When `--steps` is provided alongside other fields, two separate UPDATE statements run (one for the normal fields, one for steps)
- This violates atomicity -- the two UPDATEs could see different states
- Fix: Merge steps into the `set_parts` array so a single UPDATE covers all fields

**Issue #5: `cmd_agent_register` doesn't use `BEGIN IMMEDIATE`**

- Location: `lib/task` -- `cmd_agent_register`
- The concurrency spec requires all write operations to use `BEGIN IMMEDIATE`
- Fix: Route the INSERT through `sql_write` or wrap in `BEGIN IMMEDIATE`

**Issue #8: `cmd_renew` uses `sqlite_cmd` instead of `sql_write` for its UPDATE**

- Location: `lib/task` -- `cmd_renew`, lines 878-887
- The UPDATE uses `sqlite_cmd` (plain autocommit) instead of `sql_write` (`BEGIN IMMEDIATE` with retry-on-BUSY)
- `specs/sqlite-concurrency.md` line 41 requires: "ralph task renew must use BEGIN IMMEDIATE for their write transactions"
- Every other write command (`cmd_done`, `cmd_fail`, `cmd_create`, `cmd_claim`, `cmd_plan_sync`, `cmd_agent_register`, `cmd_agent_deregister`) already uses `sql_write`
- The current code also uses `RETURNING slug` which is a PostgreSQL-ism; should use `SELECT changes()` like `cmd_done`/`cmd_fail`
- Fix: Replace the `sqlite_cmd` call with `sql_write` following the `cmd_done` pattern: `UPDATE ... WHERE ... AND status = 'active'; SELECT changes();` and check output for `"1"`

**Issue #9: `cmd_update` has a TOCTOU race between status check and write**

- Location: `lib/task` -- `cmd_update`, lines 1391 (read) and 1430 (write)
- A separate `sqlite_cmd SELECT status` (line 1391) checks if the task is done, then a separate `sql_write UPDATE` (line 1430) performs the write
- Between these two calls, a concurrent `cmd_done` could mark the task as done, and `cmd_update` would overwrite it
- `cmd_done` and `cmd_fail` explicitly avoid this with an inline comment: "Atomic: UPDATE only if status = 'active', then check changes() in same transaction. Avoids TOCTOU race between status check and update."
- The `sql_write` output is discarded (`> /dev/null`), so `cmd_update` cannot detect a zero-row update
- Fix: Add `AND status != 'done'` to the UPDATE WHERE clause, append `SELECT changes()`, check output for success, and use a diagnostic read only on failure

### LOW PRIORITY

**Issue #6: `lib/session.sh` missing file header comment (ALREADY RESOLVED)**

- `lib/session.sh` already has a proper header comment (lines 2-14) matching the convention used by other `lib/` files
- No action needed -- the review comment was incorrect
- A verification task is created to confirm this

**Issue #7: PR has no description**

- The PR body is empty; it should summarize motivation, approach, and testing strategy
- Fix: Add PR description via `gh pr edit`

## Requirements

- All numeric CLI parameters interpolated into SQL must be validated with `^[0-9]+$` before use
- All write operations must use retry-on-BUSY logic per `sqlite-concurrency.md`
- All write operations must use `BEGIN IMMEDIATE` per `sqlite-concurrency.md`
- Code duplication in `db_check()` must be eliminated
- `cmd_update` must execute a single atomic UPDATE when `--steps` is combined with other fields
- Each fix must have a corresponding BATS test added before the implementation change (TDD)

## Constraints

- Fixes must not change the external CLI interface or task data model
- Validation error messages should follow the existing convention in `lib/task` (e.g., `echo "Error: ..." >&2; return 1`)
- The retry-on-BUSY pattern must match the existing `sql_write` implementation for consistency

## Out of Scope

- Refactoring beyond the 7 identified issues
- Changing the task data model or schema
- Adding new CLI commands or flags
