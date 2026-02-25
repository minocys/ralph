#!/usr/bin/env bats
# test/task_agent_deregister.bats — Tests for the task agent deregister command
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
@test "agent deregister with no ID exits 1" {
    run "$SCRIPT_DIR/lib/task" agent deregister
    assert_failure
    [[ "$status" -eq 1 ]]
    assert_output --partial "Error: missing agent ID"
}

@test "agent deregister with no ID shows usage" {
    run "$SCRIPT_DIR/lib/task" agent deregister
    assert_failure
    assert_output --partial "Usage:"
}

# ---------------------------------------------------------------------------
# Not found
# ---------------------------------------------------------------------------
@test "agent deregister with nonexistent ID exits 2" {
    run "$SCRIPT_DIR/lib/task" agent deregister "ffff"
    assert_failure
    [[ "$status" -eq 2 ]]
    assert_output --partial "not found"
}

# ---------------------------------------------------------------------------
# Successful deregistration
# ---------------------------------------------------------------------------
@test "agent deregister changes status to stopped" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local agent_id="$output"

    run "$SCRIPT_DIR/lib/task" agent deregister "$agent_id"
    assert_success
    assert_output "deregistered $agent_id"

    # Verify status in DB
    local status
    status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM agents WHERE id = '$agent_id';")
    [[ "$status" == "stopped" ]]
}

@test "agent deregister exits 0 on success" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local agent_id="$output"

    run "$SCRIPT_DIR/lib/task" agent deregister "$agent_id"
    assert_success
}

@test "agent deregister prints confirmation message" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local agent_id="$output"

    run "$SCRIPT_DIR/lib/task" agent deregister "$agent_id"
    assert_success
    assert_output "deregistered $agent_id"
}

# ---------------------------------------------------------------------------
# Agent record preserved
# ---------------------------------------------------------------------------
@test "deregistered agent excluded from agent list" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local agent_id="$output"

    run "$SCRIPT_DIR/lib/task" agent deregister "$agent_id"
    assert_success

    # Deregistered (stopped) agent should not appear in agent list
    run "$SCRIPT_DIR/lib/task" agent list
    assert_success
    refute_output --partial "$agent_id"
}

# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------
@test "agent deregister on already-stopped agent succeeds" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local agent_id="$output"

    run "$SCRIPT_DIR/lib/task" agent deregister "$agent_id"
    assert_success

    # Deregister again — should still succeed (idempotent)
    run "$SCRIPT_DIR/lib/task" agent deregister "$agent_id"
    assert_success
    assert_output "deregistered $agent_id"
}

# ---------------------------------------------------------------------------
# Multiple agents
# ---------------------------------------------------------------------------
@test "agent deregister only affects specified agent" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local id1="$output"

    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local id2="$output"

    run "$SCRIPT_DIR/lib/task" agent deregister "$id1"
    assert_success

    # id1 should be stopped, id2 should still be active
    local status1
    status1=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM agents WHERE id = '$id1';")
    [[ "$status1" == "stopped" ]]

    local status2
    status2=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM agents WHERE id = '$id2';")
    [[ "$status2" == "active" ]]
}

# ---------------------------------------------------------------------------
# Integration: register + deregister workflow
# ---------------------------------------------------------------------------
@test "register then deregister full workflow" {
    # Register
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local agent_id="$output"
    [[ "${agent_id}" =~ ^[0-9a-f]{4}$ ]]

    # Verify active
    local status
    status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM agents WHERE id = '$agent_id';")
    [[ "$status" == "active" ]]

    # Deregister
    run "$SCRIPT_DIR/lib/task" agent deregister "$agent_id"
    assert_success

    # Verify stopped
    status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM agents WHERE id = '$agent_id';")
    [[ "$status" == "stopped" ]]

    # Verify record still exists (not deleted)
    local count
    count=$(psql "$RALPH_DB_URL" -tAX -c "SELECT COUNT(*) FROM agents WHERE id = '$agent_id';")
    [[ "$count" -eq 1 ]]
}
