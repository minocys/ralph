#!/usr/bin/env bats
# test/task_update.bats — Tests for the task update command
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
@test "task update without ID exits 1 with error" {
    run "$SCRIPT_DIR/task" update
    assert_failure
    assert_output --partial "Error: missing task ID"
}

@test "task update with ID but no flags exits 1" {
    run "$SCRIPT_DIR/task" update "test/01"
    assert_failure
    assert_output --partial "Error: no fields to update"
}

@test "task update with unknown flag exits 1" {
    "$SCRIPT_DIR/task" create "test/01" "Original title"
    run "$SCRIPT_DIR/task" update "test/01" --bogus val
    assert_failure
    assert_output --partial "Error: unknown flag"
}

# ---------------------------------------------------------------------------
# Not found
# ---------------------------------------------------------------------------
@test "task update on nonexistent task exits 2" {
    run "$SCRIPT_DIR/task" update "nonexistent/01" --title "New title"
    assert_failure
    [ "$status" -eq 2 ]
    assert_output --partial "not found"
}

# ---------------------------------------------------------------------------
# Immutability of done tasks
# ---------------------------------------------------------------------------
@test "task update on done task exits 1" {
    "$SCRIPT_DIR/task" create "test/01" "A task"
    # Directly set status to done
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status = 'done' WHERE id = 'test/01'" >/dev/null
    run "$SCRIPT_DIR/task" update "test/01" --title "New title"
    assert_failure
    [ "$status" -eq 1 ]
    assert_output --partial "done and cannot be updated"
}

# ---------------------------------------------------------------------------
# Field updates
# ---------------------------------------------------------------------------
@test "task update --title changes title" {
    "$SCRIPT_DIR/task" create "test/01" "Original title"
    run "$SCRIPT_DIR/task" update "test/01" --title "Updated title"
    assert_success
    assert_output "updated test/01"

    local new_title
    new_title=$(psql "$RALPH_DB_URL" -tAX -c "SELECT title FROM tasks WHERE id = 'test/01'")
    [ "$new_title" = "Updated title" ]
}

@test "task update --priority changes priority" {
    "$SCRIPT_DIR/task" create "test/01" "A task" -p 2
    run "$SCRIPT_DIR/task" update "test/01" --priority 0
    assert_success

    local new_pri
    new_pri=$(psql "$RALPH_DB_URL" -tAX -c "SELECT priority FROM tasks WHERE id = 'test/01'")
    [ "$new_pri" = "0" ]
}

@test "task update --description changes description" {
    "$SCRIPT_DIR/task" create "test/01" "A task" -d "Old desc"
    run "$SCRIPT_DIR/task" update "test/01" --description "New desc"
    assert_success

    local new_desc
    new_desc=$(psql "$RALPH_DB_URL" -tAX -c "SELECT description FROM tasks WHERE id = 'test/01'")
    [ "$new_desc" = "New desc" ]
}

@test "task update --status changes status" {
    "$SCRIPT_DIR/task" create "test/01" "A task"
    run "$SCRIPT_DIR/task" update "test/01" --status "active"
    assert_success

    local new_status
    new_status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE id = 'test/01'")
    [ "$new_status" = "active" ]
}

@test "task update always sets updated_at" {
    "$SCRIPT_DIR/task" create "test/01" "A task"
    # Clear updated_at to verify it gets set
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET updated_at = NULL WHERE id = 'test/01'" >/dev/null
    "$SCRIPT_DIR/task" update "test/01" --title "New"

    local updated
    updated=$(psql "$RALPH_DB_URL" -tAX -c "SELECT updated_at IS NOT NULL FROM tasks WHERE id = 'test/01'")
    [ "$updated" = "t" ]
}

# ---------------------------------------------------------------------------
# Steps replacement
# ---------------------------------------------------------------------------
@test "task update --steps replaces existing steps" {
    "$SCRIPT_DIR/task" create "test/01" "A task" -s '[{"content":"step one"},{"content":"step two"}]'

    # Verify initial steps
    local count_before
    count_before=$(psql "$RALPH_DB_URL" -tAX -c "SELECT count(*) FROM task_steps WHERE task_id = 'test/01'")
    [ "$count_before" = "2" ]

    # Replace steps
    run "$SCRIPT_DIR/task" update "test/01" --steps '[{"content":"new step A"},{"content":"new step B"},{"content":"new step C"}]'
    assert_success

    local count_after
    count_after=$(psql "$RALPH_DB_URL" -tAX -c "SELECT count(*) FROM task_steps WHERE task_id = 'test/01'")
    [ "$count_after" = "3" ]

    local first_step
    first_step=$(psql "$RALPH_DB_URL" -tAX -c "SELECT content FROM task_steps WHERE task_id = 'test/01' AND seq = 1")
    [ "$first_step" = "new step A" ]
}

@test "task update --steps with empty array clears steps" {
    "$SCRIPT_DIR/task" create "test/01" "A task" -s '[{"content":"step one"}]'
    run "$SCRIPT_DIR/task" update "test/01" --steps '[]'
    assert_success

    local count
    count=$(psql "$RALPH_DB_URL" -tAX -c "SELECT count(*) FROM task_steps WHERE task_id = 'test/01'")
    [ "$count" = "0" ]
}

# ---------------------------------------------------------------------------
# Multiple fields at once
# ---------------------------------------------------------------------------
@test "task update multiple fields at once" {
    "$SCRIPT_DIR/task" create "test/01" "A task" -p 2 -d "Old desc"
    run "$SCRIPT_DIR/task" update "test/01" --title "New title" --priority 0 --description "New desc"
    assert_success

    local title pri desc
    title=$(psql "$RALPH_DB_URL" -tAX -c "SELECT title FROM tasks WHERE id = 'test/01'")
    pri=$(psql "$RALPH_DB_URL" -tAX -c "SELECT priority FROM tasks WHERE id = 'test/01'")
    desc=$(psql "$RALPH_DB_URL" -tAX -c "SELECT description FROM tasks WHERE id = 'test/01'")
    [ "$title" = "New title" ]
    [ "$pri" = "0" ]
    [ "$desc" = "New desc" ]
}

# ---------------------------------------------------------------------------
# Special characters
# ---------------------------------------------------------------------------
@test "task update handles single quotes in title" {
    "$SCRIPT_DIR/task" create "test/01" "A task"
    run "$SCRIPT_DIR/task" update "test/01" --title "It's a test"
    assert_success

    local title
    title=$(psql "$RALPH_DB_URL" -tAX -c "SELECT title FROM tasks WHERE id = 'test/01'")
    [ "$title" = "It's a test" ]
}
