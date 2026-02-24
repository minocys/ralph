# Worker Container Image

## Overview

Ralph needs a lightweight Docker image that can run Claude Code, interact with git repositories, and communicate with the PostgreSQL task database. This spec defines the Dockerfile for the `ralph-worker` image — an Alpine-based container using the native Claude Code binary (no Node.js runtime) with a multi-stage build for minimal image size.

## Requirements

- The Dockerfile is located at `Dockerfile.worker` in the ralph repository root.
- The build uses a **multi-stage Dockerfile** with two stages:
  - **Build stage** (`alpine:3.21`): installs `curl` and `bash`, runs `curl -fsSL https://claude.ai/install.sh | bash` to download the native Claude Code binary.
  - **Runtime stage** (`alpine:3.21`): copies the binary from the build stage and installs only runtime dependencies.
- The runtime stage installs the following system packages via `apk`: `bash`, `git`, `jq`, `postgresql-client` (for `psql` and `pg_isready`), `curl` (needed by `ralph init` for toolchain downloads).
- Claude Code is copied from the build stage: `COPY --from=build /root/.local/share/claude/ /usr/local/share/claude/` with a symlink at `/usr/local/bin/claude`.
- **Layer ordering**: system packages (`apk add`) are installed before application files (`COPY`) so that package layers are cached when only ralph source changes.
- The image includes a copy of the ralph repository (`ralph.sh`, `lib/`, `skills/`, `hooks/`, `task`, `install.sh`, `models.json`, `.env.example`, `db/`).
- The default working directory inside the container is `/workspace` (where project directories will be mounted).
- The image sets `ENTRYPOINT` to the container entrypoint script (see Container Entrypoint spec).
- The image does NOT contain any secrets, API keys, or credentials. All auth is injected at runtime via environment variables or bind mounts.
- The image is tagged as `ralph-worker:latest` by default. A `.dockerignore` file excludes `.git`, `node_modules`, `.env`, `test/`, and other non-essential files from the build context.
- BuildKit cache mounts (`--mount=type=cache`) should be used in the build stage for download caching.

## Dockerfile Reference

```dockerfile
# Stage 1: build — download Claude Code native binary
FROM alpine:3.21 AS build
RUN apk add --no-cache curl bash
RUN curl -fsSL https://claude.ai/install.sh | bash

# Stage 2: runtime — minimal Alpine
FROM alpine:3.21

# System packages (rarely changes — cached layer)
RUN apk add --no-cache bash git jq postgresql-client curl

# Copy claude binary from build stage
COPY --from=build /root/.local/share/claude/ /usr/local/share/claude/
RUN ln -s /usr/local/share/claude/versions/* /usr/local/bin/claude

# Non-root user
RUN adduser -D -u 1000 ralph
RUN mkdir -p /workspace && chown ralph:ralph /workspace

# Ralph application files (changes frequently — late layer)
COPY ralph.sh lib/ skills/ hooks/ task install.sh models.json .env.example db/ /opt/ralph/
RUN chown -R ralph:ralph /opt/ralph

COPY docker/entrypoint.sh /opt/ralph/docker/entrypoint.sh
RUN chmod +x /opt/ralph/docker/entrypoint.sh && chown ralph:ralph /opt/ralph/docker/entrypoint.sh

WORKDIR /workspace
USER ralph
ENTRYPOINT ["/opt/ralph/docker/entrypoint.sh"]
```

## Constraints

- The base must be `alpine:3.21` for both stages to keep the image small (target: under 250MB).
- No Node.js runtime is required — Claude Code is distributed as a native standalone binary.
- The image must not run as root in production. A non-root user (`ralph`, UID 1000) is created and used as the default user. The entrypoint may temporarily escalate for setup tasks if needed.
- The Dockerfile must be buildable without network access to private registries (all dependencies are from public Alpine repositories and `claude.ai`).
- The native binary is Linux x86_64/aarch64 — Alpine uses musl libc. The binary must be verified to work on Alpine (expected to work since it is a static/self-contained binary, but must be tested).
- The installer in the build stage runs as root — the binary path is `/root/.local/share/claude/`. If the installer changes this path, the COPY must be adjusted.

## Out of Scope

- Publishing the image to a container registry (Docker Hub, ECR, etc.).
- GPU support or CUDA dependencies.
- Pre-baking project-specific files into the image.
