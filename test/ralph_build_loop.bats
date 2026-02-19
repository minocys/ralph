#!/usr/bin/env bats
# test/ralph_build_loop.bats — build-mode loop control tests for ralph.sh
#
# These tests verify that build mode uses `task plan-status` to decide
# when all tasks are complete, while plan mode continues to rely on the
# <promise>Tastes Like Burning.</promise> grep check.

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a task stub at $TEST_WORK_DIR/task with configurable plan-status behavior.
# Usage: create_task_stub <plan_status_output> [plan_status_exit_code]
create_task_stub() {
    local plan_status_output="${1:-}"
    local plan_status_exit="${2:-0}"

    cat > "$TEST_WORK_DIR/task" <<STUB
#!/bin/bash
case "\$1" in
    agent)
        case "\$2" in
            register) echo "t001"; exit 0 ;;
            deregister) exit 0 ;;
            *) exit 0 ;;
        esac
        ;;
    plan-status)
        echo "${plan_status_output}"
        exit ${plan_status_exit}
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "$TEST_WORK_DIR/task"
}

# Override default setup: copy ralph.sh so SCRIPT_DIR resolves to TEST_WORK_DIR
# (which lets us place a task stub alongside it).
setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export TEST_WORK_DIR STUB_DIR

    # Copy ralph.sh into the test work directory
    cp "$SCRIPT_DIR/ralph.sh" "$TEST_WORK_DIR/ralph.sh"
    chmod +x "$TEST_WORK_DIR/ralph.sh"

    # Minimal specs/ directory so preflight passes
    mkdir -p "$TEST_WORK_DIR/specs"
    echo "# dummy spec" > "$TEST_WORK_DIR/specs/dummy.md"

    # Claude stub — outputs valid stream-JSON (no promise text)
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"working on tasks..."}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

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
# Build-mode loop control via task plan-status
# ---------------------------------------------------------------------------

@test "build mode exits when task plan-status reports 0 open 0 active" {
    create_task_stub "0 open, 0 active, 5 done, 0 blocked, 0 deleted"

    run "$TEST_WORK_DIR/ralph.sh" -n 5
    assert_success
    assert_output --partial "All tasks complete"
    refute_output --partial "Reached max iterations"
}

@test "build mode continues when tasks remain" {
    create_task_stub "2 open, 1 active, 3 done, 0 blocked, 0 deleted"

    run "$TEST_WORK_DIR/ralph.sh" -n 2
    assert_success
    assert_output --partial "Reached max iterations: 2"
}

@test "build mode continues when task plan-status fails" {
    create_task_stub "" 1

    run "$TEST_WORK_DIR/ralph.sh" -n 2
    assert_success
    assert_output --partial "Reached max iterations: 2"
}

# ---------------------------------------------------------------------------
# Plan-mode promise check is retained
# ---------------------------------------------------------------------------

@test "plan mode still uses promise grep check" {
    # Override claude stub to emit the promise sentinel in valid stream-JSON
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"<promise>Tastes Like Burning.</promise>"}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$TEST_WORK_DIR/ralph.sh" --plan -n 2
    assert_success
    assert_output --partial "Ralph completed successfully"
}
