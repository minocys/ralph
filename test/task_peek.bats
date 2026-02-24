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
    run "$SCRIPT_DIR/lib/task" list
    assert_success

    run "$SCRIPT_DIR/lib/task" peek
    assert_success
    assert_output ""
}

# ---------------------------------------------------------------------------
# Claimable tasks as markdown-KV
# ---------------------------------------------------------------------------
@test "task peek returns claimable tasks as markdown-KV with status: open" {
    "$SCRIPT_DIR/lib/task" create "t-a" "Task A" -p 1
    "$SCRIPT_DIR/lib/task" create "t-b" "Task B" -p 2

    run "$SCRIPT_DIR/lib/task" peek
    assert_success

    # Should have 2 task sections
    local section_count
    section_count=$(echo "$output" | grep -c '^## Task ')
    [[ "$section_count" -eq 2 ]]

    # Each section should have status: open
    echo "$output" | grep -q '^status: open'
    local status_count
    status_count=$(echo "$output" | grep -c '^status: open')
    [[ "$status_count" -eq 2 ]]
}

# ---------------------------------------------------------------------------
# Active tasks
# ---------------------------------------------------------------------------
@test "task peek returns active tasks with status: active and assignee" {
    "$SCRIPT_DIR/lib/task" create "t-act" "Active task" -p 0

    # Claim to make it active
    "$SCRIPT_DIR/lib/task" claim --agent "a1b2" >/dev/null

    run "$SCRIPT_DIR/lib/task" peek
    assert_success

    # Should have an active section
    echo "$output" | grep -q '^status: active'

    # Active section should include assignee
    echo "$output" | grep -q '^assignee: a1b2'
}

# ---------------------------------------------------------------------------
# Sort order
# ---------------------------------------------------------------------------
@test "task peek sorts claimable by priority ASC then created_at ASC" {
    "$SCRIPT_DIR/lib/task" create "t-p2" "Priority 2" -p 2
    sleep 0.1
    "$SCRIPT_DIR/lib/task" create "t-p0" "Priority 0" -p 0
    sleep 0.1
    "$SCRIPT_DIR/lib/task" create "t-p1" "Priority 1" -p 1

    run "$SCRIPT_DIR/lib/task" peek
    assert_success

    # Extract task IDs in order from ## Task headers
    local ids
    ids=$(echo "$output" | grep '^## Task ' | sed 's/^## Task //')

    local first_id second_id third_id
    first_id=$(echo "$ids" | sed -n '1p')
    second_id=$(echo "$ids" | sed -n '2p')
    third_id=$(echo "$ids" | sed -n '3p')

    [[ "$first_id" == "t-p0" ]]
    [[ "$second_id" == "t-p1" ]]
    [[ "$third_id" == "t-p2" ]]
}

# ---------------------------------------------------------------------------
# Markdown-KV keys
# ---------------------------------------------------------------------------
@test "task peek uses full key names in markdown-KV output" {
    "$SCRIPT_DIR/lib/task" create "t-keys" "Key test" -p 1 -c feat -d "A description"

    run "$SCRIPT_DIR/lib/task" peek
    assert_success

    # Verify full key names present
    echo "$output" | grep -q '^## Task t-keys'
    echo "$output" | grep -q '^id: t-keys'
    echo "$output" | grep -q '^title: Key test'
    echo "$output" | grep -q '^priority: 1'
    echo "$output" | grep -q '^status: open'
    echo "$output" | grep -q '^category: feat'
}

# ---------------------------------------------------------------------------
# N limit
# ---------------------------------------------------------------------------
@test "task peek -n 2 limits claimable tasks to 2" {
    for i in 1 2 3 4 5; do
        "$SCRIPT_DIR/lib/task" create "t-$i" "Task $i" -p 1
    done

    run "$SCRIPT_DIR/lib/task" peek -n 2
    assert_success

    # Count task sections with status: open — should be exactly 2
    local open_count
    open_count=$(echo "$output" | grep -c '^status: open')
    [[ "$open_count" -eq 2 ]]
}

@test "task peek default N is 5" {
    for i in 1 2 3 4 5 6 7 8; do
        "$SCRIPT_DIR/lib/task" create "t-$i" "Task $i" -p 1
    done

    run "$SCRIPT_DIR/lib/task" peek
    assert_success

    # Count claimable sections — should be exactly 5
    local open_count
    open_count=$(echo "$output" | grep -c '^status: open')
    [[ "$open_count" -eq 5 ]]
}

