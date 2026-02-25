#!/usr/bin/env bats
# test/docker_exec_invocation.bats — verify run_loop branches on RALPH_EXEC_MODE
#
# When RALPH_EXEC_MODE=docker, claude must be invoked via docker exec ralph-worker.
# When RALPH_EXEC_MODE=local (default), claude is called directly.

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a task stub in $TEST_WORK_DIR with peek returning a dummy task.
_create_task_stub() {
    cat > "$TEST_WORK_DIR/lib/task" <<'STUB'
#!/bin/bash
case "$1" in
    agent)
        case "$2" in
            register) echo "t001"; exit 0 ;;
            deregister) exit 0 ;;
            *) exit 0 ;;
        esac
        ;;
    plan-status) echo "1 open, 0 active, 0 done, 0 blocked, 0 deleted"; exit 0 ;;
    peek) echo '## Task abc'; exit 0 ;;
    list) exit 0 ;;
    fail) exit 0 ;;
    *) exit 0 ;;
esac
STUB
    chmod +x "$TEST_WORK_DIR/lib/task"
}

# Override default setup: copy ralph project into test dir like ralph_build_loop.bats
setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export TEST_WORK_DIR STUB_DIR

    # Copy ralph.sh, lib/, and models.json into the test work directory
    cp "$SCRIPT_DIR/ralph.sh" "$TEST_WORK_DIR/ralph.sh"
    chmod +x "$TEST_WORK_DIR/ralph.sh"
    cp -r "$SCRIPT_DIR/lib" "$TEST_WORK_DIR/lib"
    cp "$SCRIPT_DIR/models.json" "$TEST_WORK_DIR/models.json"

    # Minimal specs/ directory so preflight passes
    mkdir -p "$TEST_WORK_DIR/specs"
    echo "# dummy spec" > "$TEST_WORK_DIR/specs/dummy.md"

    _create_task_stub

    # Claude stub that logs its invocation
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo "DIRECT_CLAUDE_CALLED" >> "$TEST_WORK_DIR/invocation.log"
printf '%s\n' "$@" >> "$TEST_WORK_DIR/invocation.log"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    # Docker stub that logs docker exec calls
    cat > "$STUB_DIR/docker" <<DOCKERSTUB
#!/bin/bash
case "\$1" in
    compose)
        shift
        while [ \$# -gt 0 ]; do
            case "\$1" in
                --project-directory) shift 2 ;;
                --format)            shift 2 ;;
                -d)                  shift ;;
                -*)                  shift ;;
                version) echo "Docker Compose version v2.24.0"; exit 0 ;;
                ps) echo "running"; exit 0 ;;
                up)  exit 0 ;;
                *)   shift ;;
            esac
        done
        exit 0
        ;;
    inspect)
        if echo "\$*" | grep -q "State.Running"; then echo "true"
        elif echo "\$*" | grep -q "Health.Status"; then echo "healthy"; fi
        exit 0
        ;;
    exec)
        shift  # remove 'exec'
        echo "DOCKER_EXEC_CALLED" >> "$TEST_WORK_DIR/invocation.log"
        # Log container name and command
        printf '%s\n' "\$@" >> "$TEST_WORK_DIR/invocation.log"
        # Emit valid stream-JSON output so the pipeline completes
        echo '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}'
        echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
        exit 0
        ;;
esac
exit 0
DOCKERSTUB
    chmod +x "$STUB_DIR/docker"

    cat > "$STUB_DIR/pg_isready" <<'PGSTUB'
#!/bin/bash
exit 0
PGSTUB
    chmod +x "$STUB_DIR/pg_isready"

    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"

    cd "$TEST_WORK_DIR"
}

teardown() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    [[ -d "${TEST_WORK_DIR:-}" ]] && rm -rf "$TEST_WORK_DIR"
    [[ -d "${STUB_DIR:-}" ]] && rm -rf "$STUB_DIR"
}

# ---------------------------------------------------------------------------
# Local mode (default): claude called directly
# ---------------------------------------------------------------------------

@test "local mode calls claude directly" {
    unset DOCKER_EXECUTOR
    run "$TEST_WORK_DIR/ralph.sh" build -n 1
    assert_success

    [ -f "$TEST_WORK_DIR/invocation.log" ]
    run head -1 "$TEST_WORK_DIR/invocation.log"
    assert_output "DIRECT_CLAUDE_CALLED"
}

