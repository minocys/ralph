#!/usr/bin/env bats
# test/task_update.bats — Tests for the task update command

load test_helper

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
@test "task update without ID exits 1 with error" {
    run "$SCRIPT_DIR/lib/task" update
    assert_failure
    assert_output --partial "Error: missing task ID"
}

@test "task update with ID but no flags exits 1" {
    run "$SCRIPT_DIR/lib/task" update "test/01"
    assert_failure
    assert_output --partial "Error: no fields to update"
}

@test "task update with unknown flag exits 1" {
    "$SCRIPT_DIR/lib/task" create "test/01" "Original title"
    run "$SCRIPT_DIR/lib/task" update "test/01" --bogus val
    assert_failure
    assert_output --partial "Error: unknown flag"
}

# ---------------------------------------------------------------------------
# Not found
# ---------------------------------------------------------------------------
@test "task update on nonexistent task exits 2" {
    run "$SCRIPT_DIR/lib/task" update "nonexistent/01" --title "New title"
    assert_failure
    [ "$status" -eq 2 ]
    assert_output --partial "not found"
}

# ---------------------------------------------------------------------------
# Immutability of done tasks
# ---------------------------------------------------------------------------
@test "task update on done task exits 1" {
    "$SCRIPT_DIR/lib/task" create "test/01" "A task"
    # Directly set status to done
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status = 'done' WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'"
    run "$SCRIPT_DIR/lib/task" update "test/01" --title "New title"
    assert_failure
    [ "$status" -eq 1 ]
    assert_output --partial "done and cannot be updated"
}

# ---------------------------------------------------------------------------
# Field updates
# ---------------------------------------------------------------------------
@test "task update --title changes title" {
    "$SCRIPT_DIR/lib/task" create "test/01" "Original title"
    run "$SCRIPT_DIR/lib/task" update "test/01" --title "Updated title"
    assert_success
    assert_output "updated test/01"

    local new_title
    new_title=$(sqlite3 "$RALPH_DB_PATH" "SELECT title FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$new_title" = "Updated title" ]
}

@test "task update --priority changes priority" {
    "$SCRIPT_DIR/lib/task" create "test/01" "A task" -p 2
    run "$SCRIPT_DIR/lib/task" update "test/01" --priority 0
    assert_success

    local new_pri
    new_pri=$(sqlite3 "$RALPH_DB_PATH" "SELECT priority FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$new_pri" = "0" ]
}

@test "task update --description changes description" {
    "$SCRIPT_DIR/lib/task" create "test/01" "A task" -d "Old desc"
    run "$SCRIPT_DIR/lib/task" update "test/01" --description "New desc"
    assert_success

    local new_desc
    new_desc=$(sqlite3 "$RALPH_DB_PATH" "SELECT description FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$new_desc" = "New desc" ]
}

@test "task update --status changes status" {
    "$SCRIPT_DIR/lib/task" create "test/01" "A task"
    run "$SCRIPT_DIR/lib/task" update "test/01" --status "active"
    assert_success

    local new_status
    new_status=$(sqlite3 "$RALPH_DB_PATH" "SELECT status FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$new_status" = "active" ]
}

@test "task update always sets updated_at" {
    "$SCRIPT_DIR/lib/task" create "test/01" "A task"
    # Clear updated_at to verify it gets set
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET updated_at = NULL WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'"
    "$SCRIPT_DIR/lib/task" update "test/01" --title "New"

    local updated
    updated=$(sqlite3 "$RALPH_DB_PATH" "SELECT CASE WHEN updated_at IS NOT NULL THEN 1 ELSE 0 END FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$updated" = "1" ]
}

# ---------------------------------------------------------------------------
# Steps replacement
# ---------------------------------------------------------------------------
@test "task update --steps replaces existing steps" {
    "$SCRIPT_DIR/lib/task" create "test/01" "A task" -s '["step one","step two"]'

    # Verify initial steps
    local count_before
    count_before=$(sqlite3 "$RALPH_DB_PATH" "SELECT json_array_length(steps) FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$count_before" = "2" ]

    # Replace steps
    run "$SCRIPT_DIR/lib/task" update "test/01" --steps '["new step A","new step B","new step C"]'
    assert_success

    local count_after
    count_after=$(sqlite3 "$RALPH_DB_PATH" "SELECT json_array_length(steps) FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$count_after" = "3" ]

    local first_step
    first_step=$(sqlite3 "$RALPH_DB_PATH" "SELECT json_extract(steps, '\$[0]') FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$first_step" = "new step A" ]
}

@test "task update --steps with empty array clears steps" {
    "$SCRIPT_DIR/lib/task" create "test/01" "A task" -s '["step one"]'
    run "$SCRIPT_DIR/lib/task" update "test/01" --steps '[]'
    assert_success

    local steps_null
    steps_null=$(sqlite3 "$RALPH_DB_PATH" "SELECT CASE WHEN steps IS NULL THEN 1 ELSE 0 END FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$steps_null" = "1" ]
}

# ---------------------------------------------------------------------------
# Multiple fields at once
# ---------------------------------------------------------------------------
@test "task update multiple fields at once" {
    "$SCRIPT_DIR/lib/task" create "test/01" "A task" -p 2 -d "Old desc"
    run "$SCRIPT_DIR/lib/task" update "test/01" --title "New title" --priority 0 --description "New desc"
    assert_success

    local title pri desc
    title=$(sqlite3 "$RALPH_DB_PATH" "SELECT title FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    pri=$(sqlite3 "$RALPH_DB_PATH" "SELECT priority FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    desc=$(sqlite3 "$RALPH_DB_PATH" "SELECT description FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$title" = "New title" ]
    [ "$pri" = "0" ]
    [ "$desc" = "New desc" ]
}

@test "task update --title and --steps together applies both in single UPDATE" {
    "$SCRIPT_DIR/lib/task" create "test/01" "Original" -s '["old step"]'
    run "$SCRIPT_DIR/lib/task" update "test/01" --title "Combined" --steps '["new step A","new step B"]'
    assert_success

    local title steps_count first_step
    title=$(sqlite3 "$RALPH_DB_PATH" "SELECT title FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    steps_count=$(sqlite3 "$RALPH_DB_PATH" "SELECT json_array_length(steps) FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    first_step=$(sqlite3 "$RALPH_DB_PATH" "SELECT json_extract(steps, '\$[0]') FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$title" = "Combined" ]
    [ "$steps_count" = "2" ]
    [ "$first_step" = "new step A" ]
}

@test "task update --steps alone updates only steps" {
    "$SCRIPT_DIR/lib/task" create "test/01" "Keep this title" -s '["old step"]'
    run "$SCRIPT_DIR/lib/task" update "test/01" --steps '["only step"]'
    assert_success

    local title steps_count
    title=$(sqlite3 "$RALPH_DB_PATH" "SELECT title FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    steps_count=$(sqlite3 "$RALPH_DB_PATH" "SELECT json_array_length(steps) FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$title" = "Keep this title" ]
    [ "$steps_count" = "1" ]
}

# ---------------------------------------------------------------------------
# Special characters
# ---------------------------------------------------------------------------
@test "task update handles single quotes in title" {
    "$SCRIPT_DIR/lib/task" create "test/01" "A task"
    run "$SCRIPT_DIR/lib/task" update "test/01" --title "It's a test"
    assert_success

    local title
    title=$(sqlite3 "$RALPH_DB_PATH" "SELECT title FROM tasks WHERE slug = 'test/01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [ "$title" = "It's a test" ]
}
