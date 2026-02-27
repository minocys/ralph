#!/bin/bash
# lib/docker.sh — Docker lifecycle and PostgreSQL readiness for ralph.sh
#
# Provides:
#   check_docker_installed()  — verify docker CLI and compose V2 plugin
#   is_container_running()    — check if ralph-task-dev container is running
#   wait_for_healthy()        — poll until container healthy + pg_isready
#   ensure_env_file()         — create .env from .env.example if missing
#   load_env()                — ensure .env exists and source it
#   ensure_postgres()         — orchestrate full Docker lifecycle
#   derive_sandbox_name()     — deterministic sandbox name from repo+branch
#   lookup_sandbox()          — check sandbox existence and state
#
# Globals used:
#   SCRIPT_DIR (must be set before sourcing)
#   DOCKER_HEALTH_TIMEOUT (optional, default 30s)
#   POSTGRES_PORT (optional, default 5464)

# check_docker_installed: verify docker CLI and compose V2 are available
check_docker_installed() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Error: docker CLI not found. Install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    if ! docker compose version >/dev/null 2>&1; then
        echo "Error: docker compose V2 plugin not found. Install the Compose plugin: https://docs.docker.com/compose/install/"
        exit 1
    fi
}

# is_container_running: check if ralph-task-dev container is running
is_container_running() {
    docker inspect --format '{{.State.Running}}' ralph-task-dev 2>/dev/null | grep -q 'true'
}

# wait_for_healthy: poll docker health + pg_isready until healthy or timeout
wait_for_healthy() {
    local timeout="${DOCKER_HEALTH_TIMEOUT:-30}"
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        local health_status
        health_status=$(docker inspect --format '{{.State.Health.Status}}' ralph-task-dev 2>/dev/null) || true
        if [ "$health_status" = "healthy" ] && pg_isready -h localhost -p "${POSTGRES_PORT:-5464}" -q 2>/dev/null; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "Error: ralph-task-dev failed to become healthy within ${timeout}s"
    exit 1
}

# ensure_env_file: create .env from .env.example if missing
ensure_env_file() {
    if [ -f "$SCRIPT_DIR/.env" ]; then
        return 0
    fi
    if [ -f "$SCRIPT_DIR/.env.example" ]; then
        cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
        echo "Created .env from .env.example — edit as needed."
        return 0
    fi
    echo "Warning: .env.example not found in $SCRIPT_DIR — set RALPH_DB_URL manually or run: cp .env.example .env"
}

# load_env: ensure .env exists and source it, preserving existing RALPH_DB_URL
load_env() {
    ensure_env_file
    if [ -f "$SCRIPT_DIR/.env" ]; then
        local _saved_db_url="${RALPH_DB_URL:-}"
        # shellcheck disable=SC1091
        . "$SCRIPT_DIR/.env"
        if [ -n "$_saved_db_url" ]; then RALPH_DB_URL="$_saved_db_url"; fi
    fi
}

# ensure_postgres: orchestrate Docker container startup and health check
ensure_postgres() {
    if [ "${RALPH_SKIP_DOCKER:-}" = "1" ]; then
        return 0
    fi
    check_docker_installed
    if is_container_running; then
        wait_for_healthy
        return 0
    fi
    docker compose --project-directory "$SCRIPT_DIR" up -d
    wait_for_healthy
}

# _sanitize_name_component: replace non-alphanumeric chars with dashes,
# collapse consecutive dashes, strip leading/trailing dashes.
# Usage: _sanitize_name_component "some/string"
# Outputs sanitized string on stdout.
_sanitize_name_component() {
    local input="$1"
    # Replace non-alphanumeric with dash
    local sanitized
    sanitized=$(printf '%s' "$input" | tr -c 'a-zA-Z0-9' '-')
    # Collapse consecutive dashes
    sanitized=$(printf '%s' "$sanitized" | sed 's/-\{2,\}/-/g')
    # Strip leading dashes
    sanitized="${sanitized#-}"
    # Strip trailing dashes
    sanitized="${sanitized%-}"
    printf '%s' "$sanitized"
}

# derive_sandbox_name: build deterministic sandbox name from repo+branch.
# Pattern: ralph-{sanitized_repo}-{sanitized_branch}
# Truncated to 63 characters (no trailing dash).
# Repo/branch derived from env vars or git (same logic as lib/task get_scope).
# Sets global: SANDBOX_NAME
derive_sandbox_name() {
    local scope_repo scope_branch

    # Repo: env var takes precedence over git
    if [ -n "${RALPH_SCOPE_REPO:-}" ]; then
        scope_repo="$RALPH_SCOPE_REPO"
    else
        if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            echo 'Error: not inside a git repository' >&2
            exit 1
        fi

        local remote_url
        if ! remote_url=$(git remote get-url origin 2>/dev/null); then
            echo 'Error: no git remote "origin" found' >&2
            exit 1
        fi

        # Strip trailing .git suffix
        local clean_url="${remote_url%.git}"

        if [[ "$clean_url" =~ ^[a-zA-Z]+:// ]]; then
            # URL format: https://github.com/owner/repo
            local path="${clean_url#*://}"  # remove scheme
            path="${path#*/}"               # remove host
            scope_repo="$path"
        else
            # SCP-like SSH format: git@github.com:owner/repo
            scope_repo="${clean_url##*:}"
        fi
    fi

    # Branch: env var takes precedence over git
    if [ -n "${RALPH_SCOPE_BRANCH:-}" ]; then
        scope_branch="$RALPH_SCOPE_BRANCH"
    else
        if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            echo 'Error: not inside a git repository' >&2
            exit 1
        fi

        local branch
        branch=$(git branch --show-current)
        if [ -z "$branch" ]; then
            echo 'Error: detached HEAD state. Checkout a branch first' >&2
            exit 1
        fi
        scope_branch="$branch"
    fi

    # Sanitize components: replace slash between owner/repo with dash
    local sanitized_repo sanitized_branch
    sanitized_repo=$(_sanitize_name_component "$scope_repo")
    sanitized_branch=$(_sanitize_name_component "$scope_branch")

    # Assemble name
    local name="ralph-${sanitized_repo}-${sanitized_branch}"

    # Truncate to 63 characters
    if [ "${#name}" -gt 63 ]; then
        name="${name:0:63}"
        # Ensure no trailing dash after truncation
        name="${name%-}"
    fi

    SANDBOX_NAME="$name"
}

# lookup_sandbox: check if a sandbox exists and return its status.
# Usage: lookup_sandbox <name>
# Outputs: "running", "stopped", or "" (not found).
lookup_sandbox() {
    local name="$1"
    local json
    json=$(docker sandbox ls --json 2>/dev/null) || { echo ""; return 0; }

    local status
    status=$(printf '%s' "$json" | jq -r --arg name "$name" \
        '.[] | select(.name == $name) | .status // empty' 2>/dev/null)

    case "$status" in
        running) echo "running" ;;
        stopped|exited) echo "stopped" ;;
        *) echo "" ;;
    esac
}
