# Persistent Toolchain Volume

## Overview

Tools installed inside the ralph-worker container (language runtimes, package managers, project dependencies) are lost when the container restarts. A named Docker volume mounted at the ralph user's local prefix preserves installed toolchains across container lifecycles.

## Requirements

- A named volume `ralph-toolchain` is defined in `docker-compose.yml`.
- The volume is mounted at `/home/ralph/.local` in the `ralph-worker` service.
- The entrypoint ensures `$HOME/.local/bin` exists and is prepended to `$PATH`.
- The volume is independent of the project bind mount — toolchains persist even if the project mount changes.
- `docker compose down` preserves the volume. Only `docker compose down -v` destroys it.

## Constraints

- The volume must be owned by the `ralph` user (UID 1000) — the entrypoint runs as ralph, so `mkdir -p` succeeds without root.
- The volume must not shadow files created during the Docker image build phase (no pre-population of `/home/ralph/.local` in the Dockerfile).
- The volume path (`~/.local`) follows XDG conventions so standard toolchain installers (rustup, pyenv, nvm) find it automatically.

## Out of Scope

- Automatic cleanup or garbage collection of stale toolchains.
- Volume backup or migration utilities.
- Shared toolchain volumes across multiple worker containers.
