# Task CLI

Bash command-line interface for agents and the ralph planner to interact with the task backlog. Phase-specific commands optimized for minimal token usage in LLM context windows.

## Requirements

- Implement as a standalone bash script (`task`) that operates on PostgreSQL via `psql`
- Read connection string from `RALPH_DB_URL` environment variable
- Initialize the database schema automatically on first invocation
- Provide phase-specific and shared commands:

### Plan Phase Commands

- `task plan-sync` — read JSONL from stdin, upsert tasks into the database using the diff algorithm (see Task Scheduling spec), print summary of changes (inserted, updated, deleted)
- `task plan-export` — dump the full task DAG as markdown-KV format
- `task plan-status` — print summary line: `N open, N active, N done, N blocked, N deleted`

### Build Phase Commands

- `task peek [-n 5]` — return the top N claimable tasks (open + unblocked, or active with expired lease) sorted by priority/created_at, plus all currently active tasks with assignees; output is JSONL matching the standard short-key format; if no claimable or active tasks exist, output is empty and exit code is 0
- `task claim [<id>] [--lease 600]` — when called without `<id>`, atomically claim the highest-priority unblocked task (existing behavior); when called with `<id>`, claim that specific task after verifying it is eligible (open + unblocked, or active with expired lease); return full context as JSON (task fields + steps + blocker results); default lease is 600 seconds; exit code 2 if no eligible task or if the specified task is not eligible
- `task renew <id> [--lease 600]` — extend the lease on an active task
- `task step-done <id> <seq>` — mark a step as done
- `task done <id> --result '<json>'` — mark task as done, store result JSONB (must include `commit` key)
- `task fail <id> --reason "<text>"` — release task back to `open`, clear assignee, increment `retry_count`

### Shared Commands

- `task list [--status open,active] [--json]` — show tasks filtered by status; default is compact table, `--json` outputs JSONL
- `task show <id> [--with-deps]` — full detail for one task; `--with-deps` includes blocker task results
- `task create <id> <title> [-p PRIORITY] [-c CATEGORY] [-d DESCRIPTION] [-s STEPS_JSON] [-r SPEC_REF] [--ref REF] [--deps DEP_IDS]` — create a task with a given ID and title, print its ID
- `task update <id> [--title T] [--priority N] [--description D] [--steps S] [--status S]` — update fields on a non-done task
- `task delete <id>` — soft delete
- `task deps <id>` — show dependency tree for a task

### Dependency Commands

- `task block <id> --by <blocker-id>` — add a dependency
- `task unblock <id> --by <blocker-id>` — remove a dependency

### Agent Commands

- `task agent register` — register a new agent (auto-generates 4-char hex ID, records PID and hostname), prints agent ID
- `task agent list` — show active agents
- `task agent deregister <id>` — mark agent as stopped

### JSONL Format

All JSONL output uses short keys for token efficiency:
- `id`, `t` (title), `d` (description), `p` (priority), `s` (status), `cat` (category), `spec` (spec_ref), `ref`, `deps` (array of blocker IDs), `steps` (array of step objects)
- `task claim` returns a JSON object with all of the above plus `blocker_results` (map of blocker ID to its result JSONB)

### Table Format

Default for `task list` and `task plan-export` — aligned columns, compact:
```
ID              P S      CAT  TITLE                              AGENT
task-cli/01     0 active feat Implement CLI skeleton              a7f2
task-cli/02     1 open   feat Implement atomic claim              -
task-store/01   0 done   feat Create PostgreSQL schema            -
```

### Output Rules

- All commands must print to stdout for piping; errors to stderr
- Exit code 0 on success, 1 on error, 2 on "not found" (e.g. `task claim` when no tasks available)

## Constraints

- Bash only — no Python, Node, or compiled dependencies beyond `psql`
- All database operations via `psql` with parameterized queries where possible
- The script must be portable across macOS and Linux (bash 3.2+)
- `task claim` must not succeed for two concurrent agents on the same task — PostgreSQL's `SELECT FOR UPDATE SKIP LOCKED` guarantees this

## Out of Scope

- Interactive/TUI mode
- Bulk operations (multi-task claim, batch create)
- Filtering by date ranges
- Authentication or role-based access to commands
