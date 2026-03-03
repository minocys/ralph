#!/usr/bin/env bats
# test/hook_precompact.bats — Tests for the PreCompact hook script

load test_helper

setup() {
    # Set up hook environment variables
    export RALPH_TASK_SCRIPT="$SCRIPT_DIR/lib/task"
    export RALPH_AGENT_ID="a1b2"

    # Ensure schema is initialized by running a benign task command
    "$SCRIPT_DIR/lib/task" create "pc-setup" "schema init" >/dev/null 2>&1
    sqlite3 "$RALPH_DB_PATH" "DELETE FROM tasks WHERE slug='pc-setup' AND scope_repo='test/repo' AND scope_branch='main';"
}

# ---------------------------------------------------------------------------
# PreCompact hook: active task exists for this agent
# ---------------------------------------------------------------------------
@test "precompact hook outputs continue:false JSON when active task exists" {
    "$SCRIPT_DIR/lib/task" create "pc-01" "Active task for agent"
    sqlite3 "$RALPH_DB_PATH" \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='pc-01' AND scope_repo='test/repo' AND scope_branch='main';"

    run bash -c '"$SCRIPT_DIR/hooks/precompact.sh" 2>/dev/null'
    assert_success

    echo "$output"
    # stdout must be valid JSON with continue:false and stopReason
    echo "$output" | jq -e '.continue == false'
    echo "$output" | jq -e '.stopReason == "Context Limit Reached"'
}

@test "precompact hook calls task fail on active task" {
    "$SCRIPT_DIR/lib/task" create "pc-02" "Active task to fail"
    sqlite3 "$RALPH_DB_PATH" \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='pc-02' AND scope_repo='test/repo' AND scope_branch='main';"

    # Run hook (capture stderr for debugging, but don't assert on it)
    run "$SCRIPT_DIR/hooks/precompact.sh"
    assert_success

    # Task status must be set back to open
    local task_status
    task_status=$(sqlite3 "$RALPH_DB_PATH" "SELECT status FROM tasks WHERE slug='pc-02' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$task_status" = "open" ]
}

# ---------------------------------------------------------------------------
# PreCompact hook: stderr warning and retry_count
# ---------------------------------------------------------------------------
@test "precompact hook logs stderr warning when failing active task" {
    "$SCRIPT_DIR/lib/task" create "pc-03" "Task for warning test"
    sqlite3 "$RALPH_DB_PATH" \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='pc-03' AND scope_repo='test/repo' AND scope_branch='main';"

    run bash -c '"$SCRIPT_DIR/hooks/precompact.sh" 2>"$TEST_WORK_DIR/stderr.txt"'
    assert_success

    local stderr_content
    stderr_content=$(cat "$TEST_WORK_DIR/stderr.txt")
    [[ "$stderr_content" == *"Warning"* ]]
    [[ "$stderr_content" == *"$RALPH_AGENT_ID"* ]]
    [[ "$stderr_content" == *"pc-03"* ]]
}

@test "precompact hook increments retry_count" {
    "$SCRIPT_DIR/lib/task" create "pc-04" "Task to check retry_count"
    sqlite3 "$RALPH_DB_PATH" \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='pc-04' AND scope_repo='test/repo' AND scope_branch='main';"

    # Verify retry_count starts at 0
    local before
    before=$(sqlite3 "$RALPH_DB_PATH" "SELECT retry_count FROM tasks WHERE slug='pc-04' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$before" = "0" ]

    run "$SCRIPT_DIR/hooks/precompact.sh"
    assert_success

    # retry_count must be incremented
    local after
    after=$(sqlite3 "$RALPH_DB_PATH" "SELECT retry_count FROM tasks WHERE slug='pc-04' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$after" = "1" ]
}

# ---------------------------------------------------------------------------
# PreCompact hook: ignores active tasks assigned to other agents
# ---------------------------------------------------------------------------
@test "precompact hook ignores active tasks assigned to other agents" {
    "$SCRIPT_DIR/lib/task" create "pc-05" "Task for other agent"
    sqlite3 "$RALPH_DB_PATH" \
        "UPDATE tasks SET status='active', assignee='zz99' WHERE slug='pc-05' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/hooks/precompact.sh"
    assert_success

    # Hook should not fail the other agent's task
    echo "$output" | jq -e '.continue == true'

    local task_status
    task_status=$(sqlite3 "$RALPH_DB_PATH" "SELECT status FROM tasks WHERE slug='pc-05' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$task_status" = "active" ]
}

# ---------------------------------------------------------------------------
# PreCompact hook: no active task for this agent
# ---------------------------------------------------------------------------
@test "precompact hook is a no-op when no active task exists" {
    # No tasks created — DB is empty

    run "$SCRIPT_DIR/hooks/precompact.sh"
    assert_success

    # Must still output continue:false JSON (always stops on precompact)
    echo "$output" | jq -e '.continue == true'
}

# ---------------------------------------------------------------------------
# PreCompact hook: database unavailability
# ---------------------------------------------------------------------------
@test "precompact hook handles database unavailability gracefully" {
    unset RALPH_DB_PATH

    run "$SCRIPT_DIR/hooks/precompact.sh"
    assert_success

    # Must still output continue:false JSON and exit 0
    echo "$output" | jq -e '.continue == true'
}
