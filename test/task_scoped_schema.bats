#!/usr/bin/env bats
# test/task_scoped_schema.bats — verify scoped schema columns, constraints, and index (SQLite)

load test_helper

setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export TEST_WORK_DIR STUB_DIR

    # Initialize git repo so db_check() can derive database path
    git -C "$TEST_WORK_DIR" init --quiet
    git -C "$TEST_WORK_DIR" config user.email "test@test.com"
    git -C "$TEST_WORK_DIR" config user.name "Test"

    # db_check() derives path from git root: <git-root>/.ralph/tasks.db
    export RALPH_DB_PATH="$TEST_WORK_DIR/.ralph/tasks.db"
    export RALPH_SCOPE_REPO="test/repo"
    export RALPH_SCOPE_BRANCH="main"

    cd "$TEST_WORK_DIR"

    # Ensure the schema exists by invoking a command that triggers ensure_schema
    "$SCRIPT_DIR/lib/task" create "dummy" "dummy" >/dev/null 2>&1 || true
}

teardown() {
    [[ -d "${TEST_WORK_DIR:-}" ]] && rm -rf "$TEST_WORK_DIR"
    [[ -d "${STUB_DIR:-}" ]] && rm -rf "$STUB_DIR"
}

# ---------------------------------------------------------------------------
# tasks table: new columns exist
# ---------------------------------------------------------------------------
@test "tasks table has slug column" {
    run sqlite3 "$RALPH_DB_PATH" "
        SELECT name FROM pragma_table_info('tasks') WHERE name='slug';
    "
    assert_success
    assert_output "slug"
}

@test "tasks table has scope_repo column" {
    run sqlite3 "$RALPH_DB_PATH" "
        SELECT name FROM pragma_table_info('tasks') WHERE name='scope_repo';
    "
    assert_success
    assert_output "scope_repo"
}

@test "tasks table has scope_branch column" {
    run sqlite3 "$RALPH_DB_PATH" "
        SELECT name FROM pragma_table_info('tasks') WHERE name='scope_branch';
    "
    assert_success
    assert_output "scope_branch"
}

# ---------------------------------------------------------------------------
# tasks.id column type is TEXT (SQLite equivalent of UUID)
# ---------------------------------------------------------------------------
@test "tasks.id column is TEXT type" {
    run sqlite3 "$RALPH_DB_PATH" "
        SELECT type FROM pragma_table_info('tasks') WHERE name='id';
    "
    assert_success
    assert_output "TEXT"
}

@test "tasks.id has no default (UUID generated in bash)" {
    # In SQLite, id is TEXT PRIMARY KEY with no DEFAULT — UUID is generated in bash
    run sqlite3 "$RALPH_DB_PATH" "
        SELECT dflt_value FROM pragma_table_info('tasks') WHERE name='id';
    "
    assert_success
    assert_output ""
}

# ---------------------------------------------------------------------------
# NOT NULL constraints on slug, scope_repo, scope_branch
# ---------------------------------------------------------------------------
@test "tasks.slug is NOT NULL" {
    run sqlite3 "$RALPH_DB_PATH" "
        SELECT CASE WHEN \"notnull\" = 1 THEN 'NO' ELSE 'YES' END
        FROM pragma_table_info('tasks') WHERE name='slug';
    "
    assert_success
    assert_output "NO"
}

@test "tasks.scope_repo is NOT NULL" {
    run sqlite3 "$RALPH_DB_PATH" "
        SELECT CASE WHEN \"notnull\" = 1 THEN 'NO' ELSE 'YES' END
        FROM pragma_table_info('tasks') WHERE name='scope_repo';
    "
    assert_success
    assert_output "NO"
}

@test "tasks.scope_branch is NOT NULL" {
    run sqlite3 "$RALPH_DB_PATH" "
        SELECT CASE WHEN \"notnull\" = 1 THEN 'NO' ELSE 'YES' END
        FROM pragma_table_info('tasks') WHERE name='scope_branch';
    "
    assert_success
    assert_output "NO"
}

