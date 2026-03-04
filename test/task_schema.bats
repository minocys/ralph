#!/usr/bin/env bats
# test/task_schema.bats — Integration tests for idempotent schema creation (SQLite)

load test_helper

setup() {
    # Call the shared setup (creates TEST_WORK_DIR with RALPH_DB_PATH, STUB_DIR, etc.)
    # We rely on the default setup from test_helper which sets RALPH_DB_PATH
    TEST_WORK_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export TEST_WORK_DIR STUB_DIR
    export RALPH_DB_PATH="$TEST_WORK_DIR/tasks.db"

    # Ensure the schema exists by invoking a command that triggers ensure_schema
    "$SCRIPT_DIR/lib/task" create "dummy" "dummy" >/dev/null 2>&1 || true
}

teardown() {
    # Clean up temp directories
    [[ -d "${TEST_WORK_DIR:-}" ]] && rm -rf "$TEST_WORK_DIR"
    [[ -d "${STUB_DIR:-}" ]] && rm -rf "$STUB_DIR"
}

# ---------------------------------------------------------------------------
# Schema creation
# ---------------------------------------------------------------------------
@test "ensure_schema creates all three tables" {
    # Run any command that triggers ensure_schema — list will call it
    run "$SCRIPT_DIR/lib/task" list

    # Verify tables exist
    run sqlite3 "$RALPH_DB_PATH" "
        SELECT name FROM sqlite_master
        WHERE type='table' AND name IN ('tasks', 'task_deps', 'agents')
        ORDER BY name;
    "
    assert_success
    assert_output --partial "agents"
    assert_output --partial "task_deps"
    assert_output --partial "tasks"
}

@test "ensure_schema is idempotent (second run succeeds)" {
    # First run — creates tables
    run "$SCRIPT_DIR/lib/task" list

    # Second run — should not fail
    run "$SCRIPT_DIR/lib/task" list

    # Tables should still exist and be intact
    run sqlite3 "$RALPH_DB_PATH" "
        SELECT count(*) FROM sqlite_master
        WHERE type='table'
        AND name IN ('tasks', 'task_deps', 'agents');
    "
    assert_success
    assert_output "3"
}

@test "tasks table has correct columns" {
    run "$SCRIPT_DIR/lib/task" list

    run sqlite3 "$RALPH_DB_PATH" "
        SELECT name FROM pragma_table_info('tasks') ORDER BY cid;
    "
    assert_success
    assert_output --partial "id"
    assert_output --partial "slug"
    assert_output --partial "scope_repo"
    assert_output --partial "scope_branch"
    assert_output --partial "title"
    assert_output --partial "description"
    assert_output --partial "category"
    assert_output --partial "priority"
    assert_output --partial "status"
    assert_output --partial "spec_ref"
    assert_output --partial "ref"
    assert_output --partial "result"
    assert_output --partial "assignee"
    assert_output --partial "lease_expires_at"
    assert_output --partial "retry_count"
    assert_output --partial "fail_reason"
    assert_output --partial "steps"
    assert_output --partial "created_at"
    assert_output --partial "updated_at"
    assert_output --partial "deleted_at"
}

@test "task_steps table does not exist" {
    run "$SCRIPT_DIR/lib/task" list

    run sqlite3 "$RALPH_DB_PATH" "
        SELECT count(*) FROM sqlite_master
        WHERE type='table' AND name = 'task_steps';
    "
    assert_success
    assert_output "0"
}

@test "task_deps table has correct columns" {
    run "$SCRIPT_DIR/lib/task" list

    run sqlite3 "$RALPH_DB_PATH" "
        SELECT name FROM pragma_table_info('task_deps') ORDER BY cid;
    "
    assert_success
    assert_output --partial "task_id"
    assert_output --partial "blocked_by"
}

@test "agents table has correct columns" {
    run "$SCRIPT_DIR/lib/task" list

    run sqlite3 "$RALPH_DB_PATH" "
        SELECT name FROM pragma_table_info('agents') ORDER BY cid;
    "
    assert_success
    assert_output --partial "id"
    assert_output --partial "pid"
    assert_output --partial "hostname"
    assert_output --partial "scope_repo"
    assert_output --partial "scope_branch"
    assert_output --partial "started_at"
    assert_output --partial "status"
}

@test "tasks.steps column is TEXT type" {
    run "$SCRIPT_DIR/lib/task" list

    run sqlite3 "$RALPH_DB_PATH" "
        SELECT type FROM pragma_table_info('tasks') WHERE name='steps';
    "
    assert_success
    assert_output "TEXT"
}

@test "task_deps has foreign key to tasks with cascade delete" {
    run "$SCRIPT_DIR/lib/task" list

    # Insert two tasks, add a dep, delete the blocker — dep should cascade
    sqlite3 "$RALPH_DB_PATH" "
        PRAGMA foreign_keys=ON;
        INSERT INTO tasks (id, slug, scope_repo, scope_branch, title)
        VALUES ('550e8400-e29b-41d4-a716-446655440001', 'dep-1', 'owner/repo', 'main', 'Dep Test 1');
        INSERT INTO tasks (id, slug, scope_repo, scope_branch, title)
        VALUES ('550e8400-e29b-41d4-a716-446655440002', 'dep-2', 'owner/repo', 'main', 'Dep Test 2');
        INSERT INTO task_deps (task_id, blocked_by)
        VALUES ('550e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440002');
        DELETE FROM tasks WHERE id = '550e8400-e29b-41d4-a716-446655440002';
    "
    run sqlite3 "$RALPH_DB_PATH" "
        SELECT count(*) FROM task_deps
        WHERE task_id = '550e8400-e29b-41d4-a716-446655440001';
    "
    assert_success
    assert_output "0"
}

@test "tasks table defaults are correct" {
    run "$SCRIPT_DIR/lib/task" list

    sqlite3 "$RALPH_DB_PATH" "
        INSERT INTO tasks (id, slug, scope_repo, scope_branch, title)
        VALUES ('550e8400-e29b-41d4-a716-446655440099', 'test-defaults', 'owner/repo', 'main', 'Default Test');
    "
    run sqlite3 -separator '|' "$RALPH_DB_PATH" "
        SELECT priority, status, retry_count FROM tasks
        WHERE slug = 'test-defaults' AND scope_repo = 'owner/repo' AND scope_branch = 'main';
    "
    assert_success
    assert_output "2|open|0"
}
