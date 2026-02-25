# Docker Executor Toggle

## Overview

Ralph currently runs Claude Code as a local process on the host machine. This spec introduces a `DOCKER_EXECUTOR` environment variable that switches ralph between local execution (current behavior) and containerized execution, where Claude Code runs inside a Docker container. When disabled or unset, ralph behaves identically to today — no code paths change.

## Requirements

- A new environment variable `DOCKER_EXECUTOR` controls execution mode. Recognized values: `true` (containerized) and `false` or unset (local).
- When `DOCKER_EXECUTOR` is not set or is `false`, ralph.sh follows the existing local execution path with zero behavioral changes.
- When `DOCKER_EXECUTOR=true`, ralph.sh delegates Claude Code invocation to a running `ralph-worker` Docker container instead of calling `claude` directly on the host.
- The toggle is checked once during ralph.sh startup, after `parse_args` and before `run_loop`. The execution mode does not change mid-session.
- `DOCKER_EXECUTOR` can be set in the shell environment, in `.env`, or in `.env.example` (default: commented out or absent, meaning local mode).
- The `print_banner()` function displays the current execution mode (`local` or `docker`) so the user can confirm which path is active.
- When `DOCKER_EXECUTOR=true`, ralph.sh verifies that the `ralph-worker` container is running before entering the loop. If not running, it starts the worker service via `docker compose up -d ralph-worker`.

## Constraints

- The toggle must not affect plan mode vs build mode selection — both modes work under either execution mode.
- All existing CLI flags (`--plan`, `--model`, `--danger`, `-n`) must be forwarded to the containerized claude invocation.
- The `DOCKER_EXECUTOR` variable must not be confused with `RALPH_SKIP_DOCKER` (which controls PostgreSQL container startup, not execution mode).

## Out of Scope

- Automatic image building when `DOCKER_EXECUTOR=true` (the user must build the image beforehand or it is pulled).
- GUI or interactive mode inside the container.
- Windows or WSL-specific container execution paths.
