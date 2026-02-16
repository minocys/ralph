# Task CLI

Bash command-line interface for agents and humans to interact with the task backlog. Optimized for minimal token usage in LLM context windows.

## Requirements

- Implement as a standalone bash script (`task`) that operates on `.ralph/tasks.db`
- Initialize the database and schema automatically on first invocation
- Provide the following commands:

### Task Commands

- `task list [--json]` — show all non-deleted tasks; default is compact table, `--json` outputs JSONL with short keys
- `task next [--json]` — show highest-priority unclaimed unblocked task; single line output
- `task show <id>` — full detail for one task (all fields)
- `task create <title> [-p PRIORITY] [-c CATEGORY] [-d DESCRIPTION] [-s STEPS_JSON] [-r REF]` — create a task, print its ID
- `task claim <id> <agent-id>` — atomically claim a task (must be open and unblocked)
- `task done <id>` — mark task as done
- `task update <id> [--title T] [--priority N] [--description D] [--steps S] [--status S]` — update fields
- `task delete <id>` — soft delete

### Dependency Commands

- `task block <id> --by <blocker-id>` — add a dependency
- `task unblock <id> --by <blocker-id>` — remove a dependency

### Agent Commands

- `task agent register` — register a new agent (auto-generates ID, records PID), prints agent ID
- `task agent list` — show active agents
- `task agent deregister <id>` — mark agent as stopped
- `task agent recover <id>` — release all active tasks held by agent back to open, mark agent stopped

### Output Formats

- **Table format** (default for `task list`) — aligned columns, ~15 tokens per task:
  ```
  ID  P S      CAT  TITLE                        AGENT
  t01 0 active bug  Fix backend elif chain       a7f2
  t02 1 open   feat Add model selection          -
  ```
- **JSONL format** (`--json` flag) — one JSON object per line, short keys for token efficiency:
  - `id`, `p` (priority), `s` (status), `a` (assignee), `cat` (category), `t` (title)
  - `task next --json` additionally includes `d` (description), `steps`, `ref`
- All commands must print to stdout for piping; errors to stderr
- Exit code 0 on success, 1 on error, 2 on "not found" (e.g. `task next` when no tasks available)

## Constraints

- Bash only — no Python, Node, or compiled dependencies beyond `sqlite3`
- All database operations via `sqlite3` CLI with `-cmd` for pragmas
- The script must be portable across macOS and Linux (bash 3.2+)
- `task claim` must fail atomically if the task is not open or has unresolved blockers — no partial state

## Out of Scope

- Interactive/TUI mode
- Importing from IMPLEMENTATION_PLAN.json (separate migration concern)
- Filtering by category, assignee, or date ranges (can be added later)
- Bulk operations (multi-task claim, batch create)
