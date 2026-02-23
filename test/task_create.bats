#!/usr/bin/env bats
# test/task_create.bats — Tests for the task create command
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
@test "task create without ID exits 1 with error" {
    run "$SCRIPT_DIR/task" create
    assert_failure
    assert_output --partial "Error: missing task ID"
}

@test "task create without title exits 1 with error" {
    run "$SCRIPT_DIR/task" create "test-01"
    assert_failure
    assert_output --partial "Error: missing task title"
}

# ---------------------------------------------------------------------------
# Minimal create
# ---------------------------------------------------------------------------
@test "task create with minimal args inserts task and prints ID" {
    run "$SCRIPT_DIR/task" create "test-01" "My first task"
    assert_success
    assert_output "test-01"

    # Verify task exists in DB
    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT slug, title, priority, status, retry_count FROM tasks WHERE slug = 'test-01' AND scope_repo = 'test/repo' AND scope_branch = 'main';
    "
    assert_success
    assert_output "test-01|My first task|2|open|0"
}

@test "task create sets updated_at on insert" {
    run "$SCRIPT_DIR/task" create "test-ts" "Timestamp test"
    assert_success

    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT CASE WHEN updated_at IS NOT NULL THEN 'set' ELSE 'null' END FROM tasks WHERE slug = 'test-ts' AND scope_repo = 'test/repo' AND scope_branch = 'main';
    "
    assert_success
    assert_output "set"
}

# ---------------------------------------------------------------------------
# Create with all flags
# ---------------------------------------------------------------------------
@test "task create with all flags stores correct values" {
    run "$SCRIPT_DIR/task" create "feat-01" "Full task" \
        -p 1 \
        -c "feat" \
        -d "A detailed description" \
        -r "task-cli" \
        --ref "specs/task-cli.md"
    assert_success
    assert_output "feat-01"

    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT slug, title, description, category, priority, spec_ref, ref
        FROM tasks WHERE slug = 'feat-01' AND scope_repo = 'test/repo' AND scope_branch = 'main';
    "
    assert_success
    assert_output "feat-01|Full task|A detailed description|feat|1|task-cli|specs/task-cli.md"
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------
@test "task create with steps stores steps in TEXT[] column" {
    run "$SCRIPT_DIR/task" create "step-01" "Task with steps" \
        -s '["First step","Second step","Third step"]'
    assert_success

    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT unnest(steps) FROM tasks WHERE slug = 'step-01' AND scope_repo = 'test/repo' AND scope_branch = 'main';
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
    "$SCRIPT_DIR/task" create "blocker-a" "Blocker A" > /dev/null
    "$SCRIPT_DIR/task" create "blocker-b" "Blocker B" > /dev/null

    run "$SCRIPT_DIR/task" create "dep-01" "Dependent task" --deps "blocker-a,blocker-b"
    assert_success

    run psql "$RALPH_DB_URL" -tAX -c "
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
    run "$SCRIPT_DIR/task" create "def-01" "Default check"
    assert_success

    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT priority, status FROM tasks WHERE slug = 'def-01' AND scope_repo = 'test/repo' AND scope_branch = 'main';
    "
    assert_success
    assert_output "2|open"
}

@test "task create with NULL description and category" {
    run "$SCRIPT_DIR/task" create "null-01" "Null fields test"
    assert_success

    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT
            CASE WHEN description IS NULL THEN 'null' ELSE description END,
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
    "$SCRIPT_DIR/task" create "dup-01" "First" > /dev/null
    run "$SCRIPT_DIR/task" create "dup-01" "Second"
    assert_failure
}

# ---------------------------------------------------------------------------
# Special characters in title
# ---------------------------------------------------------------------------
@test "task create handles single quotes in title" {
    run "$SCRIPT_DIR/task" create "quote-01" "It's a task"
    assert_success
    assert_output "quote-01"

    run psql "$RALPH_DB_URL" -tAX -c "
        SELECT title FROM tasks WHERE slug = 'quote-01' AND scope_repo = 'test/repo' AND scope_branch = 'main';
    "
    assert_success
    assert_output "It's a task"
}
