#!/usr/bin/env bats
# test/task_deps.bats — Tests for the task deps command
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

# ===========================================================================
# Argument validation
# ===========================================================================

@test "task deps without ID exits 1" {
    run "$SCRIPT_DIR/task" deps
    assert_failure
    assert_output --partial "Error: missing task ID"
}

@test "task deps with nonexistent task exits 2" {
    run "$SCRIPT_DIR/task" deps "nonexistent/01"
    assert_failure
    [ "$status" -eq 2 ]
    assert_output --partial "not found"
}

# ===========================================================================
# No dependencies
# ===========================================================================

@test "task deps with no blockers prints no dependencies" {
    "$SCRIPT_DIR/task" create "test/01" "Task with no deps"

    run "$SCRIPT_DIR/task" deps "test/01"
    assert_success
    assert_output "(no dependencies)"
}

# ===========================================================================
# Direct dependencies
# ===========================================================================

@test "task deps shows direct blockers" {
    "$SCRIPT_DIR/task" create "test/01" "Main task"
    "$SCRIPT_DIR/task" create "blocker/01" "First blocker"
    "$SCRIPT_DIR/task" create "blocker/02" "Second blocker"
    "$SCRIPT_DIR/task" block "test/01" --by "blocker/01"
    "$SCRIPT_DIR/task" block "test/01" --by "blocker/02"

    run "$SCRIPT_DIR/task" deps "test/01"
    assert_success
    assert_output --partial "blocker/01"
    assert_output --partial "blocker/02"
    assert_output --partial "[open]"
}

@test "task deps shows blocker status" {
    "$SCRIPT_DIR/task" create "test/01" "Main task"
    "$SCRIPT_DIR/task" create "blocker/01" "Done blocker"
    "$SCRIPT_DIR/task" block "test/01" --by "blocker/01"
    "$SCRIPT_DIR/task" update "blocker/01" --status done

    run "$SCRIPT_DIR/task" deps "test/01"
    assert_success
    assert_output --partial "blocker/01"
    assert_output --partial "[done]"
}

@test "task deps shows blocker title" {
    "$SCRIPT_DIR/task" create "test/01" "Main task"
    "$SCRIPT_DIR/task" create "blocker/01" "Important Blocker Title"
    "$SCRIPT_DIR/task" block "test/01" --by "blocker/01"

    run "$SCRIPT_DIR/task" deps "test/01"
    assert_success
    assert_output --partial "Important Blocker Title"
}

# ===========================================================================
# Recursive / transitive dependencies (chain)
# ===========================================================================

@test "task deps shows transitive dependency chain" {
    "$SCRIPT_DIR/task" create "test/01" "Top task"
    "$SCRIPT_DIR/task" create "mid/01" "Middle task"
    "$SCRIPT_DIR/task" create "leaf/01" "Leaf task"
    "$SCRIPT_DIR/task" block "test/01" --by "mid/01"
    "$SCRIPT_DIR/task" block "mid/01" --by "leaf/01"

    run "$SCRIPT_DIR/task" deps "test/01"
    assert_success
    assert_output --partial "mid/01"
    assert_output --partial "leaf/01"
}

@test "task deps indents transitive deps deeper than direct deps" {
    "$SCRIPT_DIR/task" create "test/01" "Top task"
    "$SCRIPT_DIR/task" create "mid/01" "Middle task"
    "$SCRIPT_DIR/task" create "leaf/01" "Leaf task"
    "$SCRIPT_DIR/task" block "test/01" --by "mid/01"
    "$SCRIPT_DIR/task" block "mid/01" --by "leaf/01"

    run "$SCRIPT_DIR/task" deps "test/01"
    assert_success
    # Direct dep (depth 1) has no indent
    echo "$output" | grep -q '^mid/01'
    # Transitive dep (depth 2) has indent
    echo "$output" | grep -q '^  leaf/01'
}

@test "task deps shows deep chain (3 levels)" {
    "$SCRIPT_DIR/task" create "a" "Task A"
    "$SCRIPT_DIR/task" create "b" "Task B"
    "$SCRIPT_DIR/task" create "c" "Task C"
    "$SCRIPT_DIR/task" create "d" "Task D"
    "$SCRIPT_DIR/task" block "a" --by "b"
    "$SCRIPT_DIR/task" block "b" --by "c"
    "$SCRIPT_DIR/task" block "c" --by "d"

    run "$SCRIPT_DIR/task" deps "a"
    assert_success
    assert_output --partial "b"
    assert_output --partial "c"
    assert_output --partial "d"
    # Check indentation levels
    echo "$output" | grep -q '^b '
    echo "$output" | grep -q '^  c '
    echo "$output" | grep -q '^    d '
}

# ===========================================================================
# Diamond dependency
# ===========================================================================

@test "task deps handles diamond dependency pattern" {
    "$SCRIPT_DIR/task" create "top" "Top"
    "$SCRIPT_DIR/task" create "left" "Left"
    "$SCRIPT_DIR/task" create "right" "Right"
    "$SCRIPT_DIR/task" create "bottom" "Bottom"
    "$SCRIPT_DIR/task" block "top" --by "left"
    "$SCRIPT_DIR/task" block "top" --by "right"
    "$SCRIPT_DIR/task" block "left" --by "bottom"
    "$SCRIPT_DIR/task" block "right" --by "bottom"

    run "$SCRIPT_DIR/task" deps "top"
    assert_success
    # All deps should appear
    assert_output --partial "left"
    assert_output --partial "right"
    assert_output --partial "bottom"
}

# ===========================================================================
# Special characters
# ===========================================================================

@test "task deps handles IDs with single quotes" {
    "$SCRIPT_DIR/task" create "test/it's" "Quoted task"
    "$SCRIPT_DIR/task" create "block/it's" "Quoted blocker"
    "$SCRIPT_DIR/task" block "test/it's" --by "block/it's"

    run "$SCRIPT_DIR/task" deps "test/it's"
    assert_success
    assert_output --partial "block/it's"
}