@test "task peek active tasks are not limited by N" {
    # Create 4 tasks: 3 will be claimed (active), 1 remains open
    "$SCRIPT_DIR/lib/task" create "t-open" "Open task" -p 0
    "$SCRIPT_DIR/lib/task" create "t-act1" "Active 1" -p 1
    "$SCRIPT_DIR/lib/task" create "t-act2" "Active 2" -p 2
    "$SCRIPT_DIR/lib/task" create "t-act3" "Active 3" -p 3

    # Claim 3 tasks to make them active
    "$SCRIPT_DIR/lib/task" claim --agent "agnt" >/dev/null
    "$SCRIPT_DIR/lib/task" claim --agent "agnt" >/dev/null
    "$SCRIPT_DIR/lib/task" claim --agent "agnt" >/dev/null

    # Peek with -n 1: should get 1 claimable + all 3 active
    run "$SCRIPT_DIR/lib/task" peek -n 1
    assert_success

    local open_count
    open_count=$(echo "$output" | grep -c '^status: open')
    [[ "$open_count" -eq 1 ]]

    local active_count
    active_count=$(echo "$output" | grep -c '^status: active')
    [[ "$active_count" -eq 3 ]]

    # Total task sections should be 4
    local total_sections
    total_sections=$(echo "$output" | grep -c '^## Task ')
    [[ "$total_sections" -eq 4 ]]
}

# ---------------------------------------------------------------------------
# Blocked tasks
# ---------------------------------------------------------------------------
@test "task peek excludes blocked tasks from claimable" {
    "$SCRIPT_DIR/lib/task" create "t-blocker" "Blocker" -p 0
    "$SCRIPT_DIR/lib/task" create "t-blocked" "Blocked" -p 0
    "$SCRIPT_DIR/lib/task" block "t-blocked" --by "t-blocker"

    run "$SCRIPT_DIR/lib/task" peek
    assert_success

    # Only t-blocker should appear
    echo "$output" | grep -q '^id: t-blocker'

    # t-blocked should NOT appear
    ! echo "$output" | grep -q '^id: t-blocked'
}

# ---------------------------------------------------------------------------
# Expired lease eligibility
# ---------------------------------------------------------------------------
@test "task peek includes active-with-expired-lease as claimable (status: open)" {
    "$SCRIPT_DIR/lib/task" create "t-expired" "Expired lease" -p 0

    # Claim with a 1-second lease
    "$SCRIPT_DIR/lib/task" claim --agent "agnt" --lease 1 >/dev/null

    # Wait for lease to expire
    sleep 2

    run "$SCRIPT_DIR/lib/task" peek
    assert_success

    # Should appear as claimable with status: open
    echo "$output" | grep -q '^## Task t-expired'
    echo "$output" | grep -q '^status: open'
}

# ---------------------------------------------------------------------------
# Non-locking (no FOR UPDATE)
# ---------------------------------------------------------------------------
@test "task peek does not modify task state (non-locking read)" {
    "$SCRIPT_DIR/lib/task" create "t-nl1" "Non-lock 1" -p 0
    "$SCRIPT_DIR/lib/task" create "t-nl2" "Non-lock 2" -p 1

    # Run peek
    run "$SCRIPT_DIR/lib/task" peek
    assert_success

    # Verify tasks are still status=open in DB
    local db_status
    db_status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE slug='t-nl1' AND scope_repo='test/repo' AND scope_branch='main'")
    [[ "$db_status" == "open" ]]

    db_status=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE slug='t-nl2' AND scope_repo='test/repo' AND scope_branch='main'")
    [[ "$db_status" == "open" ]]

    # Verify assignee is still NULL
    local db_assignee
    db_assignee=$(psql "$RALPH_DB_URL" -tAX -c "SELECT assignee FROM tasks WHERE slug='t-nl1' AND scope_repo='test/repo' AND scope_branch='main'")
    [[ -z "$db_assignee" ]]
}

# ---------------------------------------------------------------------------
# Blank line separation between task sections
# ---------------------------------------------------------------------------
@test "task peek separates task sections with blank lines" {
    "$SCRIPT_DIR/lib/task" create "t-sep1" "Sep 1" -p 0
    "$SCRIPT_DIR/lib/task" create "t-sep2" "Sep 2" -p 1

    run "$SCRIPT_DIR/lib/task" peek
    assert_success

    # There should be a blank line between sections
    # The second ## Task should be preceded by a blank line
    echo "$output" | grep -qP '^\s*$' || echo "$output" | grep -q '^$'
}
