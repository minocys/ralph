#!/usr/bin/env bats
# test/task_create.bats — Tests for the task create command

load test_helper

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
@test "task create without ID exits 1 with error" {
    run "$SCRIPT_DIR/lib/task" create
    assert_failure
    assert_output --partial "Error: missing task ID"
}

@test "task create without title exits 1 with error" {
    run "$SCRIPT_DIR/lib/task" create "test-01"
    assert_failure
    assert_output --partial "Error: missing task title"
}

# ---------------------------------------------------------------------------
# Minimal create
# ---------------------------------------------------------------------------
@test "task create with minimal args inserts task and prints ID" {
    run "$SCRIPT_DIR/lib/task" create "test-01" "My first task"
    assert_success
    assert_output "test-01"

    # Verify task exists in DB
    run sqlite3 "$RALPH_DB_PATH" "
        SELECT slug || '|' || title || '|' || priority || '|' || status || '|' || retry_count FROM tasks WHERE slug = 'test-01' AND scope_repo = 'test/repo' AND scope_branch = 'main';
    "
    assert_success
    assert_output "test-01|My first task|2|open|0"
}

@test "task create sets updated_at on insert" {
    run "$SCRIPT_DIR/lib/task" create "test-ts" "Timestamp test"
    assert_success

    run sqlite3 "$RALPH_DB_PATH" "
        SELECT CASE WHEN updated_at IS NOT NULL THEN 'set' ELSE 'null' END FROM tasks WHERE slug = 'test-ts' AND scope_repo = 'test/repo' AND scope_branch = 'main';
    "
    assert_success
    assert_output "set"
}

# ---------------------------------------------------------------------------
# Create with all flags
# ---------------------------------------------------------------------------
@test "task create with all flags stores correct values" {
    run "$SCRIPT_DIR/lib/task" create "feat-01" "Full task" \
        -p 1 \
        -c "feat" \
        -d "A detailed description" \
        -r "task-cli" \
        --ref "specs/task-cli.md"
    assert_success
    assert_output "feat-01"

    run sqlite3 "$RALPH_DB_PATH" "
        SELECT slug || '|' || title || '|' || description || '|' || category || '|' || priority || '|' || spec_ref || '|' || ref
        FROM tasks WHERE slug = 'feat-01' AND scope_repo = 'test/repo' AND scope_branch = 'main';
    "
    assert_success
    assert_output "feat-01|Full task|A detailed description|feat|1|task-cli|specs/task-cli.md"
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------
@test "task create with steps stores steps in JSON column" {
    run "$SCRIPT_DIR/lib/task" create "step-01" "Task with steps" \
        -s '["First step","Second step","Third step"]'
    assert_success

    run sqlite3 "$RALPH_DB_PATH" "
        SELECT value FROM tasks, json_each(tasks.steps) WHERE slug = 'step-01' AND scope_repo = 'test/repo' AND scope_branch = 'main';
    "
    assert_success
    assert_output "First step
Second step
Third step"
}

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------
@test "task create with deps inserts into task_deps" {
    # Create blocker tasks first
    "$SCRIPT_DIR/lib/task" create "blocker-a" "Blocker A" > /dev/null
    "$SCRIPT_DIR/lib/task" create "blocker-b" "Blocker B" > /dev/null

    run "$SCRIPT_DIR/lib/task" create "dep-01" "Dependent task" --deps "blocker-a,blocker-b"
    assert_success

    run sqlite3 "$RALPH_DB_PATH" "
        SELECT t.slug FROM task_deps td JOIN tasks t ON t.id = td.blocked_by WHERE td.task_id = (SELECT id FROM tasks WHERE slug = 'dep-01' AND scope_repo = 'test/repo' AND scope_branch = 'main') ORDER BY t.slug;
    "
    assert_success
    assert_output "blocker-a
blocker-b"
}

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
@test "task create defaults priority to 2, status to open" {
    run "$SCRIPT_DIR/lib/task" create "def-01" "Default check"
    assert_success

    run sqlite3 "$RALPH_DB_PATH" "
        SELECT priority || '|' || status FROM tasks WHERE slug = 'def-01' AND scope_repo = 'test/repo' AND scope_branch = 'main';
    "
    assert_success
    assert_output "2|open"
}

@test "task create with NULL description and category" {
    run "$SCRIPT_DIR/lib/task" create "null-01" "Null fields test"
    assert_success

    run sqlite3 "$RALPH_DB_PATH" "
        SELECT
            CASE WHEN description IS NULL THEN 'null' ELSE description END || '|' ||
            CASE WHEN category IS NULL THEN 'null' ELSE category END
        FROM tasks WHERE slug = 'null-01' AND scope_repo = 'test/repo' AND scope_branch = 'main';
    "
    assert_success
    assert_output "null|null"
}

# ---------------------------------------------------------------------------
# Duplicate ID
# ---------------------------------------------------------------------------
@test "task create with duplicate ID fails" {
    "$SCRIPT_DIR/lib/task" create "dup-01" "First" > /dev/null
    run "$SCRIPT_DIR/lib/task" create "dup-01" "Second"
    assert_failure
}

# ---------------------------------------------------------------------------
# Special characters in title
# ---------------------------------------------------------------------------
@test "task create handles single quotes in title" {
    run "$SCRIPT_DIR/lib/task" create "quote-01" "It's a task"
    assert_success
    assert_output "quote-01"

    run sqlite3 "$RALPH_DB_PATH" "
        SELECT title FROM tasks WHERE slug = 'quote-01' AND scope_repo = 'test/repo' AND scope_branch = 'main';
    "
    assert_success
    assert_output "It's a task"
}

# ---------------------------------------------------------------------------
# Priority (-p) integer validation
# ---------------------------------------------------------------------------
@test "task create with non-numeric -p exits 1 with error" {
    run "$SCRIPT_DIR/lib/task" create "val-01" "Bad priority" -p abc
    assert_failure
    assert_output --partial "Error: -p (priority) must be a non-negative integer"
}

@test "task create with negative -p exits 1 with error" {
    run "$SCRIPT_DIR/lib/task" create "val-02" "Negative priority" -p -1
    assert_failure
    assert_output --partial "Error: -p (priority) must be a non-negative integer"
}

@test "task create with float -p exits 1 with error" {
    run "$SCRIPT_DIR/lib/task" create "val-03" "Float priority" -p 1.5
    assert_failure
    assert_output --partial "Error: -p (priority) must be a non-negative integer"
}

@test "task create with valid -p succeeds" {
    run "$SCRIPT_DIR/lib/task" create "val-04" "Valid priority" -p 3
    assert_success
    assert_output "val-04"

    run sqlite3 "$RALPH_DB_PATH" "
        SELECT priority FROM tasks WHERE slug = 'val-04' AND scope_repo = 'test/repo' AND scope_branch = 'main';
    "
    assert_success
    assert_output "3"
}
