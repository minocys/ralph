# Task Batch Delete

Extend `ralph task delete` with filter-based batch deletion so users can soft-delete groups of tasks by status, spec, and category instead of one at a time. Supersedes the single-ID-only delete documented in `task-cli.md`.

## Requirements

### Single-task delete (unchanged)

- `ralph task delete <id>` — soft-delete one task by slug, exactly as today; print `deleted <id>`; exit 2 if not found
- A positional `<id>` is mutually exclusive with `--status`, `--all`, `--spec`, and `--category`; if both a positional ID and any flag are provided, exit 1 with a usage error

### Batch delete by status

- `ralph task delete --status <csv>` — soft-delete all tasks in the current scope whose status matches any value in the comma-separated list
- Valid status values: `open`, `active`, `done`; reject `deleted` (already deleted) with exit 1
- Multiple statuses may be combined: `--status open,active`
- Print `deleted N tasks` on success (N may be 0 if no tasks matched)

### Filter by spec ref

- `--spec <spec_ref>` — restrict batch deletion to tasks whose `spec_ref` column matches the given value
- Must be combined with `--status` or `--all`; `--spec` alone (without `--status` or `--all`) exits 1 with a usage error

### Filter by category

- `--category <cat>` — restrict batch deletion to tasks whose `category` column matches the given value
- Must be combined with `--status` or `--all`; `--category` alone (without `--status` or `--all`) exits 1 with a usage error

### Combinable filters

- `--spec` and `--category` may be used together and with `--status` or `--all`
- Filters are combined with AND: `--status open --spec task-cli.md --category feat` deletes only open tasks from spec `task-cli.md` with category `feat`

### Delete all

- `ralph task delete --all --confirm` — soft-delete every non-deleted task in the current scope regardless of status
- `--all` without `--confirm` exits 1 and prints: `Error: --all requires --confirm flag`
- `--all` is mutually exclusive with `--status`; combining them exits 1 with a usage error
- `--all` may be combined with `--spec` and/or `--category` to narrow scope
- Print `deleted N tasks` on success

### Soft-delete semantics

- All batch deletes use the same SQL pattern as single-task delete: `SET status = 'deleted', deleted_at = datetime('now'), updated_at = datetime('now')`
- Already-deleted tasks are excluded from the UPDATE (`WHERE status != 'deleted'`) so they are not re-stamped and N counts only newly deleted tasks
- The entire batch operation runs inside a single `sql_write` transaction

### Output

- Single-task: `deleted <id>` (unchanged)
- Batch: `deleted N tasks` where N is the number of rows affected
- Exit 0 on success (even if N is 0), exit 1 on argument errors, exit 2 on single-task not found

## Constraints

- Bash only — no new dependencies beyond `sqlite3`
- Portable across macOS and Linux (bash 3.2+)
- All writes via `sql_write` (inherits retry-on-BUSY and `BEGIN IMMEDIATE` transactional safety)
- Must not alter existing single-task delete behavior or exit codes
- `task-cli.md` out-of-scope note "Bulk operations (multi-task claim, batch create)" should be updated to remove batch delete from the exclusion (batch claim and batch create remain out of scope)

## Out of Scope

- Batch claim or batch create
- Hard deletes (physical row removal)
- Interactive confirmation prompts (the `--confirm` flag is the safety mechanism, not a y/n prompt)
- Dry-run / preview mode
- Undo / restore of deleted tasks
