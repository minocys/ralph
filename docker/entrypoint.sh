#!/bin/bash
# docker/entrypoint.sh — container entrypoint for ralph-worker
#
# Bootstraps the container environment (skills, hooks, symlinks),
# validates required environment variables, and keeps the container
# running for interactive docker exec sessions.

set -euo pipefail

RALPH_DIR="/opt/ralph"

# Source .env defaults from ralph installation directory
if [ -f "$RALPH_DIR/.env.example" ]; then
    # shellcheck disable=SC1091
    . "$RALPH_DIR/.env.example"
fi

# Default RALPH_DB_URL to internal Docker network address
export RALPH_DB_URL="${RALPH_DB_URL:-postgres://ralph:ralph@ralph-task-db:5432/ralph}"

# Validate required database connection
if [ -z "${RALPH_DB_URL:-}" ] && [ -z "${POSTGRES_USER:-}" ]; then
    echo "Error: RALPH_DB_URL or POSTGRES_* variables must be set."
    echo "Set RALPH_DB_URL or provide POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB, POSTGRES_PORT."
    exit 1
fi

# Run install.sh to set up skills, hooks, and symlinks (idempotent)
if [ -x "$RALPH_DIR/install.sh" ]; then
    "$RALPH_DIR/install.sh"
fi

# Warn if /workspace is empty (no project mounted)
if [ -z "$(ls -A /workspace 2>/dev/null)" ]; then
    echo "Warning: /workspace is empty — mount a project directory to get started."
fi

# Keep the container running for docker exec sessions
exec sleep infinity
