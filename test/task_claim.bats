#!/usr/bin/env bats
# test/task_claim.bats — Tests for the task claim command
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
# No eligible tasks
# ---------------------------------------------------------------------------
@test "task claim with no tasks exits 2" {
    # Ensure schema exists but no tasks
    run "$SCRIPT_DIR/task" list
    assert_success

    run "$SCRIPT_DIR/task" claim
    assert_failure 2
    assert_output --partial "No eligible tasks"
}

# ---------------------------------------------------------------------------
# Basic claim
# ---------------------------------------------------------------------------
@test "task claim returns highest priority open task as JSON" {
    "$SCRIPT_DIR/task" create "t-low" "Low priority" -p 2
    "$SCRIPT_DIR/task" create "t-high" "High priority" -p 0

    run "$SCRIPT_DIR/task" claim
    assert_success

    # Should return JSON with the higher priority task
    echo "$output" | jq -e '.id == "t-high"'
    echo "$output" | jq -e '.s == "active"'
    echo "$output" | jq -e '.p == 0'
}

@test "task claim sets assignee from --agent flag" {
    "$SCRIPT_DIR/task" create "t-agent" "Agent test" -p 1

    run "$SCRIPT_DIR/task" claim --agent "a1b2"
    assert_success

    echo "$output" | jq -e '.assignee == "a1b2"'
}

@test "task claim sets assignee from RALPH_AGENT_ID env var" {
    "$SCRIPT_DIR/task" create "t-env" "Env test" -p 1

    RALPH_AGENT_ID="c3d4" run "$SCRIPT_DIR/task" claim
    assert_success

    echo "$output" | jq -e '.assignee == "c3d4"'
}

@test "task claim uses short keys in JSON output" {
    "$SCRIPT_DIR/task" create "t-keys" "Key test" -p 1 -c feat -d "A description"

    run "$SCRIPT_DIR/task" claim
    assert_success

    # Verify all short keys present
    echo "$output" | jq -e 'has("id")'
    echo "$output" | jq -e 'has("t")'
    echo "$output" | jq -e 'has("d")'
    echo "$output" | jq -e 'has("p")'
    echo "$output" | jq -e 'has("s")'
    echo "$output" | jq -e 'has("cat")'
    echo "$output" | jq -e 'has("deps")'
    echo "$output" | jq -e 'has("steps")'
    echo "$output" | jq -e 'has("blocker_results")'
}

# ---------------------------------------------------------------------------
# Priority ordering and tiebreaker
# ---------------------------------------------------------------------------
@test "task claim selects by priority then created_at" {
    "$SCRIPT_DIR/task" create "t-p1-first" "First p1" -p 1
    sleep 0.1
    "$SCRIPT_DIR/task" create "t-p1-second" "Second p1" -p 1

    run "$SCRIPT_DIR/task" claim
    assert_success
    echo "$output" | jq -e '.id == "t-p1-first"'
}

# ---------------------------------------------------------------------------
# Blocked tasks are skipped
# ---------------------------------------------------------------------------
@test "task claim skips tasks with unresolved blockers" {
    "$SCRIPT_DIR/task" create "t-blocker" "Blocker" -p 0
    "$SCRIPT_DIR/task" create "t-blocked" "Blocked" -p 0
    "$SCRIPT_DIR/task" block "t-blocked" --by "t-blocker"

    run "$SCRIPT_DIR/task" claim
    assert_success
    # Should claim the blocker (unblocked), not the blocked task
    echo "$output" | jq -e '.id == "t-blocker"'
}

@test "task claim picks unblocked task even if lower priority" {
    "$SCRIPT_DIR/task" create "t-blocker2" "Blocker" -p 2
    "$SCRIPT_DIR/task" create "t-blocked2" "Blocked high pri" -p 0
    "$SCRIPT_DIR/task" block "t-blocked2" --by "t-blocker2"

    run "$SCRIPT_DIR/task" claim
    assert_success
    # Only the blocker is eligible
    echo "$output" | jq -e '.id == "t-blocker2"'
}

@test "task claim returns blocked task after blocker is done" {
    "$SCRIPT_DIR/task" create "t-b-done" "Blocker" -p 0
    "$SCRIPT_DIR/task" create "t-b-wait" "Waiting" -p 0
    "$SCRIPT_DIR/task" block "t-b-wait" --by "t-b-done"

    # Claim and complete the blocker
    run "$SCRIPT_DIR/task" claim
    assert_success
    echo "$output" | jq -e '.id == "t-b-done"'

    # Mark blocker as done
    "$SCRIPT_DIR/task" update "t-b-done" --status done

    # Now the waiting task should be eligible
    run "$SCRIPT_DIR/task" claim
    assert_success
    echo "$output" | jq -e '.id == "t-b-wait"'
}

