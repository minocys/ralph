#!/usr/bin/env bats
# test/task_block.bats — Tests for the task block and unblock commands
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

# ===========================================================================
# task block
# ===========================================================================

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
@test "task block without ID exits 1" {
    run "$SCRIPT_DIR/task" block
    assert_failure
    assert_output --partial "Error: missing task ID"
}

@test "task block without --by exits 1" {
    run "$SCRIPT_DIR/task" block "test/01"
    assert_failure
    assert_output --partial "Error: missing --by"
}

# ---------------------------------------------------------------------------
# Not found
# ---------------------------------------------------------------------------
@test "task block with nonexistent task exits 2" {
    "$SCRIPT_DIR/task" create "blocker/01" "Blocker"
    run "$SCRIPT_DIR/task" block "nonexistent/01" --by "blocker/01"
    assert_failure
    [ "$status" -eq 2 ]
    assert_output --partial "not found"
}

@test "task block with nonexistent blocker exits 2" {
    "$SCRIPT_DIR/task" create "test/01" "Task"
    run "$SCRIPT_DIR/task" block "test/01" --by "nonexistent/01"
    assert_failure
    [ "$status" -eq 2 ]
    assert_output --partial "not found"
}

# ---------------------------------------------------------------------------
# Successful block
# ---------------------------------------------------------------------------
@test "task block adds dependency" {
    "$SCRIPT_DIR/task" create "test/01" "Task"
    "$SCRIPT_DIR/task" create "blocker/01" "Blocker"

    run "$SCRIPT_DIR/task" block "test/01" --by "blocker/01"
    assert_success
    assert_output "blocked test/01 by blocker/01"

    # Verify in database
    local dep_count
    dep_count=$(psql "$RALPH_DB_URL" -tAX -c "SELECT count(*) FROM task_deps WHERE task_id = 'test/01' AND blocked_by = 'blocker/01'")
    [ "$dep_count" = "1" ]
}

@test "task block is idempotent (duplicate does not error)" {
    "$SCRIPT_DIR/task" create "test/01" "Task"
    "$SCRIPT_DIR/task" create "blocker/01" "Blocker"

    "$SCRIPT_DIR/task" block "test/01" --by "blocker/01"
    run "$SCRIPT_DIR/task" block "test/01" --by "blocker/01"
    assert_success

    # Still only one row
    local dep_count
    dep_count=$(psql "$RALPH_DB_URL" -tAX -c "SELECT count(*) FROM task_deps WHERE task_id = 'test/01' AND blocked_by = 'blocker/01'")
    [ "$dep_count" = "1" ]
}

@test "task block dependency appears in task show" {
    "$SCRIPT_DIR/task" create "test/01" "Task"
    "$SCRIPT_DIR/task" create "blocker/01" "Blocker"
    "$SCRIPT_DIR/task" block "test/01" --by "blocker/01"

    run "$SCRIPT_DIR/task" show "test/01"
    assert_success
    assert_output --partial "Dependencies:"
    assert_output --partial "blocker/01"
}

@test "task block dependency appears in list --json" {
    "$SCRIPT_DIR/task" create "test/01" "Task"
    "$SCRIPT_DIR/task" create "blocker/01" "Blocker"
    "$SCRIPT_DIR/task" block "test/01" --by "blocker/01"

    run "$SCRIPT_DIR/task" list --json
    assert_success
    # The markdown-KV output for test/01 should include blocker/01 in deps
    assert_output --partial "id: test/01"
    assert_output --partial "deps: blocker/01"
}

# ---------------------------------------------------------------------------
# Special characters
# ---------------------------------------------------------------------------
@test "task block handles IDs with single quotes" {
    "$SCRIPT_DIR/task" create "test/it's" "Quoted task"
    "$SCRIPT_DIR/task" create "block/it's" "Quoted blocker"

    run "$SCRIPT_DIR/task" block "test/it's" --by "block/it's"
    assert_success

    local dep_count
    dep_count=$(psql "$RALPH_DB_URL" -tAX -c "SELECT count(*) FROM task_deps WHERE task_id = 'test/it''s' AND blocked_by = 'block/it''s'")
    [ "$dep_count" = "1" ]
}

