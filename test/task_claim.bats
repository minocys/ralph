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
    run "$SCRIPT_DIR/lib/task" list
    assert_success

    run "$SCRIPT_DIR/lib/task" claim
    assert_failure 2
    assert_output --partial "No eligible tasks"
}

# ---------------------------------------------------------------------------
# Basic claim
# ---------------------------------------------------------------------------
@test "task claim returns highest priority open task as markdown-KV" {
    "$SCRIPT_DIR/lib/task" create "t-low" "Low priority" -p 2
    "$SCRIPT_DIR/lib/task" create "t-high" "High priority" -p 0

    run "$SCRIPT_DIR/lib/task" claim
    assert_success

    # Should return markdown-KV with the higher priority task
    assert_output --partial "## Task t-high"
    assert_output --partial "id: t-high"
    assert_output --partial "status: active"
    assert_output --partial "priority: 0"
}

@test "task claim sets assignee from --agent flag" {
    "$SCRIPT_DIR/lib/task" create "t-agent" "Agent test" -p 1

    run "$SCRIPT_DIR/lib/task" claim --agent "a1b2"
    assert_success

    assert_output --partial "assignee: a1b2"
}

@test "task claim sets assignee from RALPH_AGENT_ID env var" {
    "$SCRIPT_DIR/lib/task" create "t-env" "Env test" -p 1

    RALPH_AGENT_ID="c3d4" run "$SCRIPT_DIR/lib/task" claim
    assert_success

    assert_output --partial "assignee: c3d4"
}

@test "task claim outputs markdown-KV with expected fields" {
    "$SCRIPT_DIR/lib/task" create "t-keys" "Key test" -p 1 -c feat

    run "$SCRIPT_DIR/lib/task" claim
    assert_success

    # Verify markdown-KV fields present
    assert_output --partial "## Task t-keys"
    assert_output --partial "id: t-keys"
    assert_output --partial "title: Key test"
    assert_output --partial "priority: 1"
    assert_output --partial "status: active"
    assert_output --partial "category: feat"
    assert_output --partial "lease_expires_at:"
    assert_output --partial "retry_count: 0"
}

# ---------------------------------------------------------------------------
# Priority ordering and tiebreaker
# ---------------------------------------------------------------------------
@test "task claim selects by priority then created_at" {
    "$SCRIPT_DIR/lib/task" create "t-p1-first" "First p1" -p 1
    sleep 0.1
    "$SCRIPT_DIR/lib/task" create "t-p1-second" "Second p1" -p 1

    run "$SCRIPT_DIR/lib/task" claim
    assert_success
    assert_output --partial "id: t-p1-first"
}

# ---------------------------------------------------------------------------
# Blocked tasks are skipped
# ---------------------------------------------------------------------------
@test "task claim skips tasks with unresolved blockers" {
    "$SCRIPT_DIR/lib/task" create "t-blocker" "Blocker" -p 0
    "$SCRIPT_DIR/lib/task" create "t-blocked" "Blocked" -p 0
    "$SCRIPT_DIR/lib/task" block "t-blocked" --by "t-blocker"

    run "$SCRIPT_DIR/lib/task" claim
    assert_success
    # Should claim the blocker (unblocked), not the blocked task
    assert_output --partial "id: t-blocker"
}

@test "task claim picks unblocked task even if lower priority" {
    "$SCRIPT_DIR/lib/task" create "t-blocker2" "Blocker" -p 2
    "$SCRIPT_DIR/lib/task" create "t-blocked2" "Blocked high pri" -p 0
    "$SCRIPT_DIR/lib/task" block "t-blocked2" --by "t-blocker2"

    run "$SCRIPT_DIR/lib/task" claim
    assert_success
    # Only the blocker is eligible
    assert_output --partial "id: t-blocker2"
}

@test "task claim returns blocked task after blocker is done" {
    "$SCRIPT_DIR/lib/task" create "t-b-done" "Blocker" -p 0
    "$SCRIPT_DIR/lib/task" create "t-b-wait" "Waiting" -p 0
    "$SCRIPT_DIR/lib/task" block "t-b-wait" --by "t-b-done"

    # Claim and complete the blocker
    run "$SCRIPT_DIR/lib/task" claim
    assert_success
    assert_output --partial "id: t-b-done"

    # Mark blocker as done
    "$SCRIPT_DIR/lib/task" update "t-b-done" --status done

    # Now the waiting task should be eligible
    run "$SCRIPT_DIR/lib/task" claim
    assert_success
    assert_output --partial "id: t-b-wait"
}

