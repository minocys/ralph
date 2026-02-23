#!/usr/bin/env bats
# test/task_delete.bats — Tests for the task delete command (soft delete)
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
@test "task delete without ID exits 1 with error" {
    run "$SCRIPT_DIR/task" delete
    assert_failure
    assert_output --partial "Error: missing task ID"
}

# ---------------------------------------------------------------------------
# Not found
# ---------------------------------------------------------------------------
@test "task delete on nonexistent task exits 2" {
    run "$SCRIPT_DIR/task" delete "nonexistent/01"
    assert_failure
    [ "$status" -eq 2 ]
    assert_output --partial "not found"
}

# ---------------------------------------------------------------------------
# Successful soft delete
# ---------------------------------------------------------------------------
@test "task delete sets status to deleted" {
    "$SCRIPT_DIR/task" create "test/01" "A task to delete"
    run "$SCRIPT_DIR/task" delete "test/01"
    assert_success
    assert_output "deleted test/01"

    local task_status
    task_status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$task_status" = "deleted" ]
}

@test "task delete sets deleted_at timestamp" {
    "$SCRIPT_DIR/task" create "test/01" "A task to delete"
    "$SCRIPT_DIR/task" delete "test/01"

    local deleted_at
    deleted_at=$(psql "$RALPH_DB_URL" -tAX -c "SELECT deleted_at IS NOT NULL FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$deleted_at" = "t" ]
}

@test "task delete sets updated_at timestamp" {
    "$SCRIPT_DIR/task" create "test/01" "A task to delete"
    # Clear updated_at to verify it gets set
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET updated_at = NULL WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'" >/dev/null
    "$SCRIPT_DIR/task" delete "test/01"

    local updated_at
    updated_at=$(psql "$RALPH_DB_URL" -tAX -c "SELECT updated_at IS NOT NULL FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$updated_at" = "t" ]
}

# ---------------------------------------------------------------------------
# Integration with list
# ---------------------------------------------------------------------------
@test "deleted task is excluded from default list" {
    "$SCRIPT_DIR/task" create "test/01" "Visible task"
    "$SCRIPT_DIR/task" create "test/02" "Task to delete"
    "$SCRIPT_DIR/task" delete "test/02"

    run "$SCRIPT_DIR/task" list
    assert_success
    assert_output --partial "test/01"
    refute_output --partial "test/02"
}

@test "deleted task appears with --status deleted filter" {
    "$SCRIPT_DIR/task" create "test/01" "Task to delete"
    "$SCRIPT_DIR/task" delete "test/01"

    run "$SCRIPT_DIR/task" list --status deleted
    assert_success
    assert_output --partial "test/01"
}

# ---------------------------------------------------------------------------
# Special characters
# ---------------------------------------------------------------------------
@test "task delete handles ID with single quotes" {
    "$SCRIPT_DIR/task" create "test/it's" "Quoted task"
    run "$SCRIPT_DIR/task" delete "test/it's"
    assert_success
    assert_output "deleted test/it's"

    local task_status
    task_status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE slug = 'test/it''s' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$task_status" = "deleted" ]
}

# ---------------------------------------------------------------------------
# Task record preserved
# ---------------------------------------------------------------------------
@test "task delete preserves the task record (soft delete)" {
    "$SCRIPT_DIR/task" create "test/01" "Soft deleted task" -d "Should still exist"
    "$SCRIPT_DIR/task" delete "test/01"

    # Task should still exist in the database
    local count
    count=$(psql "$RALPH_DB_URL" -tAX -c "SELECT count(*) FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$count" = "1" ]

    # Original fields should be preserved
    local title
    title=$(psql "$RALPH_DB_URL" -tAX -c "SELECT title FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$title" = "Soft deleted task" ]
}

@test "deleted task visible via task show" {
    "$SCRIPT_DIR/task" create "test/01" "A task"
    "$SCRIPT_DIR/task" delete "test/01"

    run "$SCRIPT_DIR/task" show "test/01"
    assert_success
    assert_output --partial "Status:      deleted"
    assert_output --partial "Deleted:"
}
