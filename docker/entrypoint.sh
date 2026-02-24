#!/bin/bash
# docker/entrypoint.sh — container entrypoint for ralph-worker
#
# Bootstraps the container environment (skills, hooks, symlinks),
# validates required environment variables, and keeps the container
# running for interactive docker exec sessions.

set -euo pipefail

RALPH_DIR="/opt/ralph"

# ---------------------------------------------------------------------------
# Environment validation
# ---------------------------------------------------------------------------

# Source .env defaults — prefer .env, fall back to .env.example
if [ -f "$RALPH_DIR/.env" ]; then
    # shellcheck disable=SC1091
    . "$RALPH_DIR/.env"
elif [ -f "$RALPH_DIR/.env.example" ]; then
    # shellcheck disable=SC1091
    . "$RALPH_DIR/.env.example"
fi

# Default RALPH_DB_URL to internal Docker network address
export RALPH_DB_URL="${RALPH_DB_URL:-postgres://ralph:ralph@ralph-task-db:5432/ralph}"

# Validate required database connection
if [ -z "${RALPH_DB_URL:-}" ] && \
   { [ -z "${POSTGRES_USER:-}" ] || [ -z "${POSTGRES_PASSWORD:-}" ] || [ -z "${POSTGRES_DB:-}" ]; }; then
    echo "Error: Database connection is not configured." >&2
    echo "" >&2
    echo "Fix: set RALPH_DB_URL or provide all of POSTGRES_USER, POSTGRES_PASSWORD, and POSTGRES_DB." >&2
    echo "" >&2
    echo "  Option 1 — set RALPH_DB_URL directly:" >&2
    echo "    export RALPH_DB_URL=\"postgres://user:pass@host:5432/dbname\"" >&2
    echo "" >&2
    echo "  Option 2 — set individual POSTGRES_* variables:" >&2
    echo "    export POSTGRES_USER=ralph" >&2
    echo "    export POSTGRES_PASSWORD=ralph" >&2
    echo "    export POSTGRES_DB=ralph" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Symlinks
# ---------------------------------------------------------------------------

# Run install.sh to set up skills and binary symlinks (idempotent)
if [ -x "$RALPH_DIR/install.sh" ]; then
    "$RALPH_DIR/install.sh"
fi

# ---------------------------------------------------------------------------
# Hooks
# ---------------------------------------------------------------------------

# Claude Code hooks (PreCompact, SessionEnd) are configured by install.sh
# above. Additional hook setup can be added here if needed.

# ---------------------------------------------------------------------------
# Keep-alive
# ---------------------------------------------------------------------------

# Warn if /workspace is empty (no project mounted)
if [ -z "$(ls -A /workspace 2>/dev/null)" ]; then
    echo "Warning: /workspace is empty — mount a project directory to get started."
fi

# Keep the container running for docker exec sessions
exec sleep infinity
