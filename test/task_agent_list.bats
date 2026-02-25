#!/usr/bin/env bats
# test/task_agent_list.bats — Tests for the task agent list command
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
@test "agent list with no agents exits 0 with no output" {
    run "$SCRIPT_DIR/lib/task" agent list
    assert_success
    # Output should be empty (no header when no agents)
    [[ -z "${output}" ]]
}

# ---------------------------------------------------------------------------
# Single agent
# ---------------------------------------------------------------------------
@test "agent list shows registered agent" {
    # Register an agent first
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local agent_id="$output"

    run "$SCRIPT_DIR/lib/task" agent list
    assert_success
    assert_output --partial "$agent_id"
}

@test "agent list shows header row" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success

    run "$SCRIPT_DIR/lib/task" agent list
    assert_success
    assert_output --partial "ID"
    assert_output --partial "PID"
    assert_output --partial "HOSTNAME"
    assert_output --partial "STARTED"
    assert_output --partial "STATUS"
}

@test "agent list shows active status" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success

    run "$SCRIPT_DIR/lib/task" agent list
    assert_success
    assert_output --partial "active"
}

@test "agent list shows PID" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success

    run "$SCRIPT_DIR/lib/task" agent list
    assert_success
    # Output should contain a numeric PID
    [[ "${output}" =~ [0-9]+ ]]
}

@test "agent list shows hostname" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success

    local expected_host="${HOSTNAME:-$(hostname)}"

    run "$SCRIPT_DIR/lib/task" agent list
    assert_success
    assert_output --partial "$expected_host"
}

# ---------------------------------------------------------------------------
# Multiple agents
# ---------------------------------------------------------------------------
@test "agent list shows multiple agents" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local id1="$output"

    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local id2="$output"

    run "$SCRIPT_DIR/lib/task" agent list
    assert_success
    assert_output --partial "$id1"
    assert_output --partial "$id2"
}

@test "agent list excludes stopped agents" {
    # Register and then manually stop one agent
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local id1="$output"

    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local id2="$output"

    # Manually stop one agent
    psql "$RALPH_DB_URL" -tAX -c "UPDATE agents SET status = 'stopped' WHERE id = '$id1';" >/dev/null

    run "$SCRIPT_DIR/lib/task" agent list
    assert_success
    # Stopped agent should NOT appear in the list
    refute_output --partial "$id1"
    # Active agent should still appear
    assert_output --partial "$id2"
    refute_output --partial "stopped"
    assert_output --partial "active"
}

# ---------------------------------------------------------------------------
# Output format
# ---------------------------------------------------------------------------
@test "agent list columns are aligned" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success

    run "$SCRIPT_DIR/lib/task" agent list
    assert_success

    # Should have at least 2 lines (header + 1 agent)
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    [[ "$line_count" -ge 2 ]]
}

@test "agent list shows started_at timestamp" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success

    run "$SCRIPT_DIR/lib/task" agent list
    assert_success
    # Timestamp should contain a date-like pattern (YYYY-MM-DD)
    [[ "${output}" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]
}
