#!/usr/bin/env bats
# test/task_plan_status.bats — Tests for the task plan-status command
# Requires: running PostgreSQL (docker compose up -d)

load test_helper

# ---------------------------------------------------------------------------
# Helper: check if PostgreSQL is reachable
# ---------------------------------------------------------------------------
db_available() {
    [[ -n "${RALPH_DB_URL:-}" ]] && psql "$RALPH_DB_URL" -tAX -c "SELECT 1" >/dev/null 2>&1
}

setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export TEST_WORK_DIR STUB_DIR

    if ! db_available; then
        skip "PostgreSQL not available (set RALPH_DB_URL and start database)"
    fi

    TEST_SCHEMA="test_$(date +%s)_$$"
    export TEST_SCHEMA

    psql "$RALPH_DB_URL" -tAX -c "CREATE SCHEMA $TEST_SCHEMA" >/dev/null 2>&1
    export RALPH_DB_URL_ORIG="$RALPH_DB_URL"
    export RALPH_DB_URL="${RALPH_DB_URL}?options=-csearch_path%3D${TEST_SCHEMA}"
}

teardown() {
    if [[ -n "${TEST_SCHEMA:-}" ]] && [[ -n "${RALPH_DB_URL_ORIG:-}" ]]; then
        psql "$RALPH_DB_URL_ORIG" -tAX -c "DROP SCHEMA IF EXISTS $TEST_SCHEMA CASCADE" >/dev/null 2>&1
    fi
    [[ -d "${TEST_WORK_DIR:-}" ]] && rm -rf "$TEST_WORK_DIR"
    [[ -d "${STUB_DIR:-}" ]] && rm -rf "$STUB_DIR"
}

# ---------------------------------------------------------------------------
# Empty database
# ---------------------------------------------------------------------------
@test "plan-status: empty database shows all zeros" {
    run "$SCRIPT_DIR/lib/task" plan-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 open"* ]]
    [[ "$output" == *"0 active"* ]]
    [[ "$output" == *"0 done"* ]]
    [[ "$output" == *"0 blocked"* ]]
    [[ "$output" == *"0 deleted"* ]]
}

# ---------------------------------------------------------------------------
# Single open task
# ---------------------------------------------------------------------------
@test "plan-status: counts open tasks" {
    "$SCRIPT_DIR/lib/task" create ps-open-1 "Open task 1"
    "$SCRIPT_DIR/lib/task" create ps-open-2 "Open task 2"
    run "$SCRIPT_DIR/lib/task" plan-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 open"* ]]
    [[ "$output" == *"0 active"* ]]
    [[ "$output" == *"0 done"* ]]
    [[ "$output" == *"0 blocked"* ]]
    [[ "$output" == *"0 deleted"* ]]
}

# ---------------------------------------------------------------------------
# Active tasks
# ---------------------------------------------------------------------------
@test "plan-status: counts active tasks" {
    "$SCRIPT_DIR/lib/task" create ps-act-1 "Active task" -p 0
    RALPH_AGENT_ID=test-agent "$SCRIPT_DIR/lib/task" claim --lease 600 >/dev/null
    run "$SCRIPT_DIR/lib/task" plan-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 open"* ]]
    [[ "$output" == *"1 active"* ]]
}

# ---------------------------------------------------------------------------
# Done tasks
# ---------------------------------------------------------------------------
@test "plan-status: counts done tasks" {
    "$SCRIPT_DIR/lib/task" create ps-done-1 "Done task" -p 0
    RALPH_AGENT_ID=test-agent "$SCRIPT_DIR/lib/task" claim --lease 600 >/dev/null
    "$SCRIPT_DIR/lib/task" done ps-done-1
    run "$SCRIPT_DIR/lib/task" plan-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 done"* ]]
    [[ "$output" == *"0 open"* ]]
}

# ---------------------------------------------------------------------------
# Deleted tasks
# ---------------------------------------------------------------------------
@test "plan-status: counts deleted tasks" {
    "$SCRIPT_DIR/lib/task" create ps-del-1 "Delete me"
    "$SCRIPT_DIR/lib/task" delete ps-del-1
    run "$SCRIPT_DIR/lib/task" plan-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 deleted"* ]]
    [[ "$output" == *"0 open"* ]]
}

# ---------------------------------------------------------------------------
# Blocked tasks (have unresolved blockers)
# ---------------------------------------------------------------------------
@test "plan-status: counts blocked tasks" {
    "$SCRIPT_DIR/lib/task" create ps-blocker "Blocker task"
    "$SCRIPT_DIR/lib/task" create ps-blocked "Blocked task"
    "$SCRIPT_DIR/lib/task" block ps-blocked --by ps-blocker
    run "$SCRIPT_DIR/lib/task" plan-status
    [ "$status" -eq 0 ]
    # ps-blocker is open (unblocked), ps-blocked is open but blocked
    [[ "$output" == *"1 open"* ]]
    [[ "$output" == *"1 blocked"* ]]
}

