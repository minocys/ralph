# Task CLI Spec Filtering

The `ralph task` subcommands `peek`, `plan-status`, and `plan-sync` accept a `--specs` flag to scope their operations to tasks whose spec-slug matches the provided glob patterns.

## Requirements

### Shared matching logic

- All three commands (`peek`, `plan-status`, `plan-sync`) accept `--specs <patterns>` where `<patterns>` is a comma-separated list of glob patterns
- A task matches if its spec-slug (derived from its ID: the portion before the first `/`) matches any of the provided patterns using shell glob semantics
- When `--specs` is omitted, the command reads the `RALPH_SPEC_FILTER` environment variable as a fallback — if set and non-empty, it is used as the patterns value
- An explicit `--specs` flag always takes precedence over the `RALPH_SPEC_FILTER` environment variable
- When neither `--specs` nor `RALPH_SPEC_FILTER` is provided, behavior is unchanged — all tasks in the current scope are considered

### `ralph task peek --specs <patterns>`

- Claimable tasks: only tasks whose spec-slug matches at least one pattern are returned, subject to the existing eligibility criteria (open/unblocked or active with expired lease) and priority ordering
- Active tasks: only active tasks whose spec-slug matches at least one pattern are returned — this ensures the builder only sees relevant parallel work
- The `-n N` limit applies to the filtered claimable set
- If no matching claimable or active tasks exist, output is empty and exit code is 0

### `ralph task plan-status --specs <patterns>`

- `plan-status` currently reports counts of open and active tasks to determine if work remains
- With `--specs`, the counts must only include tasks whose spec-slug matches at least one pattern
- The build loop uses this to exit when all filtered tasks are done — "0 open and 0 active" means the targeted work is complete, even if unfiltered tasks remain

### `ralph task plan-sync --specs <patterns>`

- The `--specs` flag scopes orphan deletion: only tasks whose `spec_ref` matches a pattern AND whose `spec_ref` appears in the input JSONL are candidates for orphan deletion
- Tasks whose `spec_ref` does not match any pattern are never touched by orphan deletion, even if their `spec_ref` is absent from the input JSONL
- Insert and update operations are unaffected — any task present in the input JSONL is processed normally regardless of whether it matches a pattern
- This prevents a targeted `ralph plan --specs ui-tabs` from accidentally soft-deleting tasks belonging to `auth-oauth` or other unrelated spec_refs

### SQL-level filtering

- Spec-slug matching must happen at the SQL query level, not as a post-filter on query results
- The spec-slug is derived from the task's `slug` column: `substr(slug, 1, instr(slug, '/') - 1)` extracts the prefix before the first `/`
- For each glob pattern, SQLite `GLOB` function provides native glob matching (case-sensitive, supports `*` and `?`)
- Multiple patterns are joined with `OR` in the WHERE clause

## Constraints

- SQLite `GLOB` is case-sensitive — this is intentional since spec-slugs are always lowercase kebab-case
- The `--specs` flag must not conflict with existing flags on these subcommands
- Filtering is additive to existing scope filtering (repo + branch) — `--specs` further narrows within the current scope
- Performance: the number of distinct spec-slugs is small (typically < 100), so linear pattern matching in SQL is acceptable

## Out of Scope

- Adding `--specs` to other task subcommands (`list`, `claim`, `done`, `fail`, etc.)
- Full-text search or fuzzy matching on spec-slugs
- Caching or indexing spec-slug prefixes as a separate column
