#!/usr/bin/env bats
# test/task_agent_register.bats — Tests for the task agent register command

load test_helper

# ---------------------------------------------------------------------------
# Basic registration
# ---------------------------------------------------------------------------
@test "agent register returns 4-char hex ID" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    # Output should be exactly a 4-char hex string
    [[ "${output}" =~ ^[0-9a-f]{4}$ ]]
}

@test "agent register exits 0 on success" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
}

# ---------------------------------------------------------------------------
# Database record
# ---------------------------------------------------------------------------
@test "agent register creates record in agents table" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local agent_id="$output"

    run sqlite3 "$RALPH_DB_PATH" "SELECT id FROM agents WHERE id = '$agent_id';"
    assert_success
    assert_output "$agent_id"
}

@test "agent register records PID" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local agent_id="$output"

    run sqlite3 "$RALPH_DB_PATH" "SELECT pid FROM agents WHERE id = '$agent_id';"
    assert_success
    # PID should be a positive integer
    [[ "${output}" =~ ^[0-9]+$ ]]
}

@test "agent register records hostname" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local agent_id="$output"

    run sqlite3 "$RALPH_DB_PATH" "SELECT hostname FROM agents WHERE id = '$agent_id';"
    assert_success
    # Hostname should be non-empty
    [[ -n "${output}" ]]
}

@test "agent register sets status to active" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local agent_id="$output"

    run sqlite3 "$RALPH_DB_PATH" "SELECT status FROM agents WHERE id = '$agent_id';"
    assert_success
    assert_output "active"
}

@test "agent register sets started_at" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local agent_id="$output"

    run sqlite3 "$RALPH_DB_PATH" "SELECT started_at IS NOT NULL FROM agents WHERE id = '$agent_id';"
    assert_success
    assert_output "1"
}

@test "agent register records scope_repo from env" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local agent_id="$output"

    run sqlite3 "$RALPH_DB_PATH" "SELECT scope_repo FROM agents WHERE id = '$agent_id';"
    assert_success
    assert_output "test/repo"
}

@test "agent register records scope_branch from env" {
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local agent_id="$output"

    run sqlite3 "$RALPH_DB_PATH" "SELECT scope_branch FROM agents WHERE id = '$agent_id';"
    assert_success
    assert_output "main"
}

@test "agent register records custom scope values" {
    RALPH_SCOPE_REPO="custom/repo" RALPH_SCOPE_BRANCH="feature-branch" \
        run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local agent_id="$output"

    run sqlite3 "$RALPH_DB_PATH" "SELECT scope_repo || '|' || scope_branch FROM agents WHERE id = '$agent_id';"
    assert_success
    assert_output "custom/repo|feature-branch"
}

# ---------------------------------------------------------------------------
# Uniqueness
# ---------------------------------------------------------------------------
@test "agent register produces unique IDs across multiple registrations" {
    local ids=()
    for i in $(seq 1 5); do
        run "$SCRIPT_DIR/lib/task" agent register
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
    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local id1="$output"

    run "$SCRIPT_DIR/lib/task" agent register
    assert_success
    local id2="$output"

    # Both should exist in the database
    run sqlite3 "$RALPH_DB_PATH" "SELECT count(*) FROM agents WHERE id IN ('$id1', '$id2');"
    assert_success
    assert_output "2"
}

# ---------------------------------------------------------------------------
# Agent subcommand routing
# ---------------------------------------------------------------------------
@test "agent with missing subcommand exits 1" {
    run "$SCRIPT_DIR/lib/task" agent
    assert_failure
    assert_output --partial "Error: missing agent subcommand"
}

@test "agent with unknown subcommand exits 1" {
    run "$SCRIPT_DIR/lib/task" agent bogus
    assert_failure
    assert_output --partial "Error: unknown agent subcommand"
}

# ---------------------------------------------------------------------------
# Concurrent registration (BEGIN IMMEDIATE guard)
# ---------------------------------------------------------------------------
@test "concurrent agent registrations all succeed without SQLITE_BUSY errors" {
    local count=4
    local i
    local pids=()

    for (( i = 1; i <= count; i++ )); do
        (
            rc=0
            "$SCRIPT_DIR/lib/task" agent register \
                > "$TEST_WORK_DIR/agent_reg${i}.out" 2>&1 || rc=$?
            echo "$rc" > "$TEST_WORK_DIR/agent_reg${i}.rc"
        ) &
        pids+=($!)
    done

    # Wait for all background processes
    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done

    # All should succeed (exit 0)
    for (( i = 1; i <= count; i++ )); do
        local rc
        rc=$(cat "$TEST_WORK_DIR/agent_reg${i}.rc")
        [[ "$rc" == "0" ]]
    done

    # All should return valid 4-char hex IDs
    local ids=()
    for (( i = 1; i <= count; i++ )); do
        local out
        out=$(cat "$TEST_WORK_DIR/agent_reg${i}.out")
        [[ "$out" =~ ^[0-9a-f]{4}$ ]]
        ids+=("$out")
    done

    # All IDs should be unique
    local unique_count
    unique_count=$(printf '%s\n' "${ids[@]}" | sort -u | wc -l | tr -d ' ')
    [[ "$unique_count" -eq "$count" ]]

    # Database should have exactly $count active agents
    local db_count
    db_count=$(sqlite3 "$RALPH_DB_PATH" \
        "SELECT COUNT(*) FROM agents WHERE status = 'active' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [[ "$db_count" -eq "$count" ]]
}
