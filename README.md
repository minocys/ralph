# Ralph

![Ralph target architecture](./assets/ralph-target.png)

Autonomous build loop powered by Claude Code. Turns a conversation into specs, a plan, and working code.

## Workflow

```
Discuss JTBD → ralph-spec → ralph plan → ralph
```

1. **Discuss** — Start a Claude Code session and have it interview you about what you want to build. Flesh out the Job to be Done (JTBD) through conversation before generating any specs.
2. **Spec** — Run `/ralph-spec` in the same session. Ralph splits the JTBD into topics of concern and writes a spec file for each under `./specs/`.
3. **Plan** — Run `ralph --plan` from your terminal. Ralph studies the specs and codebase, then produces `IMPLEMENTATION_PLAN.json` — a task list with completion tracking.
4. **Build** — Run `ralph` from your terminal. Ralph picks up incomplete tasks from the plan, implements them, runs tests, commits, and loops until everything is done.

### Videos

- [Basic explanation of the technique](https://www.youtube.com/watch?v=I7azCAgoUHc)
- [First principles from creator](https://www.youtube.com/watch?v=4Nna09dG_c0)
- [Additional context](https://www.youtube.com/watch?v=SB6cO97tfiY)

## Concepts

| Term               | Definition                                                      |
| ------------------ | --------------------------------------------------------------- |
| Job to be Done     | High-level user need or outcome                                 |
| Topic of Concern   | A distinct aspect or component within a JTBD                    |
| Spec               | Requirements doc for one topic of concern (`specs/<name>.md`)   |
| Task               | Unit of work derived from comparing specs to code               |

- 1 JTBD &rarr; many topics of concern
- 1 topic of concern &rarr; 1 spec
- 1 spec &rarr; many tasks

**Scope test:** Can you describe a topic in one sentence without "and"? If not, split it.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- [jq](https://jqlang.github.io/jq/)
- [Docker](https://docs.docker.com/get-docker/) (for PostgreSQL task database)
- [psql](https://www.postgresql.org/docs/current/app-psql.html) (PostgreSQL client)

## Installation

```sh
git clone <repo-url> && cd ralph
./install.sh
```

This symlinks the skills into `~/.claude/skills/` and both `ralph` and `task` into `~/.local/bin/`. Make sure `~/.local/bin` is in your `PATH`.

## Usage

```sh
# Step 1: Start a Claude Code session, discuss your JTBD, then:
/ralph-spec

# Step 2: Generate implementation plan from specs
ralph --plan              # plan mode, unlimited iterations
ralph --plan -n 5         # plan mode, max 5 iterations

# Step 3: Build loop — implement, test, commit, repeat
ralph                     # build mode, unlimited iterations
ralph -n 20               # build mode, max 20 iterations

# Options
ralph --help              # show usage
ralph --danger            # enable --dangerously-skip-permissions
ralph --plan -n 5 --danger

# Model selection
ralph -m opus-4.5         # use a model alias from models.json
ralph --model sonnet      # long form
ralph --model claude-opus-4-5-20251101  # full model ID pass-through
```

### Model Selection

Use `--model` (or `-m`) to pick which Claude model to run. Ralph resolves short aliases via `models.json`, which maps each alias to the correct model ID for your backend (Anthropic API or Bedrock). The backend is detected automatically from `~/.claude/settings.json`.

| Alias | Bedrock Model ID |
| --- | --- |
| `opus-4.6` | `global.anthropic.claude-opus-4-6-v1` |
| `opus-4.5` | `global.anthropic.claude-opus-4-5-20251101-v1:0` |
| `sonnet` | `global.anthropic.claude-sonnet-4-5-20250929-v1:0` |
| `haiku` | `global.anthropic.claude-haiku-4-5-20251001-v1:0` |

**Note**: When using the Anthropic backend, aliases are passed through as-is to Claude Code. The table above shows Bedrock-specific model ID mappings only.

If the value you pass isn't a known alias, Ralph passes it through as a literal model ID. Omitting `--model` uses Claude Code's default.

#### Backend Selection

The backend (Anthropic API or AWS Bedrock) is determined by checking `CLAUDE_CODE_USE_BEDROCK` in the following order of precedence:

1. **Environment variable** (inline or exported): `CLAUDE_CODE_USE_BEDROCK=1 ./ralph.sh`
2. **Local settings (project-specific, git-ignored)**: `./.claude/settings.local.json` → `.env.CLAUDE_CODE_USE_BEDROCK`
3. **Local settings (project-level)**: `./.claude/settings.json` → `.env.CLAUDE_CODE_USE_BEDROCK`
4. **User settings (fallback)**: `~/.claude/settings.json` → `.env.CLAUDE_CODE_USE_BEDROCK`

If `CLAUDE_CODE_USE_BEDROCK` equals `"1"` from any source, the backend is `bedrock`; otherwise it is `anthropic`.

The active backend is displayed in the startup banner when Ralph runs.

**Example**: Force Bedrock backend for a single run:

```sh
CLAUDE_CODE_USE_BEDROCK=1 ralph -m opus-4.5
```

### AGENTS.md

Ralph respects [`AGENTS.md`](https://agents.md) — a plain-Markdown file at the root of your repo (or in subdirectories) that gives AI coding agents project-specific instructions: build commands, test invocations, code style rules, and other conventions.

If your repo has an `AGENTS.md`, Ralph will pick it up automatically during the plan and build phases. This is a good place to put information that Ralph needs but that would clutter your human-facing README — things like exact linting flags, preferred patterns, or areas of the codebase to avoid touching.

See [agents.md](https://agents.md) for the format and examples.

## Task Management

The `task` CLI is a PostgreSQL-backed command-line tool for managing work items across the plan and build phases. It enables multi-agent coordination with atomic operations, lease-based claiming, and DAG-aware dependency scheduling.

### Plan Phase Commands

Commands used during planning to synchronize specs with the task backlog:

```sh
# Sync tasks from JSONL input (idempotent — safe to re-run)
cat tasks.jsonl | task plan-sync

# Export full task DAG as markdown-KV
ralph task list --all --markdown

# Show status summary (open, active, done, blocked, deleted)
task plan-status
```

### Build Phase Commands

Commands used by agents during the build loop to claim and complete work:

```sh
# Claim the highest-priority eligible task (atomic, lease-based)
task claim --agent <agent-id>
task claim --agent <agent-id> --lease 900    # custom lease (default 600s)

# Extend an active task's lease
task renew <id> --agent <agent-id>

# Mark a step within a task as done
task step-done <id> <seq>

# Complete a task (optionally with a result JSON)
task done <id>
task done <id> --result '{"commit":"abc123"}'

# Release a task back to open (increments retry count)
task fail <id>
task fail <id> --reason "build error"
```

### CRUD Commands

```sh
# Create a task
task create <id> <title> -p <priority> -c <category> -d <description>

# List tasks (excludes deleted by default)
task list
task list --status open,active
task list --markdown

# Show full task detail
task show <id>
task show <id> --with-deps      # include blocker results

# Update a task (done tasks are immutable)
task update <id> --title "New title" --priority 1

# Soft-delete a task
task delete <id>
```

### Dependency Commands

```sh
# Add a dependency (task is blocked until blocker is done)
task block <id> --by <blocker-id>

# Remove a dependency
task unblock <id> --by <blocker-id>

# Show recursive dependency tree
task deps <id>
```

### Agent Commands

Agents register before entering the build loop and deregister on exit:

```sh
# Register a new agent (returns 4-char hex ID)
task agent register

# List all agents
task agent list

# Deregister an agent (sets status to stopped)
task agent deregister <id>
```

Ralph's build loop handles agent registration automatically — it calls `task agent register` on startup and `task agent deregister` on exit via a trap handler. The agent ID is exported as `RALPH_AGENT_ID` for use when claiming tasks.

### Exit Codes

| Code | Meaning |
| ---- | ------- |
| `0`  | Success |
| `1`  | Error (invalid args, immutable task, wrong assignee) |
| `2`  | Not found (task, agent, step, or dependency doesn't exist) |

## Project Structure

```
ralph.sh              # Main loop runner
models.json           # Model alias → ID mapping
install.sh            # Installer (symlinks skills + CLI + task)
task                  # Task management CLI (PostgreSQL-backed)
docker-compose.yml    # PostgreSQL dev database
specs/                # Specification files (one per topic of concern)
skills/
  ralph-spec/         # JTBD → spec files
  ralph-plan/         # Specs → implementation plan
  ralph-build/        # Plan → working code
test/
  test_helper.bash    # Shared test setup
  libs/               # BATS helper libraries (git submodules)
  ralph_args.bats     # Argument parsing tests
  ralph_preflight.bats # Preflight check tests
  ralph_model.bats    # Model/backend resolution tests
  ralph_agent_lifecycle.bats # Agent register/deregister in build loop
  install.bats        # Installer tests
  task_*.bats         # Task CLI tests (create, list, show, update, delete,
                      #   block, deps, claim, renew, step_done, done, fail,
                      #   plan_sync, plan_status, agent_*)
```

## Development Database

The `task` CLI requires PostgreSQL. A Docker Compose file is provided for local development with PostgreSQL 17:

```sh
# Start PostgreSQL
docker compose up -d

# Set the connection URL (required for task CLI)
export RALPH_DB_URL="postgres://ralph:ralph@localhost:5464/ralph"

# Verify the connection
task plan-status

# Stop (data persists across restarts)
docker compose down

# Stop and wipe data
docker compose down -v
```

The `RALPH_DB_URL` environment variable must be set for all `task` commands. The database schema (tables: `tasks`, `task_steps`, `task_deps`, `agents`) is created automatically on first invocation.

## Testing

Ralph uses [bats-core](https://github.com/bats-core/bats-core) for testing the shell script logic.

### Setup

```sh
# Install bats-core (macOS)
brew install bats-core

# Or via npm
npm install -g bats

# Initialize test helper submodules (first time only)
git submodule update --init --recursive
```

### Running tests

```sh
# Run all tests
bats test/

# Run a specific test file
bats test/ralph_args.bats

# TAP output for machine consumption
bats --tap test/
```

```sh
# Run task-specific tests (requires running PostgreSQL)
bats test/task_create.bats
bats test/task_claim.bats
```

The test suite covers argument parsing, preflight checks, model/backend resolution, and the full task CLI (CRUD, dependencies, claiming, plan sync, agents). Shell tests run in isolation using temporary directories and stub the `claude` CLI. Task tests require a running PostgreSQL instance via `RALPH_DB_URL`.

## Acknowledgements

Ralph is based on the autonomous build loop technique [created by Geoffrey Huntley](https://ghuntley.com/ralph/). [The Ralph Playbook](https://github.com/ClaytonFarr/ralph-playbook) by Clayton Farr was a key inspiration for this implementation — it organizes the technique's principles, loop mechanics, and file conventions into a clear, actionable reference.
