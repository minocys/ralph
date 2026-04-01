#!/usr/bin/env bats
# test/ralph_scoped_plan.bats — scoped plan execution tests
#
# Tests that ralph plan --specs <patterns> correctly:
#   - exports RALPH_SPEC_FILTER for Claude skill preprocessing (plan-sync scoping)
#   - keeps COMMAND as /ralph-plan regardless of --specs
#   - does not export RALPH_SPEC_FILTER when --specs is absent

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a task stub at $TEST_WORK_DIR/lib/task with plan-mode behavior.
# The plan loop does not call plan-status or peek — only the skill
# references task list and plan-sync via backtick expansion in SKILL.md.
create_task_stub() {
    local list_all_output="${1:-}"

    printf '%s' "$list_all_output" > "$TEST_WORK_DIR/.list_all_data"

    cat > "$TEST_WORK_DIR/lib/task" <<STUB
#!/bin/bash
echo "\$*" >> "${TEST_WORK_DIR}/task_calls.log"
case "\$1" in
    agent)
        case "\$2" in
            register) echo "a1b2"; exit 0 ;;
            deregister) exit 0 ;;
            *) exit 0 ;;
        esac
        ;;
    list)
        if echo "\$*" | grep -q -- '--all'; then
            LIST_DATA=\$(cat "${TEST_WORK_DIR}/.list_all_data")
            if [ -n "\$LIST_DATA" ]; then
                echo "\$LIST_DATA"
            fi
        fi
        exit 0
        ;;
    plan-status)
        echo "1 open, 0 active, 0 done, 0 blocked, 0 deleted"
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

    # Default claude stub — captures args and outputs valid stream-JSON
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_WORK_DIR/claude_args.txt"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"planning..."}]}}'
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
# RALPH_SPEC_FILTER export to Claude process (plan-sync scoping)
# ---------------------------------------------------------------------------

@test "scoped plan exports RALPH_SPEC_FILTER to claude process" {
    create_task_stub ""

    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo "${RALPH_SPEC_FILTER:-UNSET}" > "$TEST_WORK_DIR/spec_filter_env.log"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"planning..."}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$TEST_WORK_DIR/ralph.sh" plan -n 1 --specs 'ui-tabs'
    assert_success

    [ -f "$TEST_WORK_DIR/spec_filter_env.log" ]
    run cat "$TEST_WORK_DIR/spec_filter_env.log"
    assert_output "ui-tabs"
}

@test "scoped plan exports comma-separated RALPH_SPEC_FILTER" {
    create_task_stub ""

    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo "${RALPH_SPEC_FILTER:-UNSET}" > "$TEST_WORK_DIR/spec_filter_env.log"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"planning..."}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$TEST_WORK_DIR/ralph.sh" plan -n 1 --specs 'ui-tabs,auth-oauth'
    assert_success

    [ -f "$TEST_WORK_DIR/spec_filter_env.log" ]
    run cat "$TEST_WORK_DIR/spec_filter_env.log"
    assert_output "ui-tabs,auth-oauth"
}

@test "scoped plan exports wildcard RALPH_SPEC_FILTER" {
    create_task_stub ""

    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo "${RALPH_SPEC_FILTER:-UNSET}" > "$TEST_WORK_DIR/spec_filter_env.log"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"planning..."}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$TEST_WORK_DIR/ralph.sh" plan -n 1 --specs 'ui-*'
    assert_success

    [ -f "$TEST_WORK_DIR/spec_filter_env.log" ]
    run cat "$TEST_WORK_DIR/spec_filter_env.log"
    assert_output "ui-*"
}

@test "scoped plan exports exact RALPH_SPEC_FILTER value with mixed wildcards" {
    create_task_stub ""

    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo "${RALPH_SPEC_FILTER:-UNSET}" > "$TEST_WORK_DIR/spec_filter_env.log"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"planning..."}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$TEST_WORK_DIR/ralph.sh" plan -n 1 --specs 'ui-?,db-*'
    assert_success

    [ -f "$TEST_WORK_DIR/spec_filter_env.log" ]
    run cat "$TEST_WORK_DIR/spec_filter_env.log"
    assert_output "ui-?,db-*"
}

# ---------------------------------------------------------------------------
# Unfiltered plan (no --specs)
# ---------------------------------------------------------------------------

@test "unfiltered plan does not export RALPH_SPEC_FILTER" {
    create_task_stub ""

    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo "${RALPH_SPEC_FILTER:-UNSET}" > "$TEST_WORK_DIR/spec_filter_env.log"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"planning..."}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$TEST_WORK_DIR/ralph.sh" plan -n 1
    assert_success

    [ -f "$TEST_WORK_DIR/spec_filter_env.log" ]
    run cat "$TEST_WORK_DIR/spec_filter_env.log"
    assert_output "UNSET"
}

# ---------------------------------------------------------------------------
# COMMAND is /ralph-plan regardless of --specs
# ---------------------------------------------------------------------------

