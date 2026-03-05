#!/usr/bin/env bats
# test/task_concurrent_claim.bats — concurrent claim atomicity tests
#
# Verifies that SQLite's BEGIN IMMEDIATE serialization prevents duplicate
# claims when multiple agents race for the same task(s).

load test_helper

# ---------------------------------------------------------------------------
# Helper: run N parallel claims, collect exit codes and outputs
# ---------------------------------------------------------------------------
run_parallel_claims() {
    local count="$1"
    shift
    # Remaining args are passed to each claim invocation
    local extra_args=("$@")

    local i
    local pids=()
    for (( i = 1; i <= count; i++ )); do
        (
            rc=0
            "$SCRIPT_DIR/lib/task" claim "${extra_args[@]}" --agent "agent-$i" \
                > "$TEST_WORK_DIR/claim${i}.out" 2>&1 || rc=$?
            echo "$rc" > "$TEST_WORK_DIR/claim${i}.rc"
        ) &
        pids+=($!)
    done

    # Wait for all background processes
    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done
}

# ---------------------------------------------------------------------------
# Single task, two agents
# ---------------------------------------------------------------------------
@test "concurrent claim: exactly one of two agents wins a single task" {
    "$SCRIPT_DIR/lib/task" create "t-race" "Race condition test" -p 0

    run_parallel_claims 2

    local rc1 rc2
    rc1=$(cat "$TEST_WORK_DIR/claim1.rc")
    rc2=$(cat "$TEST_WORK_DIR/claim2.rc")

    # Exactly one succeeds (0) and one fails (2)
    local wins=0 losses=0
    [[ "$rc1" == "0" ]] && wins=$((wins + 1))
    [[ "$rc2" == "0" ]] && wins=$((wins + 1))
    [[ "$rc1" == "2" ]] && losses=$((losses + 1))
    [[ "$rc2" == "2" ]] && losses=$((losses + 1))

    [[ "$wins" -eq 1 ]]
    [[ "$losses" -eq 1 ]]

    # Winner's output contains the task
    if [[ "$rc1" == "0" ]]; then
        [[ "$(cat "$TEST_WORK_DIR/claim1.out")" == *"id: t-race"* ]]
        [[ "$(cat "$TEST_WORK_DIR/claim1.out")" == *"status: active"* ]]
    else
        [[ "$(cat "$TEST_WORK_DIR/claim2.out")" == *"id: t-race"* ]]
        [[ "$(cat "$TEST_WORK_DIR/claim2.out")" == *"status: active"* ]]
    fi

    # Database has exactly one active claim
    local active_count
    active_count=$(sqlite3 "$TEST_DB_PATH" \
        "SELECT COUNT(*) FROM tasks WHERE slug = 't-race' AND scope_repo = 'test/repo' AND scope_branch = 'main' AND status = 'active'")
    [[ "$active_count" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# Single task, three agents
# ---------------------------------------------------------------------------
@test "concurrent claim: exactly one of three agents wins a single task" {
    "$SCRIPT_DIR/lib/task" create "t-triple" "Triple race test" -p 0

    run_parallel_claims 3

    local wins=0
    local i
    for (( i = 1; i <= 3; i++ )); do
        local rc
        rc=$(cat "$TEST_WORK_DIR/claim${i}.rc")
        [[ "$rc" == "0" ]] && wins=$((wins + 1))
    done

    [[ "$wins" -eq 1 ]]

    # Database has exactly one active claim
    local active_count
    active_count=$(sqlite3 "$TEST_DB_PATH" \
        "SELECT COUNT(*) FROM tasks WHERE slug = 't-triple' AND scope_repo = 'test/repo' AND scope_branch = 'main' AND status = 'active'")
    [[ "$active_count" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# Two tasks, two agents — each should get a different task
# ---------------------------------------------------------------------------
@test "concurrent claim: two agents each get a different task when two are available" {
    "$SCRIPT_DIR/lib/task" create "t-a" "Task A" -p 0
    "$SCRIPT_DIR/lib/task" create "t-b" "Task B" -p 0

    run_parallel_claims 2

    local rc1 rc2
    rc1=$(cat "$TEST_WORK_DIR/claim1.rc")
    rc2=$(cat "$TEST_WORK_DIR/claim2.rc")

    # Both should succeed
    [[ "$rc1" == "0" ]]
    [[ "$rc2" == "0" ]]

    # Each agent got a task — verify the tasks are different
    local id1 id2
    id1=$(grep '^id: ' "$TEST_WORK_DIR/claim1.out" | head -1 | sed 's/^id: //')
    id2=$(grep '^id: ' "$TEST_WORK_DIR/claim2.out" | head -1 | sed 's/^id: //')

    [[ "$id1" != "$id2" ]]

    # Database has exactly two active claims, no duplicates
    local active_count
    active_count=$(sqlite3 "$TEST_DB_PATH" \
        "SELECT COUNT(*) FROM tasks WHERE scope_repo = 'test/repo' AND scope_branch = 'main' AND status = 'active'")
    [[ "$active_count" -eq 2 ]]
}

# ---------------------------------------------------------------------------
# Targeted claim: two agents target the same task ID
# ---------------------------------------------------------------------------
@test "concurrent targeted claim: exactly one wins when both target the same task" {
    "$SCRIPT_DIR/lib/task" create "t-target" "Targeted race test" -p 0

    run_parallel_claims 2 "t-target"

    local rc1 rc2
    rc1=$(cat "$TEST_WORK_DIR/claim1.rc")
    rc2=$(cat "$TEST_WORK_DIR/claim2.rc")

    # Exactly one succeeds, one fails
    local wins=0 losses=0
    [[ "$rc1" == "0" ]] && wins=$((wins + 1))
    [[ "$rc2" == "0" ]] && wins=$((wins + 1))
    [[ "$rc1" == "2" ]] && losses=$((losses + 1))
    [[ "$rc2" == "2" ]] && losses=$((losses + 1))

    [[ "$wins" -eq 1 ]]
    [[ "$losses" -eq 1 ]]

    # Database has exactly one active claim
    local active_count
    active_count=$(sqlite3 "$TEST_DB_PATH" \
        "SELECT COUNT(*) FROM tasks WHERE slug = 't-target' AND scope_repo = 'test/repo' AND scope_branch = 'main' AND status = 'active'")
    [[ "$active_count" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# No duplicate assignees on same task
# ---------------------------------------------------------------------------
@test "concurrent claim: no duplicate assignees on a single task" {
    "$SCRIPT_DIR/lib/task" create "t-assign" "Assignee uniqueness test" -p 0

    run_parallel_claims 2

    # Check the assignee is set to exactly one agent (not both, not empty)
    local assignee
    assignee=$(sqlite3 "$TEST_DB_PATH" \
        "SELECT assignee FROM tasks WHERE slug = 't-assign' AND scope_repo = 'test/repo' AND scope_branch = 'main'")

    # Assignee should be one of agent-1 or agent-2, not blank
    [[ "$assignee" == "agent-1" ]] || [[ "$assignee" == "agent-2" ]]

    # Only one row with active status
    local active_count
    active_count=$(sqlite3 "$TEST_DB_PATH" \
        "SELECT COUNT(*) FROM tasks WHERE slug = 't-assign' AND scope_repo = 'test/repo' AND scope_branch = 'main' AND status = 'active'")
    [[ "$active_count" -eq 1 ]]
}
