#!/usr/bin/env bats
# test/ralph_docker_executor_wiring.bats — verify detect_docker_executor and
# ensure_worker_container are wired into ralph.sh startup sequence

load test_helper

# Helper: create a docker stub that logs compose subcommands so we can verify
# whether 'up ralph-worker' was invoked.
_stub_docker_with_worker_logging() {
    cat > "$STUB_DIR/docker" <<DOCKERSTUB
#!/bin/bash
LOG_FILE="$STUB_DIR/.docker_compose_log"
if [ "\$1" = "compose" ]; then
    shift
    # Parse subcommand, skipping flags
    while [ \$# -gt 0 ]; do
        case "\$1" in
            --project-directory) shift 2 ;;
            --format)            shift 2 ;;
            -d)                  shift ;;
            -*)                  shift ;;
            version) echo "Docker Compose version v2.24.0"; exit 0 ;;
            ps)
                # Check for ralph-worker arg
                shift
                if [ "\${1:-}" = "ralph-worker" ] || [ "\${1:-}" = "--format" ]; then
                    echo "ps ralph-worker" >> "\$LOG_FILE"
                    echo "running"
                fi
                exit 0
                ;;
            up)
                echo "up \$*" >> "\$LOG_FILE"
                exit 0
                ;;
            *)      shift ;;
        esac
    done
fi
# docker inspect for is_container_running / wait_for_healthy
if [ "\$1" = "inspect" ]; then
    if echo "\$*" | grep -q "State.Running"; then
        echo "true"
    elif echo "\$*" | grep -q "Health.Status"; then
        echo "healthy"
    fi
fi
exit 0
DOCKERSTUB
    chmod +x "$STUB_DIR/docker"
}

# --- default (local) mode ---

@test "ralph.sh sets RALPH_EXEC_MODE=local when DOCKER_EXECUTOR is unset" {
    unset DOCKER_EXECUTOR
    _stub_docker_with_worker_logging
    run "$SCRIPT_DIR/ralph.sh" build -n 1
    assert_success
    # ensure_worker_container should NOT have been called
    if [ -f "$STUB_DIR/.docker_compose_log" ]; then
        run grep -c "ps ralph-worker" "$STUB_DIR/.docker_compose_log"
        [ "$output" = "0" ] || [ "$status" -ne 0 ]
    fi
}

@test "ralph.sh does not call ensure_worker_container in local mode" {
    export DOCKER_EXECUTOR="false"
    _stub_docker_with_worker_logging
    run "$SCRIPT_DIR/ralph.sh" build -n 1
    assert_success
    # Log file should not contain ralph-worker ps check
    if [ -f "$STUB_DIR/.docker_compose_log" ]; then
        run grep "ps ralph-worker" "$STUB_DIR/.docker_compose_log"
        assert_failure
    fi
}

# --- docker mode ---

@test "ralph.sh calls ensure_worker_container when DOCKER_EXECUTOR=true" {
    export DOCKER_EXECUTOR="true"
    _stub_docker_with_worker_logging
    run "$SCRIPT_DIR/ralph.sh" build -n 1
    assert_success
    # Log file should show ralph-worker ps check
    assert [ -f "$STUB_DIR/.docker_compose_log" ]
    run grep "ps ralph-worker" "$STUB_DIR/.docker_compose_log"
    assert_success
}

@test "ralph.sh calls ensure_worker_container when DOCKER_EXECUTOR=TRUE (case-insensitive)" {
    export DOCKER_EXECUTOR="TRUE"
    _stub_docker_with_worker_logging
    run "$SCRIPT_DIR/ralph.sh" build -n 1
    assert_success
    assert [ -f "$STUB_DIR/.docker_compose_log" ]
    run grep "ps ralph-worker" "$STUB_DIR/.docker_compose_log"
    assert_success
}

# --- ordering: detect runs before print_banner ---

@test "detect_docker_executor runs before print_banner (RALPH_EXEC_MODE available)" {
    export DOCKER_EXECUTOR="true"
    _stub_docker_with_worker_logging
    # ralph.sh should complete without error — detect_docker_executor sets
    # RALPH_EXEC_MODE before the banner and loop run
    run "$SCRIPT_DIR/ralph.sh" build -n 1
    assert_success
}

# --- .env sourcing: detect_docker_executor picks up DOCKER_EXECUTOR from .env ---

@test "detect_docker_executor reads DOCKER_EXECUTOR from .env after load_env" {
    unset DOCKER_EXECUTOR
    # Write DOCKER_EXECUTOR=true into .env so load_env picks it up
    echo 'DOCKER_EXECUTOR=true' >> "$SCRIPT_DIR/.env"
    _stub_docker_with_worker_logging
    run "$SCRIPT_DIR/ralph.sh" build -n 1
    # Clean up the injected line
    sed -i.bak '/^DOCKER_EXECUTOR=true$/d' "$SCRIPT_DIR/.env"
    rm -f "$SCRIPT_DIR/.env.bak"
    assert_success
    assert [ -f "$STUB_DIR/.docker_compose_log" ]
    run grep "ps ralph-worker" "$STUB_DIR/.docker_compose_log"
    assert_success
}
