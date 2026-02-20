#!/usr/bin/env bats
# test/task_fail.bats — Tests for the task fail command
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
@test "task fail without args exits 1 with error" {
    run "$SCRIPT_DIR/task" fail
    assert_failure
    assert_output --partial "Error: missing task ID"
}

# ---------------------------------------------------------------------------
# Not found
# ---------------------------------------------------------------------------
@test "task fail on nonexistent task exits 2" {
    run "$SCRIPT_DIR/task" fail "nonexistent"
    assert_failure
    [ "$status" -eq 2 ]
    assert_output --partial "Error: task 'nonexistent' not found"
}

# ---------------------------------------------------------------------------
# Status validation
# ---------------------------------------------------------------------------
@test "task fail on open task exits 1" {
    "$SCRIPT_DIR/task" create "tf-01" "Open task"
    run "$SCRIPT_DIR/task" fail "tf-01"
    assert_failure
    [ "$status" -eq 1 ]
    assert_output --partial "is not active"
}

@test "task fail on done task exits 1" {
    "$SCRIPT_DIR/task" create "tf-02" "Done task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='done' WHERE id='tf-02';" >/dev/null

    run "$SCRIPT_DIR/task" fail "tf-02"
    assert_failure
    [ "$status" -eq 1 ]
    assert_output --partial "is not active"
}

# ---------------------------------------------------------------------------
# Successful fail
# ---------------------------------------------------------------------------
@test "task fail on active task succeeds" {
    "$SCRIPT_DIR/task" create "tf-03" "Active task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE id='tf-03';" >/dev/null

    run "$SCRIPT_DIR/task" fail "tf-03"
    assert_success
    assert_output "failed tf-03"
}

@test "task fail sets status back to open" {
    "$SCRIPT_DIR/task" create "tf-04" "Active task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE id='tf-04';" >/dev/null

    "$SCRIPT_DIR/task" fail "tf-04"

    local task_status
    task_status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE id='tf-04';")
    [ "$task_status" = "open" ]
}

@test "task fail clears assignee" {
    "$SCRIPT_DIR/task" create "tf-05" "Active task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE id='tf-05';" >/dev/null

    "$SCRIPT_DIR/task" fail "tf-05"

    local assignee
    assignee=$(psql "$RALPH_DB_URL" -tAX -c "SELECT assignee FROM tasks WHERE id='tf-05';")
    [ -z "$assignee" ]
}

@test "task fail clears lease_expires_at" {
    "$SCRIPT_DIR/task" create "tf-06" "Active task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1', lease_expires_at=now()+interval '600 seconds' WHERE id='tf-06';" >/dev/null

    "$SCRIPT_DIR/task" fail "tf-06"

    local lease
    lease=$(psql "$RALPH_DB_URL" -tAX -c "SELECT lease_expires_at FROM tasks WHERE id='tf-06';")
    [ -z "$lease" ]
}

@test "task fail increments retry_count" {
    "$SCRIPT_DIR/task" create "tf-07" "Active task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1', retry_count=0 WHERE id='tf-07';" >/dev/null

    "$SCRIPT_DIR/task" fail "tf-07"

    local retry_count
    retry_count=$(psql "$RALPH_DB_URL" -tAX -c "SELECT retry_count FROM tasks WHERE id='tf-07';")
    [ "$retry_count" -eq 1 ]
}

@test "task fail increments retry_count cumulatively" {
    "$SCRIPT_DIR/task" create "tf-08" "Active task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1', retry_count=3 WHERE id='tf-08';" >/dev/null

    "$SCRIPT_DIR/task" fail "tf-08"

    local retry_count
    retry_count=$(psql "$RALPH_DB_URL" -tAX -c "SELECT retry_count FROM tasks WHERE id='tf-08';")
    [ "$retry_count" -eq 4 ]
}

