#!/usr/bin/env bats
# test/task_scoped_schema.bats — verify scoped schema columns, constraints, and index
# Requires: running PostgreSQL (docker compose up -d)
# Set RALPH_DB_URL to run these tests.

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
# tasks table: new columns exist
# ---------------------------------------------------------------------------
@test "tasks table has slug column" {
    run "$SCRIPT_DIR/lib/task" list
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT column_name FROM information_schema.columns
        WHERE table_schema = '$TEST_SCHEMA' AND table_name = 'tasks' AND column_name = 'slug';
    "
    assert_success
    assert_output "slug"
}

@test "tasks table has scope_repo column" {
    run "$SCRIPT_DIR/lib/task" list
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT column_name FROM information_schema.columns
        WHERE table_schema = '$TEST_SCHEMA' AND table_name = 'tasks' AND column_name = 'scope_repo';
    "
    assert_success
    assert_output "scope_repo"
}

@test "tasks table has scope_branch column" {
    run "$SCRIPT_DIR/lib/task" list
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT column_name FROM information_schema.columns
        WHERE table_schema = '$TEST_SCHEMA' AND table_name = 'tasks' AND column_name = 'scope_branch';
    "
    assert_success
    assert_output "scope_branch"
}

# ---------------------------------------------------------------------------
# tasks.id column type is UUID
# ---------------------------------------------------------------------------
@test "tasks.id column is UUID type" {
    run "$SCRIPT_DIR/lib/task" list
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT data_type FROM information_schema.columns
        WHERE table_schema = '$TEST_SCHEMA' AND table_name = 'tasks' AND column_name = 'id';
    "
    assert_success
    assert_output "uuid"
}

@test "tasks.id has a default (gen_random_uuid)" {
    run "$SCRIPT_DIR/lib/task" list
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT column_default FROM information_schema.columns
        WHERE table_schema = '$TEST_SCHEMA' AND table_name = 'tasks' AND column_name = 'id';
    "
    assert_success
    assert_output --partial "gen_random_uuid"
}

# ---------------------------------------------------------------------------
# NOT NULL constraints on slug, scope_repo, scope_branch
# ---------------------------------------------------------------------------
@test "tasks.slug is NOT NULL" {
    run "$SCRIPT_DIR/lib/task" list
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT is_nullable FROM information_schema.columns
        WHERE table_schema = '$TEST_SCHEMA' AND table_name = 'tasks' AND column_name = 'slug';
    "
    assert_success
    assert_output "NO"
}

@test "tasks.scope_repo is NOT NULL" {
    run "$SCRIPT_DIR/lib/task" list
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT is_nullable FROM information_schema.columns
        WHERE table_schema = '$TEST_SCHEMA' AND table_name = 'tasks' AND column_name = 'scope_repo';
    "
    assert_success
    assert_output "NO"
}

@test "tasks.scope_branch is NOT NULL" {
    run "$SCRIPT_DIR/lib/task" list
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT is_nullable FROM information_schema.columns
        WHERE table_schema = '$TEST_SCHEMA' AND table_name = 'tasks' AND column_name = 'scope_branch';
    "
    assert_success
    assert_output "NO"
}

# ---------------------------------------------------------------------------
# UNIQUE constraint on (scope_repo, scope_branch, slug)
# ---------------------------------------------------------------------------
@test "UNIQUE constraint exists on (scope_repo, scope_branch, slug)" {
    run "$SCRIPT_DIR/lib/task" list
    # Query pg_constraint for a unique constraint covering slug, scope_repo, scope_branch
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT count(*) FROM pg_constraint c
        JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = '$TEST_SCHEMA'
          AND c.conrelid = '${TEST_SCHEMA}.tasks'::regclass
          AND c.contype = 'u'
          AND (
              SELECT array_agg(a.attname::text ORDER BY a.attnum)
              FROM unnest(c.conkey) AS k(num)
              JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.num
          ) @> ARRAY['slug','scope_repo','scope_branch'];
    "
    assert_success
    assert_output "1"
}

