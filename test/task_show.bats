#!/usr/bin/env bats
# test/task_show.bats — Tests for the task show command

load test_helper


# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
@test "task show without ID exits 1 with error" {
    run "$SCRIPT_DIR/lib/task" show
    assert_failure
    assert_output --partial "Error: missing task ID"
}

# ---------------------------------------------------------------------------
# Task not found
# ---------------------------------------------------------------------------
@test "task show nonexistent task exits 2" {
    run "$SCRIPT_DIR/lib/task" show "nonexistent-id"
    [ "$status" -eq 2 ]
    assert_output --partial "not found"
}

# ---------------------------------------------------------------------------
# Show existing task
# ---------------------------------------------------------------------------
@test "task show displays task detail" {
    "$SCRIPT_DIR/lib/task" create "show-01" "Show test task" \
        -p 1 -c "feat" -d "A description" -r "task-cli" --ref "specs/task-cli.md" > /dev/null

    run "$SCRIPT_DIR/lib/task" show "show-01"
    assert_success
    assert_output --partial "ID:          show-01"
    assert_output --partial "Title:       Show test task"
    assert_output --partial "Status:      open"
    assert_output --partial "Priority:    1"
    assert_output --partial "Category:    feat"
    assert_output --partial "Description: A description"
    assert_output --partial "Spec:        task-cli"
    assert_output --partial "Ref:         specs/task-cli.md"
    assert_output --partial "Created:"
}

# ---------------------------------------------------------------------------
# Show task with steps
# ---------------------------------------------------------------------------
@test "task show displays steps" {
    "$SCRIPT_DIR/lib/task" create "show-steps" "Task with steps" > /dev/null
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET steps = '[\"First step\",\"Second step\"]' WHERE slug = 'show-steps' AND scope_repo = 'test/repo' AND scope_branch = 'main'"

    run "$SCRIPT_DIR/lib/task" show "show-steps"
    assert_success
    assert_output --partial "Steps:"
    assert_output --partial "1. First step"
    assert_output --partial "2. Second step"
}

# ---------------------------------------------------------------------------
# Show task with dependencies
# ---------------------------------------------------------------------------
@test "task show displays dependencies" {
    "$SCRIPT_DIR/lib/task" create "dep-a" "Blocker A" > /dev/null
    "$SCRIPT_DIR/lib/task" create "dep-b" "Blocker B" > /dev/null
    "$SCRIPT_DIR/lib/task" create "show-deps" "Dependent task" --deps "dep-a,dep-b" > /dev/null

    run "$SCRIPT_DIR/lib/task" show "show-deps"
    assert_success
    assert_output --partial "Dependencies:"
    assert_output --partial "dep-a (open)"
    assert_output --partial "dep-b (open)"
}

# ---------------------------------------------------------------------------
# Show with --with-deps includes blocker results
# ---------------------------------------------------------------------------
@test "task show --with-deps includes blocker results" {
    "$SCRIPT_DIR/lib/task" create "res-a" "Blocker with result" > /dev/null
    "$SCRIPT_DIR/lib/task" create "show-wd" "Dependent task" --deps "res-a" > /dev/null

    # Set blocker to done with result
    sqlite3 "$TEST_DB_PATH" "
        UPDATE tasks SET status = 'done', result = '{\"commit\": \"abc123\"}' WHERE slug = 'res-a' AND scope_repo = 'test/repo' AND scope_branch = 'main';
    "

    run "$SCRIPT_DIR/lib/task" show "show-wd" --with-deps
    assert_success
    assert_output --partial "Blocker Results:"
    assert_output --partial 'res-a: {"commit": "abc123"}'
}

@test "task show --with-deps with no results omits blocker results section" {
    "$SCRIPT_DIR/lib/task" create "nores-a" "Blocker no result" > /dev/null
    "$SCRIPT_DIR/lib/task" create "show-nores" "Dependent task" --deps "nores-a" > /dev/null

    run "$SCRIPT_DIR/lib/task" show "show-nores" --with-deps
    assert_success
    assert_output --partial "Dependencies:"
    refute_output --partial "Blocker Results:"
}

# ---------------------------------------------------------------------------
# Show without --with-deps omits blocker results even if they exist
# ---------------------------------------------------------------------------
@test "task show without --with-deps omits blocker results" {
    "$SCRIPT_DIR/lib/task" create "res-b" "Blocker with result" > /dev/null
    "$SCRIPT_DIR/lib/task" create "show-nwd" "Dependent task" --deps "res-b" > /dev/null

    sqlite3 "$TEST_DB_PATH" "
        UPDATE tasks SET status = 'done', result = '{\"commit\": \"def456\"}' WHERE slug = 'res-b' AND scope_repo = 'test/repo' AND scope_branch = 'main';
    "

    run "$SCRIPT_DIR/lib/task" show "show-nwd"
    assert_success
    refute_output --partial "Blocker Results:"
}

# ---------------------------------------------------------------------------
# Minimal task (no optional fields)
# ---------------------------------------------------------------------------
@test "task show minimal task omits null fields" {
    "$SCRIPT_DIR/lib/task" create "show-min" "Minimal task" > /dev/null

    run "$SCRIPT_DIR/lib/task" show "show-min"
    assert_success
    assert_output --partial "ID:          show-min"
    assert_output --partial "Title:       Minimal task"
    refute_output --partial "Category:"
    refute_output --partial "Description:"
    refute_output --partial "Spec:"
    refute_output --partial "Ref:"
    refute_output --partial "Assignee:"
    refute_output --partial "Steps:"
    refute_output --partial "Dependencies:"
}

# ---------------------------------------------------------------------------
# Special characters in task ID
# ---------------------------------------------------------------------------
@test "task show handles single quotes in task data" {
    "$SCRIPT_DIR/lib/task" create "quote-show" "It's a task" -d "Description with 'quotes'" > /dev/null

    run "$SCRIPT_DIR/lib/task" show "quote-show"
    assert_success
    assert_output --partial "Title:       It's a task"
    assert_output --partial "Description: Description with 'quotes'"
}
