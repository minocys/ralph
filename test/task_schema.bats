#!/usr/bin/env bats
# test/task_schema.bats — Integration tests for idempotent schema creation
# Requires: running PostgreSQL (docker compose up -d)
# Set RALPH_DB_URL to run these tests.

load test_helper

# ---------------------------------------------------------------------------
# Helper: check if PostgreSQL is reachable
# ---------------------------------------------------------------------------
db_available() {
    [[ -n "${RALPH_DB_URL:-}" ]] && psql "$RALPH_DB_URL" -tAX -c "SELECT 1" >/dev/null 2>&1
}

# Use a unique test database schema to avoid interfering with real data
setup() {
    # Call the shared setup (creates STUB_DIR, TEST_WORK_DIR, etc.)
    # We override the default setup from test_helper
    TEST_WORK_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export TEST_WORK_DIR STUB_DIR

    if ! db_available; then
        skip "PostgreSQL not available (set RALPH_DB_URL and start database)"
    fi

    # Create a unique test schema to isolate tests
    TEST_SCHEMA="test_$(date +%s)_$$"
    export TEST_SCHEMA

    # Set search_path so our tables are created in the test schema
    psql "$RALPH_DB_URL" -tAX -c "CREATE SCHEMA $TEST_SCHEMA" >/dev/null 2>&1
    # Modify RALPH_DB_URL to use the test schema via options
    export RALPH_DB_URL_ORIG="$RALPH_DB_URL"
    export RALPH_DB_URL="${RALPH_DB_URL}?options=-csearch_path%3D${TEST_SCHEMA}"
}

teardown() {
    # Drop the test schema if it was created
    if [[ -n "${TEST_SCHEMA:-}" ]] && [[ -n "${RALPH_DB_URL_ORIG:-}" ]]; then
        psql "$RALPH_DB_URL_ORIG" -tAX -c "DROP SCHEMA IF EXISTS $TEST_SCHEMA CASCADE" >/dev/null 2>&1
    fi

    # Clean up temp directories
    [[ -d "${TEST_WORK_DIR:-}" ]] && rm -rf "$TEST_WORK_DIR"
    [[ -d "${STUB_DIR:-}" ]] && rm -rf "$STUB_DIR"
}

# ---------------------------------------------------------------------------
# Schema creation
# ---------------------------------------------------------------------------
@test "ensure_schema creates all four tables" {
    # Run any command that triggers ensure_schema — list will call it
    # even though list is a stub, schema gets created before the stub runs
    run "$SCRIPT_DIR/task" list
    # list is a stub that exits 1, but schema should be created

    # Verify tables exist
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = '$TEST_SCHEMA'
        ORDER BY table_name;
    "
    assert_success
    assert_output --partial "agents"
    assert_output --partial "task_deps"
    assert_output --partial "task_steps"
    assert_output --partial "tasks"
}

@test "ensure_schema is idempotent (second run succeeds)" {
    # First run — creates tables
    run "$SCRIPT_DIR/task" list
    # Ignore exit code (stub exits 1)

    # Second run — should not fail
    run "$SCRIPT_DIR/task" list
    # Ignore exit code (stub exits 1)

    # Tables should still exist and be intact
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT count(*) FROM information_schema.tables
        WHERE table_schema = '$TEST_SCHEMA'
        AND table_name IN ('tasks', 'task_steps', 'task_deps', 'agents');
    "
    assert_success
    assert_output "4"
}

@test "tasks table has correct columns" {
    run "$SCRIPT_DIR/task" list

    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT column_name FROM information_schema.columns
        WHERE table_schema = '$TEST_SCHEMA' AND table_name = 'tasks'
        ORDER BY ordinal_position;
    "
    assert_success
    assert_output --partial "id"
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
    assert_output --partial "created_at"
    assert_output --partial "updated_at"
    assert_output --partial "deleted_at"
}

@test "task_steps table has correct columns" {
    run "$SCRIPT_DIR/task" list

    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT column_name FROM information_schema.columns
        WHERE table_schema = '$TEST_SCHEMA' AND table_name = 'task_steps'
        ORDER BY ordinal_position;
    "
    assert_success
    assert_output --partial "task_id"
    assert_output --partial "seq"
    assert_output --partial "content"
    assert_output --partial "status"
}

@test "task_deps table has correct columns" {
    run "$SCRIPT_DIR/task" list

    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT column_name FROM information_schema.columns
        WHERE table_schema = '$TEST_SCHEMA' AND table_name = 'task_deps'
        ORDER BY ordinal_position;
    "
    assert_success
    assert_output --partial "task_id"
    assert_output --partial "blocked_by"
}

@test "agents table has correct columns" {
    run "$SCRIPT_DIR/task" list

    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT column_name FROM information_schema.columns
        WHERE table_schema = '$TEST_SCHEMA' AND table_name = 'agents'
        ORDER BY ordinal_position;
    "
    assert_success
    assert_output --partial "id"
    assert_output --partial "pid"
    assert_output --partial "hostname"
    assert_output --partial "started_at"
    assert_output --partial "status"
}

@test "task_steps has foreign key to tasks with cascade delete" {
    run "$SCRIPT_DIR/task" list

    # Insert a task, add a step, delete the task — step should cascade
    psql "$RALPH_DB_URL" -tAX -c "
        INSERT INTO tasks (id, title) VALUES ('test-fk-1', 'FK Test');
        INSERT INTO task_steps (task_id, seq, content) VALUES ('test-fk-1', 1, 'Step 1');
        DELETE FROM tasks WHERE id = 'test-fk-1';
    "
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT count(*) FROM task_steps WHERE task_id = 'test-fk-1';
    "
    assert_success
    assert_output "0"
}

@test "task_deps has foreign key to tasks with cascade delete" {
    run "$SCRIPT_DIR/task" list

    # Insert two tasks, add a dep, delete the blocker — dep should cascade
    psql "$RALPH_DB_URL" -tAX -c "
        INSERT INTO tasks (id, title) VALUES ('test-dep-1', 'Dep Test 1');
        INSERT INTO tasks (id, title) VALUES ('test-dep-2', 'Dep Test 2');
        INSERT INTO task_deps (task_id, blocked_by) VALUES ('test-dep-1', 'test-dep-2');
        DELETE FROM tasks WHERE id = 'test-dep-2';
    "
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT count(*) FROM task_deps WHERE task_id = 'test-dep-1';
    "
    assert_success
    assert_output "0"
}

@test "tasks table defaults are correct" {
    run "$SCRIPT_DIR/task" list

    psql "$RALPH_DB_URL" -tAX -c "
        INSERT INTO tasks (id, title) VALUES ('test-defaults', 'Default Test');
    "
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT priority, status, retry_count FROM tasks WHERE id = 'test-defaults';
    "
    assert_success
    assert_output "2|open|0"
}