@test "task claim unblocks when blocker is deleted" {
    "$SCRIPT_DIR/lib/task" create "t-del-blocker" "Blocker" -p 0
    "$SCRIPT_DIR/lib/task" create "t-del-wait" "Waiting" -p 0
    "$SCRIPT_DIR/lib/task" block "t-del-wait" --by "t-del-blocker"

    # Delete the blocker
    "$SCRIPT_DIR/lib/task" delete "t-del-blocker"

    # The waiting task should now be eligible
    run "$SCRIPT_DIR/lib/task" claim
    assert_success
    assert_output --partial "id: t-del-wait"
}

# ---------------------------------------------------------------------------
# Already-active tasks are not re-claimed (unless lease expired)
# ---------------------------------------------------------------------------
@test "task claim skips already-active tasks with valid lease" {
    "$SCRIPT_DIR/lib/task" create "t-active" "Active task" -p 0
    "$SCRIPT_DIR/lib/task" create "t-backup" "Backup task" -p 1

    # Claim first task
    run "$SCRIPT_DIR/lib/task" claim
    assert_success
    assert_output --partial "id: t-active"

    # Second claim should get the backup task
    run "$SCRIPT_DIR/lib/task" claim
    assert_success
    assert_output --partial "id: t-backup"
}

@test "task claim re-claims task with expired lease" {
    "$SCRIPT_DIR/lib/task" create "t-expire" "Expiring task" -p 0

    # Claim with a very short lease (1 second)
    run "$SCRIPT_DIR/lib/task" claim --lease 1
    assert_success
    assert_output --partial "id: t-expire"
    assert_output --partial "retry_count: 0"

    # Wait for lease to expire
    sleep 2

    # Re-claim should work and increment retry_count
    run "$SCRIPT_DIR/lib/task" claim
    assert_success
    assert_output --partial "id: t-expire"
    assert_output --partial "retry_count: 1"
}

# ---------------------------------------------------------------------------
# Steps and dependencies in output
# ---------------------------------------------------------------------------
@test "task claim includes steps in output" {
    "$SCRIPT_DIR/lib/task" create "t-steps" "Steps task" -p 0
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET steps = ARRAY['step one','step two']::TEXT[] WHERE slug = 't-steps' AND scope_repo = 'test/repo' AND scope_branch = 'main'" >/dev/null

    run "$SCRIPT_DIR/lib/task" claim
    assert_success
    assert_output --partial "steps:"
    assert_output --partial "- step one"
    assert_output --partial "- step two"
}

@test "task claim includes blocker_results for resolved deps" {
    "$SCRIPT_DIR/lib/task" create "t-dep-a" "Dep A" -p 0
    "$SCRIPT_DIR/lib/task" create "t-dep-b" "Dep B" -p 0
    "$SCRIPT_DIR/lib/task" block "t-dep-b" --by "t-dep-a"

    # Claim and complete dep-a with a result
    run "$SCRIPT_DIR/lib/task" claim
    assert_success

    # Set the blocker to done with a result via direct SQL
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='done', result='{\"commit\":\"abc123\"}' WHERE slug='t-dep-a' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    # Now claim dep-b
    run "$SCRIPT_DIR/lib/task" claim
    assert_success
    assert_output --partial "id: t-dep-b"
    assert_output --partial "blocker_results:"
    assert_output --partial '- t-dep-a: {"commit":"abc123"}'
}