# ---------------------------------------------------------------------------
# Resolved blockers don't count as blocked
# ---------------------------------------------------------------------------
@test "plan-status: resolved blocker removes blocked count" {
    "$SCRIPT_DIR/lib/task" create ps-blk-r "Blocker" -p 0
    "$SCRIPT_DIR/lib/task" create ps-blkd-r "Blocked"
    "$SCRIPT_DIR/lib/task" block ps-blkd-r --by ps-blk-r
    # Blocker is done -> blocked task becomes unblocked
    RALPH_AGENT_ID=test-agent "$SCRIPT_DIR/lib/task" claim --lease 600 >/dev/null
    "$SCRIPT_DIR/lib/task" done ps-blk-r
    run "$SCRIPT_DIR/lib/task" plan-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 blocked"* ]]
    [[ "$output" == *"1 open"* ]]
    [[ "$output" == *"1 done"* ]]
}

# ---------------------------------------------------------------------------
# Deleted blocker also resolves blocked status
# ---------------------------------------------------------------------------
@test "plan-status: deleted blocker resolves blocked status" {
    "$SCRIPT_DIR/lib/task" create ps-blk-d "Blocker to delete"
    "$SCRIPT_DIR/lib/task" create ps-blkd-d "Blocked by deletable"
    "$SCRIPT_DIR/lib/task" block ps-blkd-d --by ps-blk-d
    "$SCRIPT_DIR/lib/task" delete ps-blk-d
    run "$SCRIPT_DIR/lib/task" plan-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 blocked"* ]]
    [[ "$output" == *"1 open"* ]]
    [[ "$output" == *"1 deleted"* ]]
}

# ---------------------------------------------------------------------------
# Mixed statuses
# ---------------------------------------------------------------------------
@test "plan-status: mixed statuses counted correctly" {
    # 1 open
    "$SCRIPT_DIR/lib/task" create ps-mix-open "Open task"
    # 1 active
    "$SCRIPT_DIR/lib/task" create ps-mix-act "Active task" -p 0
    RALPH_AGENT_ID=test-agent "$SCRIPT_DIR/lib/task" claim --lease 600 >/dev/null
    # 1 done
    "$SCRIPT_DIR/lib/task" create ps-mix-done "Done task" -p 0
    RALPH_AGENT_ID=test-agent "$SCRIPT_DIR/lib/task" claim --lease 600 >/dev/null
    "$SCRIPT_DIR/lib/task" done ps-mix-done
    # 1 deleted
    "$SCRIPT_DIR/lib/task" create ps-mix-del "Deleted task"
    "$SCRIPT_DIR/lib/task" delete ps-mix-del
    # 1 blocked (open + unresolved blocker)
    "$SCRIPT_DIR/lib/task" create ps-mix-blk "Blocker"
    "$SCRIPT_DIR/lib/task" create ps-mix-blkd "Blocked"
    "$SCRIPT_DIR/lib/task" block ps-mix-blkd --by ps-mix-blk

    run "$SCRIPT_DIR/lib/task" plan-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 open"* ]]
    [[ "$output" == *"1 active"* ]]
    [[ "$output" == *"1 done"* ]]
    [[ "$output" == *"1 blocked"* ]]
    [[ "$output" == *"1 deleted"* ]]
}

# ---------------------------------------------------------------------------
# Output format: single line with comma-separated counts
# ---------------------------------------------------------------------------
@test "plan-status: output is a single line" {
    run "$SCRIPT_DIR/lib/task" plan-status
    [ "$status" -eq 0 ]
    local line_count
    line_count=$(echo "$output" | wc -l)
    [ "$line_count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Blocked task that is also active counts as blocked, not active
# ---------------------------------------------------------------------------
@test "plan-status: active task with unresolved blocker counts as blocked" {
    "$SCRIPT_DIR/lib/task" create ps-blk-a "Blocker"
    "$SCRIPT_DIR/lib/task" create ps-blkd-a "Will be active but blocked" -p 0
    # First claim the task (before blocking it)
    RALPH_AGENT_ID=test-agent "$SCRIPT_DIR/lib/task" claim --lease 600 >/dev/null
    # Then add a blocker after it's already active
    "$SCRIPT_DIR/lib/task" block ps-blkd-a --by ps-blk-a

    run "$SCRIPT_DIR/lib/task" plan-status
    [ "$status" -eq 0 ]
    # The active+blocked task should count as blocked
    [[ "$output" == *"1 blocked"* ]]
}

# ---------------------------------------------------------------------------
# Unknown flags rejected
# ---------------------------------------------------------------------------
@test "plan-status: unknown flag rejected" {
    run "$SCRIPT_DIR/lib/task" plan-status --bogus
    [ "$status" -ne 0 ]
}
