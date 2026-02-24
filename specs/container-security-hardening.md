# Container Security Hardening

## Overview

The default ralph Docker setup prioritizes developer convenience over security. This spec adds defense-in-depth measures — read-only root filesystem, privilege escalation prevention, restart policies, and credential hygiene — without breaking the development workflow.

## Requirements

- The `ralph-worker` service in `docker-compose.yml` sets `read_only: true` to make the root filesystem immutable.
- Writable paths are explicitly declared via `tmpfs` mounts:
  - `/tmp` (size 100M) for temporary files.
  - `/home/ralph/.claude` (size 50M) for entrypoint-generated settings and hook config.
- The persistent toolchain volume (`/home/ralph/.local`) and project bind mount (`/workspace`) remain writable.
- Both `ralph-worker` and `ralph-task-db` set `security_opt: [no-new-privileges:true]` to prevent privilege escalation via setuid/setgid binaries.
- Both services set `restart: unless-stopped` so containers recover from crashes without manual intervention.
- The entrypoint symlinks `ralph` and `task` into `$HOME/.local/bin/` (writable) instead of `/usr/local/bin/` (now read-only).
- `.env.example` includes a comment warning that the default PostgreSQL password should be changed for non-local deployments.

## Constraints

- The read-only filesystem must not break the entrypoint — all entrypoint write operations must target tmpfs or volume paths.
- The `jq` settings.json merge in the entrypoint writes to `$HOME/.claude/`, which is covered by the tmpfs mount. Settings are recreated on each container start (acceptable because the entrypoint is idempotent).
- Custom seccomp profiles are not included — they risk breaking Claude Code's toolchain installation and require profiling to build correctly.
- Resource limits (CPU/memory) are not included — the user indicated memory efficiency is not a priority.

## Out of Scope

- Custom seccomp or AppArmor profiles.
- TLS between worker and database containers.
- Secret management (Vault, Docker secrets).
- CPU or memory resource limits.
- Network policies.
