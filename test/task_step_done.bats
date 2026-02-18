#!/usr/bin/env bats
# test/task_step_done.bats — Tests for the task step-done command
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
# Argument validation
# ---------------------------------------------------------------------------
@test "task step-done without args exits 1 with error" {
    run "$SCRIPT_DIR/task" step-done
    assert_failure
    assert_output --partial "Error: missing task ID"
}

@test "task step-done without seq exits 1 with error" {
    run "$SCRIPT_DIR/task" step-done "test-01"
    assert_failure
    assert_output --partial "Error: missing step sequence number"
}

# ---------------------------------------------------------------------------
# Not found cases
# ---------------------------------------------------------------------------
@test "task step-done on nonexistent task exits 2" {
    run "$SCRIPT_DIR/task" step-done "nonexistent" 1
    assert_failure
    [ "$status" -eq 2 ]
    assert_output --partial "Error: task 'nonexistent' not found"
}

@test "task step-done on nonexistent step exits 2" {
    "$SCRIPT_DIR/task" create "sd-01" "Task with steps" -s '[{"content":"Step 1"}]'
    run "$SCRIPT_DIR/task" step-done "sd-01" 99
    assert_failure
    [ "$status" -eq 2 ]
    assert_output --partial "Error: step 99 not found"
}

# ---------------------------------------------------------------------------
# Successful step-done
# ---------------------------------------------------------------------------
@test "task step-done marks step as done" {
    "$SCRIPT_DIR/task" create "sd-02" "Task with steps" -s '[{"content":"Step one"},{"content":"Step two"}]'

    run "$SCRIPT_DIR/task" step-done "sd-02" 1
    assert_success
    assert_output "step-done sd-02 1"

    # Verify step status changed in DB
    local step_status
    step_status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM task_steps WHERE task_id = 'sd-02' AND seq = 1;")
    [ "$step_status" = "done" ]
}

@test "task step-done only affects the specified step" {
    "$SCRIPT_DIR/task" create "sd-03" "Task with steps" -s '[{"content":"Step one"},{"content":"Step two"},{"content":"Step three"}]'

    "$SCRIPT_DIR/task" step-done "sd-03" 2

    # Step 1 should still be pending
    local s1_status
    s1_status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM task_steps WHERE task_id = 'sd-03' AND seq = 1;")
    [ "$s1_status" = "pending" ]

    # Step 2 should be done
    local s2_status
    s2_status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM task_steps WHERE task_id = 'sd-03' AND seq = 2;")
    [ "$s2_status" = "done" ]

    # Step 3 should still be pending
    local s3_status
    s3_status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM task_steps WHERE task_id = 'sd-03' AND seq = 3;")
    [ "$s3_status" = "pending" ]
}

# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------
@test "task step-done is idempotent (marking done step again succeeds)" {
    "$SCRIPT_DIR/task" create "sd-04" "Task with steps" -s '[{"content":"Step one"}]'

    run "$SCRIPT_DIR/task" step-done "sd-04" 1
    assert_success

    # Run again — should still succeed
    run "$SCRIPT_DIR/task" step-done "sd-04" 1
    assert_success
    assert_output "step-done sd-04 1"
}

# ---------------------------------------------------------------------------
# Integration with show
# ---------------------------------------------------------------------------
@test "task step-done is visible in task show output" {
    "$SCRIPT_DIR/task" create "sd-05" "Task with steps" -s '[{"content":"Step one"},{"content":"Step two"}]'

    "$SCRIPT_DIR/task" step-done "sd-05" 1

    run "$SCRIPT_DIR/task" show "sd-05"
    assert_success
    assert_output --partial "1. [done] Step one"
    assert_output --partial "2. [pending] Step two"
}

# ---------------------------------------------------------------------------
# Special characters
# ---------------------------------------------------------------------------
@test "task step-done works with special characters in task ID" {
    "$SCRIPT_DIR/task" create "sd/special-06" "Task with special ID" -s '[{"content":"Step one"}]'

    run "$SCRIPT_DIR/task" step-done "sd/special-06" 1
    assert_success
    assert_output "step-done sd/special-06 1"
}

@test "task step-done works with single quotes in task ID" {
    "$SCRIPT_DIR/task" create "sd'quoted" "Task with quote" -s '[{"content":"Step one"}]'

    run "$SCRIPT_DIR/task" step-done "sd'quoted" 1
    assert_success
}

# ---------------------------------------------------------------------------
# Multiple steps completion
# ---------------------------------------------------------------------------
@test "task step-done can mark all steps done sequentially" {
    "$SCRIPT_DIR/task" create "sd-07" "Task with steps" -s '[{"content":"Step one"},{"content":"Step two"},{"content":"Step three"}]'

    run "$SCRIPT_DIR/task" step-done "sd-07" 1
    assert_success
    run "$SCRIPT_DIR/task" step-done "sd-07" 2
    assert_success
    run "$SCRIPT_DIR/task" step-done "sd-07" 3
    assert_success

    # All steps should be done
    local done_count
    done_count=$(psql "$RALPH_DB_URL" -tAX -c "SELECT count(*) FROM task_steps WHERE task_id = 'sd-07' AND status = 'done';")
    [ "$done_count" = "3" ]
}
