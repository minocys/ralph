# Ralph Modular Refactor

## Overview

`ralph.sh` has grown to 258 lines covering argument parsing, backend detection, model resolution, signal handling, output formatting, and the main loop. As new features are added (Docker auto-start, environment configuration), maintaining a single file becomes unwieldy. This spec splits `ralph.sh` into sourced `lib/` modules organized by concern, reducing the main script to a thin orchestrator.

## Requirements

- `ralph.sh` is refactored into a thin orchestrator (~50 lines) that sources five `lib/` modules and calls their functions in sequence.
- The `lib/` directory contains:
  - `lib/config.sh` — `parse_args()`, `detect_backend()`, `resolve_model()`. Extracted from current ralph.sh lines 20-111.
  - `lib/docker.sh` — `ensure_postgres()` and supporting functions (`check_docker_installed`, `ensure_env_file`, `is_container_running`, `wait_for_healthy`). New code per docker-auto-start spec.
  - `lib/signals.sh` — `setup_cleanup_trap()`, `setup_signal_handlers()`, `handle_int()`, `handle_term()`. Extracted from current ralph.sh lines 138-177.
  - `lib/output.sh` — `JQ_FILTER` variable and `print_banner()`. Extracted from current ralph.sh lines 179-215.
  - `lib/loop.sh` — `run_loop()`. Extracted from current ralph.sh lines 217-257.
- `ralph.sh` resolves `SCRIPT_DIR` using a portable symlink-following loop (`while [ -L "$SOURCE" ]`) instead of the current `dirname "$0"` pattern. This fixes a pre-existing bug where invocation via the `~/.local/bin/ralph` symlink would resolve `SCRIPT_DIR` to `~/.local/bin/` instead of the repo directory.
- `SCRIPT_DIR` is exported so all `lib/` modules and child processes can reference it.
- All `lib/` files share the same global namespace (sourced, not subshelled). Global variables use `UPPER_CASE`; function-local variables use the `local` keyword.
- The `--help` flag continues to work by reading from `$0` (which is `ralph.sh`, the orchestrator that retains the comment header).
- The orchestrator executes phases in order: (1) parse args, (2) detect backend / resolve model, (3) preflight checks (specs, plan file), (4) ensure postgres, (5) session setup (iteration counter, branch, tmpfile, agent registration), (6) setup traps, (7) print banner, (8) run loop.
- Existing BATS tests pass without modification beyond adding `export RALPH_SKIP_DOCKER=1` to test setup functions.
- A new `test/ralph_docker.bats` file tests Docker functions using stubbed `docker` commands (same PATH-stub pattern as existing tests).

## Constraints

- All `lib/` files are `source`d, not executed as subprocesses. They share globals and can reference each other's variables.
- No changes to the public interface: `ralph.sh` accepts the same flags (`--plan`, `-n`, `--model`, `--danger`, `--help`) and produces the same output.
- The `install.sh` script requires no changes — it symlinks `ralph.sh` which now follows the symlink chain internally.
- Bash 3.2+ compatibility must be maintained (macOS default).

## Out of Scope

- Refactoring the `task` script into modules (it remains a single file).
- Adding new CLI flags beyond what exists today.
- Changing the output format or jq filter behavior.
- Restructuring the test directory or test framework.