# ===========================================================================
# task unblock
# ===========================================================================

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
@test "task unblock without ID exits 1" {
    run "$SCRIPT_DIR/task" unblock
    assert_failure
    assert_output --partial "Error: missing task ID"
}

@test "task unblock without --by exits 1" {
    run "$SCRIPT_DIR/task" unblock "test/01"
    assert_failure
    assert_output --partial "Error: missing --by"
}

# ---------------------------------------------------------------------------
# Not found
# ---------------------------------------------------------------------------
@test "task unblock nonexistent dependency exits 2" {
    "$SCRIPT_DIR/task" create "test/01" "Task"
    "$SCRIPT_DIR/task" create "blocker/01" "Blocker"

    run "$SCRIPT_DIR/task" unblock "test/01" --by "blocker/01"
    assert_failure
    [ "$status" -eq 2 ]
    assert_output --partial "dependency not found"
}

# ---------------------------------------------------------------------------
# Successful unblock
# ---------------------------------------------------------------------------
@test "task unblock removes dependency" {
    "$SCRIPT_DIR/task" create "test/01" "Task"
    "$SCRIPT_DIR/task" create "blocker/01" "Blocker"
    "$SCRIPT_DIR/task" block "test/01" --by "blocker/01"

    run "$SCRIPT_DIR/task" unblock "test/01" --by "blocker/01"
    assert_success
    assert_output "unblocked test/01 from blocker/01"

    # Verify removed from database
    local dep_count
    dep_count=$(psql "$RALPH_DB_URL" -tAX -c "SELECT count(*) FROM task_deps WHERE task_id = 'test/01' AND blocked_by = 'blocker/01'")
    [ "$dep_count" = "0" ]
}

@test "task unblock removes only specified dependency" {
    "$SCRIPT_DIR/task" create "test/01" "Task"
    "$SCRIPT_DIR/task" create "blocker/01" "Blocker 1"
    "$SCRIPT_DIR/task" create "blocker/02" "Blocker 2"
    "$SCRIPT_DIR/task" block "test/01" --by "blocker/01"
    "$SCRIPT_DIR/task" block "test/01" --by "blocker/02"

    "$SCRIPT_DIR/task" unblock "test/01" --by "blocker/01"

    # blocker/01 removed, blocker/02 still there
    local dep_count
    dep_count=$(psql "$RALPH_DB_URL" -tAX -c "SELECT count(*) FROM task_deps WHERE task_id = 'test/01'")
    [ "$dep_count" = "1" ]

    local remaining
    remaining=$(psql "$RALPH_DB_URL" -tAX -c "SELECT blocked_by FROM task_deps WHERE task_id = 'test/01'")
    [ "$remaining" = "blocker/02" ]
}

@test "task unblock dependency no longer appears in task show" {
    "$SCRIPT_DIR/task" create "test/01" "Task"
    "$SCRIPT_DIR/task" create "blocker/01" "Blocker"
    "$SCRIPT_DIR/task" block "test/01" --by "blocker/01"
    "$SCRIPT_DIR/task" unblock "test/01" --by "blocker/01"

    run "$SCRIPT_DIR/task" show "test/01"
    assert_success
    refute_output --partial "Dependencies:"
    refute_output --partial "blocker/01"
}

# ---------------------------------------------------------------------------
# Special characters
# ---------------------------------------------------------------------------
@test "task unblock handles IDs with single quotes" {
    "$SCRIPT_DIR/task" create "test/it's" "Quoted task"
    "$SCRIPT_DIR/task" create "block/it's" "Quoted blocker"
    "$SCRIPT_DIR/task" block "test/it's" --by "block/it's"

    run "$SCRIPT_DIR/task" unblock "test/it's" --by "block/it's"
    assert_success

    local dep_count
    dep_count=$(psql "$RALPH_DB_URL" -tAX -c "SELECT count(*) FROM task_deps WHERE task_id = 'test/it''s' AND blocked_by = 'block/it''s'")
    [ "$dep_count" = "0" ]
}
