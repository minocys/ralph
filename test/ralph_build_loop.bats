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

# Create a task stub at $TEST_WORK_DIR/task with configurable behavior.
# Usage: create_task_stub <plan_status_output> [plan_status_exit_code] [peek_output] [peek_exit_code]
create_task_stub() {
    local plan_status_output="${1:-}"
    local plan_status_exit="${2:-0}"
    local peek_output="${3:-}"
    local peek_exit="${4:-0}"
    local list_active_output="${5:-}"

    # Write peek output to a data file (avoids quoting issues with JSONL in heredoc)
    printf '%s' "$peek_output" > "$TEST_WORK_DIR/.peek_data"

    # Write list output to a data file
    printf '%s' "$list_active_output" > "$TEST_WORK_DIR/.list_data"

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
        echo "plan-status" >> "${TEST_WORK_DIR}/event_log"
        echo "${plan_status_output}"
        exit ${plan_status_exit}
        ;;
    peek)
        PEEK_DATA=\$(cat "${TEST_WORK_DIR}/.peek_data")
        if [ -n "\$PEEK_DATA" ]; then
            echo "\$PEEK_DATA"
        fi
        exit ${peek_exit}
        ;;
    list)
        LIST_DATA=\$(cat "${TEST_WORK_DIR}/.list_data")
        if [ -n "\$LIST_DATA" ]; then
            echo "\$LIST_DATA"
        fi
        exit 0
        ;;
    fail)
        shift
        echo "\$*" >> "${TEST_WORK_DIR}/fail_calls.log"
        echo "fail" >> "${TEST_WORK_DIR}/event_log"
        exit 0
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

    # Copy ralph.sh and lib/ into the test work directory
    cp "$SCRIPT_DIR/ralph.sh" "$TEST_WORK_DIR/ralph.sh"
    chmod +x "$TEST_WORK_DIR/ralph.sh"
    cp -r "$SCRIPT_DIR/lib" "$TEST_WORK_DIR/lib"

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

    # Skip Docker checks — these tests don't need a running container
    export RALPH_SKIP_DOCKER=1

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
    # With peek: no claimable/active tasks → peek returns empty → exits early
    create_task_stub "0 open, 0 active, 5 done, 0 blocked, 0 deleted"

    run "$TEST_WORK_DIR/ralph.sh" -n 5
    assert_success
    assert_output --partial "No tasks available"
    refute_output --partial "Reached max iterations"
}

@test "build mode continues when tasks remain" {
    create_task_stub "2 open, 1 active, 3 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","t":"Task one","s":"open","p":0}'

    run "$TEST_WORK_DIR/ralph.sh" -n 2
    assert_success
    assert_output --partial "Reached max iterations: 2"
}

@test "build mode continues when task plan-status fails" {
    create_task_stub "" 1 '{"id":"t1","t":"Task one","s":"open","p":0}'

    run "$TEST_WORK_DIR/ralph.sh" -n 2
    assert_success
    assert_output --partial "Reached max iterations: 2"
}

# ---------------------------------------------------------------------------
# Build-mode pre-invocation peek
# ---------------------------------------------------------------------------

@test "build mode passes peek JSONL to claude via prompt" {
    create_task_stub "2 open, 0 active, 0 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","t":"Test task","s":"open","p":0}'

    # Override claude stub to capture arguments
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo "$*" > "$TEST_WORK_DIR/claude_args.log"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"working..."}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$TEST_WORK_DIR/ralph.sh" -n 1
    assert_success

    # Verify claude received the peek JSONL in its prompt argument
    [ -f "$TEST_WORK_DIR/claude_args.log" ]
    run cat "$TEST_WORK_DIR/claude_args.log"
    assert_output --partial '{"id":"t1"'
}

@test "build mode exits loop when peek returns empty output" {
    create_task_stub "2 open, 0 active, 0 done, 0 blocked, 0 deleted" 0 "" 0

    # Override claude stub to leave a marker file if called
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
touch "$TEST_WORK_DIR/claude_was_called"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"working..."}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$TEST_WORK_DIR/ralph.sh" -n 5
    assert_success
    assert_output --partial "No tasks available"
    refute_output --partial "Reached max iterations"

    # Verify claude was not called
    [ ! -f "$TEST_WORK_DIR/claude_was_called" ]
}

@test "build mode continues loop when peek fails with non-zero exit" {
    create_task_stub "2 open, 1 active, 0 done, 0 blocked, 0 deleted" 0 "" 1

    run "$TEST_WORK_DIR/ralph.sh" -n 2
    assert_success
    assert_output --partial "Reached max iterations: 2"
}

@test "build mode prompt format is /ralph-build followed by JSONL" {
    create_task_stub "2 open, 0 active, 0 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","s":"open"}'

    # Override claude stub to capture each argument on its own line
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_WORK_DIR/claude_args.log"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"working..."}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$TEST_WORK_DIR/ralph.sh" -n 1
    assert_success

    # The -p value should be "/ralph-build {JSONL}" as a single argument
    [ -f "$TEST_WORK_DIR/claude_args.log" ]
    run cat "$TEST_WORK_DIR/claude_args.log"
    assert_output --partial '/ralph-build {"id":"t1","s":"open"}'
}

# ---------------------------------------------------------------------------
# Build-mode crash-safety fallback (fail active tasks after claude exits)
# ---------------------------------------------------------------------------

@test "build mode fails active task after claude exits" {
    create_task_stub "0 open, 0 active, 5 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","t":"Task one","s":"open","p":0}' 0 \
        '{"id":"t1","t":"Task one","s":"active","assignee":"t001"}'

    run "$TEST_WORK_DIR/ralph.sh" -n 1
    assert_success

    # Verify fail was called with the task ID and reason
    [ -f "$TEST_WORK_DIR/fail_calls.log" ]
    run cat "$TEST_WORK_DIR/fail_calls.log"
    assert_output --partial "t1"
    assert_output --partial "session exited without completing task"
}

@test "build mode crash-safety is no-op when no active tasks" {
    create_task_stub "0 open, 0 active, 5 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","t":"Task one","s":"open","p":0}' 0 \
        ""

    run "$TEST_WORK_DIR/ralph.sh" -n 1
    assert_success

    # Verify fail was NOT called
    [ ! -f "$TEST_WORK_DIR/fail_calls.log" ]
}

@test "build mode crash-safety runs before plan-status check" {
    create_task_stub "2 open, 1 active, 0 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","t":"Task one","s":"open","p":0}' 0 \
        '{"id":"t1","t":"Task one","s":"active","assignee":"t001"}'

    run "$TEST_WORK_DIR/ralph.sh" -n 1
    assert_success

    # Verify ordered execution: fail before plan-status
    [ -f "$TEST_WORK_DIR/event_log" ]
    run cat "$TEST_WORK_DIR/event_log"
    assert_line --index 0 "fail"
    assert_line --index 1 "plan-status"
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
