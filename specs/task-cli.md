# Task CLI

Bash command-line interface for agents and the ralph planner to interact with the task backlog. Phase-specific commands optimized for minimal token usage in LLM context windows. Invoked via `ralph task <command>` (see task-cli-relocation spec).

## Requirements

- Implement as a bash script (`lib/task`) that operates on PostgreSQL via `psql`, invoked via `ralph task <command>`
- Read connection string from `RALPH_DB_URL` environment variable
- Initialize the database schema automatically on first invocation
- Provide phase-specific and shared commands:

### Plan Phase Commands

- `ralph task plan-sync` — read JSONL from stdin, upsert tasks into the database using the diff algorithm (see Task Scheduling spec), print summary of changes (inserted, updated, deleted)
- `ralph task plan-status` — print summary line: `N open, N active, N done, N blocked, N deleted`

### Build Phase Commands

- `ralph task peek [-n 5]` — return the top N claimable tasks (open + unblocked, or active with expired lease) sorted by priority/created_at, plus all currently active tasks with assignees; output is markdown-KV; if no claimable or active tasks exist, output is empty and exit code is 0
- `ralph task claim [<id>] [--lease 600]` — when called without `<id>`, atomically claim the highest-priority unblocked task (existing behavior); when called with `<id>`, claim that specific task after verifying it is eligible (open + unblocked, or active with expired lease); return full context as markdown-KV (task fields + steps + blocker results); default lease is 600 seconds; exit code 2 if no eligible task or if the specified task is not eligible
- `ralph task renew <id> [--lease 600]` — extend the lease on an active task
- `ralph task done <id> --result '<json>'` — mark task as done, store result JSONB (must include `commit` key)
- `ralph task fail <id> --reason "<text>"` — release task back to `open`, clear assignee, increment `retry_count`

### Shared Commands

- `ralph task list [--status open,active] [--all] [--markdown]` — show tasks filtered by status; default excludes deleted, `--all` shows all statuses including deleted (replaces `plan-export`), `--markdown` outputs markdown-KV; `--all` and `--status` are mutually exclusive
- `ralph task show <id> [--with-deps]` — full detail for one task; `--with-deps` includes blocker task results
- `ralph task create <id> <title> [-p PRIORITY] [-c CATEGORY] [-d DESCRIPTION] [-s STEPS_JSON] [-r SPEC_REF] [--ref REF] [--deps DEP_IDS]` — create a task with a given ID and title, print its ID
- `ralph task update <id> [--title T] [--priority N] [--description D] [--steps S] [--status S]` — update fields on a non-done task
- `ralph task delete <id>` — soft delete
- `ralph task deps <id>` — show dependency tree for a task

### Dependency Commands

- `ralph task block <id> --by <blocker-id>` — add a dependency
- `ralph task unblock <id> --by <blocker-id>` — remove a dependency

### Agent Commands

- `ralph task agent register` — register a new agent (auto-generates 4-char hex ID, records PID and hostname), prints agent ID
- `ralph task agent list` — show active agents
- `ralph task agent deregister <id>` — mark agent as stopped

### Markdown-KV Format

Commands that pass task state to LLMs use markdown-KV format (defined in `specs/task-output-format.md`):
- `ralph task peek`, `ralph task claim` always output markdown-KV
- `ralph task list --markdown` and `ralph task list --all --markdown` output markdown-KV when the flag is set
- Keys use full names: `id`, `title`, `priority`, `status`, `category`, `spec`, `ref`, `assignee`, `deps`, `steps`
- `ralph task claim` additionally includes `lease_expires_at`, `retry_count`, and `blocker_results`

### Table Format

Default for `ralph task list` and `ralph task list --all` — aligned columns, compact:
```
ID              P S      CAT  TITLE                              AGENT
task-cli/01     0 active feat Implement CLI skeleton              a7f2
task-cli/02     1 open   feat Implement atomic claim              -
task-store/01   0 done   feat Create PostgreSQL schema            -
```

### Output Rules

- All commands must print to stdout for piping; errors to stderr
- Exit code 0 on success, 1 on error, 2 on "not found" (e.g. `ralph task claim` when no tasks available)

## Constraints

- Bash only — no Python, Node, or compiled dependencies beyond `psql`
- All database operations via `psql` with parameterized queries where possible
- The script must be portable across macOS and Linux (bash 3.2+)
- `ralph task claim` must not succeed for two concurrent agents on the same task — PostgreSQL's `SELECT FOR UPDATE SKIP LOCKED` guarantees this

## Out of Scope

- Interactive/TUI mode
- Bulk operations (multi-task claim, batch create)
- Filtering by date ranges
- Authentication or role-based access to commands
