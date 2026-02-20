#!/usr/bin/env bats
# test/task_peek.bats — Tests for the task peek command
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
# Empty state
# ---------------------------------------------------------------------------
@test "task peek with no tasks exits 0 with empty output" {
    # Ensure schema exists (list triggers ensure_schema)
    run "$SCRIPT_DIR/task" list
    assert_success

    run "$SCRIPT_DIR/task" peek
    assert_success
    assert_output ""
}

# ---------------------------------------------------------------------------
# Claimable tasks as JSONL
# ---------------------------------------------------------------------------
@test "task peek returns claimable tasks as JSONL with s=open" {
    "$SCRIPT_DIR/task" create "t-a" "Task A" -p 1
    "$SCRIPT_DIR/task" create "t-b" "Task B" -p 2

    run "$SCRIPT_DIR/task" peek
    assert_success

    # Should have 2 lines of JSONL
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    [[ "$line_count" -eq 2 ]]

    # Each line should be valid JSON with s='open'
    echo "$output" | while IFS= read -r line; do
        echo "$line" | jq -e '.s == "open"'
    done
}

# ---------------------------------------------------------------------------
# Active tasks
# ---------------------------------------------------------------------------
@test "task peek returns active tasks with s=active and assignee" {
    "$SCRIPT_DIR/task" create "t-act" "Active task" -p 0

    # Claim to make it active
    "$SCRIPT_DIR/task" claim --agent "a1b2" >/dev/null

    run "$SCRIPT_DIR/task" peek
    assert_success

    # Should have 1 active line
    local active_line
    active_line=$(echo "$output" | jq -r 'select(.s == "active")')
    [[ -n "$active_line" ]]

    echo "$output" | jq -e 'select(.s == "active") | .assignee == "a1b2"'
}

# ---------------------------------------------------------------------------
# Sort order
# ---------------------------------------------------------------------------
@test "task peek sorts claimable by priority ASC then created_at ASC" {
    "$SCRIPT_DIR/task" create "t-p2" "Priority 2" -p 2
    sleep 0.1
    "$SCRIPT_DIR/task" create "t-p0" "Priority 0" -p 0
    sleep 0.1
    "$SCRIPT_DIR/task" create "t-p1" "Priority 1" -p 1

    run "$SCRIPT_DIR/task" peek
    assert_success

    # First claimable line should be the p=0 task
    local first_id
    first_id=$(echo "$output" | head -1 | jq -r '.id')
    [[ "$first_id" == "t-p0" ]]

    # Second should be p=1, third should be p=2
    local second_id
    second_id=$(echo "$output" | sed -n '2p' | jq -r '.id')
    [[ "$second_id" == "t-p1" ]]

    local third_id
    third_id=$(echo "$output" | sed -n '3p' | jq -r '.id')
    [[ "$third_id" == "t-p2" ]]
}

# ---------------------------------------------------------------------------
# Short keys
# ---------------------------------------------------------------------------
@test "task peek uses short keys in JSONL output" {
    "$SCRIPT_DIR/task" create "t-keys" "Key test" -p 1 -c feat -d "A description"

    run "$SCRIPT_DIR/task" peek
    assert_success

    # Verify short keys present
    echo "$output" | head -1 | jq -e 'has("id")'
    echo "$output" | head -1 | jq -e 'has("t")'
    echo "$output" | head -1 | jq -e 'has("p")'
    echo "$output" | head -1 | jq -e 'has("s")'
    echo "$output" | head -1 | jq -e 'has("cat")'
    echo "$output" | head -1 | jq -e 'has("deps")'
}

# ---------------------------------------------------------------------------
# N limit
# ---------------------------------------------------------------------------
@test "task peek -n 2 limits claimable tasks to 2" {
    for i in 1 2 3 4 5; do
        "$SCRIPT_DIR/task" create "t-$i" "Task $i" -p 1
    done

    run "$SCRIPT_DIR/task" peek -n 2
    assert_success

    # Count lines with s='open' — should be exactly 2
    local open_count
    open_count=$(echo "$output" | jq -r 'select(.s == "open")' | jq -s 'length')
    [[ "$open_count" -eq 2 ]]
}