# ---------------------------------------------------------------------------
# Lease duration
# ---------------------------------------------------------------------------
@test "task claim sets lease_expires_at in the future" {
    "$SCRIPT_DIR/lib/task" create "t-lease" "Lease test" -p 0

    run "$SCRIPT_DIR/lib/task" claim --lease 300
    assert_success
    # lease_expires_at should be present in the output
    assert_output --partial "lease_expires_at:"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------
@test "task claim with all tasks done exits 2" {
    "$SCRIPT_DIR/lib/task" create "t-alldone" "All done" -p 0
    "$SCRIPT_DIR/lib/task" claim >/dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='done' WHERE slug='t-alldone' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    run "$SCRIPT_DIR/lib/task" claim
    assert_failure 2
}

@test "task claim with all tasks deleted exits 2" {
    "$SCRIPT_DIR/lib/task" create "t-alldeleted" "All deleted" -p 0
    "$SCRIPT_DIR/lib/task" delete "t-alldeleted"

    run "$SCRIPT_DIR/lib/task" claim
    assert_failure 2
}

@test "task claim with unknown flag exits 1" {
    run "$SCRIPT_DIR/lib/task" claim --unknown
    assert_failure
    assert_output --partial "Error: unknown flag"
}

# ---------------------------------------------------------------------------
# Targeted claim: task claim <id>
# ---------------------------------------------------------------------------
@test "task claim <id> claims specific eligible task regardless of priority" {
    "$SCRIPT_DIR/lib/task" create "t-a" "Lower priority" -p 2
    "$SCRIPT_DIR/lib/task" create "t-b" "Higher priority" -p 0

    # Targeted claim should get t-a even though t-b has higher priority
    run "$SCRIPT_DIR/lib/task" claim t-a
    assert_success
    assert_output --partial "id: t-a"
}

@test "task claim <id> sets status to active with assignee and lease" {
    "$SCRIPT_DIR/lib/task" create "t-1" "Targeted task" -p 1

    run "$SCRIPT_DIR/lib/task" claim t-1 --agent a1b2
    assert_success
    assert_output --partial "status: active"
    assert_output --partial "assignee: a1b2"
    assert_output --partial "lease_expires_at:"
}

@test "task claim <id> returns exit code 2 for already-active task with valid lease" {
    "$SCRIPT_DIR/lib/task" create "t-active-tgt" "Active target" -p 0

    # Claim it first (untargeted)
    run "$SCRIPT_DIR/lib/task" claim
    assert_success
    assert_output --partial "id: t-active-tgt"

    # Targeted claim of same task by different agent should fail
    run "$SCRIPT_DIR/lib/task" claim t-active-tgt --agent other-agent
    assert_failure 2
}

@test "task claim <id> returns exit code 2 for blocked task" {
    "$SCRIPT_DIR/lib/task" create "t-blocker-tgt" "Blocker" -p 0
    "$SCRIPT_DIR/lib/task" create "t-blocked-tgt" "Blocked" -p 0
    "$SCRIPT_DIR/lib/task" block "t-blocked-tgt" --by "t-blocker-tgt"

    run "$SCRIPT_DIR/lib/task" claim t-blocked-tgt
    assert_failure 2
}

@test "task claim <id> returns exit code 2 for done task" {
    "$SCRIPT_DIR/lib/task" create "t-done-tgt" "Done task" -p 0
    # Claim and complete
    "$SCRIPT_DIR/lib/task" claim >/dev/null
    "$SCRIPT_DIR/lib/task" done t-done-tgt

    run "$SCRIPT_DIR/lib/task" claim t-done-tgt
    assert_failure 2
}

@test "task claim <id> returns exit code 2 for deleted task" {
    "$SCRIPT_DIR/lib/task" create "t-del-tgt" "Deleted task" -p 0
    "$SCRIPT_DIR/lib/task" delete "t-del-tgt"

    run "$SCRIPT_DIR/lib/task" claim t-del-tgt
    assert_failure 2
}

@test "task claim <id> succeeds for active task with expired lease" {
    "$SCRIPT_DIR/lib/task" create "t-exp-tgt" "Expiring task" -p 0

    # Claim with 1-second lease
    run "$SCRIPT_DIR/lib/task" claim t-exp-tgt --lease 1
    assert_success
    assert_output --partial "retry_count: 0"

    # Wait for lease to expire
    sleep 2

    # Targeted re-claim should succeed and increment retry_count
    run "$SCRIPT_DIR/lib/task" claim t-exp-tgt --agent reclaimer
    assert_success
    assert_output --partial "id: t-exp-tgt"
    assert_output --partial "retry_count: 1"
    assert_output --partial "assignee: reclaimer"
}

@test "task claim <id> returns blocker_results and steps like untargeted claim" {
    "$SCRIPT_DIR/lib/task" create "t-dep-tgt-a" "Dep A" -p 0
    "$SCRIPT_DIR/lib/task" create "t-dep-tgt-b" "Dep B" -p 0
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET steps = ARRAY['step one','step two']::TEXT[] WHERE slug = 't-dep-tgt-b' AND scope_repo = 'test/repo' AND scope_branch = 'main'" >/dev/null
    "$SCRIPT_DIR/lib/task" block "t-dep-tgt-b" --by "t-dep-tgt-a"

    # Claim and complete dep-a with a result
    "$SCRIPT_DIR/lib/task" claim >/dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status='done', result='{\"commit\":\"def456\"}' WHERE slug='t-dep-tgt-a' AND scope_repo='test/repo' AND scope_branch='main';" >/dev/null

    # Targeted claim of dep-b
    run "$SCRIPT_DIR/lib/task" claim t-dep-tgt-b
    assert_success
    assert_output --partial "id: t-dep-tgt-b"
    assert_output --partial "blocker_results:"
    assert_output --partial '- t-dep-tgt-a: {"commit":"def456"}'
    assert_output --partial "steps:"
    assert_output --partial "- step one"
    assert_output --partial "- step two"
}

@test "task claim <id> returns exit code 2 for nonexistent task" {
    run "$SCRIPT_DIR/lib/task" claim nonexistent-id
    assert_failure 2
}

# ---------------------------------------------------------------------------
# Concurrent claim atomicity (FOR UPDATE SKIP LOCKED)
# ---------------------------------------------------------------------------
@test "concurrent claims: exactly one wins when two agents race for same task" {
    # Insert a single claimable task
    "$SCRIPT_DIR/lib/task" create "t-race" "Race condition test" -p 0

    # Launch two concurrent claims in background, capturing exit codes and output
    local out1="$TEST_WORK_DIR/claim1.out"
    local out2="$TEST_WORK_DIR/claim2.out"
    local rc1_file="$TEST_WORK_DIR/claim1.rc"
    local rc2_file="$TEST_WORK_DIR/claim2.rc"

    (
        rc=0
        "$SCRIPT_DIR/lib/task" claim --agent agent-1 > "$out1" 2>&1 || rc=$?
        echo "$rc" > "$rc1_file"
    ) &
    local pid1=$!

    (
        rc=0
        "$SCRIPT_DIR/lib/task" claim --agent agent-2 > "$out2" 2>&1 || rc=$?
        echo "$rc" > "$rc2_file"
    ) &
    local pid2=$!

    # Wait for both to finish
    wait "$pid1" "$pid2" || true

    local rc1 rc2
    rc1=$(cat "$rc1_file")
    rc2=$(cat "$rc2_file")

    # Exactly one must succeed (exit 0) and one must fail (exit 2)
    local wins=0 losses=0
    [[ "$rc1" == "0" ]] && wins=$((wins + 1))
    [[ "$rc2" == "0" ]] && wins=$((wins + 1))
    [[ "$rc1" == "2" ]] && losses=$((losses + 1))
    [[ "$rc2" == "2" ]] && losses=$((losses + 1))

    [[ "$wins" -eq 1 ]]
    [[ "$losses" -eq 1 ]]

    # The winner's output should show the task as active
    if [[ "$rc1" == "0" ]]; then
        [[ "$(cat "$out1")" == *"id: t-race"* ]]
        [[ "$(cat "$out1")" == *"status: active"* ]]
    else
        [[ "$(cat "$out2")" == *"id: t-race"* ]]
        [[ "$(cat "$out2")" == *"status: active"* ]]
    fi

    # Verify the task is claimed exactly once in the database
    local active_count
    active_count=$(psql "$RALPH_DB_URL" -tAX -c "SELECT COUNT(*) FROM tasks WHERE slug = 't-race' AND scope_repo = 'test/repo' AND scope_branch = 'main' AND status = 'active'")
    [[ "$active_count" -eq 1 ]]
}