@test "scoped plan prompt is /ralph-plan with --specs" {
    create_task_stub ""

    run "$TEST_WORK_DIR/ralph.sh" plan -n 1 --specs 'ui-tabs'
    assert_success

    [ -f "$TEST_WORK_DIR/claude_args.txt" ]
    run cat "$TEST_WORK_DIR/claude_args.txt"
    assert_output --partial '/ralph-plan'
    # --specs must not alter the prompt passed to Claude
    refute_output --partial '--specs'
    refute_output --partial 'ui-tabs'
}

@test "scoped plan prompt is /ralph-plan with comma-separated --specs" {
    create_task_stub ""

    run "$TEST_WORK_DIR/ralph.sh" plan -n 1 --specs 'ui-tabs,auth*'
    assert_success

    [ -f "$TEST_WORK_DIR/claude_args.txt" ]
    run cat "$TEST_WORK_DIR/claude_args.txt"
    assert_output --partial '/ralph-plan'
    refute_output --partial '--specs'
    refute_output --partial 'ui-tabs'
    refute_output --partial 'auth'
}

@test "scoped plan prompt is /ralph-plan with wildcard --specs" {
    create_task_stub ""

    run "$TEST_WORK_DIR/ralph.sh" plan -n 1 --specs 'task-*'
    assert_success

    [ -f "$TEST_WORK_DIR/claude_args.txt" ]
    run cat "$TEST_WORK_DIR/claude_args.txt"
    assert_output --partial '/ralph-plan'
    refute_output --partial '--specs'
    refute_output --partial 'task-'
}

@test "unfiltered plan prompt is /ralph-plan without --specs" {
    create_task_stub ""

    run "$TEST_WORK_DIR/ralph.sh" plan -n 1
    assert_success

    [ -f "$TEST_WORK_DIR/claude_args.txt" ]
    run cat "$TEST_WORK_DIR/claude_args.txt"
    assert_output --partial '/ralph-plan'
    refute_output --partial '--specs'
}

# ---------------------------------------------------------------------------
# RALPH_SPEC_FILTER is consistent across multiple iterations
# ---------------------------------------------------------------------------

@test "scoped plan exports same RALPH_SPEC_FILTER across iterations" {
    # Task stub returns a different plan-status on each call so the
    # change-detection logic does not trigger an early exit.
    printf '%s' "" > "$TEST_WORK_DIR/.list_all_data"

    cat > "$TEST_WORK_DIR/lib/task" <<STUB
#!/bin/bash
echo "\$*" >> "${TEST_WORK_DIR}/task_calls.log"
case "\$1" in
    agent)
        case "\$2" in
            register) echo "a1b2"; exit 0 ;;
            deregister) exit 0 ;;
            *) exit 0 ;;
        esac
        ;;
    list)
        if echo "\$*" | grep -q -- '--all'; then
            LIST_DATA=\$(cat "${TEST_WORK_DIR}/.list_all_data")
            if [ -n "\$LIST_DATA" ]; then echo "\$LIST_DATA"; fi
        fi
        exit 0
        ;;
    plan-status)
        # Increment a counter so each call returns a different status,
        # preventing the plan loop from exiting early.
        COUNTER_FILE="${TEST_WORK_DIR}/.plan_status_counter"
        COUNT=\$(cat "\$COUNTER_FILE" 2>/dev/null || echo 0)
        COUNT=\$((COUNT + 1))
        echo "\$COUNT" > "\$COUNTER_FILE"
        echo "\$COUNT open, 0 active, 0 done, 0 blocked, 0 deleted"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "$TEST_WORK_DIR/lib/task"

    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo "${RALPH_SPEC_FILTER:-UNSET}" >> "$TEST_WORK_DIR/spec_filter_env.log"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"planning..."}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$TEST_WORK_DIR/ralph.sh" plan -n 3 --specs 'ui-tabs'
    assert_success

    [ -f "$TEST_WORK_DIR/spec_filter_env.log" ]
    # All 3 iterations should see the same RALPH_SPEC_FILTER
    local filter_count
    filter_count=$(grep -c 'ui-tabs' "$TEST_WORK_DIR/spec_filter_env.log")
    [ "$filter_count" -eq 3 ]
    # No UNSET values should appear
    local unset_count
    unset_count=$(grep -c 'UNSET' "$TEST_WORK_DIR/spec_filter_env.log" || true)
    [ "$unset_count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Plan loop does NOT inject task data into the prompt (preserved from
# ralph_plan_mode.bats — confirm --specs doesn't alter this behavior)
# ---------------------------------------------------------------------------

@test "scoped plan does not inject task data into prompt" {
    create_task_stub '## Task t-01
id: t-01
title: Test task
status: open'

    run "$TEST_WORK_DIR/ralph.sh" plan -n 1 --specs 'ui-tabs'
    assert_success

    [ -f "$TEST_WORK_DIR/claude_args.txt" ]
    run cat "$TEST_WORK_DIR/claude_args.txt"
    assert_output --partial '/ralph-plan'
    # The loop must NOT inject task data into the prompt
    refute_output --partial '## Task'
}
