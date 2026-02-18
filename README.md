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

## Installation

```sh
git clone <repo-url> && cd ralph
./install.sh
```

This symlinks the skills into `~/.claude/skills/` and `ralph` into `~/.local/bin/`. Make sure `~/.local/bin` is in your `PATH`.

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

## Project Structure

```
ralph.sh              # Main loop runner
models.json           # Model alias → ID mapping
install.sh            # Installer (symlinks skills + CLI)
task                  # Task management CLI (PostgreSQL-backed)
docker-compose.yml    # PostgreSQL dev database
skills/
  ralph-spec/         # JTBD → spec files
  ralph-plan/         # Specs → implementation plan
  ralph-build/        # Plan → working code
test/
  ralph_args.bats     # Argument parsing tests
  ralph_preflight.bats # Preflight check tests
  ralph_model.bats    # Model/backend resolution tests
  task_cli.bats       # Task CLI tests
  test_helper.bash    # Shared test setup
  libs/               # BATS helper libraries (git submodules)
```

## Development Database

The `task` CLI requires PostgreSQL. A Docker Compose file is provided for local development:

```sh
# Start PostgreSQL
docker compose up -d

# Set the connection URL
export RALPH_DB_URL="postgres://ralph:ralph@localhost:5432/ralph"

# Verify the connection
task --help

# Stop (data persists across restarts)
docker compose down

# Stop and wipe data
docker compose down -v
```

The database schema is created automatically on first `task` invocation.

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

The test suite covers argument parsing, preflight checks, and model/backend resolution logic. All tests run in isolation using temporary directories and stub the `claude` CLI to avoid external dependencies.

## Acknowledgements

Ralph is based on the autonomous build loop technique [created by Geoffrey Huntley](https://ghuntley.com/ralph/). [The Ralph Playbook](https://github.com/ClaytonFarr/ralph-playbook) by Clayton Farr was a key inspiration for this implementation — it organizes the technique's principles, loop mechanics, and file conventions into a clear, actionable reference.
