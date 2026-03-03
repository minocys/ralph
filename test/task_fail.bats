#!/usr/bin/env bats
# test/task_fail.bats — Tests for the task fail command

load test_helper

setup() {
    load test_helper
}

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
@test "task fail without args exits 1 with error" {
    run "$SCRIPT_DIR/lib/task" fail
    assert_failure
    assert_output --partial "Error: missing task ID"
}

# ---------------------------------------------------------------------------
# Not found
# ---------------------------------------------------------------------------
@test "task fail on nonexistent task exits 2" {
    run "$SCRIPT_DIR/lib/task" fail "nonexistent"
    assert_failure
    [ "$status" -eq 2 ]
    assert_output --partial "Error: task 'nonexistent' not found"
}

# ---------------------------------------------------------------------------
# Status validation
# ---------------------------------------------------------------------------
@test "task fail on open task exits 1" {
    "$SCRIPT_DIR/lib/task" create "tf-01" "Open task"
    run "$SCRIPT_DIR/lib/task" fail "tf-01"
    assert_failure
    [ "$status" -eq 1 ]
    assert_output --partial "is not active"
}

@test "task fail on done task exits 1" {
    "$SCRIPT_DIR/lib/task" create "tf-02" "Done task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status='done' WHERE slug='tf-02' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/lib/task" fail "tf-02"
    assert_failure
    [ "$status" -eq 1 ]
    assert_output --partial "is not active"
}

# ---------------------------------------------------------------------------
# Successful fail
# ---------------------------------------------------------------------------
@test "task fail on active task succeeds" {
    "$SCRIPT_DIR/lib/task" create "tf-03" "Active task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='tf-03' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/lib/task" fail "tf-03"
    assert_success
    assert_output "failed tf-03"
}

@test "task fail sets status back to open" {
    "$SCRIPT_DIR/lib/task" create "tf-04" "Active task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='tf-04' AND scope_repo='test/repo' AND scope_branch='main';"

    "$SCRIPT_DIR/lib/task" fail "tf-04"

    local task_status
    task_status=$(sqlite3 "$RALPH_DB_PATH" "SELECT status FROM tasks WHERE slug='tf-04' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$task_status" = "open" ]
}

@test "task fail clears assignee" {
    "$SCRIPT_DIR/lib/task" create "tf-05" "Active task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='tf-05' AND scope_repo='test/repo' AND scope_branch='main';"

    "$SCRIPT_DIR/lib/task" fail "tf-05"

    local assignee
    assignee=$(sqlite3 "$RALPH_DB_PATH" "SELECT assignee FROM tasks WHERE slug='tf-05' AND scope_repo='test/repo' AND scope_branch='main';")
    [ -z "$assignee" ]
}

@test "task fail clears lease_expires_at" {
    "$SCRIPT_DIR/lib/task" create "tf-06" "Active task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1', lease_expires_at=datetime('now','+600 seconds') WHERE slug='tf-06' AND scope_repo='test/repo' AND scope_branch='main';"

    "$SCRIPT_DIR/lib/task" fail "tf-06"

    local lease
    lease=$(sqlite3 "$RALPH_DB_PATH" "SELECT lease_expires_at FROM tasks WHERE slug='tf-06' AND scope_repo='test/repo' AND scope_branch='main';")
    [ -z "$lease" ]
}

@test "task fail increments retry_count" {
    "$SCRIPT_DIR/lib/task" create "tf-07" "Active task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1', retry_count=0 WHERE slug='tf-07' AND scope_repo='test/repo' AND scope_branch='main';"

    "$SCRIPT_DIR/lib/task" fail "tf-07"

    local retry_count
    retry_count=$(sqlite3 "$RALPH_DB_PATH" "SELECT retry_count FROM tasks WHERE slug='tf-07' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$retry_count" -eq 1 ]
}

@test "task fail increments retry_count cumulatively" {
    "$SCRIPT_DIR/lib/task" create "tf-08" "Active task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1', retry_count=3 WHERE slug='tf-08' AND scope_repo='test/repo' AND scope_branch='main';"

    "$SCRIPT_DIR/lib/task" fail "tf-08"

    local retry_count
    retry_count=$(sqlite3 "$RALPH_DB_PATH" "SELECT retry_count FROM tasks WHERE slug='tf-08' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$retry_count" -eq 4 ]
}

