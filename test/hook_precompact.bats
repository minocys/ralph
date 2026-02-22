#!/usr/bin/env bats
# test/hook_precompact.bats — Tests for the PreCompact hook script
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

    # Set up hook environment variables
    export RALPH_TASK_SCRIPT="$SCRIPT_DIR/task"
    export RALPH_AGENT_ID="a1b2"

    # Ensure schema is initialized by running a benign task command
    "$SCRIPT_DIR/task" create "pc-setup" "schema init" >/dev/null 2>&1
    psql "$RALPH_DB_URL" -tAX -c "DELETE FROM tasks WHERE slug='pc-setup' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null 2>&1
}

teardown() {
    if [[ -n "${TEST_SCHEMA:-}" ]] && [[ -n "${RALPH_DB_URL_ORIG:-}" ]]; then
        psql "$RALPH_DB_URL_ORIG" -tAX -c "DROP SCHEMA IF EXISTS $TEST_SCHEMA CASCADE" >/dev/null 2>&1
    fi
    [[ -d "${TEST_WORK_DIR:-}" ]] && rm -rf "$TEST_WORK_DIR"
    [[ -d "${STUB_DIR:-}" ]] && rm -rf "$STUB_DIR"
}

# ---------------------------------------------------------------------------
# PreCompact hook: active task exists for this agent
# ---------------------------------------------------------------------------
@test "precompact hook outputs continue:false JSON when active task exists" {
    "$SCRIPT_DIR/task" create "pc-01" "Active task for agent"
    psql "$RALPH_DB_URL" -tAX -c \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='pc-01' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    run bash -c '"$SCRIPT_DIR/hooks/precompact.sh" 2>/dev/null'
    assert_success

    echo "$output"
    # stdout must be valid JSON with continue:false and stopReason
    echo "$output" | jq -e '.continue == false'
    echo "$output" | jq -e '.stopReason == "Context Limit Reached"'
}

@test "precompact hook calls task fail on active task" {
    "$SCRIPT_DIR/task" create "pc-02" "Active task to fail"
    psql "$RALPH_DB_URL" -tAX -c \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='pc-02' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    # Run hook (capture stderr for debugging, but don't assert on it)
    run "$SCRIPT_DIR/hooks/precompact.sh"
    assert_success

    # Task status must be set back to open
    local task_status
    task_status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE slug='pc-02' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$task_status" = "open" ]
}

# ---------------------------------------------------------------------------
# PreCompact hook: stderr warning and retry_count
# ---------------------------------------------------------------------------
@test "precompact hook logs stderr warning when failing active task" {
    "$SCRIPT_DIR/task" create "pc-03" "Task for warning test"
    psql "$RALPH_DB_URL" -tAX -c \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='pc-03' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    run bash -c '"$SCRIPT_DIR/hooks/precompact.sh" 2>"$TEST_WORK_DIR/stderr.txt"'
    assert_success

    local stderr_content
    stderr_content=$(cat "$TEST_WORK_DIR/stderr.txt")
    [[ "$stderr_content" == *"Warning"* ]]
    [[ "$stderr_content" == *"$RALPH_AGENT_ID"* ]]
    [[ "$stderr_content" == *"pc-03"* ]]
}

@test "precompact hook increments retry_count" {
    "$SCRIPT_DIR/task" create "pc-04" "Task to check retry_count"
    psql "$RALPH_DB_URL" -tAX -c \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='pc-04' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    # Verify retry_count starts at 0
    local before
    before=$(psql "$RALPH_DB_URL" -tAX -c "SELECT retry_count FROM tasks WHERE slug='pc-04' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$before" = "0" ]

    run "$SCRIPT_DIR/hooks/precompact.sh"
    assert_success

    # retry_count must be incremented
    local after
    after=$(psql "$RALPH_DB_URL" -tAX -c "SELECT retry_count FROM tasks WHERE slug='pc-04' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$after" = "1" ]
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
    unset RALPH_DB_URL

    run "$SCRIPT_DIR/hooks/precompact.sh"
    assert_success

    # Must still output continue:false JSON and exit 0
    echo "$output" | jq -e '.continue == true'
}
