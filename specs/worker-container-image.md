# Worker Container Image

## Overview

Ralph needs a lightweight Docker image that can run Claude Code, interact with git repositories, and communicate with the PostgreSQL task database. This spec defines the Dockerfile for the `ralph-worker` image — an Alpine-based container with the minimum dependencies required to execute ralph loops.

## Requirements

- The Dockerfile is located at `Dockerfile.worker` in the ralph repository root.
- The base image is `node:20-alpine` (provides Node.js runtime required by Claude Code's npm package).
- The image installs the following system packages via `apk`: `bash`, `git`, `jq`, `postgresql-client` (for `psql` and `pg_isready`).
- Claude Code is installed globally via `npm install -g @anthropic-ai/claude-code`.
- The image includes a copy of the ralph repository (`ralph.sh`, `lib/`, `skills/`, `hooks/`, `task`, `install.sh`, `models.json`, `.env.example`, `db/`).
- The default working directory inside the container is `/workspace` (where project directories will be mounted).
- The image sets `ENTRYPOINT` to the container entrypoint script (see Container Entrypoint spec).
- The image does NOT contain any secrets, API keys, or credentials. All auth is injected at runtime via environment variables or bind mounts.
- The image is tagged as `ralph-worker:latest` by default. A `.dockerignore` file excludes `.git`, `node_modules`, `.env`, `test/`, and other non-essential files from the build context.

## Constraints

- The base must be Alpine-derived to keep the image small (target: under 400MB).
- `node:20-alpine` is required because Claude Code is an npm package — a separate Node.js install on plain Alpine would add unnecessary complexity.
- The image must not run as root in production. A non-root user (`ralph`, UID 1000) is created and used as the default user. The entrypoint may temporarily escalate for setup tasks if needed.
- The Dockerfile must be buildable without network access to private registries (all dependencies are from public npm and Alpine repositories).

## Out of Scope

- Multi-stage builds or image size optimization beyond Alpine base selection.
- Publishing the image to a container registry (Docker Hub, ECR, etc.).
- GPU support or CUDA dependencies.
- Pre-baking project-specific files into the image.