@test "task fail sets updated_at" {
    "$SCRIPT_DIR/lib/task" create "tf-09" "Active task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1', updated_at=NULL WHERE slug='tf-09' AND scope_repo='test/repo' AND scope_branch='main';"

    "$SCRIPT_DIR/lib/task" fail "tf-09"

    local updated
    updated=$(sqlite3 "$RALPH_DB_PATH" "SELECT updated_at FROM tasks WHERE slug='tf-09' AND scope_repo='test/repo' AND scope_branch='main';")
    [ -n "$updated" ]
}

# ---------------------------------------------------------------------------
# --reason flag
# ---------------------------------------------------------------------------
@test "task fail with --reason succeeds" {
    "$SCRIPT_DIR/lib/task" create "tf-10" "Active task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='tf-10' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/lib/task" fail "tf-10" --reason "out of memory"
    assert_success
    assert_output "failed tf-10"
}

@test "task fail with --reason persists reason in database" {
    "$SCRIPT_DIR/lib/task" create "tf-10a" "Active task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='tf-10a' AND scope_repo='test/repo' AND scope_branch='main';"

    "$SCRIPT_DIR/lib/task" fail "tf-10a" --reason "out of memory"

    local fail_reason
    fail_reason=$(sqlite3 "$RALPH_DB_PATH" "SELECT fail_reason FROM tasks WHERE slug='tf-10a' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$fail_reason" = "out of memory" ]
}

@test "task fail without --reason stores NULL fail_reason" {
    "$SCRIPT_DIR/lib/task" create "tf-10b" "Active task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='tf-10b' AND scope_repo='test/repo' AND scope_branch='main';"

    "$SCRIPT_DIR/lib/task" fail "tf-10b"

    local fail_reason
    fail_reason=$(sqlite3 "$RALPH_DB_PATH" "SELECT fail_reason FROM tasks WHERE slug='tf-10b' AND scope_repo='test/repo' AND scope_branch='main';")
    [ -z "$fail_reason" ]
}

# ---------------------------------------------------------------------------
# Integration: failed task is re-claimable
# ---------------------------------------------------------------------------
@test "failed task can be re-claimed" {
    export RALPH_AGENT_ID="agent-test"

    "$SCRIPT_DIR/lib/task" create "tf-11" "Re-claimable task" -p 1

    # Claim the task
    run "$SCRIPT_DIR/lib/task" claim
    assert_success
    assert_output --partial "tf-11"

    # Fail it
    "$SCRIPT_DIR/lib/task" fail "tf-11"

    # Should be claimable again
    run "$SCRIPT_DIR/lib/task" claim
    assert_success
    assert_output --partial "tf-11"
}

@test "failed task retry_count increments through claim-fail cycle" {
    export RALPH_AGENT_ID="agent-test"

    "$SCRIPT_DIR/lib/task" create "tf-12" "Retry task" -p 1

    # First claim-fail cycle
    "$SCRIPT_DIR/lib/task" claim >/dev/null
    "$SCRIPT_DIR/lib/task" fail "tf-12"

    local retry1
    retry1=$(sqlite3 "$RALPH_DB_PATH" "SELECT retry_count FROM tasks WHERE slug='tf-12' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$retry1" -eq 1 ]

    # Second claim-fail cycle
    "$SCRIPT_DIR/lib/task" claim >/dev/null
    "$SCRIPT_DIR/lib/task" fail "tf-12"

    local retry2
    retry2=$(sqlite3 "$RALPH_DB_PATH" "SELECT retry_count FROM tasks WHERE slug='tf-12' AND scope_repo='test/repo' AND scope_branch='main';")
    [ "$retry2" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Special characters
# ---------------------------------------------------------------------------
@test "task fail works with special characters in task ID" {
    "$SCRIPT_DIR/lib/task" create "tf/special-13" "Special ID task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='tf/special-13' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/lib/task" fail "tf/special-13"
    assert_success
    assert_output "failed tf/special-13"
}

@test "task fail works with single quotes in task ID" {
    "$SCRIPT_DIR/lib/task" create "tf'quoted" "Quoted ID task"
    sqlite3 "$RALPH_DB_PATH" "UPDATE tasks SET status='active', assignee='agent-1' WHERE slug='tf''quoted' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/lib/task" fail "tf'quoted"
    assert_success
}
