# Project & Auth Mounting

## Overview

The `ralph-worker` container needs access to project source code and Claude Code credentials at runtime. This spec defines the bind-mount strategy for injecting project directories and authentication materials into the container without baking secrets into the image.

## Requirements

- Project directories are bind-mounted into the container at `/workspace/<project-name>`. The mount is read-write so Claude Code can edit files and git can create commits.
- The host's `~/.claude` directory is bind-mounted into the container at `/home/ralph/.claude` (read-only). This provides Claude Code with OAuth tokens, settings, and installed skill symlinks.
- API credentials are passed via environment variables at container start (e.g., `ANTHROPIC_API_KEY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `CLAUDE_CODE_USE_BEDROCK`). No credentials are written to the image or to files inside the container.
- The `docker-compose.yml` worker service defines volume mounts using variable interpolation so users can configure project paths without editing the compose file directly. For example: `${RALPH_PROJECT_DIR:-.}:/workspace/project`.
- The container's `/home/ralph/.claude/skills` directory is populated by the entrypoint (see Container Entrypoint spec) so skills resolve correctly inside the container.
- The host's git configuration (`~/.gitconfig`) is bind-mounted read-only into the container so git operations (commits, branch creation) use the correct user identity.
- The container user (`ralph`, UID 1000) must have write access to mounted project directories. If UID mismatch occurs, the entrypoint should document the issue (not silently fail).

## Constraints

- Bind mounts are used (not named volumes) for project directories because the source of truth is the host filesystem.
- `~/.claude` is mounted read-only to prevent the container from modifying host-side Claude Code configuration.
- Environment variables for credentials must not appear in `docker-compose.yml` defaults or `.env.example` — they are passed at runtime via `docker compose run -e` or an `.env` override.
- On macOS with Docker Desktop, bind-mount performance for large repositories may be slow. This is a known Docker Desktop limitation, not a ralph issue.

## Out of Scope

- SSH key forwarding for private git remotes (users can mount `~/.ssh` manually if needed).
- Docker secrets or vault integration for credential management.
- Automatic UID/GID remapping to match host user.
- Syncing changes from container back to host (bind mounts are bidirectional by default).
