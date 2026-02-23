#!/usr/bin/env bats
# test/task_plan_export.bats — Tests for the task plan-export command
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
# Empty database
# ---------------------------------------------------------------------------
@test "plan-export returns empty output with no tasks" {
    run bash -c "'$SCRIPT_DIR/task' plan-export 2>/dev/null"
    assert_success
    assert_output ""
}

# ---------------------------------------------------------------------------
# Default table format
# ---------------------------------------------------------------------------
@test "plan-export defaults to table format" {
    "$SCRIPT_DIR/task" create "pe-01" "First task" -p 1 -c "feat" > /dev/null

    run "$SCRIPT_DIR/task" plan-export
    assert_success
    assert_output --partial "ID"
    assert_output --partial "TITLE"
    assert_output --partial "pe-01"
    assert_output --partial "First task"
    # Should NOT contain markdown-KV markers
    refute_output --partial "## Task"
}

@test "plan-export table includes deleted tasks (full DAG)" {
    "$SCRIPT_DIR/task" create "pe-alive" "Alive task" > /dev/null
    "$SCRIPT_DIR/task" create "pe-dead" "Dead task" > /dev/null
    "$SCRIPT_DIR/task" delete "pe-dead" > /dev/null

    run "$SCRIPT_DIR/task" plan-export
    assert_success
    assert_output --partial "pe-alive"
    assert_output --partial "pe-dead"
    assert_output --partial "deleted"
}

@test "plan-export table orders by priority ascending" {
    "$SCRIPT_DIR/task" create "pe-low" "Low priority" -p 3 > /dev/null
    "$SCRIPT_DIR/task" create "pe-high" "High priority" -p 0 > /dev/null
    "$SCRIPT_DIR/task" create "pe-mid" "Mid priority" -p 1 > /dev/null

    run "$SCRIPT_DIR/task" plan-export
    assert_success
    local high_line mid_line low_line
    high_line=$(echo "$output" | grep -n "pe-high" | cut -d: -f1)
    mid_line=$(echo "$output" | grep -n "pe-mid" | cut -d: -f1)
    low_line=$(echo "$output" | grep -n "pe-low" | cut -d: -f1)
    [ "$high_line" -lt "$mid_line" ]
    [ "$mid_line" -lt "$low_line" ]
}

@test "plan-export table shows header columns" {
    "$SCRIPT_DIR/task" create "pe-hdr" "Header test" -p 1 -c "feat" > /dev/null

    run "$SCRIPT_DIR/task" plan-export
    assert_success
    # Verify header row has the expected columns
    assert_output --partial "ID"
    assert_output --partial "P"
    assert_output --partial "CAT"
    assert_output --partial "TITLE"
    assert_output --partial "AGENT"
}

@test "plan-export table shows assignee when set" {
    "$SCRIPT_DIR/task" create "pe-agent" "Assigned task" > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET assignee = 'b3c4', status = 'active' WHERE slug = 'pe-agent' AND scope_repo = 'test/repo' AND scope_branch = 'main'" > /dev/null

    run "$SCRIPT_DIR/task" plan-export
    assert_success
    assert_output --partial "b3c4"
}

# ---------------------------------------------------------------------------
# Markdown-KV format (--markdown flag)
# ---------------------------------------------------------------------------
@test "plan-export --markdown outputs markdown-KV sections" {
    "$SCRIPT_DIR/task" create "pe-01" "First task" -p 1 -c "feat" > /dev/null

    run "$SCRIPT_DIR/task" plan-export --markdown
    assert_success
    assert_output --partial "## Task pe-01"
    assert_output --partial "id: pe-01"
    assert_output --partial "title: First task"
    assert_output --partial "priority: 1"
    assert_output --partial "status: open"
    assert_output --partial "category: feat"
}

@test "plan-export --markdown omits null and empty fields" {
    # Create task with only required fields — no category, spec, ref, assignee, deps, steps
    "$SCRIPT_DIR/task" create "pe-minimal" "Minimal task" > /dev/null

    run "$SCRIPT_DIR/task" plan-export --markdown
    assert_success
    assert_output --partial "## Task pe-minimal"
    assert_output --partial "id: pe-minimal"
    assert_output --partial "title: Minimal task"
    # These null/empty fields must be omitted entirely per spec
    refute_output --partial "category:"
    refute_output --partial "spec:"
    refute_output --partial "ref:"
    refute_output --partial "assignee:"
    refute_output --partial "deps:"
    refute_output --partial "steps:"
}

@test "plan-export --markdown includes deleted tasks (full DAG)" {
    "$SCRIPT_DIR/task" create "pe-alive" "Alive task" > /dev/null
    "$SCRIPT_DIR/task" create "pe-dead" "Dead task" > /dev/null
    "$SCRIPT_DIR/task" delete "pe-dead" > /dev/null

    run "$SCRIPT_DIR/task" plan-export --markdown
    assert_success
    assert_output --partial "## Task pe-alive"
    assert_output --partial "## Task pe-dead"
    assert_output --partial "status: deleted"
}

@test "plan-export --markdown orders by priority ascending" {
    "$SCRIPT_DIR/task" create "pe-low" "Low priority" -p 3 > /dev/null
    "$SCRIPT_DIR/task" create "pe-high" "High priority" -p 0 > /dev/null
    "$SCRIPT_DIR/task" create "pe-mid" "Mid priority" -p 1 > /dev/null

    run "$SCRIPT_DIR/task" plan-export --markdown
    assert_success
    local high_line mid_line low_line
    high_line=$(echo "$output" | grep -n "## Task pe-high" | cut -d: -f1)
    mid_line=$(echo "$output" | grep -n "## Task pe-mid" | cut -d: -f1)
    low_line=$(echo "$output" | grep -n "## Task pe-low" | cut -d: -f1)
    [ "$high_line" -lt "$mid_line" ]
    [ "$mid_line" -lt "$low_line" ]
}

