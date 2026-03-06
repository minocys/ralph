# Sandbox Signal Handling

## Overview

When ralph runs inside a Docker sandbox via `--docker`, the host ralph process is attached to the sandbox via `docker sandbox exec -it`. The existing two-stage interrupt (graceful then force-kill) does not apply here because the host ralph is not managing a local pipeline — it is forwarding I/O to a remote exec session. This spec defines how Ctrl+C behaves in the `--docker` context: detach from the sandbox, leaving it running.

## Requirements

### Ctrl+C behavior

- When the user presses Ctrl+C while attached to a `docker sandbox exec -it` session, the terminal sends SIGINT to the foreground process group.
- `docker sandbox exec -it` propagates SIGINT to the process running inside the sandbox. The sandboxed ralph receives SIGINT and handles it via its own two-stage interrupt logic (inside the sandbox).
- From the host perspective, a single Ctrl+C causes `docker sandbox exec` to detach and return. The sandbox continues running.
- The host ralph process exits with the exit code returned by `docker sandbox exec`.

### No custom signal handlers

- The `--docker` dispatch path must NOT install the custom SIGINT/SIGTERM handlers from `lib/signals.sh`. Those handlers are designed for the local pipeline pattern (`claude | tee | jq &; wait`), which does not apply.
- The `--docker` dispatch path does not source `lib/signals.sh` at all.
- Default signal behavior is sufficient: SIGINT interrupts the `docker sandbox exec` foreground process, which detaches and returns.

### Exit code forwarding

- The host ralph process must exit with the same exit code as `docker sandbox exec`.
- If exec returns 0, ralph exits 0.
- If exec returns 130 (SIGINT inside sandbox), ralph exits 130.
- If exec returns non-zero for other reasons, ralph forwards that code.

### Sandbox continuity

- After the host ralph process detaches (via Ctrl+C or natural exit), the sandbox remains in the running state.
- Internal processes (PostgreSQL, any running ralph loops) continue executing inside the sandbox.
- The user can re-attach by running the same `ralph --docker <subcommand>` command again, which will exec a new ralph process in the existing running sandbox.

## Constraints

- The host ralph process in `--docker` mode is a thin wrapper around `docker sandbox exec`. It must not introduce signal handling complexity that interferes with the exec session's native behavior.
- The `docker sandbox exec -it` command manages its own TTY and signal propagation. Ralph should not layer additional signal logic on top.

## Out of Scope

- Custom detach key sequences (Docker's `--detach-keys` option).
- Reattaching to a specific running ralph process inside the sandbox (each exec starts a new process).
- Graceful shutdown of the sandbox itself from the host ralph process.
- Background monitoring of sandbox health after detach.