# ---------------------------------------------------------------------------
# UNIQUE constraint on (scope_repo, scope_branch, slug)
# ---------------------------------------------------------------------------
@test "UNIQUE constraint exists on (scope_repo, scope_branch, slug)" {
    # In SQLite, UNIQUE constraints create automatic indexes.
    # Check that an index exists covering scope_repo, scope_branch, slug.
    # Use PRAGMA index_list to find unique indexes, then index_info to check columns.
    run sqlite3 "$RALPH_DB_PATH" "
        SELECT count(*) FROM (
            SELECT il.name AS idx_name
            FROM pragma_index_list('tasks') il
            WHERE il.\"unique\" = 1
              AND (SELECT count(*) FROM pragma_index_info(il.name)) = 3
              AND EXISTS (SELECT 1 FROM pragma_index_info(il.name) WHERE name='scope_repo')
              AND EXISTS (SELECT 1 FROM pragma_index_info(il.name) WHERE name='scope_branch')
              AND EXISTS (SELECT 1 FROM pragma_index_info(il.name) WHERE name='slug')
        );
    "
    assert_success
    assert_output "1"
}

@test "UNIQUE constraint rejects duplicate slug within same scope" {
    # Insert first row
    sqlite3 "$RALPH_DB_PATH" "
        INSERT INTO tasks (id, slug, scope_repo, scope_branch, title)
        VALUES ('550e8400-e29b-41d4-a716-446655440010', 'task-01', 'owner/repo', 'main', 'First');
    "
    # Duplicate slug in same scope should fail
    run sqlite3 "$RALPH_DB_PATH" "
        INSERT INTO tasks (id, slug, scope_repo, scope_branch, title)
        VALUES ('550e8400-e29b-41d4-a716-446655440011', 'task-01', 'owner/repo', 'main', 'Duplicate');
    "
    assert_failure
}

@test "UNIQUE constraint allows same slug in different scope" {
    sqlite3 "$RALPH_DB_PATH" "
        INSERT INTO tasks (id, slug, scope_repo, scope_branch, title)
        VALUES ('550e8400-e29b-41d4-a716-446655440010', 'task-01', 'owner/repo', 'main', 'First');
    "
    # Same slug but different branch should succeed
    run sqlite3 "$RALPH_DB_PATH" "
        INSERT INTO tasks (id, slug, scope_repo, scope_branch, title)
        VALUES ('550e8400-e29b-41d4-a716-446655440012', 'task-01', 'owner/repo', 'feature', 'Second');
    "
    assert_success
}

# ---------------------------------------------------------------------------
# Index on (scope_repo, scope_branch, status, priority, created_at)
# ---------------------------------------------------------------------------
@test "index idx_tasks_scope_status exists" {
    run sqlite3 "$RALPH_DB_PATH" "
        SELECT name FROM sqlite_master
        WHERE type='index'
          AND tbl_name='tasks'
          AND name='idx_tasks_scope_status';
    "
    assert_success
    assert_output "idx_tasks_scope_status"
}

@test "idx_tasks_scope_status covers correct columns" {
    run sqlite3 "$RALPH_DB_PATH" "
        SELECT name FROM pragma_index_info('idx_tasks_scope_status') ORDER BY seqno;
    "
    assert_success
    assert_output --partial "scope_repo"
    assert_output --partial "scope_branch"
    assert_output --partial "status"
    assert_output --partial "priority"
    assert_output --partial "created_at"
}

# ---------------------------------------------------------------------------
# task_deps columns are TEXT type (SQLite equivalent of UUID)
# ---------------------------------------------------------------------------
@test "task_deps.task_id is TEXT type" {
    run sqlite3 "$RALPH_DB_PATH" "
        SELECT type FROM pragma_table_info('task_deps') WHERE name='task_id';
    "
    assert_success
    assert_output "TEXT"
}

@test "task_deps.blocked_by is TEXT type" {
    run sqlite3 "$RALPH_DB_PATH" "
        SELECT type FROM pragma_table_info('task_deps') WHERE name='blocked_by';
    "
    assert_success
    assert_output "TEXT"
}

# ---------------------------------------------------------------------------
# task_deps cascade delete still works with TEXT ids
# ---------------------------------------------------------------------------
@test "task_deps cascade delete works with TEXT ids" {
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
