# PR #20 Review Fixes

Address 7 issues identified during code review of the PostgreSQL-to-SQLite migration PR (#20).

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
