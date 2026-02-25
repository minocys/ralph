#!/usr/bin/env bats
# test/task_done.bats — Tests for the task done command
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
@test "task done without args exits 1 with error" {
    run "$SCRIPT_DIR/lib/task" done
    assert_failure
    assert_output --partial "Error: missing task ID"
}

# ---------------------------------------------------------------------------
# Not found
# ---------------------------------------------------------------------------
@test "task done on nonexistent task exits 2" {
    run "$SCRIPT_DIR/lib/task" done "nonexistent"
    assert_failure
    [ "$status" -eq 2 ]
    assert_output --partial "Error: task 'nonexistent' not found"
}

# ---------------------------------------------------------------------------
# Status validation
# ---------------------------------------------------------------------------
@test "task done on open task exits 1" {
    "$SCRIPT_DIR/lib/task" create "td-01" "Open task"
    run "$SCRIPT_DIR/lib/task" done "td-01"
    assert_failure
    [ "$status" -eq 1 ]
    assert_output --partial "is not active"
}

@test "task done on already done task exits 1" {
    "$SCRIPT_DIR/lib/task" create "td-02" "Task to complete"
    # Set status to active directly
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-02' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null
    "$SCRIPT_DIR/lib/task" done "td-02"

    # Try marking done again
    run "$SCRIPT_DIR/lib/task" done "td-02"
    assert_failure
    [ "$status" -eq 1 ]
    assert_output --partial "is not active"
}

# ---------------------------------------------------------------------------
# Successful done
# ---------------------------------------------------------------------------
@test "task done on active task succeeds" {
    "$SCRIPT_DIR/lib/task" create "td-03" "Active task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-03' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    run "$SCRIPT_DIR/lib/task" done "td-03"
    assert_success
    assert_output "done td-03"
}

@test "task done sets status to done" {
    "$SCRIPT_DIR/lib/task" create "td-04" "Active task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-04' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    "$SCRIPT_DIR/lib/task" done "td-04"

    local task_status
    task_status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE slug='td-04' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$task_status" = "done" ]
}

@test "task done sets updated_at" {
    "$SCRIPT_DIR/lib/task" create "td-05" "Active task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1', updated_at=NULL WHERE slug='td-05' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    "$SCRIPT_DIR/lib/task" done "td-05"

    local updated
    updated=$(psql "$RALPH_DB_URL" -tAX -c "SELECT updated_at FROM tasks WHERE slug='td-05' AND scope_repo='test/repo' AND scope_branch='main';")
    [ -n "$updated" ]
}

# ---------------------------------------------------------------------------
# Result JSON
# ---------------------------------------------------------------------------
@test "task done with --result stores JSONB" {
    "$SCRIPT_DIR/lib/task" create "td-06" "Task with result"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-06' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    run "$SCRIPT_DIR/lib/task" done "td-06" --result '{"commit":"abc123","output":"success","files":["a.txt"]}'
    assert_success
    assert_output "done td-06"

    local result
    result=$(psql "$RALPH_DB_URL" -tAX -c "SELECT result->>'output' FROM tasks WHERE slug='td-06' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$result" = "success" ]
}

@test "task done with --result missing commit key exits 1" {
    "$SCRIPT_DIR/lib/task" create "td-06b" "Task missing commit"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-06b' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    run "$SCRIPT_DIR/lib/task" done "td-06b" --result '{"output":"success"}'
    assert_failure
    [ "$status" -eq 1 ]
    assert_output --partial "result JSON must include a 'commit' key"
}

@test "task done with --result commit null exits 1" {
    "$SCRIPT_DIR/lib/task" create "td-06c" "Task commit null"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-06c' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    run "$SCRIPT_DIR/lib/task" done "td-06c" --result '{"commit":null}'
    assert_failure
    [ "$status" -eq 1 ]
    assert_output --partial "result JSON must include a 'commit' key"
}

@test "task done commit key validation via claim flow" {
    export RALPH_AGENT_ID="agent-test"

    # Step 1: Create a task and claim it
    "$SCRIPT_DIR/lib/task" create "td-commit-e2e" "Commit key e2e test"
    run "$SCRIPT_DIR/lib/task" claim "td-commit-e2e"
    assert_success
    assert_output --partial "td-commit-e2e"

    # Step 2-3: Call task done with result JSON missing commit key → fails
    run "$SCRIPT_DIR/lib/task" done "td-commit-e2e" --result '{"output":"no commit here"}'
    assert_failure
    [ "$status" -eq 1 ]
    assert_output --partial "result JSON must include a 'commit' key"

    # Step 4-5: Call task done with result JSON containing commit key → succeeds
    run "$SCRIPT_DIR/lib/task" done "td-commit-e2e" --result '{"commit":"abc123"}'
    assert_success
    assert_output "done td-commit-e2e"
}

@test "task done without --result stores no result" {
    "$SCRIPT_DIR/lib/task" create "td-07" "Task without result"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-07' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    "$SCRIPT_DIR/lib/task" done "td-07"

    local result
    result=$(psql "$RALPH_DB_URL" -tAX -c "SELECT result FROM tasks WHERE slug='td-07' AND scope_repo='test/repo' AND scope_branch='main';")
    [ -z "$result" ]
}

# ---------------------------------------------------------------------------
# Integration: done unblocks downstream
# ---------------------------------------------------------------------------
@test "task done implicitly unblocks downstream tasks for claim" {
    export RALPH_AGENT_ID="agent-test"

    # Create blocker and downstream
    "$SCRIPT_DIR/lib/task" create "td-blocker" "Blocker task" -p 1
    "$SCRIPT_DIR/lib/task" create "td-downstream" "Downstream task" -p 1 --deps "td-blocker"

    # Downstream should not be claimable while blocker is open
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-test' WHERE slug='td-blocker' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null
    run "$SCRIPT_DIR/lib/task" claim
    assert_failure
    [ "$status" -eq 2 ]

    # Complete the blocker
    "$SCRIPT_DIR/lib/task" done "td-blocker" --result '{"commit":"abc123","ok":true}'

    # Now downstream should be claimable
    run "$SCRIPT_DIR/lib/task" claim
    assert_success
    assert_output --partial "td-downstream"
}

# ---------------------------------------------------------------------------
# Integration with show
# ---------------------------------------------------------------------------
@test "task done result is visible in show output" {
    "$SCRIPT_DIR/lib/task" create "td-08" "Task to show"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-08' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    "$SCRIPT_DIR/lib/task" done "td-08" --result '{"commit":"abc123","summary":"all good"}'

    run "$SCRIPT_DIR/lib/task" show "td-08"
    assert_success
    assert_output --partial "Status:      done"
    assert_output --partial "Result:"
    assert_output --partial "all good"
}

# ---------------------------------------------------------------------------
# Special characters
# ---------------------------------------------------------------------------
@test "task done works with special characters in task ID" {
    "$SCRIPT_DIR/lib/task" create "td/special-09" "Special ID task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td/special-09' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    run "$SCRIPT_DIR/lib/task" done "td/special-09"
    assert_success
    assert_output "done td/special-09"
}

@test "task done works with single quotes in task ID" {
    "$SCRIPT_DIR/lib/task" create "td'quoted" "Quoted ID task"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td''quoted' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    run "$SCRIPT_DIR/lib/task" done "td'quoted"
    assert_success
}

@test "task done with result containing special JSON characters" {
    "$SCRIPT_DIR/lib/task" create "td-10" "JSON special chars"
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-10' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    run "$SCRIPT_DIR/lib/task" done "td-10" --result '{"commit":"abc123","msg":"it'\''s \"working\""}'
    assert_success
}