@test "plan-export --markdown shows assignee when set" {
    "$SCRIPT_DIR/task" create "pe-agent" "Assigned task" > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET assignee = 'b3c4', status = 'active' WHERE slug = 'pe-agent' AND scope_repo = 'test/repo' AND scope_branch = 'main'" > /dev/null

    run "$SCRIPT_DIR/task" plan-export --markdown
    assert_success
    assert_output --partial "assignee: b3c4"
}

@test "plan-export --markdown includes steps and deps" {
    "$SCRIPT_DIR/task" create "pe-blocker" "Blocker" > /dev/null
    "$SCRIPT_DIR/task" create "pe-03" "Task with steps and deps" --deps "pe-blocker" > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET steps = ARRAY['Do thing']::TEXT[] WHERE slug = 'pe-03' AND scope_repo = 'test/repo' AND scope_branch = 'main'" >/dev/null

    run "$SCRIPT_DIR/task" plan-export --markdown
    assert_success
    assert_output --partial "deps: pe-blocker"
    assert_output --partial "steps:"
    assert_output --partial "- Do thing"
}

@test "plan-export --markdown separates tasks with blank lines" {
    "$SCRIPT_DIR/task" create "pe-a" "Task A" -p 0 > /dev/null
    "$SCRIPT_DIR/task" create "pe-b" "Task B" -p 1 > /dev/null

    run "$SCRIPT_DIR/task" plan-export --markdown
    assert_success
    # There should be a blank line between the two task sections
    local blank_count
    blank_count=$(echo "$output" | grep -c '^$' || true)
    [ "$blank_count" -ge 1 ]
}

@test "plan-export --markdown returns empty output with no tasks" {
    run bash -c "'$SCRIPT_DIR/task' plan-export --markdown 2>/dev/null"
    assert_success
    assert_output ""
}

# ---------------------------------------------------------------------------
# Difference from list: plan-export shows ALL statuses
# ---------------------------------------------------------------------------
@test "plan-export shows all statuses unlike list" {
    "$SCRIPT_DIR/task" create "pe-open" "Open" > /dev/null
    "$SCRIPT_DIR/task" create "pe-del" "Deleted" > /dev/null
    "$SCRIPT_DIR/task" delete "pe-del" > /dev/null

    # list excludes deleted
    run "$SCRIPT_DIR/task" list
    assert_success
    refute_output --partial "pe-del"

    # plan-export includes deleted (table format)
    run "$SCRIPT_DIR/task" plan-export
    assert_success
    assert_output --partial "pe-del"
    assert_output --partial "pe-open"
}

# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------
@test "plan-export rejects unknown flags" {
    run "$SCRIPT_DIR/task" plan-export --invalid
    assert_failure
    assert_output --partial "unknown flag"
}

@test "plan-export rejects --json flag" {
    run "$SCRIPT_DIR/task" plan-export --json
    assert_failure
    assert_output --partial "unknown flag"
}

# ---------------------------------------------------------------------------
# Deprecation warning
# ---------------------------------------------------------------------------
@test "plan-export prints deprecation warning to stderr" {
    run "$SCRIPT_DIR/task" plan-export
    assert_success
    assert_output --partial "Warning: plan-export is deprecated"
    assert_output --partial "task list --all"
}

@test "plan-export deprecation warning appears on stderr separately" {
    local stderr_file="$TEST_WORK_DIR/stderr.txt"
    "$SCRIPT_DIR/task" plan-export 2>"$stderr_file" || true

    # stderr must contain the deprecation warning
    run cat "$stderr_file"
    assert_output --partial "Warning: plan-export is deprecated"
    assert_output --partial "task list --all"
}

@test "plan-export stdout is not polluted by deprecation warning" {
    "$SCRIPT_DIR/task" create "pe-clean" "Clean stdout test" -p 1 -c "feat" > /dev/null

    # Capture stdout only (discard stderr)
    local stdout_output
    stdout_output=$("$SCRIPT_DIR/task" plan-export 2>/dev/null)

    # stdout should contain task data
    [[ "$stdout_output" == *"pe-clean"* ]]
    [[ "$stdout_output" == *"Clean stdout test"* ]]

    # stdout must NOT contain the deprecation warning
    [[ "$stdout_output" != *"deprecated"* ]]
    [[ "$stdout_output" != *"Warning"* ]]
}

@test "plan-export --markdown stdout is not polluted by deprecation warning" {
    "$SCRIPT_DIR/task" create "pe-md-clean" "Markdown clean test" -p 1 > /dev/null

    # Capture stdout and stderr separately
    local stdout_output stderr_file="$TEST_WORK_DIR/stderr_md.txt"
    stdout_output=$("$SCRIPT_DIR/task" plan-export --markdown 2>"$stderr_file")

    # stdout should have markdown-KV content
    [[ "$stdout_output" == *"## Task pe-md-clean"* ]]
    [[ "$stdout_output" != *"deprecated"* ]]
    [[ "$stdout_output" != *"Warning"* ]]

    # stderr should have the warning
    run cat "$stderr_file"
    assert_output --partial "Warning: plan-export is deprecated"
}