@test "local mode does not use docker exec" {
    export DOCKER_EXECUTOR="false"
    run "$TEST_WORK_DIR/ralph.sh" build -n 1
    assert_success

    [ -f "$TEST_WORK_DIR/invocation.log" ]
    run grep "DOCKER_EXEC_CALLED" "$TEST_WORK_DIR/invocation.log"
    assert_failure
}

# ---------------------------------------------------------------------------
# Docker mode: claude invoked via docker exec ralph-worker
# ---------------------------------------------------------------------------

@test "docker mode invokes claude via docker exec ralph-worker" {
    export DOCKER_EXECUTOR="true"
    run "$TEST_WORK_DIR/ralph.sh" build -n 1
    assert_success

    [ -f "$TEST_WORK_DIR/invocation.log" ]
    run head -1 "$TEST_WORK_DIR/invocation.log"
    assert_output "DOCKER_EXEC_CALLED"
    # Verify container name is ralph-worker
    run sed -n '2p' "$TEST_WORK_DIR/invocation.log"
    assert_output "ralph-worker"
    # Verify claude is the command
    run sed -n '3p' "$TEST_WORK_DIR/invocation.log"
    assert_output "claude"
}

@test "docker mode does not call claude directly" {
    export DOCKER_EXECUTOR="true"
    run "$TEST_WORK_DIR/ralph.sh" build -n 1
    assert_success

    [ -f "$TEST_WORK_DIR/invocation.log" ]
    run grep "DIRECT_CLAUDE_CALLED" "$TEST_WORK_DIR/invocation.log"
    assert_failure
}

# ---------------------------------------------------------------------------
# CLI flag forwarding in docker mode
# ---------------------------------------------------------------------------

@test "docker mode forwards --output-format flag" {
    export DOCKER_EXECUTOR="true"
    run "$TEST_WORK_DIR/ralph.sh" build -n 1
    assert_success

    [ -f "$TEST_WORK_DIR/invocation.log" ]
    run grep "output-format=stream-json" "$TEST_WORK_DIR/invocation.log"
    assert_success
}

@test "docker mode forwards --dangerously-skip-permissions flag" {
    export DOCKER_EXECUTOR="true"
    run "$TEST_WORK_DIR/ralph.sh" build -n 1 --danger
    assert_success

    [ -f "$TEST_WORK_DIR/invocation.log" ]
    run grep "dangerously-skip-permissions" "$TEST_WORK_DIR/invocation.log"
    assert_success
}

@test "docker mode forwards --model flag" {
    export DOCKER_EXECUTOR="true"
    run "$TEST_WORK_DIR/ralph.sh" build -n 1 -m sonnet
    assert_success

    [ -f "$TEST_WORK_DIR/invocation.log" ]
    run grep "\-\-model" "$TEST_WORK_DIR/invocation.log"
    assert_success
}

@test "docker mode forwards --verbose flag" {
    export DOCKER_EXECUTOR="true"
    run "$TEST_WORK_DIR/ralph.sh" build -n 1
    assert_success

    [ -f "$TEST_WORK_DIR/invocation.log" ]
    run grep "verbose" "$TEST_WORK_DIR/invocation.log"
    assert_success
}

# ---------------------------------------------------------------------------
# Exit code capture
# ---------------------------------------------------------------------------

@test "docker mode captures exit code from docker exec" {
    export DOCKER_EXECUTOR="true"

    # Make docker exec return non-zero
    cat > "$STUB_DIR/docker" <<DOCKERSTUB
#!/bin/bash
case "\$1" in
    compose)
        shift
        while [ \$# -gt 0 ]; do
            case "\$1" in
                --project-directory) shift 2 ;;
                --format)            shift 2 ;;
                -d)                  shift ;;
                -*)                  shift ;;
                version) echo "Docker Compose version v2.24.0"; exit 0 ;;
                ps) echo "running"; exit 0 ;;
                up)  exit 0 ;;
                *)   shift ;;
            esac
        done
        exit 0
        ;;
    inspect)
        if echo "\$*" | grep -q "State.Running"; then echo "true"
        elif echo "\$*" | grep -q "Health.Status"; then echo "healthy"; fi
        exit 0
        ;;
    exec)
        # Emit valid JSON so jq doesn't error, then exit 0
        echo '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}'
        echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
        exit 0
        ;;
esac
exit 0
DOCKERSTUB
    chmod +x "$STUB_DIR/docker"

    # ralph.sh should complete normally when docker exec succeeds
    run "$TEST_WORK_DIR/ralph.sh" build -n 1
    assert_success
}
