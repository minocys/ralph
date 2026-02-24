#!/bin/bash
# lib/docker.sh — Docker lifecycle and PostgreSQL readiness for ralph.sh
#
# Provides:
#   detect_docker_executor()  — set RALPH_EXEC_MODE based on DOCKER_EXECUTOR
#   check_docker_installed()  — verify docker CLI and compose V2 plugin
#   is_container_running()    — check if ralph-task-db container is running
#   wait_for_healthy()        — poll until container healthy + pg_isready
#   ensure_env_file()         — create .env from .env.example if missing
#   load_env()                — ensure .env exists and source it
#   ensure_postgres()         — orchestrate full Docker lifecycle
#
# Globals used:
#   SCRIPT_DIR (must be set before sourcing)
#   DOCKER_HEALTH_TIMEOUT (optional, default 30s)
#   POSTGRES_PORT (optional, default 5499)

# detect_docker_executor: set RALPH_EXEC_MODE based on DOCKER_EXECUTOR env var
# When DOCKER_EXECUTOR is "true" (case-insensitive), sets RALPH_EXEC_MODE=docker.
# Otherwise sets RALPH_EXEC_MODE=local. Always returns 0.
detect_docker_executor() {
    local val="${DOCKER_EXECUTOR:-}"
    # Case-insensitive comparison
    val="$(echo "$val" | tr '[:upper:]' '[:lower:]')"
    if [ "$val" = "true" ]; then
        RALPH_EXEC_MODE="docker"
    else
        RALPH_EXEC_MODE="local"
    fi
    export RALPH_EXEC_MODE
    return 0
}

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

# is_container_running: check if ralph-task-db container is running
is_container_running() {
    docker inspect --format '{{.State.Running}}' ralph-task-db 2>/dev/null | grep -q 'true'
}

# wait_for_healthy: poll docker health + pg_isready until healthy or timeout
wait_for_healthy() {
    local timeout="${DOCKER_HEALTH_TIMEOUT:-30}"
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        local health_status
        health_status=$(docker inspect --format '{{.State.Health.Status}}' ralph-task-db 2>/dev/null) || true
        if [ "$health_status" = "healthy" ] && pg_isready -h localhost -p "${POSTGRES_PORT:-5499}" -q 2>/dev/null; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "Error: ralph-task-db failed to become healthy within ${timeout}s"
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
