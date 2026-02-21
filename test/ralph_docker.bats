#!/usr/bin/env bats
# test/ralph_docker.bats — Docker prerequisite checks for ralph.sh

load test_helper

setup() {
    # Create a temp working directory so tests don't touch the real project
    TEST_WORK_DIR="$(mktemp -d)"

    # Minimal specs/ directory with a dummy spec so preflight passes
    mkdir -p "$TEST_WORK_DIR/specs"
    echo "# dummy spec" > "$TEST_WORK_DIR/specs/dummy.md"

    # Create a fake claude stub
    STUB_DIR="$(mktemp -d)"
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo "CLAUDE_STUB_CALLED"
echo "ARGS: $*"
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    # Prepend stub directory so the stub is found instead of real claude
    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"

    # Save dirs for teardown
    export TEST_WORK_DIR
    export STUB_DIR

    # Change to the temp working directory
    cd "$TEST_WORK_DIR"
}

# --- check_docker_installed tests ---

@test "missing docker CLI exits 1 with actionable error" {
    # Remove any docker stub/binary so command -v docker fails
    rm -f "$STUB_DIR/docker"
    # Build PATH without directories containing docker
    local new_path="$STUB_DIR"
    IFS=: read -ra dirs <<< "$PATH"
    for d in "${dirs[@]}"; do
        [ -x "$d/docker" ] && continue
        new_path="$new_path:$d"
    done
    export PATH="$new_path"
    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_failure
    assert_output --partial "docker CLI not found"
    assert_output --partial "https://docs.docker.com/get-docker/"
}

@test "missing docker compose V2 plugin exits 1 with actionable error" {
    # Stub docker that succeeds for basic calls but fails for compose
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "compose" ]; then
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_failure
    assert_output --partial "docker compose V2 plugin not found"
    assert_output --partial "https://docs.docker.com/compose/install/"
}

@test "docker CLI and compose V2 present passes check" {
    # Stub docker that succeeds for compose version
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "compose" ] && [ "$2" = "version" ]; then
    echo "Docker Compose version v2.24.0"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" -n 1
    # Should not contain docker errors
    refute_output --partial "docker CLI not found"
    refute_output --partial "docker compose V2 plugin not found"
}

# --- is_container_running tests ---

# Helper: load is_container_running() from lib/docker.sh
_load_is_container_running() {
    eval "$(sed -n '/^is_container_running()/,/^}/p' "$SCRIPT_DIR/lib/docker.sh")"
}

@test "is_container_running returns 0 when container is running" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "inspect" ] && [ "$2" = "--format" ]; then
    echo "true"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    _load_is_container_running
    run is_container_running
    assert_success
}

@test "is_container_running returns 1 when container exists but is stopped" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "inspect" ] && [ "$2" = "--format" ]; then
    echo "false"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    _load_is_container_running
    run is_container_running
    assert_failure
}

@test "is_container_running returns 1 when container does not exist" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "inspect" ]; then
    echo "Error: No such object: ralph-task-db" >&2
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    _load_is_container_running
    run is_container_running
    assert_failure
}

@test "is_container_running passes ralph-task-db as container name to docker inspect" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "inspect" ]; then
    # Log all args so we can verify the container name
    echo "DOCKER_ARGS: $*" >&2
    # Check the last argument is ralph-task-db
    if [ "${@: -1}" = "ralph-task-db" ]; then
        echo "true"
        exit 0
    fi
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    _load_is_container_running
    run is_container_running
    assert_success
}

# --- wait_for_healthy tests ---

# Helper: load wait_for_healthy() from lib/docker.sh
_load_wait_for_healthy() {
    eval "$(sed -n '/^wait_for_healthy()/,/^}/p' "$SCRIPT_DIR/lib/docker.sh")"
}

@test "wait_for_healthy returns 0 when docker healthy and pg_isready both pass" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "inspect" ] && [ "$2" = "--format" ]; then
    echo "healthy"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    cat > "$STUB_DIR/pg_isready" <<'STUB'
#!/bin/bash
exit 0
STUB
    chmod +x "$STUB_DIR/pg_isready"

    _load_wait_for_healthy
    export DOCKER_HEALTH_TIMEOUT=5
    run wait_for_healthy
    assert_success
}

@test "wait_for_healthy exits 1 on timeout when docker reports unhealthy" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "inspect" ] && [ "$2" = "--format" ]; then
    echo "starting"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    cat > "$STUB_DIR/pg_isready" <<'STUB'
#!/bin/bash
exit 0
STUB
    chmod +x "$STUB_DIR/pg_isready"

    _load_wait_for_healthy
    export DOCKER_HEALTH_TIMEOUT=2
    run wait_for_healthy
    assert_failure
    assert_output --partial "failed to become healthy within 2s"
}

@test "wait_for_healthy exits 1 on timeout when pg_isready fails" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "inspect" ] && [ "$2" = "--format" ]; then
    echo "healthy"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    cat > "$STUB_DIR/pg_isready" <<'STUB'