@test "UNIQUE constraint rejects duplicate slug within same scope" {
    run "$SCRIPT_DIR/lib/task" list
    # Insert first row
    psql "$RALPH_DB_URL" -tAX -c "
        INSERT INTO tasks (slug, scope_repo, scope_branch, title)
        VALUES ('task-01', 'owner/repo', 'main', 'First');
    "
    # Duplicate slug in same scope should fail
    run psql "$RALPH_DB_URL" -tAX -c "
        INSERT INTO tasks (slug, scope_repo, scope_branch, title)
        VALUES ('task-01', 'owner/repo', 'main', 'Duplicate');
    "
    assert_failure
}

@test "UNIQUE constraint allows same slug in different scope" {
    run "$SCRIPT_DIR/lib/task" list
    psql "$RALPH_DB_URL" -tAX -c "
        INSERT INTO tasks (slug, scope_repo, scope_branch, title)
        VALUES ('task-01', 'owner/repo', 'main', 'First');
    "
    # Same slug but different branch should succeed
    run psql "$RALPH_DB_URL" -tAX -c "
        INSERT INTO tasks (slug, scope_repo, scope_branch, title)
        VALUES ('task-01', 'owner/repo', 'feature', 'Second');
    "
    assert_success
}

# ---------------------------------------------------------------------------
# Index on (scope_repo, scope_branch, status, priority, created_at)
# ---------------------------------------------------------------------------
@test "index idx_tasks_scope_status exists" {
    run "$SCRIPT_DIR/lib/task" list
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT indexname FROM pg_indexes
        WHERE schemaname = '$TEST_SCHEMA'
          AND tablename = 'tasks'
          AND indexname = 'idx_tasks_scope_status';
    "
    assert_success
    assert_output "idx_tasks_scope_status"
}

@test "idx_tasks_scope_status covers correct columns" {
    run "$SCRIPT_DIR/lib/task" list
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT indexdef FROM pg_indexes
        WHERE schemaname = '$TEST_SCHEMA'
          AND indexname = 'idx_tasks_scope_status';
    "
    assert_success
    assert_output --partial "scope_repo"
    assert_output --partial "scope_branch"
    assert_output --partial "status"
    assert_output --partial "priority"
    assert_output --partial "created_at"
}

# ---------------------------------------------------------------------------
# task_deps columns are UUID type
# ---------------------------------------------------------------------------
@test "task_deps.task_id is UUID type" {
    run "$SCRIPT_DIR/lib/task" list
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT data_type FROM information_schema.columns
        WHERE table_schema = '$TEST_SCHEMA' AND table_name = 'task_deps' AND column_name = 'task_id';
    "
    assert_success
    assert_output "uuid"
}

@test "task_deps.blocked_by is UUID type" {
    run "$SCRIPT_DIR/lib/task" list
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT data_type FROM information_schema.columns
        WHERE table_schema = '$TEST_SCHEMA' AND table_name = 'task_deps' AND column_name = 'blocked_by';
    "
    assert_success
    assert_output "uuid"
}

# ---------------------------------------------------------------------------
# task_deps cascade delete still works with UUID
# ---------------------------------------------------------------------------
@test "task_deps cascade delete works with UUID ids" {
    run "$SCRIPT_DIR/lib/task" list
    psql "$RALPH_DB_URL" -tAX -c "
        INSERT INTO tasks (id, slug, scope_repo, scope_branch, title)
        VALUES ('550e8400-e29b-41d4-a716-446655440001', 'dep-1', 'owner/repo', 'main', 'Dep Test 1');
        INSERT INTO tasks (id, slug, scope_repo, scope_branch, title)
        VALUES ('550e8400-e29b-41d4-a716-446655440002', 'dep-2', 'owner/repo', 'main', 'Dep Test 2');
        INSERT INTO task_deps (task_id, blocked_by)
        VALUES ('550e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440002');
        DELETE FROM tasks WHERE id = '550e8400-e29b-41d4-a716-446655440002';
    "
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT count(*) FROM task_deps
        WHERE task_id = '550e8400-e29b-41d4-a716-446655440001';
    "
    assert_success
    assert_output "0"
}
