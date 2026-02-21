#!/usr/bin/env bats
# test/ralph_plan_mode.bats — plan-mode task export integration tests for ralph.sh
#
# These tests verify that plan mode pre-fetches the task DAG via
# `task plan-export` and passes it to Claude as part of the prompt.

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a task stub at $TEST_WORK_DIR/task with configurable behavior.
# Usage: create_task_stub [plan_export_output] [plan_export_exit_code]
create_task_stub() {
    local plan_export_output="${1:-}"
    local plan_export_exit="${2:-0}"

    # Write plan-export output to a data file (avoids quoting issues with JSONL in heredoc)
    printf '%s' "$plan_export_output" > "$TEST_WORK_DIR/.plan_export_data"

    cat > "$TEST_WORK_DIR/task" <<STUB
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
    plan-export)
        EXPORT_DATA=\$(cat "${TEST_WORK_DIR}/.plan_export_data")
        if [ -n "\$EXPORT_DATA" ]; then
            echo "\$EXPORT_DATA"
        fi
        exit ${plan_export_exit}
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

    # Claude stub — captures all arguments and outputs valid stream-JSON
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_WORK_DIR/claude_args.txt"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"<promise>Tastes Like Burning.</promise>"}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.01,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"

    # Docker/pg_isready stubs so ensure_postgres passes in copied ralph.sh
    cat > "$STUB_DIR/docker" <<'DOCKERSTUB'
#!/bin/bash
case "$1" in
    compose)
        if [ "$2" = "version" ]; then echo "Docker Compose version v2.24.0"; fi
        exit 0 ;;
    inspect)
        if [ "$3" = "{{.State.Running}}" ]; then echo "true"
        elif [ "$3" = "{{.State.Health.Status}}" ]; then echo "healthy"; fi
        exit 0 ;;
esac
exit 0
DOCKERSTUB
    chmod +x "$STUB_DIR/docker"
    cat > "$STUB_DIR/pg_isready" <<'PGSTUB'
#!/bin/bash
exit 0
PGSTUB
    chmod +x "$STUB_DIR/pg_isready"

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

@test "plan mode calls task plan-export before claude invocation" {
    create_task_stub '## Task t-01
id: t-01
title: Test task
status: open'

    run "$TEST_WORK_DIR/ralph.sh" --plan -n 1
    assert_success

    # Verify task stub was called with plan-export (no --json)
    [ -f "$TEST_WORK_DIR/task_calls.log" ]
    run cat "$TEST_WORK_DIR/task_calls.log"
    assert_output --partial "plan-export"
    refute_output --partial "plan-export --json"

    # Verify claude was called
    [ -f "$TEST_WORK_DIR/claude_args.txt" ]
}

@test "plan mode passes markdown-KV to claude prompt argument" {
    create_task_stub '## Task t-01
id: t-01
title: Test task
status: open'

    run "$TEST_WORK_DIR/ralph.sh" --plan -n 1
    assert_success

    # The -p value should be "/ralph-plan {markdown-KV}" as a single argument
    [ -f "$TEST_WORK_DIR/claude_args.txt" ]
    run cat "$TEST_WORK_DIR/claude_args.txt"
    assert_output --partial '## Task t-01'
    assert_output --partial 'title: Test task'
}

@test "plan mode handles empty plan-export output" {
    create_task_stub ""

    run "$TEST_WORK_DIR/ralph.sh" --plan -n 1
    assert_success

    # Claude should still be called with just /ralph-plan (no task data appended)
    [ -f "$TEST_WORK_DIR/claude_args.txt" ]
    run cat "$TEST_WORK_DIR/claude_args.txt"
    assert_output --partial '/ralph-plan'
    # Should NOT contain any task data
    refute_output --partial '## Task'
}
