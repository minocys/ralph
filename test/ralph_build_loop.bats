#!/usr/bin/env bats
# test/ralph_build_loop.bats — build-mode loop control tests for ralph.sh
#
# These tests verify that build mode uses `ralph task plan-status` for both
# pre-invocation and post-invocation completion checks. The skill loads its
# own task data via `!` command preprocessing in SKILL.md; the loop no longer
# pre-fetches task data via `ralph task peek` or passes it to claude via prompt.
# Plan mode uses a deterministic for-loop (no sentinel check).

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a task stub at $TEST_WORK_DIR/task with configurable behavior.
# Usage: create_task_stub <plan_status_output> [plan_status_exit_code] [peek_output] [peek_exit_code]
# Note: peek_output is kept in the stub so the skill can still load data via ! syntax,
# but the loop itself no longer uses peek for loop control or prompt construction.
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

    cat > "$TEST_WORK_DIR/lib/task" <<STUB
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
    chmod +x "$TEST_WORK_DIR/lib/task"
}

# Override default setup: copy ralph.sh so SCRIPT_DIR resolves to TEST_WORK_DIR
# (which lets us place a task stub alongside it).
setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export TEST_WORK_DIR STUB_DIR

    # Copy ralph.sh and lib/*.sh into the test work directory
    cp "$SCRIPT_DIR/ralph.sh" "$TEST_WORK_DIR/ralph.sh"
    chmod +x "$TEST_WORK_DIR/ralph.sh"
    mkdir -p "$TEST_WORK_DIR/lib"
    for f in "$SCRIPT_DIR"/lib/*.sh; do
        cp "$f" "$TEST_WORK_DIR/lib/"
    done

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

    run "$TEST_WORK_DIR/ralph.sh" build -n 5
    assert_success
    assert_output --partial "All tasks complete. Exiting loop."
    refute_output --partial "Reached max iterations"
}

@test "build mode continues when tasks remain" {
    create_task_stub "2 open, 1 active, 3 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","t":"Task one","s":"open","p":0}'

    run "$TEST_WORK_DIR/ralph.sh" build -n 2
    assert_success
    assert_output --partial "Reached max iterations: 2"
}

@test "build mode continues when task plan-status fails" {
    create_task_stub "" 1 '{"id":"t1","t":"Task one","s":"open","p":0}'

    run "$TEST_WORK_DIR/ralph.sh" build -n 2
    assert_success
    assert_output --partial "Reached max iterations: 2"
}

@test "build mode continues loop when peek fails with non-zero exit" {
    create_task_stub "2 open, 1 active, 0 done, 0 blocked, 0 deleted" 0 "" 1

    run "$TEST_WORK_DIR/ralph.sh" build -n 2
    assert_success
    assert_output --partial "Reached max iterations: 2"
}

@test "build mode prompt is /ralph-build without task data" {
    create_task_stub "2 open, 1 active, 0 done, 0 blocked, 0 deleted" 0 \
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

    run "$TEST_WORK_DIR/ralph.sh" build -n 1
    assert_success

    # The -p value should be exactly "/ralph-build" with no task data appended
    [ -f "$TEST_WORK_DIR/claude_args.log" ]
    run cat "$TEST_WORK_DIR/claude_args.log"
    assert_output --partial '/ralph-build'
    refute_output --partial '{"id":"t1"'
}

# ---------------------------------------------------------------------------
# Build-mode crash-safety fallback (fail active tasks after claude exits)
# ---------------------------------------------------------------------------

@test "build mode fails active task after claude exits" {
    create_task_stub "1 open, 1 active, 0 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","t":"Task one","s":"open","p":0}' 0 \
        $'## Task t1\nid: t1\ntitle: Task one\nstatus: active\nassignee: t001'

    run "$TEST_WORK_DIR/ralph.sh" build -n 1
    assert_success

    # Verify fail was called with the task ID and reason
    [ -f "$TEST_WORK_DIR/fail_calls.log" ]
    run cat "$TEST_WORK_DIR/fail_calls.log"
    assert_output --partial "t1"
    assert_output --partial "session exited without completing task"
}

@test "build mode fails all active tasks after claude exits" {
    create_task_stub "1 open, 1 active, 0 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","t":"Task one","s":"open","p":0}' 0 \
        $'## Task t1\nid: t1\ntitle: Task one\nstatus: active\nassignee: t001\n\n## Task t2\nid: t2\ntitle: Task two\nstatus: active\nassignee: t001'

    run "$TEST_WORK_DIR/ralph.sh" build -n 1
    assert_success

    # Verify fail was called for both tasks
    [ -f "$TEST_WORK_DIR/fail_calls.log" ]
    run cat "$TEST_WORK_DIR/fail_calls.log"
    assert_output --partial "t1"
    assert_output --partial "t2"

    # Verify fail was called exactly twice
    local count
    count=$(wc -l < "$TEST_WORK_DIR/fail_calls.log")
    [ "$count" -eq 2 ]
}

@test "build mode crash-safety is no-op when no active tasks" {
    create_task_stub "0 open, 0 active, 5 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","t":"Task one","s":"open","p":0}' 0 \
        ""

    run "$TEST_WORK_DIR/ralph.sh" build -n 1
    assert_success

    # Verify fail was NOT called
    [ ! -f "$TEST_WORK_DIR/fail_calls.log" ]
}

@test "build mode crash-safety runs before plan-status check" {
    create_task_stub "2 open, 1 active, 0 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","t":"Task one","s":"open","p":0}' 0 \
        $'## Task t1\nid: t1\ntitle: Task one\nstatus: active\nassignee: t001'

    run "$TEST_WORK_DIR/ralph.sh" build -n 1
    assert_success

    # Verify ordered execution: pre-invocation plan-status → crash-safety fail → post-invocation plan-status
    [ -f "$TEST_WORK_DIR/event_log" ]
    run cat "$TEST_WORK_DIR/event_log"
    assert_line --index 0 "plan-status"
    assert_line --index 1 "fail"
    assert_line --index 2 "plan-status"
}

# ---------------------------------------------------------------------------
# Plan-mode for-loop iteration control
# ---------------------------------------------------------------------------

@test "plan mode runs exactly N iterations" {
    # Override claude stub to count invocations
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo "claude-call" >> "$TEST_WORK_DIR/call_count.log"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"planning..."}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$TEST_WORK_DIR/ralph.sh" plan -n 3
    assert_success
    assert_output --partial "Reached max iterations: 3"

    # Verify claude was called exactly 3 times
    [ -f "$TEST_WORK_DIR/call_count.log" ]
    local count
    count=$(wc -l < "$TEST_WORK_DIR/call_count.log")
    [ "$count" -eq 3 ]
}

@test "plan mode does not check for sentinel" {
    # Claude emits the old sentinel text — plan mode should ignore it and
    # continue to the next iteration (no early exit)
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"<promise>Tastes Like Burning.</promise>"}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$TEST_WORK_DIR/ralph.sh" plan -n 2
    assert_success
    # Should run all iterations, not exit early on sentinel
    assert_output --partial "Reached max iterations: 2"
    refute_output --partial "Ralph completed successfully"
}
