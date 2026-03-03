#!/usr/bin/env bats
# test/task_renew.bats — Tests for the task renew command

load test_helper


# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
@test "task renew with no args exits 1" {
    run "$SCRIPT_DIR/lib/task" renew
    assert_failure 1
    assert_output --partial "missing task ID"
}

@test "task renew with non-numeric --lease exits 1 with error" {
    run "$SCRIPT_DIR/lib/task" renew "some-task" --lease abc
    assert_failure
    assert_output --partial "Error: --lease must be a non-negative integer"
}

@test "task renew with negative --lease exits 1 with error" {
    run "$SCRIPT_DIR/lib/task" renew "some-task" --lease -5
    assert_failure
    assert_output --partial "Error: --lease must be a non-negative integer"
}

@test "task renew with float --lease exits 1 with error" {
    run "$SCRIPT_DIR/lib/task" renew "some-task" --lease 1.5
    assert_failure
    assert_output --partial "Error: --lease must be a non-negative integer"
}

# ---------------------------------------------------------------------------
# Not found
# ---------------------------------------------------------------------------
@test "task renew on nonexistent task exits 2" {
    # Ensure schema exists
    run "$SCRIPT_DIR/lib/task" list
    assert_success

    run "$SCRIPT_DIR/lib/task" renew "nonexistent-task"
    assert_failure 2
    assert_output --partial "not found"
}

# ---------------------------------------------------------------------------
# Task not active
# ---------------------------------------------------------------------------
@test "task renew on open task exits 1" {
    "$SCRIPT_DIR/lib/task" create "renew-open-01" "Open Task"

    run "$SCRIPT_DIR/lib/task" renew "renew-open-01"
    assert_failure 1
    assert_output --partial "not active"
}

@test "task renew on done task exits 1" {
    "$SCRIPT_DIR/lib/task" create "renew-done-01" "Done Task"
    # Manually set status to active then done
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status = 'active', assignee = 'agent1' WHERE slug = 'renew-done-01' AND scope_repo = 'test/repo' AND scope_branch = 'main'"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status = 'done' WHERE slug = 'renew-done-01' AND scope_repo = 'test/repo' AND scope_branch = 'main'"

    run "$SCRIPT_DIR/lib/task" renew "renew-done-01"
    assert_failure 1
    assert_output --partial "not active"
}

# ---------------------------------------------------------------------------
# Assignee verification
# ---------------------------------------------------------------------------
@test "task renew fails for non-assignee" {
    "$SCRIPT_DIR/lib/task" create "renew-assign-01" "Assigned Task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status = 'active', assignee = 'agent-A' WHERE slug = 'renew-assign-01' AND scope_repo = 'test/repo' AND scope_branch = 'main'"

    export RALPH_AGENT_ID="agent-B"
    run "$SCRIPT_DIR/lib/task" renew "renew-assign-01"
    assert_failure 1
    assert_output --partial "not the assignee"
}

@test "task renew fails when no agent ID provided and task has assignee" {
    "$SCRIPT_DIR/lib/task" create "renew-noagent-01" "Task With Agent"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status = 'active', assignee = 'agent-X' WHERE slug = 'renew-noagent-01' AND scope_repo = 'test/repo' AND scope_branch = 'main'"

    unset RALPH_AGENT_ID
    run "$SCRIPT_DIR/lib/task" renew "renew-noagent-01"
    assert_failure 1
    assert_output --partial "not the assignee"
}

