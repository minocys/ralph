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
    run "$SCRIPT_DIR/task" plan-export
    assert_success
    assert_output ""
}

@test "plan-export --json returns empty output with no tasks" {
    run "$SCRIPT_DIR/task" plan-export --json
    assert_success
    assert_output ""
}

# ---------------------------------------------------------------------------
# Table format (default)
# ---------------------------------------------------------------------------
@test "plan-export table shows header and tasks" {
    "$SCRIPT_DIR/task" create "pe-01" "First task" -p 1 -c "feat" > /dev/null
    run "$SCRIPT_DIR/task" plan-export
    assert_success
    assert_output --partial "ID"
    assert_output --partial "TITLE"
    assert_output --partial "AGENT"
    assert_output --partial "pe-01"
    assert_output --partial "First task"
}

@test "plan-export table includes deleted tasks (full DAG)" {
    "$SCRIPT_DIR/task" create "pe-alive" "Alive task" > /dev/null
    "$SCRIPT_DIR/task" create "pe-dead" "Dead task" > /dev/null
    "$SCRIPT_DIR/task" delete "pe-dead" > /dev/null

    run "$SCRIPT_DIR/task" plan-export
    assert_success
    assert_output --partial "pe-alive"
    assert_output --partial "pe-dead"
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

@test "plan-export table shows assignee when set" {
    "$SCRIPT_DIR/task" create "pe-agent" "Assigned task" > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET assignee = 'b3c4', status = 'active' WHERE id = 'pe-agent'" > /dev/null

    run "$SCRIPT_DIR/task" plan-export
    assert_success
    assert_output --partial "b3c4"
}

# ---------------------------------------------------------------------------
# JSON format (--json)
# ---------------------------------------------------------------------------
@test "plan-export --json outputs valid JSONL" {
    "$SCRIPT_DIR/task" create "pej-01" "JSON task" -p 1 -c "feat" -d "A description" > /dev/null

    run "$SCRIPT_DIR/task" plan-export --json
    assert_success
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "$line" | jq . > /dev/null 2>&1 || fail "Invalid JSON: $line"
    done <<< "$output"
}

@test "plan-export --json includes short keys" {
    "$SCRIPT_DIR/task" create "pej-02" "JSON keys test" -p 1 -c "feat" > /dev/null

    run "$SCRIPT_DIR/task" plan-export --json
    assert_success
    echo "$output" | jq -e '.id' > /dev/null
    echo "$output" | jq -e '.t' > /dev/null
    echo "$output" | jq -e '.p' > /dev/null
    echo "$output" | jq -e '.s' > /dev/null
    echo "$output" | jq -e '.cat' > /dev/null
}

@test "plan-export --json includes steps and deps" {
    "$SCRIPT_DIR/task" create "pej-blocker" "Blocker" > /dev/null
    "$SCRIPT_DIR/task" create "pej-03" "Task with steps and deps" --deps "pej-blocker" > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET steps = ARRAY['Do thing']::TEXT[] WHERE id = 'pej-03'" >/dev/null

    run "$SCRIPT_DIR/task" plan-export --json
    assert_success
    local task_line
    task_line=$(echo "$output" | grep '"pej-03"')
    echo "$task_line" | jq -e '.steps | length == 1' > /dev/null
    echo "$task_line" | jq -e '.deps | length == 1' > /dev/null
    echo "$task_line" | jq -e '.deps[0] == "pej-blocker"' > /dev/null
}

@test "plan-export --json includes deleted tasks (full DAG)" {
    "$SCRIPT_DIR/task" create "pej-alive" "Alive" > /dev/null
    "$SCRIPT_DIR/task" create "pej-dead" "Dead" > /dev/null
    "$SCRIPT_DIR/task" delete "pej-dead" > /dev/null

    run "$SCRIPT_DIR/task" plan-export --json
    assert_success
    assert_output --partial "pej-alive"
    assert_output --partial "pej-dead"
    local dead_line
    dead_line=$(echo "$output" | grep '"pej-dead"')
    echo "$dead_line" | jq -e '.s == "deleted"' > /dev/null
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

    # plan-export includes deleted
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