@test "task claim unblocks when blocker is deleted" {
    "$SCRIPT_DIR/task" create "t-del-blocker" "Blocker" -p 0
    "$SCRIPT_DIR/task" create "t-del-wait" "Waiting" -p 0
    "$SCRIPT_DIR/task" block "t-del-wait" --by "t-del-blocker"

    # Delete the blocker
    "$SCRIPT_DIR/task" delete "t-del-blocker"

    # The waiting task should now be eligible
    run "$SCRIPT_DIR/task" claim
    assert_success
    echo "$output" | jq -e '.id == "t-del-wait"'
}

# ---------------------------------------------------------------------------
# Already-active tasks are not re-claimed (unless lease expired)
# ---------------------------------------------------------------------------
@test "task claim skips already-active tasks with valid lease" {
    "$SCRIPT_DIR/task" create "t-active" "Active task" -p 0
    "$SCRIPT_DIR/task" create "t-backup" "Backup task" -p 1

    # Claim first task
    run "$SCRIPT_DIR/task" claim
    assert_success
    echo "$output" | jq -e '.id == "t-active"'

    # Second claim should get the backup task
    run "$SCRIPT_DIR/task" claim
    assert_success
    echo "$output" | jq -e '.id == "t-backup"'
}

@test "task claim re-claims task with expired lease" {
    "$SCRIPT_DIR/task" create "t-expire" "Expiring task" -p 0

    # Claim with a very short lease (1 second)
    run "$SCRIPT_DIR/task" claim --lease 1
    assert_success
    echo "$output" | jq -e '.id == "t-expire"'
    echo "$output" | jq -e '.retry_count == 0'

    # Wait for lease to expire
    sleep 2

    # Re-claim should work and increment retry_count
    run "$SCRIPT_DIR/task" claim
    assert_success
    echo "$output" | jq -e '.id == "t-expire"'
    echo "$output" | jq -e '.retry_count == 1'
}

# ---------------------------------------------------------------------------
# Steps and dependencies in output
# ---------------------------------------------------------------------------
@test "task claim includes steps in output" {
    "$SCRIPT_DIR/task" create "t-steps" "Steps task" -p 0 -s '[{"content":"step one"},{"content":"step two"}]'

    run "$SCRIPT_DIR/task" claim
    assert_success
    echo "$output" | jq -e '.steps | length == 2'
    echo "$output" | jq -e '.steps[0].content == "step one"'
}

@test "task claim includes blocker_results for resolved deps" {
    "$SCRIPT_DIR/task" create "t-dep-a" "Dep A" -p 0
    "$SCRIPT_DIR/task" create "t-dep-b" "Dep B" -p 0
    "$SCRIPT_DIR/task" block "t-dep-b" --by "t-dep-a"

    # Claim and complete dep-a with a result
    run "$SCRIPT_DIR/task" claim
    assert_success

    # Set the blocker to done with a result via direct SQL (since task done isn't implemented yet)
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='done', result='{\"commit\":\"abc123\"}' WHERE id='t-dep-a';" >/dev/null

    # Now claim dep-b
    run "$SCRIPT_DIR/task" claim
    assert_success
    echo "$output" | jq -e '.id == "t-dep-b"'
    echo "$output" | jq -e '.blocker_results["t-dep-a"].commit == "abc123"'
}

# ---------------------------------------------------------------------------
# Lease duration
# ---------------------------------------------------------------------------
@test "task claim sets lease_expires_at in the future" {
    "$SCRIPT_DIR/task" create "t-lease" "Lease test" -p 0

    run "$SCRIPT_DIR/task" claim --lease 300
    assert_success
    # lease_expires_at should be set (non-null)
    echo "$output" | jq -e '.lease_expires_at != null'
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------
@test "task claim with all tasks done exits 2" {
    "$SCRIPT_DIR/task" create "t-alldone" "All done" -p 0
    "$SCRIPT_DIR/task" claim >/dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='done' WHERE id='t-alldone';" >/dev/null

    run "$SCRIPT_DIR/task" claim
    assert_failure 2
}

@test "task claim with all tasks deleted exits 2" {
    "$SCRIPT_DIR/task" create "t-alldeleted" "All deleted" -p 0
    "$SCRIPT_DIR/task" delete "t-alldeleted"

    run "$SCRIPT_DIR/task" claim
    assert_failure 2
}

@test "task claim with unknown flag exits 1" {
    run "$SCRIPT_DIR/task" claim --unknown
    assert_failure
    assert_output --partial "Error: unknown flag"
}
