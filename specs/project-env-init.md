# Project Environment Init

## Overview

Ralph's Docker worker ships as a minimal Alpine image with no language toolchains pre-installed. The `ralph init` subcommand uses Claude Code (Haiku model by default) to analyze the mounted project, detect its language and dependency requirements, and install the necessary runtimes and tools into the persistent toolchain volume.

## Requirements

- `ralph init` is a new subcommand recognized by `parse_args()` as the first positional argument (before flags).
- `parse_args()` sets `SUBCOMMAND="init"` when `init` is the first argument, `SUBCOMMAND="run"` otherwise (default). Existing flags (`--model`, `--plan`, etc.) continue to work after the subcommand.
- `ralph.sh` dispatches on `SUBCOMMAND`: `init` runs `run_init()` then exits; `run` follows the existing orchestration path (preflight → loop).
- `ralph init` does NOT run preflight, worktree setup, agent registration, signal handlers, or the iteration loop.
- `ralph init` detects `RALPH_EXEC_MODE` and uses `docker exec ralph-worker claude` when in docker mode, `claude` when local.
- When in docker mode, `ralph init` ensures the worker container is running before invoking Claude Code.
- `run_init()` invokes Claude Code with a prompt that instructs it to:
  1. Examine project files (package.json, Cargo.toml, go.mod, requirements.txt, pyproject.toml, Gemfile, etc.) to identify languages and package managers.
  2. Install needed runtimes and tools into `~/.local/`.
  3. Run dependency installation (npm install, pip install, cargo build, etc.).
  4. Print a summary of what was installed and verified.
- The default model is `haiku` (resolved via `models.json` and `ACTIVE_BACKEND`). The user can override with `--model <alias>`.
- `--dangerously-skip-permissions` is passed to Claude Code because init must run install commands without interactive approval.
- The new module is located at `lib/init.sh` and sourced by `ralph.sh`.

## Constraints

- The subcommand must not break existing `ralph --plan`, `ralph -n 5`, or bare `ralph` invocations — backward compatibility is mandatory.
- Unknown subcommands (anything that is not `init` and does not start with `-`) print an error and exit 1.
- The init prompt must be language-agnostic — it works by examining project files, not by hardcoding language detection logic.
- `ralph init` is idempotent in practice — Claude Code inspects what's already installed and skips re-installation. This is delegated to the LLM's judgment, not enforced by ralph.

## Out of Scope

- Automatic init on first `ralph` run (init is always explicit).
- A `ralph clean` or `ralph reset` command to wipe installed toolchains.
- Caching or lockfile-based init skip logic.
- Language-specific Dockerfile variants (ralph-worker:python, etc.).
