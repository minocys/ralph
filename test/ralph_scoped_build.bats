#!/usr/bin/env bats
# test/ralph_scoped_build.bats — scoped build execution tests
#
# Tests that ralph build --specs <patterns> correctly:
#   - passes --specs to plan-status for loop exit determination
#   - exports RALPH_SPEC_FILTER for Claude skill preprocessing
#   - omits --specs when no filter is active (backward compatibility)
#   - leaves crash-safety unchanged regardless of --specs

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a task stub at $TEST_WORK_DIR/lib/task with configurable behavior.
# Usage: create_task_stub <plan_status_output> [plan_status_exit_code] [peek_output] [peek_exit_code] [list_active_output]
create_task_stub() {
    local plan_status_output="${1:-}"
    local plan_status_exit="${2:-0}"
    local peek_output="${3:-}"
    local peek_exit="${4:-0}"
    local list_active_output="${5:-}"

    printf '%s' "$peek_output" > "$TEST_WORK_DIR/.peek_data"
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
        shift
        if [ \$# -gt 0 ]; then
            echo "plan-status \$*" >> "${TEST_WORK_DIR}/event_log"
        else
            echo "plan-status" >> "${TEST_WORK_DIR}/event_log"
        fi
        echo "${plan_status_output}"
        exit ${plan_status_exit}
        ;;
    peek)
        shift
        if [ \$# -gt 0 ]; then
            echo "peek \$*" >> "${TEST_WORK_DIR}/event_log"
        else
            echo "peek" >> "${TEST_WORK_DIR}/event_log"
        fi
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

# Override default setup: copy ralph.sh so SCRIPT_DIR resolves to TEST_WORK_DIR.
setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export TEST_WORK_DIR STUB_DIR

    cp "$SCRIPT_DIR/ralph.sh" "$TEST_WORK_DIR/ralph.sh"
    chmod +x "$TEST_WORK_DIR/ralph.sh"
    mkdir -p "$TEST_WORK_DIR/lib"
    for f in "$SCRIPT_DIR"/lib/*.sh; do
        cp "$f" "$TEST_WORK_DIR/lib/"
    done

    mkdir -p "$TEST_WORK_DIR/specs"
    echo "# dummy spec" > "$TEST_WORK_DIR/specs/dummy.md"

    # Default claude stub — outputs valid stream-JSON
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
# --specs propagation to plan-status
# ---------------------------------------------------------------------------

@test "scoped build passes --specs to plan-status" {
    create_task_stub "0 open, 0 active, 3 done, 0 blocked, 0 deleted"

    run "$TEST_WORK_DIR/ralph.sh" build -n 1 --specs 'ui-tabs'
    assert_success

    [ -f "$TEST_WORK_DIR/event_log" ]
    run cat "$TEST_WORK_DIR/event_log"
    assert_line --index 0 "plan-status --specs ui-tabs"
}

@test "scoped build passes comma-separated --specs to plan-status" {
    create_task_stub "0 open, 0 active, 5 done, 0 blocked, 0 deleted"

    run "$TEST_WORK_DIR/ralph.sh" build -n 1 --specs 'ui-tabs,auth-oauth'
    assert_success

    [ -f "$TEST_WORK_DIR/event_log" ]
    run cat "$TEST_WORK_DIR/event_log"
    assert_line --index 0 "plan-status --specs ui-tabs,auth-oauth"
}

@test "scoped build passes wildcard --specs to plan-status" {
    create_task_stub "0 open, 0 active, 2 done, 0 blocked, 0 deleted"

    run "$TEST_WORK_DIR/ralph.sh" build -n 1 --specs 'ui-*'
    assert_success

    [ -f "$TEST_WORK_DIR/event_log" ]
    run cat "$TEST_WORK_DIR/event_log"
    assert_line --index 0 "plan-status --specs ui-*"
}

@test "scoped build passes --specs through both pre and post plan-status checks" {
    create_task_stub "2 open, 1 active, 0 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","t":"Task one","s":"open","p":0}' 0 \
        ""

    run "$TEST_WORK_DIR/ralph.sh" build -n 1 --specs 'auth*'
    assert_success

    [ -f "$TEST_WORK_DIR/event_log" ]
    run cat "$TEST_WORK_DIR/event_log"
    assert_line --index 0 "plan-status --specs auth*"
    # post-invocation plan-status also gets --specs
    assert_line --index 1 "plan-status --specs auth*"
}

# ---------------------------------------------------------------------------
# RALPH_SPEC_FILTER export to claude environment
# ---------------------------------------------------------------------------

@test "scoped build exports RALPH_SPEC_FILTER to claude process" {
    create_task_stub "2 open, 0 active, 0 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","s":"open"}'

    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo "${RALPH_SPEC_FILTER:-UNSET}" > "$TEST_WORK_DIR/spec_filter_env.log"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"working..."}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$TEST_WORK_DIR/ralph.sh" build -n 1 --specs 'ui-tabs,auth*'
    assert_success

    [ -f "$TEST_WORK_DIR/spec_filter_env.log" ]
    run cat "$TEST_WORK_DIR/spec_filter_env.log"
    assert_output "ui-tabs,auth*"
}

@test "scoped build exports exact RALPH_SPEC_FILTER value with wildcards" {
    create_task_stub "2 open, 0 active, 0 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","s":"open"}'

    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo "${RALPH_SPEC_FILTER:-UNSET}" > "$TEST_WORK_DIR/spec_filter_env.log"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"working..."}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$TEST_WORK_DIR/ralph.sh" build -n 1 --specs 'ui-?,db-*'
    assert_success

    [ -f "$TEST_WORK_DIR/spec_filter_env.log" ]
    run cat "$TEST_WORK_DIR/spec_filter_env.log"
    assert_output "ui-?,db-*"
}

# ---------------------------------------------------------------------------
# Unfiltered build (no --specs)
# ---------------------------------------------------------------------------

@test "unfiltered build does not pass --specs to plan-status" {
    create_task_stub "0 open, 0 active, 3 done, 0 blocked, 0 deleted"

    run "$TEST_WORK_DIR/ralph.sh" build -n 1
    assert_success

    [ -f "$TEST_WORK_DIR/event_log" ]
    run cat "$TEST_WORK_DIR/event_log"
    assert_line --index 0 "plan-status"
    # The line should be exactly "plan-status" with no --specs suffix
    refute_output --partial "--specs"
}

@test "unfiltered build does not export RALPH_SPEC_FILTER" {
    create_task_stub "2 open, 0 active, 0 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","s":"open"}'

    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo "${RALPH_SPEC_FILTER:-UNSET}" > "$TEST_WORK_DIR/spec_filter_env.log"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"working..."}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$TEST_WORK_DIR/ralph.sh" build -n 1
    assert_success

    [ -f "$TEST_WORK_DIR/spec_filter_env.log" ]
    run cat "$TEST_WORK_DIR/spec_filter_env.log"
    assert_output "UNSET"
}

# ---------------------------------------------------------------------------
# Scoped loop exit: exits when filtered tasks are complete
# ---------------------------------------------------------------------------

@test "scoped build exits when filtered tasks are all done" {
    create_task_stub "0 open, 0 active, 5 done, 0 blocked, 0 deleted"

    run "$TEST_WORK_DIR/ralph.sh" build -n 5 --specs 'ui-tabs'
    assert_success
    assert_output --partial "All tasks complete. Exiting loop."
    refute_output --partial "Reached max iterations"
}

@test "scoped build continues when filtered tasks remain" {
    create_task_stub "2 open, 1 active, 3 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","t":"Task one","s":"open","p":0}'

    run "$TEST_WORK_DIR/ralph.sh" build -n 2 --specs 'ui-tabs'
    assert_success
    assert_output --partial "Reached max iterations: 2"
}

# ---------------------------------------------------------------------------
# Crash-safety unchanged by --specs
# ---------------------------------------------------------------------------

@test "scoped build crash-safety fails active tasks regardless of filter" {
    create_task_stub "1 open, 1 active, 0 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","t":"Task one","s":"open","p":0}' 0 \
        $'## Task t1\nid: t1\ntitle: Task one\nstatus: active\nassignee: t001'

    run "$TEST_WORK_DIR/ralph.sh" build -n 1 --specs 'ui-tabs'
    assert_success

    # Crash-safety should fail active tasks even with --specs set
    [ -f "$TEST_WORK_DIR/fail_calls.log" ]
    run cat "$TEST_WORK_DIR/fail_calls.log"
    assert_output --partial "t1"
    assert_output --partial "session exited without completing task"
}

@test "scoped build crash-safety event ordering with --specs" {
    create_task_stub "2 open, 1 active, 0 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","t":"Task one","s":"open","p":0}' 0 \
        $'## Task t1\nid: t1\ntitle: Task one\nstatus: active\nassignee: t001'

    run "$TEST_WORK_DIR/ralph.sh" build -n 1 --specs 'ui-tabs'
    assert_success

    # Ordered: pre-invocation plan-status → crash-safety fail → post-invocation plan-status
    [ -f "$TEST_WORK_DIR/event_log" ]
    run cat "$TEST_WORK_DIR/event_log"
    assert_line --index 0 "plan-status --specs ui-tabs"
    assert_line --index 1 "fail"
    assert_line --index 2 "plan-status --specs ui-tabs"
}

# ---------------------------------------------------------------------------
# --specs is fixed for the loop lifetime
# ---------------------------------------------------------------------------

@test "scoped build passes same --specs on every iteration" {
    create_task_stub "2 open, 1 active, 0 done, 0 blocked, 0 deleted" 0 \
        '{"id":"t1","t":"Task one","s":"open","p":0}' 0 \
        ""

    run "$TEST_WORK_DIR/ralph.sh" build -n 3 --specs 'ui-tabs'
    assert_success

    [ -f "$TEST_WORK_DIR/event_log" ]
    # All plan-status calls should have --specs ui-tabs
    local specs_count
    specs_count=$(grep -c 'plan-status --specs ui-tabs' "$TEST_WORK_DIR/event_log")
    # Pre-invocation (3 iterations) + post-invocation (2 for non-final) = multiple calls
    # At minimum, all plan-status calls must include --specs
    [ "$specs_count" -ge 3 ]
    # No plan-status calls without --specs
    local bare_count
    bare_count=$(grep -c '^plan-status$' "$TEST_WORK_DIR/event_log" || true)
    [ "$bare_count" -eq 0 ]
}
