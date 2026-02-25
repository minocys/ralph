# CLI Subcommand Dispatch

Restructure ralph.sh from a sequential orchestrator into a thin subcommand dispatcher where `plan`, `build`, and `task` are peer subcommands.

## Requirements

### Subcommand routing

- ralph.sh must detect the first positional argument as the subcommand
- Recognized subcommands: `plan`, `build`, `task`
- `ralph task <args>` must exec directly to `lib/task` with remaining arguments, bypassing all other setup
- `ralph plan <flags>` must source shared libs (config.sh, docker.sh, signals.sh, output.sh) and plan_loop.sh, then parse flags and run the plan loop
- `ralph build <flags>` must source shared libs (config.sh, docker.sh, signals.sh, output.sh) and build_loop.sh, then parse flags and run the build loop
- `ralph` (no arguments), `ralph --help`, and `ralph -h` must print top-level help and exit 0
- Unknown subcommands must print an error to stderr and exit 1

### Top-level help

- Help must list available subcommands with brief descriptions:
  - `plan` — Run the planner (study specs, create tasks)
  - `build` — Run the builder (claim and implement tasks)
  - `task` — Interact with the task backlog
- Help must include: `Run 'ralph <command> --help' for command-specific options.`

### Per-subcommand help

- `ralph plan --help` must print plan-specific flags (iterations, model, danger) and exit 0
- `ralph build --help` must print build-specific flags (iterations, model, danger) and exit 0
- `ralph task --help` must delegate to lib/task's own usage function

### Flag parsing

- Flags must come after the subcommand: `ralph plan -n 3 --danger`
- The `--plan` / `-p` flag is removed — `plan` is now a subcommand
- Shared flags between plan and build: `--max-iterations`/`-n`, `--model`/`-m`, `--danger`, `--help`/`-h`
- `-n` defaults differ by mode: plan defaults to 1, build defaults to 0 (unlimited)
- `-n 0` must be rejected in plan mode with an error (plan requires >= 1)

### Module sourcing

- `ralph task` must not source any lib/ modules — it exec's directly to lib/task
- `ralph plan` and `ralph build` must source: lib/config.sh, lib/docker.sh, lib/signals.sh, lib/output.sh
- `ralph plan` must additionally source lib/plan_loop.sh
- `ralph build` must additionally source lib/build_loop.sh

## Constraints

- ralph.sh must remain a pure bash script (bash 3.2+, jq only external dependency)
- The portable symlink-following resolution of SCRIPT_DIR must be preserved
- The comment-header `--help` pattern (sed extracting from `$0`) is replaced by a dedicated usage function

## Out of Scope

- Adding subcommands beyond plan, build, task
- Interactive mode or subcommand auto-detection
- Tab completion or shell integration
- Changing the behavior of plan, build, or task internals — only the dispatch changes