@test "task peek default N is 5" {
    for i in 1 2 3 4 5 6 7 8; do
        "$SCRIPT_DIR/task" create "t-$i" "Task $i" -p 1
    done

    run "$SCRIPT_DIR/task" peek
    assert_success

    # Count claimable lines — should be exactly 5
    local open_count
    open_count=$(echo "$output" | jq -r 'select(.s == "open")' | jq -s 'length')
    [[ "$open_count" -eq 5 ]]
}

@test "task peek active tasks are not limited by N" {
    # Create 4 tasks: 3 will be claimed (active), 1 remains open
    "$SCRIPT_DIR/task" create "t-open" "Open task" -p 0
    "$SCRIPT_DIR/task" create "t-act1" "Active 1" -p 1
    "$SCRIPT_DIR/task" create "t-act2" "Active 2" -p 2
    "$SCRIPT_DIR/task" create "t-act3" "Active 3" -p 3

    # Claim 3 tasks to make them active
    "$SCRIPT_DIR/task" claim --agent "agnt" >/dev/null
    "$SCRIPT_DIR/task" claim --agent "agnt" >/dev/null
    "$SCRIPT_DIR/task" claim --agent "agnt" >/dev/null

    # Peek with -n 1: should get 1 claimable + all 3 active
    run "$SCRIPT_DIR/task" peek -n 1
    assert_success

    local open_count
    open_count=$(echo "$output" | jq -r 'select(.s == "open")' | jq -s 'length')
    [[ "$open_count" -eq 1 ]]

    local active_count
    active_count=$(echo "$output" | jq -r 'select(.s == "active")' | jq -s 'length')
    [[ "$active_count" -eq 3 ]]

    # Total lines should be 4
    local total_lines
    total_lines=$(echo "$output" | wc -l | tr -d ' ')
    [[ "$total_lines" -eq 4 ]]
}

# ---------------------------------------------------------------------------
# Blocked tasks
# ---------------------------------------------------------------------------
@test "task peek excludes blocked tasks from claimable" {
    "$SCRIPT_DIR/task" create "t-blocker" "Blocker" -p 0
    "$SCRIPT_DIR/task" create "t-blocked" "Blocked" -p 0
    "$SCRIPT_DIR/task" block "t-blocked" --by "t-blocker"

    run "$SCRIPT_DIR/task" peek
    assert_success

    # Only t-blocker should appear as claimable
    local claimable_ids
    claimable_ids=$(echo "$output" | jq -r 'select(.s == "open") | .id')
    [[ "$claimable_ids" == "t-blocker" ]]

    # t-blocked should NOT appear
    echo "$output" | jq -r '.id' | while IFS= read -r id; do
        [[ "$id" != "t-blocked" ]]
    done
}

# ---------------------------------------------------------------------------
# Expired lease eligibility
# ---------------------------------------------------------------------------
@test "task peek includes active-with-expired-lease as claimable (s=open)" {
    "$SCRIPT_DIR/task" create "t-expired" "Expired lease" -p 0

    # Claim with a 1-second lease
    "$SCRIPT_DIR/task" claim --agent "agnt" --lease 1 >/dev/null

    # Wait for lease to expire
    sleep 2

    run "$SCRIPT_DIR/task" peek
    assert_success

    # Should appear as claimable with s='open'
    echo "$output" | jq -e 'select(.id == "t-expired") | .s == "open"'
}

# ---------------------------------------------------------------------------
# Non-locking (no FOR UPDATE)
# ---------------------------------------------------------------------------
@test "task peek does not modify task state (non-locking read)" {
    "$SCRIPT_DIR/task" create "t-nl1" "Non-lock 1" -p 0
    "$SCRIPT_DIR/task" create "t-nl2" "Non-lock 2" -p 1

    # Run peek
    run "$SCRIPT_DIR/task" peek
    assert_success

    # Verify tasks are still status=open in DB
    local db_status
    db_status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE id='t-nl1'")
    [[ "$db_status" == "open" ]]

    db_status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE id='t-nl2'")
    [[ "$db_status" == "open" ]]

    # Verify assignee is still NULL
    local db_assignee
    db_assignee=$(psql "$RALPH_DB_URL" -tAX -c "SELECT assignee FROM tasks WHERE id='t-nl1'")
    [[ -z "$db_assignee" ]]
}
