# Docker Sandbox Dispatch

## Overview

Ralph plan and build loops run directly on the host, sharing the host's Docker daemon and filesystem. For isolation and parallelism, users need to run ralph inside a Docker sandbox — a lightweight microVM with its own Docker daemon, filesystem, and network namespace. This spec adds a `--docker` flag that intercepts the subcommand, ensures a sandbox exists for the current repo+branch, and execs the ralph command inside it.

## Requirements

### Flag parsing

- `ralph.sh` must recognize `--docker` as a global flag before the subcommand: `ralph --docker <subcommand> [flags]`.
- `--docker` is parsed and consumed in the top-level case statement, before subcommand dispatch.
- Everything after `--docker` is captured verbatim and forwarded to the ralph invocation inside the sandbox. For example, `ralph --docker build -n 3 --model opus-4.5 --danger` runs `ralph build -n 3 --model opus-4.5 --danger` inside the sandbox.
- `ralph --docker` with no subcommand must print an error to stderr and exit 1 (a subcommand is required).
- `ralph --docker --help` must print docker-specific usage showing the flag syntax and available options.

### Top-level help update

- The top-level `ralph --help` output must include `--docker` in a global options section above the subcommand list.
- Description: `--docker  Run the command inside a Docker sandbox`.

### Preflight

- Before sandbox operations, `ralph.sh` must verify that the `docker` CLI is available (which docker). If missing, exit 1 with an actionable error message.
- No further validation is required — sandbox CLI errors are surfaced directly to the user.

### Sandbox lifecycle

- Derive the sandbox name from the current repo and branch (see sandbox-identity spec).
- Check if a sandbox with that name already exists using `docker sandbox ls --json`.
- If no sandbox exists: create one, bootstrap it, then exec the ralph command (see sandbox-bootstrap spec).
- If a sandbox exists and is running: exec the ralph command directly.
- If a sandbox exists but is stopped: start it with `docker sandbox run <name>`, then exec the ralph command.

### Exec invocation

- The ralph command is executed inside the sandbox via `docker sandbox exec -it <name> ralph <subcommand> [flags]`.
- The `-it` flags are always used (interactive TTY).
- The exec call must forward the exit code from the sandboxed ralph process.
- Environment variables for credentials are passed via `-e` flags on the exec call (see sandbox-credentials spec).

### Supported subcommands

- All subcommands are supported: `plan`, `build`, `task`.
- The `--docker` flag does not alter subcommand behavior — it only changes where the subcommand runs.

## Constraints

- `ralph.sh` must remain a pure bash script (bash 3.2+, jq only external dependency).
- The `--docker` flag is mutually exclusive with direct host execution — when `--docker` is present, the host ralph does not source lib modules, start local PostgreSQL, or run loops. It delegates entirely to the sandbox.
- The `docker sandbox` CLI is an experimental Docker Desktop plugin (v4.58+). Ralph does not vendor or manage the plugin itself.

## Out of Scope

- Sandbox lifecycle management commands (`ralph --docker ls`, `ralph --docker stop`, `ralph --docker rm`). Users manage sandboxes directly via `docker sandbox` CLI.
- A `--detach` flag. Users detach by pressing Ctrl+C (see sandbox-signal-handling spec).
- Building custom sandbox templates.
- Running ralph without Docker Desktop (Linux containers, remote Docker hosts).
