#!/usr/bin/env bats
# test/task_ensure_schema.bats — verify ensure_schema() creates SQLite tables
# with correct DDL, PRAGMAs, and constraints.

load test_helper

# ---------------------------------------------------------------------------
# Helpers: extract ensure_schema + dependencies from lib/task
# ---------------------------------------------------------------------------
setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    export RALPH_DB_PATH="$TEST_WORK_DIR/test.db"
    export TEST_WORK_DIR
}

teardown() {
    [[ -d "${TEST_WORK_DIR:-}" ]] && rm -rf "$TEST_WORK_DIR"
}

# Source db_check, sqlite_cmd, and ensure_schema from lib/task without main.
_source_schema_funcs() {
    eval "$(sed -n '/^db_check()/,/^}/p' "$SCRIPT_DIR/lib/task")"
    eval "$(sed -n '/^sqlite_cmd()/,/^}/p' "$SCRIPT_DIR/lib/task")"
    eval "$(sed -n '/^ensure_schema()/,/^}/p' "$SCRIPT_DIR/lib/task")"
}

_init_schema() {
    _source_schema_funcs
    db_check
    ensure_schema
}

# ---------------------------------------------------------------------------
# Table creation
# ---------------------------------------------------------------------------
@test "ensure_schema creates tasks table" {
    _init_schema
    run sqlite_cmd "SELECT name FROM sqlite_master WHERE type='table' AND name='tasks';"
    assert_success
    assert_output "tasks"
}

@test "ensure_schema creates task_deps table" {
    _init_schema
    run sqlite_cmd "SELECT name FROM sqlite_master WHERE type='table' AND name='task_deps';"
    assert_success
    assert_output "task_deps"
}

@test "ensure_schema creates agents table" {
    _init_schema
    run sqlite_cmd "SELECT name FROM sqlite_master WHERE type='table' AND name='agents';"
    assert_success
    assert_output "agents"
}

@test "ensure_schema creates all three tables" {
    _init_schema
    run sqlite_cmd "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"
    assert_success
    assert_output --partial "agents"
    assert_output --partial "task_deps"
    assert_output --partial "tasks"
}

# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------
@test "ensure_schema is idempotent (second run succeeds)" {
    _init_schema
    # Run again — should not fail
    run ensure_schema
    assert_success
}

# ---------------------------------------------------------------------------
# PRAGMA values
# ---------------------------------------------------------------------------
@test "ensure_schema sets WAL journal mode" {
    _init_schema
    run sqlite_cmd "PRAGMA journal_mode;"
    assert_success
    assert_output "wal"
}

@test "ensure_schema includes foreign_keys pragma" {
    _source_schema_funcs
    db_check
    # Verify the ensure_schema function source contains PRAGMA foreign_keys
    local fn_body
    fn_body="$(declare -f ensure_schema)"
    [[ "$fn_body" == *"PRAGMA foreign_keys=ON"* ]]
}

@test "ensure_schema includes busy_timeout pragma" {
    _source_schema_funcs
    db_check
    # Verify the ensure_schema function source contains PRAGMA busy_timeout=5000
    local fn_body
    fn_body="$(declare -f ensure_schema)"
    [[ "$fn_body" == *"PRAGMA busy_timeout=5000"* ]]
}

# ---------------------------------------------------------------------------
# UNIQUE constraint on tasks (scope_repo, scope_branch, slug)
# ---------------------------------------------------------------------------
@test "tasks table has UNIQUE constraint on scope_repo, scope_branch, slug" {
    _init_schema
    # Insert a task
    sqlite_cmd "INSERT INTO tasks (id, slug, scope_repo, scope_branch, title) VALUES ('aaa', 'my-task', 'r', 'b', 'First');"
    # Duplicate should fail
    run sqlite_cmd "INSERT INTO tasks (id, slug, scope_repo, scope_branch, title) VALUES ('bbb', 'my-task', 'r', 'b', 'Dupe');"
    assert_failure
}

# ---------------------------------------------------------------------------
# Column types and defaults
# ---------------------------------------------------------------------------
@test "tasks id is TEXT PRIMARY KEY" {
    _init_schema
    run sqlite_cmd "PRAGMA table_info(tasks);"
    assert_success
    # id column: cid|name|type|notnull|dflt_value|pk
    assert_output --partial "id|TEXT"
}

@test "tasks default priority is 2" {
    _init_schema
    sqlite_cmd "INSERT INTO tasks (id, slug, scope_repo, scope_branch, title) VALUES ('t1', 's1', 'r', 'b', 'T');"
    run sqlite_cmd "SELECT priority FROM tasks WHERE id='t1';"
    assert_success
    assert_output "2"
}

@test "tasks default status is open" {
    _init_schema
    sqlite_cmd "INSERT INTO tasks (id, slug, scope_repo, scope_branch, title) VALUES ('t2', 's2', 'r', 'b', 'T');"
    run sqlite_cmd "SELECT status FROM tasks WHERE id='t2';"
    assert_success
    assert_output "open"
}

@test "tasks default retry_count is 0" {
    _init_schema
    sqlite_cmd "INSERT INTO tasks (id, slug, scope_repo, scope_branch, title) VALUES ('t3', 's3', 'r', 'b', 'T');"
    run sqlite_cmd "SELECT retry_count FROM tasks WHERE id='t3';"
    assert_success
    assert_output "0"
}

@test "tasks created_at defaults to a datetime" {
    _init_schema
    sqlite_cmd "INSERT INTO tasks (id, slug, scope_repo, scope_branch, title) VALUES ('t4', 's4', 'r', 'b', 'T');"
    run sqlite_cmd "SELECT created_at FROM tasks WHERE id='t4';"
    assert_success
    # Should match ISO-8601 pattern: YYYY-MM-DD HH:MM:SS
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]
}

# ---------------------------------------------------------------------------
# Foreign key cascade on task_deps
# ---------------------------------------------------------------------------
@test "task_deps cascades on delete of parent task" {
    _init_schema
    # Enable foreign keys for this connection
    sqlite_cmd "PRAGMA foreign_keys=ON;"
    sqlite_cmd "INSERT INTO tasks (id, slug, scope_repo, scope_branch, title) VALUES ('u1', 'd1', 'r', 'b', 'Task1');"
    sqlite_cmd "INSERT INTO tasks (id, slug, scope_repo, scope_branch, title) VALUES ('u2', 'd2', 'r', 'b', 'Task2');"
    sqlite_cmd "PRAGMA foreign_keys=ON; INSERT INTO task_deps (task_id, blocked_by) VALUES ('u1', 'u2');"
    # Delete blocker — dep should cascade
    sqlite_cmd "PRAGMA foreign_keys=ON; DELETE FROM tasks WHERE id='u2';"
    run sqlite_cmd "SELECT count(*) FROM task_deps WHERE task_id='u1';"
    assert_success
    assert_output "0"
}

# ---------------------------------------------------------------------------
# steps and result columns are TEXT (not array/jsonb)
# ---------------------------------------------------------------------------
@test "tasks steps column is TEXT type" {
    _init_schema
    run sqlite_cmd "PRAGMA table_info(tasks);"
    assert_success
    # Look for steps column with TEXT type
    assert_output --partial "steps|TEXT"
}

@test "tasks result column is TEXT type" {
    _init_schema
    run sqlite_cmd "PRAGMA table_info(tasks);"
    assert_success
    assert_output --partial "result|TEXT"
}
