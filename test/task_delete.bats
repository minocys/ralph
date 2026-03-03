#!/usr/bin/env bats
# test/task_delete.bats — Tests for the task delete command (soft delete)

load test_helper

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
@test "task delete without ID exits 1 with error" {
    run "$SCRIPT_DIR/lib/task" delete
    assert_failure
    assert_output --partial "Error: missing task ID"
}

# ---------------------------------------------------------------------------
# Not found
# ---------------------------------------------------------------------------
@test "task delete on nonexistent task exits 2" {
    run "$SCRIPT_DIR/lib/task" delete "nonexistent/01"
    assert_failure
    [ "$status" -eq 2 ]
    assert_output --partial "not found"
}

# ---------------------------------------------------------------------------
# Successful soft delete
# ---------------------------------------------------------------------------
@test "task delete sets status to deleted" {
    "$SCRIPT_DIR/lib/task" create "test/01" "A task to delete"
    run "$SCRIPT_DIR/lib/task" delete "test/01"
    assert_success
    assert_output "deleted test/01"

    local task_status
    task_status=$(sqlite3 "$RALPH_DB_PATH" "SELECT status FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$task_status" = "deleted" ]
}

@test "task delete sets deleted_at timestamp" {
    "$SCRIPT_DIR/lib/task" create "test/01" "A task to delete"
    "$SCRIPT_DIR/lib/task" delete "test/01"

    local deleted_at
    deleted_at=$(sqlite3 "$RALPH_DB_PATH" "SELECT CASE WHEN deleted_at IS NOT NULL THEN 1 ELSE 0 END FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$deleted_at" = "1" ]
}

@test "task delete sets updated_at timestamp" {
    "$SCRIPT_DIR/lib/task" create "test/01" "A task to delete"
    # Clear updated_at to verify it gets set
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET updated_at = NULL WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'"
    "$SCRIPT_DIR/lib/task" delete "test/01"

    local updated_at
    updated_at=$(sqlite3 "$RALPH_DB_PATH" "SELECT CASE WHEN updated_at IS NOT NULL THEN 1 ELSE 0 END FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$updated_at" = "1" ]
}

# ---------------------------------------------------------------------------
# Integration with list
# ---------------------------------------------------------------------------
@test "deleted task is excluded from default list" {
    "$SCRIPT_DIR/lib/task" create "test/01" "Visible task"
    "$SCRIPT_DIR/lib/task" create "test/02" "Task to delete"
    "$SCRIPT_DIR/lib/task" delete "test/02"

    run "$SCRIPT_DIR/lib/task" list
    assert_success
    assert_output --partial "test/01"
    refute_output --partial "test/02"
}

@test "deleted task appears with --status deleted filter" {
    "$SCRIPT_DIR/lib/task" create "test/01" "Task to delete"
    "$SCRIPT_DIR/lib/task" delete "test/01"

    run "$SCRIPT_DIR/lib/task" list --status deleted
    assert_success
    assert_output --partial "test/01"
}

# ---------------------------------------------------------------------------
# Special characters
# ---------------------------------------------------------------------------
@test "task delete handles ID with single quotes" {
    "$SCRIPT_DIR/lib/task" create "test/it's" "Quoted task"
    run "$SCRIPT_DIR/lib/task" delete "test/it's"
    assert_success
    assert_output "deleted test/it's"

    local task_status
    task_status=$(sqlite3 "$RALPH_DB_PATH" "SELECT status FROM tasks WHERE slug = 'test/it''s' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$task_status" = "deleted" ]
}

# ---------------------------------------------------------------------------
# Task record preserved
# ---------------------------------------------------------------------------
@test "task delete preserves the task record (soft delete)" {
    "$SCRIPT_DIR/lib/task" create "test/01" "Soft deleted task" -d "Should still exist"
    "$SCRIPT_DIR/lib/task" delete "test/01"

    # Task should still exist in the database
    local count
    count=$(sqlite3 "$RALPH_DB_PATH" "SELECT count(*) FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$count" = "1" ]

    # Original fields should be preserved
    local title
    title=$(sqlite3 "$RALPH_DB_PATH" "SELECT title FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$title" = "Soft deleted task" ]
}

@test "deleted task visible via task show" {
    "$SCRIPT_DIR/lib/task" create "test/01" "A task"
    "$SCRIPT_DIR/lib/task" delete "test/01"

    run "$SCRIPT_DIR/lib/task" show "test/01"
    assert_success
    assert_output --partial "Status:      deleted"
    assert_output --partial "Deleted:"
}