# ---------------------------------------------------------------------------
# Successful renew
# ---------------------------------------------------------------------------
@test "task renew extends lease on active task" {
    "$SCRIPT_DIR/lib/task" create "renew-ok-01" "Renewable Task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status = 'active', assignee = 'agent1', lease_expires_at = datetime('now', '+60 seconds') WHERE slug = 'renew-ok-01' AND scope_repo = 'test/repo' AND scope_branch = 'main'"

    export RALPH_AGENT_ID="agent1"
    run "$SCRIPT_DIR/lib/task" renew "renew-ok-01"
    assert_success
    assert_output "renewed renew-ok-01"

    # Verify lease was extended (should be > 500 seconds from now with default 600s lease)
    local remaining
    remaining=$(sqlite3 "$RALPH_DB_PATH" "SELECT CAST((julianday(lease_expires_at) - julianday('now')) * 86400 AS INTEGER) FROM tasks WHERE slug = 'renew-ok-01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [[ "$remaining" -gt 500 ]]
}

@test "task renew with custom lease duration" {
    "$SCRIPT_DIR/lib/task" create "renew-custom-01" "Custom Lease Task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status = 'active', assignee = 'agent1', lease_expires_at = datetime('now', '+60 seconds') WHERE slug = 'renew-custom-01' AND scope_repo = 'test/repo' AND scope_branch = 'main'"

    export RALPH_AGENT_ID="agent1"
    run "$SCRIPT_DIR/lib/task" renew "renew-custom-01" --lease 300
    assert_success
    assert_output "renewed renew-custom-01"

    # Verify lease is around 300 seconds (allow some margin)
    local remaining
    remaining=$(sqlite3 "$RALPH_DB_PATH" "SELECT CAST((julianday(lease_expires_at) - julianday('now')) * 86400 AS INTEGER) FROM tasks WHERE slug = 'renew-custom-01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [[ "$remaining" -gt 250 ]]
    [[ "$remaining" -le 300 ]]
}

@test "task renew updates updated_at timestamp" {
    "$SCRIPT_DIR/lib/task" create "renew-ts-01" "Timestamp Task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status = 'active', assignee = 'agent1', lease_expires_at = datetime('now', '+60 seconds'), updated_at = '2020-01-01 00:00:00' WHERE slug = 'renew-ts-01' AND scope_repo = 'test/repo' AND scope_branch = 'main'"

    export RALPH_AGENT_ID="agent1"
    run "$SCRIPT_DIR/lib/task" renew "renew-ts-01"
    assert_success

    # Verify updated_at was refreshed (should be recent, not 2020)
    local year
    year=$(sqlite3 "$RALPH_DB_PATH" "SELECT CAST(strftime('%Y', updated_at) AS INTEGER) FROM tasks WHERE slug = 'renew-ts-01' AND scope_repo = 'test/repo' AND scope_branch = 'main'")
    [[ "$year" -ge 2025 ]]
}

@test "task renew with --agent flag overrides env var" {
    "$SCRIPT_DIR/lib/task" create "renew-flag-01" "Agent Flag Task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status = 'active', assignee = 'agentX', lease_expires_at = datetime('now', '+60 seconds') WHERE slug = 'renew-flag-01' AND scope_repo = 'test/repo' AND scope_branch = 'main'"

    export RALPH_AGENT_ID="wrong-agent"
    run "$SCRIPT_DIR/lib/task" renew "renew-flag-01" --agent "agentX"
    assert_success
    assert_output "renewed renew-flag-01"
}

@test "task renew via claim and renew workflow" {
    "$SCRIPT_DIR/lib/task" create "renew-flow-01" "Flow Task" -p 0

    export RALPH_AGENT_ID="flow-agent"
    local claim_output
    claim_output=$("$SCRIPT_DIR/lib/task" claim --agent "flow-agent")

    run "$SCRIPT_DIR/lib/task" renew "renew-flow-01"
    assert_success
    assert_output "renewed renew-flow-01"
}

# ---------------------------------------------------------------------------
# Special characters
# ---------------------------------------------------------------------------
@test "task renew handles special characters in task ID" {
    "$SCRIPT_DIR/lib/task" create "renew/special-01" "Special ID Task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status = 'active', assignee = 'agent1', lease_expires_at = datetime('now', '+60 seconds') WHERE slug = 'renew/special-01' AND scope_repo = 'test/repo' AND scope_branch = 'main'"

    export RALPH_AGENT_ID="agent1"
    run "$SCRIPT_DIR/lib/task" renew "renew/special-01"
    assert_success
    assert_output "renewed renew/special-01"
}
