#!/usr/bin/env bats
# test/task_done.bats — Tests for the task done command

load test_helper

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
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-02' AND scope_repo='test/repo' AND scope_branch='main';"
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
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-03' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/lib/task" done "td-03"
    assert_success
    assert_output "done td-03"
}

@test "task done sets status to done" {
    "$SCRIPT_DIR/lib/task" create "td-04" "Active task"
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-04' AND scope_repo='test/repo' AND scope_branch='main';"

    "$SCRIPT_DIR/lib/task" done "td-04"

    local task_status
    task_status=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='td-04' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$task_status" = "done" ]
}

@test "task done sets updated_at" {
    "$SCRIPT_DIR/lib/task" create "td-05" "Active task"
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1', updated_at=NULL WHERE slug='td-05' AND scope_repo='test/repo' AND scope_branch='main';"

    "$SCRIPT_DIR/lib/task" done "td-05"

    local updated
    updated=$(sqlite3 "$TEST_DB_PATH" "SELECT updated_at FROM tasks WHERE slug='td-05' AND scope_repo='test/repo' AND scope_branch='main';")
    [ -n "$updated" ]
}

# ---------------------------------------------------------------------------
# Result JSON
# ---------------------------------------------------------------------------
@test "task done with --result stores JSON" {
    "$SCRIPT_DIR/lib/task" create "td-06" "Task with result"
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-06' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/lib/task" done "td-06" --result '{"commit":"abc123","output":"success","files":["a.txt"]}'
    assert_success
    assert_output "done td-06"

    local result
    result=$(sqlite3 "$TEST_DB_PATH" "SELECT json_extract(result, '\$.output') FROM tasks WHERE slug='td-06' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$result" = "success" ]
}

@test "task done with --result missing commit key exits 1" {
    "$SCRIPT_DIR/lib/task" create "td-06b" "Task missing commit"
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-06b' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/lib/task" done "td-06b" --result '{"output":"success"}'
    assert_failure
    [ "$status" -eq 1 ]
    assert_output --partial "result JSON must include a 'commit' key"
}

@test "task done with --result commit null exits 1" {
    "$SCRIPT_DIR/lib/task" create "td-06c" "Task commit null"
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-06c' AND scope_repo='test/repo' AND scope_branch='main';"

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

    # Step 2-3: Call task done with result JSON missing commit key -> fails
    run "$SCRIPT_DIR/lib/task" done "td-commit-e2e" --result '{"output":"no commit here"}'
    assert_failure
    [ "$status" -eq 1 ]
    assert_output --partial "result JSON must include a 'commit' key"

    # Step 4-5: Call task done with result JSON containing commit key -> succeeds
    run "$SCRIPT_DIR/lib/task" done "td-commit-e2e" --result '{"commit":"abc123"}'
    assert_success
    assert_output "done td-commit-e2e"
}

@test "task done without --result stores no result" {
    "$SCRIPT_DIR/lib/task" create "td-07" "Task without result"
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-07' AND scope_repo='test/repo' AND scope_branch='main';"

    "$SCRIPT_DIR/lib/task" done "td-07"

    local result
    result=$(sqlite3 "$TEST_DB_PATH" "SELECT result FROM tasks WHERE slug='td-07' AND scope_repo='test/repo' AND scope_branch='main';")
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
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-test' WHERE slug='td-blocker' AND scope_repo='test/repo' AND scope_branch='main';"
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
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-08' AND scope_repo='test/repo' AND scope_branch='main';"

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
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td/special-09' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/lib/task" done "td/special-09"
    assert_success
    assert_output "done td/special-09"
}

@test "task done works with single quotes in task ID" {
    "$SCRIPT_DIR/lib/task" create "td'quoted" "Quoted ID task"
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td''quoted' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/lib/task" done "td'quoted"
    assert_success
}

@test "task done with result containing special JSON characters" {
    "$SCRIPT_DIR/lib/task" create "td-10" "JSON special chars"
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='td-10' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/lib/task" done "td-10" --result '{"commit":"abc123","msg":"it'\''s \"working\""}'
    assert_success
}
