#!/usr/bin/env bats
# test/hook_session_end.bats — Tests for the SessionEnd hook script
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
    export RALPH_TASK_SCRIPT="$SCRIPT_DIR/lib/task"
    export RALPH_AGENT_ID="a1b2"

    # Ensure schema is initialized by running a benign task command
    "$SCRIPT_DIR/lib/task" create "se-setup" "schema init" >/dev/null 2>&1
    psql "$RALPH_DB_URL" -tAX -c "DELETE FROM tasks WHERE slug='se-setup' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null 2>&1
}

teardown() {
    if [[ -n "${TEST_SCHEMA:-}" ]] && [[ -n "${RALPH_DB_URL_ORIG:-}" ]]; then
        psql "$RALPH_DB_URL_ORIG" -tAX -c "DROP SCHEMA IF EXISTS $TEST_SCHEMA CASCADE" >/dev/null 2>&1
    fi
    [[ -d "${TEST_WORK_DIR:-}" ]] && rm -rf "$TEST_WORK_DIR"
    [[ -d "${STUB_DIR:-}" ]] && rm -rf "$STUB_DIR"
}

# ---------------------------------------------------------------------------
# SessionEnd hook: active task exists for this agent
# ---------------------------------------------------------------------------
@test "session end hook calls task fail on active task" {
    "$SCRIPT_DIR/lib/task" create "se-01" "Active task for agent"
    psql "$RALPH_DB_URL" -tAX -c \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='se-01' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    run "$SCRIPT_DIR/hooks/session_end.sh"
    assert_success

    # Task status must be set back to open
    local task_status
    task_status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE slug='se-01' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$task_status" = "open" ]
}

# ---------------------------------------------------------------------------
# SessionEnd hook: ignores active tasks assigned to other agents
# ---------------------------------------------------------------------------
@test "session end hook ignores active tasks assigned to other agents" {
    "$SCRIPT_DIR/lib/task" create "se-03" "Task for other agent"
    psql "$RALPH_DB_URL" -tAX -c \
        "UPDATE tasks SET status='active', assignee='zz99' WHERE slug='se-03' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    run "$SCRIPT_DIR/hooks/session_end.sh"
    assert_success

    # Hook should not fail the other agent's task
    local task_status
    task_status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE slug='se-03' AND scope_repo='test/repo' AND scope_branch='main';")
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
    unset RALPH_DB_URL

    run "$SCRIPT_DIR/hooks/session_end.sh"
    assert_success
}

# ---------------------------------------------------------------------------
# SessionEnd hook: retry_count is incremented
# ---------------------------------------------------------------------------
@test "session end hook increments retry_count" {
    "$SCRIPT_DIR/lib/task" create "se-02" "Task to check retry_count"
    psql "$RALPH_DB_URL" -tAX -c \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='se-02' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    # Verify retry_count starts at 0
    local before
    before=$(psql "$RALPH_DB_URL" -tAX -c "SELECT retry_count FROM tasks WHERE slug='se-02' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$before" = "0" ]

    run "$SCRIPT_DIR/hooks/session_end.sh"
    assert_success

    # retry_count must be incremented
    local after
    after=$(psql "$RALPH_DB_URL" -tAX -c "SELECT retry_count FROM tasks WHERE slug='se-02' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$after" = "1" ]
}
