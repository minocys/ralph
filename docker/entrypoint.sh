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
# Host ~/.claude import (read-only bind mount at /mnt/claude-host)
# ---------------------------------------------------------------------------

# Copy host Claude Code configuration into the container-local ~/.claude
# so the entrypoint can freely modify settings.json and skills/ without
# requiring write access to the host mount.
if [ -d /mnt/claude-host ]; then
    mkdir -p "$HOME/.claude"
    cp -a /mnt/claude-host/. "$HOME/.claude/"
    echo "entrypoint: imported host ~/.claude from /mnt/claude-host (read-only)" >&2
fi

# ---------------------------------------------------------------------------
# Skill symlinks
# ---------------------------------------------------------------------------

mkdir -p ~/.claude/skills/
_skill_count=0
for skill_dir in "$RALPH_DIR"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    ln -sfn "$skill_dir" ~/.claude/skills/"$skill_name"
    _skill_count=$((_skill_count + 1))
done
echo "entrypoint: linked $_skill_count skill(s) into ~/.claude/skills/" >&2

# ---------------------------------------------------------------------------
# CLI symlinks (ralph.sh and task)
# ---------------------------------------------------------------------------

ln -sf "$RALPH_DIR/ralph.sh" /usr/local/bin/ralph
ln -sf "$RALPH_DIR/task" /usr/local/bin/task
echo "entrypoint: linked ralph and task into /usr/local/bin/" >&2

# ---------------------------------------------------------------------------
# Hooks
# ---------------------------------------------------------------------------

# Configure PreCompact and SessionEnd hooks in ~/.claude/settings.json.
# If settings.json exists from a bind mount, merge hooks into it.
# Otherwise, create a new settings.json with only hook configuration.
_settings_file="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
if [ ! -f "$_settings_file" ]; then
    echo '{}' > "$_settings_file"
fi
jq --arg ralph "$RALPH_DIR" \
    '.hooks = ((.hooks // {}) * {
        "PreCompact": [{"matcher":"*","hooks":[{"type":"command","command":("bash " + $ralph + "/hooks/precompact.sh")}]}],
        "SessionEnd": [{"matcher":"*","hooks":[{"type":"command","command":("bash " + $ralph + "/hooks/session_end.sh")}]}]
    })' "$_settings_file" > "${_settings_file}.tmp" && mv "${_settings_file}.tmp" "$_settings_file"
echo "entrypoint: configured hooks in $_settings_file" >&2

# ---------------------------------------------------------------------------
# Keep-alive
# ---------------------------------------------------------------------------

# Warn if /workspace is empty (no project mounted)
if [ -z "$(ls -A /workspace 2>/dev/null)" ]; then
    echo "Warning: /workspace is empty — mount a project directory to get started." >&2
fi

# Keep the container running for docker exec sessions
exec sleep infinity
