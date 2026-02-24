# Ralph Modular Refactor

## Overview

`ralph.sh` was originally a monolith covering argument parsing, backend detection, model resolution, signal handling, output formatting, and the main loop. The first refactor split it into sourced `lib/` modules organized by concern, reducing the main script to a thin orchestrator. The second refactor (see `cli-subcommand-dispatch.md`) restructures the orchestrator into a subcommand dispatcher where `plan`, `build`, and `task` are peer subcommands, each sourcing only the modules they need.

## Requirements

- `ralph.sh` is a thin subcommand dispatcher that routes to `plan`, `build`, or `task` based on the first positional argument (see `cli-subcommand-dispatch.md`)
- The `lib/` directory contains:
  - `lib/config.sh` — `parse_args()`, `detect_backend()`, `resolve_model()`, `preflight()`. Sourced by plan and build subcommands.
  - `lib/docker.sh` — `ensure_postgres()` and supporting functions (`check_docker_installed`, `ensure_env_file`, `is_container_running`, `wait_for_healthy`). Sourced by plan and build subcommands.
  - `lib/signals.sh` — `setup_cleanup_trap()`, `setup_signal_handlers()`, `handle_int()`, `handle_term()`. Sourced by plan and build subcommands.
  - `lib/output.sh` — `JQ_FILTER` variable and `print_banner()`. Sourced by plan and build subcommands.
  - `lib/plan_loop.sh` — `setup_session()` (shared) and `run_plan_loop()`. Sourced by plan subcommand only.
  - `lib/build_loop.sh` — `run_build_loop()`. Sourced by build subcommand only.
  - `lib/task` — the task CLI script, exec'd directly by `ralph task` (see `task-cli-relocation.md`).
- `ralph.sh` resolves `SCRIPT_DIR` using a portable symlink-following loop (`while [ -L "$SOURCE" ]`) instead of the current `dirname "$0"` pattern. This fixes a pre-existing bug where invocation via the `~/.local/bin/ralph` symlink would resolve `SCRIPT_DIR` to `~/.local/bin/` instead of the repo directory.
- `SCRIPT_DIR` is exported so all `lib/` modules and child processes can reference it.
- All sourced `lib/` files share the same global namespace. Global variables use `UPPER_CASE`; function-local variables use the `local` keyword.
- `lib/task` is not sourced — it is exec'd as a separate process by the `ralph task` subcommand.
- The plan and build subcommands execute phases in order: (1) parse args, (2) detect backend / resolve model, (3) preflight checks, (4) ensure postgres, (5) session setup, (6) setup traps, (7) print banner, (8) run loop.
- Existing BATS tests pass without modification; the shared `test_helper.bash` setup already prepends PATH-stub `docker` and `pg_isready` scripts so `ensure_postgres()` succeeds without a running Docker daemon.

## Constraints

- All `lib/*.sh` files are `source`d, not executed as subprocesses. They share globals and can reference each other's variables.
- `lib/task` is the exception — it is exec'd as a standalone script.
- The public interface changes from flag-based (`ralph --plan`) to subcommand-based (`ralph plan`) — see `cli-subcommand-dispatch.md`.
- `install.sh` symlinks `ralph.sh` to `~/.local/bin/ralph` — the `task` symlink is removed (see `task-cli-relocation.md`).
- Bash 3.2+ compatibility must be maintained (macOS default).

## Out of Scope

- Adding new subcommands beyond plan, build, task.
- Changing the output format or jq filter behavior.
- Restructuring the test directory or test framework.
