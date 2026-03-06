#!/usr/bin/env bats
# test/ralph_plan_mode.bats — plan-mode integration tests for ralph.sh
#
# These tests verify that plan mode passes /ralph-plan directly to Claude.
# The skill loads its own task data via `!` command preprocessing in SKILL.md;
# the loop does NOT pre-fetch the task DAG.

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a task stub at $TEST_WORK_DIR/task with configurable behavior.
# Usage: create_task_stub [list_all_output] [list_all_exit_code]
create_task_stub() {
    local list_all_output="${1:-}"
    local list_all_exit="${2:-0}"

    # Write list --all output to a data file (avoids quoting issues with JSONL in heredoc)
    printf '%s' "$list_all_output" > "$TEST_WORK_DIR/.list_all_data"

    cat > "$TEST_WORK_DIR/lib/task" <<STUB
#!/bin/bash
# Log every invocation
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
        # Handle list --all --markdown (replacement for plan-export)
        if echo "\$*" | grep -q -- '--all'; then
            LIST_DATA=\$(cat "${TEST_WORK_DIR}/.list_all_data")
            if [ -n "\$LIST_DATA" ]; then
                echo "\$LIST_DATA"
            fi
            exit ${list_all_exit}
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

# Override default setup: copy ralph.sh so SCRIPT_DIR resolves to TEST_WORK_DIR
# (which lets us place a task stub alongside it).
setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export TEST_WORK_DIR STUB_DIR

    # Copy ralph.sh and lib/ into the test work directory
    cp "$SCRIPT_DIR/ralph.sh" "$TEST_WORK_DIR/ralph.sh"
    chmod +x "$TEST_WORK_DIR/ralph.sh"
    mkdir -p "$TEST_WORK_DIR/lib"
    for f in "$SCRIPT_DIR"/lib/*.sh; do
        cp "$f" "$TEST_WORK_DIR/lib/"
    done

    # Minimal specs/ directory so preflight passes
    mkdir -p "$TEST_WORK_DIR/specs"
    echo "# dummy spec" > "$TEST_WORK_DIR/specs/dummy.md"

    # Claude stub — captures all arguments and outputs valid stream-JSON
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
# Plan-mode task export tests
# ---------------------------------------------------------------------------

@test "plan mode prompt is /ralph-plan without task data" {
    create_task_stub '## Task t-01
id: t-01
title: Test task
status: open'

    run "$TEST_WORK_DIR/ralph.sh" plan -n 1
    assert_success

    # The prompt passed to claude should be exactly /ralph-plan with no task data appended
    [ -f "$TEST_WORK_DIR/claude_args.txt" ]
    run cat "$TEST_WORK_DIR/claude_args.txt"
    assert_output --partial '/ralph-plan'
    # The loop must NOT inject task data into the prompt
    refute_output --partial '## Task'
}

@test "plan mode prompt is /ralph-plan without pre-fetched data" {
    create_task_stub ""

    run "$TEST_WORK_DIR/ralph.sh" plan -n 1
    assert_success

    # Claude should still be called with just /ralph-plan (no task data appended)
    [ -f "$TEST_WORK_DIR/claude_args.txt" ]
    run cat "$TEST_WORK_DIR/claude_args.txt"
    assert_output --partial '/ralph-plan'
    # Should NOT contain any task data
    refute_output --partial '## Task'
}
