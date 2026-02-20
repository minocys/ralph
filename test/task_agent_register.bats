#!/usr/bin/env bats
# test/task_agent_register.bats — Tests for the task agent register command
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
# Basic registration
# ---------------------------------------------------------------------------
@test "agent register returns 4-char hex ID" {
    run "$SCRIPT_DIR/task" agent register
    assert_success
    # Output should be exactly a 4-char hex string
    [[ "${output}" =~ ^[0-9a-f]{4}$ ]]
}

@test "agent register exits 0 on success" {
    run "$SCRIPT_DIR/task" agent register
    assert_success
}

# ---------------------------------------------------------------------------
# Database record
# ---------------------------------------------------------------------------
@test "agent register creates record in agents table" {
    run "$SCRIPT_DIR/task" agent register
    assert_success
    local agent_id="$output"

    run psql "$RALPH_DB_URL" -tAX -c "SELECT id FROM agents WHERE id = '$agent_id';"
    assert_success
    assert_output "$agent_id"
}

@test "agent register records PID" {
    run "$SCRIPT_DIR/task" agent register
    assert_success
    local agent_id="$output"

    run psql "$RALPH_DB_URL" -tAX -c "SELECT pid FROM agents WHERE id = '$agent_id';"
    assert_success
    # PID should be a positive integer
    [[ "${output}" =~ ^[0-9]+$ ]]
}

@test "agent register records hostname" {
    run "$SCRIPT_DIR/task" agent register
    assert_success
    local agent_id="$output"

    run psql "$RALPH_DB_URL" -tAX -c "SELECT hostname FROM agents WHERE id = '$agent_id';"
    assert_success
    # Hostname should be non-empty
    [[ -n "${output}" ]]
}

@test "agent register sets status to active" {
    run "$SCRIPT_DIR/task" agent register
    assert_success
    local agent_id="$output"

    run psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM agents WHERE id = '$agent_id';"
    assert_success
    assert_output "active"
}

@test "agent register sets started_at" {
    run "$SCRIPT_DIR/task" agent register
    assert_success
    local agent_id="$output"

    run psql "$RALPH_DB_URL" -tAX -c "SELECT started_at IS NOT NULL FROM agents WHERE id = '$agent_id';"
    assert_success
    assert_output "t"
}

# ---------------------------------------------------------------------------
# Uniqueness
# ---------------------------------------------------------------------------
@test "agent register produces unique IDs across multiple registrations" {
    local ids=()
    for i in $(seq 1 5); do
        run "$SCRIPT_DIR/task" agent register
        assert_success
        ids+=("$output")
    done

    # Check all IDs are unique
    local unique_count
    unique_count=$(printf '%s\n' "${ids[@]}" | sort -u | wc -l | tr -d ' ')
    [[ "$unique_count" -eq 5 ]]
}

# ---------------------------------------------------------------------------
# Multiple agents
# ---------------------------------------------------------------------------
@test "agent register creates separate records for multiple agents" {
    run "$SCRIPT_DIR/task" agent register
    assert_success
    local id1="$output"

    run "$SCRIPT_DIR/task" agent register
    assert_success
    local id2="$output"

    # Both should exist in the database
    run psql "$RALPH_DB_URL" -tAX -c "SELECT count(*) FROM agents WHERE id IN ('$id1', '$id2');"
    assert_success
    assert_output "2"
}

# ---------------------------------------------------------------------------
# Agent subcommand routing
# ---------------------------------------------------------------------------
@test "agent with missing subcommand exits 1" {
    run "$SCRIPT_DIR/task" agent
    assert_failure
    assert_output --partial "Error: missing agent subcommand"
}

@test "agent with unknown subcommand exits 1" {
    run "$SCRIPT_DIR/task" agent bogus
    assert_failure
    assert_output --partial "Error: unknown agent subcommand"
}
