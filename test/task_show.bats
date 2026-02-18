#!/usr/bin/env bats
# test/task_show.bats — Tests for the task show command
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
@test "task show without ID exits 1 with error" {
    run "$SCRIPT_DIR/task" show
    assert_failure
    assert_output --partial "Error: missing task ID"
}

# ---------------------------------------------------------------------------
# Task not found
# ---------------------------------------------------------------------------
@test "task show nonexistent task exits 2" {
    run "$SCRIPT_DIR/task" show "nonexistent-id"
    [ "$status" -eq 2 ]
    assert_output --partial "not found"
}

# ---------------------------------------------------------------------------
# Show existing task
# ---------------------------------------------------------------------------
@test "task show displays task detail" {
    "$SCRIPT_DIR/task" create "show-01" "Show test task" \
        -p 1 -c "feat" -d "A description" -r "task-cli" --ref "specs/task-cli.md" > /dev/null

    run "$SCRIPT_DIR/task" show "show-01"
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
    "$SCRIPT_DIR/task" create "show-steps" "Task with steps" \
        -s '[{"content":"First step"},{"content":"Second step"}]' > /dev/null

    run "$SCRIPT_DIR/task" show "show-steps"
    assert_success
    assert_output --partial "Steps:"
    assert_output --partial "1. [pending] First step"
    assert_output --partial "2. [pending] Second step"
}

# ---------------------------------------------------------------------------
# Show task with dependencies
# ---------------------------------------------------------------------------
@test "task show displays dependencies" {
    "$SCRIPT_DIR/task" create "dep-a" "Blocker A" > /dev/null
    "$SCRIPT_DIR/task" create "dep-b" "Blocker B" > /dev/null
    "$SCRIPT_DIR/task" create "show-deps" "Dependent task" --deps "dep-a,dep-b" > /dev/null

    run "$SCRIPT_DIR/task" show "show-deps"
    assert_success
    assert_output --partial "Dependencies:"
    assert_output --partial "dep-a (open)"
    assert_output --partial "dep-b (open)"
}

# ---------------------------------------------------------------------------
# Show with --with-deps includes blocker results
# ---------------------------------------------------------------------------
@test "task show --with-deps includes blocker results" {
    "$SCRIPT_DIR/task" create "res-a" "Blocker with result" > /dev/null
    "$SCRIPT_DIR/task" create "show-wd" "Dependent task" --deps "res-a" > /dev/null

    # Set blocker to done with result
    psql "$RALPH_DB_URL" -tAX -c "
        UPDATE tasks SET status = 'done', result = '{\"commit\": \"abc123\"}' WHERE id = 'res-a';
    " > /dev/null

    run "$SCRIPT_DIR/task" show "show-wd" --with-deps
    assert_success
    assert_output --partial "Blocker Results:"
    assert_output --partial 'res-a: {"commit": "abc123"}'
}

@test "task show --with-deps with no results omits blocker results section" {
    "$SCRIPT_DIR/task" create "nores-a" "Blocker no result" > /dev/null
    "$SCRIPT_DIR/task" create "show-nores" "Dependent task" --deps "nores-a" > /dev/null

    run "$SCRIPT_DIR/task" show "show-nores" --with-deps
    assert_success
    assert_output --partial "Dependencies:"
    refute_output --partial "Blocker Results:"
}

# ---------------------------------------------------------------------------
# Show without --with-deps omits blocker results even if they exist
# ---------------------------------------------------------------------------
@test "task show without --with-deps omits blocker results" {
    "$SCRIPT_DIR/task" create "res-b" "Blocker with result" > /dev/null
    "$SCRIPT_DIR/task" create "show-nwd" "Dependent task" --deps "res-b" > /dev/null

    psql "$RALPH_DB_URL" -tAX -c "
        UPDATE tasks SET status = 'done', result = '{\"commit\": \"def456\"}' WHERE id = 'res-b';
    " > /dev/null

    run "$SCRIPT_DIR/task" show "show-nwd"
    assert_success
    refute_output --partial "Blocker Results:"
}

# ---------------------------------------------------------------------------
# Minimal task (no optional fields)
# ---------------------------------------------------------------------------
@test "task show minimal task omits null fields" {
    "$SCRIPT_DIR/task" create "show-min" "Minimal task" > /dev/null

    run "$SCRIPT_DIR/task" show "show-min"
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
    "$SCRIPT_DIR/task" create "quote-show" "It's a task" -d "Description with 'quotes'" > /dev/null

    run "$SCRIPT_DIR/task" show "quote-show"
    assert_success
    assert_output --partial "Title:       It's a task"
    assert_output --partial "Description: Description with 'quotes'"
}