@test "task fail sets updated_at" {
    "$SCRIPT_DIR/task" create "tf-09" "Active task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1', updated_at=NULL WHERE id='tf-09';" >/dev/null

    "$SCRIPT_DIR/task" fail "tf-09"

    local updated
    updated=$(psql "$RALPH_DB_URL" -tAX -c "SELECT updated_at FROM tasks WHERE id='tf-09';")
    [ -n "$updated" ]
}

# ---------------------------------------------------------------------------
# --reason flag
# ---------------------------------------------------------------------------
@test "task fail with --reason succeeds" {
    "$SCRIPT_DIR/task" create "tf-10" "Active task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE id='tf-10';" >/dev/null

    run "$SCRIPT_DIR/task" fail "tf-10" --reason "out of memory"
    assert_success
    assert_output "failed tf-10"
}

@test "task fail with --reason persists reason in database" {
    "$SCRIPT_DIR/task" create "tf-10a" "Active task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE id='tf-10a';" >/dev/null

    "$SCRIPT_DIR/task" fail "tf-10a" --reason "out of memory"

    local fail_reason
    fail_reason=$(psql "$RALPH_DB_URL" -tAX -c "SELECT fail_reason FROM tasks WHERE id='tf-10a';")
    [ "$fail_reason" = "out of memory" ]
}

@test "task fail without --reason stores NULL fail_reason" {
    "$SCRIPT_DIR/task" create "tf-10b" "Active task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE id='tf-10b';" >/dev/null

    "$SCRIPT_DIR/task" fail "tf-10b"

    local fail_reason
    fail_reason=$(psql "$RALPH_DB_URL" -tAX -c "SELECT fail_reason FROM tasks WHERE id='tf-10b';")
    [ -z "$fail_reason" ]
}

# ---------------------------------------------------------------------------
# Integration: failed task is re-claimable
# ---------------------------------------------------------------------------
@test "failed task can be re-claimed" {
    export RALPH_AGENT_ID="agent-test"

    "$SCRIPT_DIR/task" create "tf-11" "Re-claimable task" -p 1

    # Claim the task
    run "$SCRIPT_DIR/task" claim
    assert_success
    assert_output --partial "tf-11"

    # Fail it
    "$SCRIPT_DIR/task" fail "tf-11"

    # Should be claimable again
    run "$SCRIPT_DIR/task" claim
    assert_success
    assert_output --partial "tf-11"
}

@test "failed task retry_count increments through claim-fail cycle" {
    export RALPH_AGENT_ID="agent-test"

    "$SCRIPT_DIR/task" create "tf-12" "Retry task" -p 1

    # First claim-fail cycle
    "$SCRIPT_DIR/task" claim >/dev/null
    "$SCRIPT_DIR/task" fail "tf-12"

    local retry1
    retry1=$(psql "$RALPH_DB_URL" -tAX -c "SELECT retry_count FROM tasks WHERE id='tf-12';")
    [ "$retry1" -eq 1 ]

    # Second claim-fail cycle
    "$SCRIPT_DIR/task" claim >/dev/null
    "$SCRIPT_DIR/task" fail "tf-12"

    local retry2
    retry2=$(psql "$RALPH_DB_URL" -tAX -c "SELECT retry_count FROM tasks WHERE id='tf-12';")
    [ "$retry2" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Special characters
# ---------------------------------------------------------------------------
@test "task fail works with special characters in task ID" {
    "$SCRIPT_DIR/task" create "tf/special-13" "Special ID task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE id='tf/special-13';" >/dev/null

    run "$SCRIPT_DIR/task" fail "tf/special-13"
    assert_success
    assert_output "failed tf/special-13"
}

@test "task fail works with single quotes in task ID" {
    "$SCRIPT_DIR/task" create "tf'quoted" "Quoted ID task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE id='tf''quoted';" >/dev/null

    run "$SCRIPT_DIR/task" fail "tf'quoted"
    assert_success
}