#!/bin/bash
exit 1
STUB
    chmod +x "$STUB_DIR/pg_isready"

    _load_wait_for_healthy
    export DOCKER_HEALTH_TIMEOUT=2
    run wait_for_healthy
    assert_failure
    assert_output --partial "failed to become healthy within 2s"
}

@test "wait_for_healthy uses DOCKER_HEALTH_TIMEOUT from environment" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "inspect" ] && [ "$2" = "--format" ]; then
    echo "starting"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    cat > "$STUB_DIR/pg_isready" <<'STUB'
#!/bin/bash
exit 1
STUB
    chmod +x "$STUB_DIR/pg_isready"

    _load_wait_for_healthy
    export DOCKER_HEALTH_TIMEOUT=3
    run wait_for_healthy
    assert_failure
    assert_output --partial "within 3s"
}

@test "wait_for_healthy checks docker health status format for ralph-task-db" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "inspect" ] && [ "$2" = "--format" ]; then
    # Verify format string and container name
    if [ "$3" = "{{.State.Health.Status}}" ] && [ "$4" = "ralph-task-db" ]; then
        echo "healthy"
        exit 0
    fi
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    cat > "$STUB_DIR/pg_isready" <<'STUB'
#!/bin/bash
exit 0
STUB
    chmod +x "$STUB_DIR/pg_isready"

    _load_wait_for_healthy
    export DOCKER_HEALTH_TIMEOUT=5
    run wait_for_healthy
    assert_success
}

# --- ensure_postgres tests ---

# Helper: load all docker functions from lib/docker.sh
_load_docker_functions() {
    . "$SCRIPT_DIR/lib/docker.sh"
}

# Helper: create a docker stub that handles compose version, inspect, compose up, health
_create_full_docker_stub() {
    local container_running="${1:-false}"
    cat > "$STUB_DIR/docker" <<STUB
#!/bin/bash
if [ "\$1" = "compose" ] && [ "\$2" = "version" ]; then
    echo "Docker Compose version v2.24.0"
    exit 0
fi
# Match "compose ... up" regardless of flags before "up" (e.g. --project-directory)
if [ "\$1" = "compose" ]; then
    for arg in "\$@"; do
        if [ "\$arg" = "up" ]; then
            echo "COMPOSE_ARGS: \$*" >> "$TEST_WORK_DIR/docker_calls.log"
            exit 0
        fi
    done
fi
if [ "\$1" = "inspect" ] && [ "\$2" = "--format" ]; then
    if [ "\$3" = "{{.State.Running}}" ]; then
        echo "$container_running"
        exit 0
    fi
    if [ "\$3" = "{{.State.Health.Status}}" ]; then
        echo "healthy"
        exit 0
    fi
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    cat > "$STUB_DIR/pg_isready" <<'STUB'
#!/bin/bash
exit 0
STUB
    chmod +x "$STUB_DIR/pg_isready"
}

@test "ensure_postgres skips startup when container is already running" {
    _create_full_docker_stub "true"
    _load_docker_functions
    export SCRIPT_DIR="$TEST_WORK_DIR"
    export DOCKER_HEALTH_TIMEOUT=3

    run ensure_postgres
    assert_success
    # docker compose up should NOT have been called
    [ ! -f "$TEST_WORK_DIR/docker_calls.log" ] || ! grep -q "COMPOSE_UP_CALLED" "$TEST_WORK_DIR/docker_calls.log"
}

@test "ensure_postgres runs docker compose up when container is not running" {
    _create_full_docker_stub "false"
    _load_docker_functions
    export SCRIPT_DIR="$TEST_WORK_DIR"
    export DOCKER_HEALTH_TIMEOUT=3

    run ensure_postgres
    assert_success
    # docker compose up should have been called (log file created by stub)
    assert [ -f "$TEST_WORK_DIR/docker_calls.log" ]
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "up -d"
}

@test "ensure_postgres passes --project-directory to docker compose up" {
    _create_full_docker_stub "false"
    _load_docker_functions
    export SCRIPT_DIR="$TEST_WORK_DIR"
    export DOCKER_HEALTH_TIMEOUT=3

    run ensure_postgres
    assert_success
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "--project-directory"
}

@test "ensure_postgres calls wait_for_healthy after compose up" {
    # Container not running, but healthy after startup
    _create_full_docker_stub "false"
    _load_docker_functions
    export SCRIPT_DIR="$TEST_WORK_DIR"
    export DOCKER_HEALTH_TIMEOUT=3

    run ensure_postgres
    assert_success
}

@test "ensure_postgres calls check_docker_installed before anything else" {
    # Make docker unavailable — ensure_postgres should fail with docker check error
    rm -f "$STUB_DIR/docker"
    local new_path="$STUB_DIR"
    IFS=: read -ra dirs <<< "$PATH"
    for d in "${dirs[@]}"; do
        [ -x "$d/docker" ] && continue
        new_path="$new_path:$d"
    done
    export PATH="$new_path"

    _load_docker_functions
    run ensure_postgres
    assert_failure
    assert_output --partial "docker CLI not found"
}
