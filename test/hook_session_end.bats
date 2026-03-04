#!/usr/bin/env bats
# test/hook_session_end.bats — Tests for the SessionEnd hook script

load test_helper

setup() {
    common_setup
    # Set up hook environment variables
    export RALPH_TASK_SCRIPT="$SCRIPT_DIR/lib/task"
    export RALPH_AGENT_ID="a1b2"
}

# ---------------------------------------------------------------------------
# SessionEnd hook: active task exists for this agent
# ---------------------------------------------------------------------------
@test "session end hook calls task fail on active task" {
    "$SCRIPT_DIR/lib/task" create "se-01" "Active task for agent"
    sqlite3 "$RALPH_DB_PATH" \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='se-01' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/hooks/session_end.sh"
    assert_success

    # Task status must be set back to open
    local task_status
    task_status=$(sqlite3 "$RALPH_DB_PATH" "SELECT status FROM tasks WHERE slug='se-01' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$task_status" = "open" ]
}

# ---------------------------------------------------------------------------
# SessionEnd hook: ignores active tasks assigned to other agents
# ---------------------------------------------------------------------------
@test "session end hook ignores active tasks assigned to other agents" {
    "$SCRIPT_DIR/lib/task" create "se-03" "Task for other agent"
    sqlite3 "$RALPH_DB_PATH" \
        "UPDATE tasks SET status='active', assignee='zz99' WHERE slug='se-03' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/hooks/session_end.sh"
    assert_success

    # Hook should not fail the other agent's task
    local task_status
    task_status=$(sqlite3 "$RALPH_DB_PATH" "SELECT status FROM tasks WHERE slug='se-03' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$task_status" = "active" ]
}

# ---------------------------------------------------------------------------
# SessionEnd hook: no active task for this agent
# ---------------------------------------------------------------------------
@test "session end hook is a no-op when no active task exists" {
    # No tasks created — DB is empty

    run "$SCRIPT_DIR/hooks/session_end.sh"
    assert_success
}

# ---------------------------------------------------------------------------
# SessionEnd hook: database unavailability
# ---------------------------------------------------------------------------
@test "session end hook handles database unavailability gracefully" {
    unset RALPH_DB_PATH

    run "$SCRIPT_DIR/hooks/session_end.sh"
    assert_success
}

# ---------------------------------------------------------------------------
# SessionEnd hook: retry_count is incremented
# ---------------------------------------------------------------------------
@test "session end hook increments retry_count" {
    "$SCRIPT_DIR/lib/task" create "se-02" "Task to check retry_count"
    sqlite3 "$RALPH_DB_PATH" \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='se-02' AND scope_repo='test/repo' AND scope_branch='main';"

    # Verify retry_count starts at 0
    local before
    before=$(sqlite3 "$RALPH_DB_PATH" "SELECT retry_count FROM tasks WHERE slug='se-02' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$before" = "0" ]

    run "$SCRIPT_DIR/hooks/session_end.sh"
    assert_success

    # retry_count must be incremented
    local after
    after=$(sqlite3 "$RALPH_DB_PATH" "SELECT retry_count FROM tasks WHERE slug='se-02' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$after" = "1" ]
}
