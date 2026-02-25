#!/usr/bin/env bats
# test/ensure_worker_container.bats — ensure_worker_container tests for lib/docker.sh

load test_helper

# Source lib/docker.sh to get ensure_worker_container
_source_docker_lib() {
    export SCRIPT_DIR="$SCRIPT_DIR"
    . "$SCRIPT_DIR/lib/docker.sh"
}

# Helper: find compose subcommand (ps, up, version) from args.
# docker compose --project-directory <dir> ps ... → subcommand is "ps"
# We embed this logic into each stub via a function.

# Helper: create a docker stub that reports ralph-worker as running
_stub_worker_running() {
    cat > "$STUB_DIR/docker" <<'DOCKERSTUB'
#!/bin/bash
if [ "$1" != "compose" ]; then exit 0; fi
shift
# Find subcommand by skipping flags
while [ $# -gt 0 ]; do
    case "$1" in
        --project-directory) shift 2 ;;
        --format)            shift 2 ;;
        -*)                  shift ;;
        ps)     echo "running"; exit 0 ;;
        version) echo "Docker Compose version v2.24.0"; exit 0 ;;
        up)     exit 0 ;;
        *)      shift ;;
    esac
done
exit 0
DOCKERSTUB
    chmod +x "$STUB_DIR/docker"
}

# Helper: worker not running initially, starts after docker compose up
_stub_worker_not_running_then_starts() {
    cat > "$STUB_DIR/docker" <<DOCKERSTUB
#!/bin/bash
STATE_FILE="$STUB_DIR/.worker_state"
if [ "\$1" != "compose" ]; then exit 0; fi
shift
while [ \$# -gt 0 ]; do
    case "\$1" in
        --project-directory) shift 2 ;;
        --format)            shift 2 ;;
        -d)                  shift ;;
        -*)                  shift ;;
        ps)
            if [ -f "\$STATE_FILE" ]; then
                echo "running"
            else
                echo "exited"
            fi
            exit 0
            ;;
        version) echo "Docker Compose version v2.24.0"; exit 0 ;;
        up)
            touch "\$STATE_FILE"
            exit 0
            ;;
        *)      shift ;;
    esac
done
exit 0
DOCKERSTUB
    chmod +x "$STUB_DIR/docker"
}

# Helper: worker not running, docker compose up fails
_stub_worker_up_fails() {
    cat > "$STUB_DIR/docker" <<'DOCKERSTUB'
#!/bin/bash
if [ "$1" != "compose" ]; then exit 0; fi
shift
while [ $# -gt 0 ]; do
    case "$1" in
        --project-directory) shift 2 ;;
        --format)            shift 2 ;;
        -d)                  shift ;;
        -*)                  shift ;;
        ps)     echo ""; exit 0 ;;
        version) echo "Docker Compose version v2.24.0"; exit 0 ;;
        up)     echo "Error: image not found" >&2; exit 1 ;;
        *)      shift ;;
    esac
done
exit 0
DOCKERSTUB
    chmod +x "$STUB_DIR/docker"
}

# Helper: worker never reaches running state after up
_stub_worker_never_healthy() {
    cat > "$STUB_DIR/docker" <<'DOCKERSTUB'
#!/bin/bash
if [ "$1" != "compose" ]; then exit 0; fi
shift
while [ $# -gt 0 ]; do
    case "$1" in
        --project-directory) shift 2 ;;
        --format)            shift 2 ;;
        -d)                  shift ;;
        -*)                  shift ;;
        ps)     echo "created"; exit 0 ;;
        version) echo "Docker Compose version v2.24.0"; exit 0 ;;
        up)     exit 0 ;;
        *)      shift ;;
    esac
done
exit 0
DOCKERSTUB
    chmod +x "$STUB_DIR/docker"
}

# --- already running ---

@test "ensure_worker_container returns 0 when worker is already running" {
    _source_docker_lib
    _stub_worker_running
    run ensure_worker_container
    assert_success
}

@test "ensure_worker_container does not call docker compose up when already running" {
    _source_docker_lib
    cat > "$STUB_DIR/docker" <<DOCKERSTUB
#!/bin/bash
LOG_FILE="$STUB_DIR/.docker_log"
if [ "\$1" != "compose" ]; then exit 0; fi
shift
while [ \$# -gt 0 ]; do
    case "\$1" in
        --project-directory) shift 2 ;;
        --format)            shift 2 ;;
        -d)                  shift ;;
        -*)                  shift ;;
        ps)     echo "ps" >> "\$LOG_FILE"; echo "running"; exit 0 ;;
        version) echo "Docker Compose version v2.24.0"; exit 0 ;;
        up)     echo "up" >> "\$LOG_FILE"; exit 0 ;;
        *)      shift ;;
    esac
done
exit 0
DOCKERSTUB
    chmod +x "$STUB_DIR/docker"

    ensure_worker_container
    # Verify 'up' was NOT called
    if [ -f "$STUB_DIR/.docker_log" ]; then
        run grep -c "^up$" "$STUB_DIR/.docker_log"
        assert_output "0"
    fi
}

# --- not running, starts successfully ---

@test "ensure_worker_container starts worker when not running" {
    _source_docker_lib
    _stub_worker_not_running_then_starts
    run ensure_worker_container
    assert_success
}

@test "ensure_worker_container prints startup message to stderr" {
    _source_docker_lib
    _stub_worker_not_running_then_starts
    run ensure_worker_container
    assert_success
    assert_output --partial "Starting ralph-worker container..."
}

# --- docker compose up fails ---

@test "ensure_worker_container exits 1 when docker compose up fails" {
    _source_docker_lib
    _stub_worker_up_fails
    run ensure_worker_container
    assert_failure
}

@test "ensure_worker_container prints error when docker compose up fails" {
    _source_docker_lib
    _stub_worker_up_fails
    run ensure_worker_container
    assert_failure
    assert_output --partial "Error: failed to start ralph-worker container"
}

# --- timeout waiting for healthy ---

@test "ensure_worker_container exits 1 on timeout" {
    _source_docker_lib
    _stub_worker_never_healthy
    export WORKER_HEALTH_TIMEOUT=2
    run ensure_worker_container
    assert_failure
    assert_output --partial "Error: ralph-worker failed to start within 2s"
}

# --- custom timeout ---

@test "ensure_worker_container respects WORKER_HEALTH_TIMEOUT" {
    _source_docker_lib
    _stub_worker_never_healthy
    export WORKER_HEALTH_TIMEOUT=1
    run ensure_worker_container
    assert_failure
    assert_output --partial "within 1s"
}

# --- uses SCRIPT_DIR for project-directory ---

@test "ensure_worker_container passes --project-directory to docker compose" {
    _source_docker_lib
    cat > "$STUB_DIR/docker" <<DOCKERSTUB
#!/bin/bash
ARGS_FILE="$STUB_DIR/.docker_args"
if [ "\$1" != "compose" ]; then exit 0; fi
echo "\$@" >> "\$ARGS_FILE"
shift
while [ \$# -gt 0 ]; do
    case "\$1" in
        --project-directory) shift 2 ;;
        --format)            shift 2 ;;
        -d)                  shift ;;
        -*)                  shift ;;
        ps)     echo "running"; exit 0 ;;
        version) echo "Docker Compose version v2.24.0"; exit 0 ;;
        up)     exit 0 ;;
        *)      shift ;;
    esac
done
exit 0
DOCKERSTUB
    chmod +x "$STUB_DIR/docker"

    run ensure_worker_container
    assert_success
    run cat "$STUB_DIR/.docker_args"
    assert_output --partial "--project-directory"
}
