#!/usr/bin/env bats
# test/task_concurrent_plan_sync.bats — concurrent plan-sync contention tests
#
# Verifies that two parallel plan-sync invocations with overlapping task sets
# both complete without error and leave the database in a consistent state.
# SQLite's BEGIN IMMEDIATE serialization (via sql_write or busy_timeout)
# ensures no duplicate slugs and correct final task counts.

load test_helper

# ---------------------------------------------------------------------------
# Helper: run N parallel plan-sync invocations, each with its own JSONL input
# Usage: run_parallel_syncs <input1> <input2> [input3] ...
# Writes exit codes to $TEST_WORK_DIR/sync{N}.rc and output to sync{N}.out
# ---------------------------------------------------------------------------
run_parallel_syncs() {
    local pids=()
    local i=0
    for input in "$@"; do
        i=$((i + 1))
        (
            rc=0
            printf '%s\n' "$input" \
                | "$SCRIPT_DIR/lib/task" plan-sync \
                > "$TEST_WORK_DIR/sync${i}.out" 2>&1 || rc=$?
            echo "$rc" > "$TEST_WORK_DIR/sync${i}.rc"
        ) &
        pids+=($!)
    done

    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done
}

# ---------------------------------------------------------------------------
# Helper: count tasks in a given status within test scope
# ---------------------------------------------------------------------------
count_tasks_by_status() {
    local status="$1"
    sqlite3 "$RALPH_DB_PATH" \
        "SELECT COUNT(*) FROM tasks
         WHERE scope_repo = 'test/repo'
           AND scope_branch = 'main'
           AND status = '${status}'"
}

# ---------------------------------------------------------------------------
# Helper: count total non-deleted tasks within test scope
# ---------------------------------------------------------------------------
count_live_tasks() {
    sqlite3 "$RALPH_DB_PATH" \
        "SELECT COUNT(*) FROM tasks
         WHERE scope_repo = 'test/repo'
           AND scope_branch = 'main'
           AND status != 'deleted'"
}

# ---------------------------------------------------------------------------
# Helper: check for duplicate slugs within test scope
# ---------------------------------------------------------------------------
count_duplicate_slugs() {
    sqlite3 "$RALPH_DB_PATH" \
        "SELECT COUNT(*) FROM (
             SELECT slug, COUNT(*) as cnt FROM tasks
             WHERE scope_repo = 'test/repo'
               AND scope_branch = 'main'
             GROUP BY slug
             HAVING cnt > 1
         )"
}

# ---------------------------------------------------------------------------
# Two syncs with identical task sets
# ---------------------------------------------------------------------------
@test "concurrent plan-sync: two identical syncs both succeed" {
    local input='{"id":"cps-01","t":"Task one","p":1,"spec":"cps-spec"}
{"id":"cps-02","t":"Task two","p":2,"spec":"cps-spec"}'

    run_parallel_syncs "$input" "$input"

    local rc1 rc2
    rc1=$(cat "$TEST_WORK_DIR/sync1.rc")
    rc2=$(cat "$TEST_WORK_DIR/sync2.rc")

    # Both should succeed
    [[ "$rc1" -eq 0 ]]
    [[ "$rc2" -eq 0 ]]

    # No duplicate slugs
    local dupes
    dupes=$(count_duplicate_slugs)
    [[ "$dupes" -eq 0 ]]

    # Exactly 2 tasks exist (not 4)
    local live
    live=$(count_live_tasks)
    [[ "$live" -eq 2 ]]

    # Both tasks are open
    local open_count
    open_count=$(count_tasks_by_status "open")
    [[ "$open_count" -eq 2 ]]
}

# ---------------------------------------------------------------------------
# Two syncs with overlapping task sets
# ---------------------------------------------------------------------------
@test "concurrent plan-sync: overlapping task sets produce correct final state" {
    local input1='{"id":"cps-ov-01","t":"Shared task","p":1,"spec":"ov-spec"}
{"id":"cps-ov-02","t":"Only in sync 1","p":2,"spec":"ov-spec"}'

    local input2='{"id":"cps-ov-01","t":"Shared task updated","p":0,"spec":"ov-spec"}
{"id":"cps-ov-03","t":"Only in sync 2","p":2,"spec":"ov-spec"}'

    run_parallel_syncs "$input1" "$input2"

    local rc1 rc2
    rc1=$(cat "$TEST_WORK_DIR/sync1.rc")
    rc2=$(cat "$TEST_WORK_DIR/sync2.rc")

    # Both should succeed
    [[ "$rc1" -eq 0 ]]
    [[ "$rc2" -eq 0 ]]

    # No duplicate slugs
    local dupes
    dupes=$(count_duplicate_slugs)
    [[ "$dupes" -eq 0 ]]

    # The shared task should exist exactly once
    local shared_count
    shared_count=$(sqlite3 "$RALPH_DB_PATH" \
        "SELECT COUNT(*) FROM tasks
         WHERE slug = 'cps-ov-01'
           AND scope_repo = 'test/repo'
           AND scope_branch = 'main'")
    [[ "$shared_count" -eq 1 ]]

    # The shared task should have a valid title (one of the two inputs won)
    local title
    title=$(sqlite3 "$RALPH_DB_PATH" \
        "SELECT title FROM tasks
         WHERE slug = 'cps-ov-01'
           AND scope_repo = 'test/repo'
           AND scope_branch = 'main'")
    [[ "$title" == "Shared task" ]] || [[ "$title" == "Shared task updated" ]]
}

# ---------------------------------------------------------------------------
# Two syncs with disjoint task sets under the same spec_ref
# ---------------------------------------------------------------------------
@test "concurrent plan-sync: disjoint sets under same spec_ref both succeed" {
    local input1='{"id":"cps-dj-01","t":"Sync 1 task A","p":1,"spec":"dj-spec"}
{"id":"cps-dj-02","t":"Sync 1 task B","p":2,"spec":"dj-spec"}'

    local input2='{"id":"cps-dj-03","t":"Sync 2 task C","p":1,"spec":"dj-spec"}
{"id":"cps-dj-04","t":"Sync 2 task D","p":2,"spec":"dj-spec"}'

    run_parallel_syncs "$input1" "$input2"

    local rc1 rc2
    rc1=$(cat "$TEST_WORK_DIR/sync1.rc")
    rc2=$(cat "$TEST_WORK_DIR/sync2.rc")

    # Both should succeed
    [[ "$rc1" -eq 0 ]]
    [[ "$rc2" -eq 0 ]]

    # No duplicate slugs
    local dupes
    dupes=$(count_duplicate_slugs)
    [[ "$dupes" -eq 0 ]]

    # Note: with disjoint sets under the same spec_ref, each sync will
    # soft-delete the other's tasks. The last-write-wins: final state
    # depends on execution order. We just verify consistency.
    # Total tasks with this spec_ref (any status):
    local total
    total=$(sqlite3 "$RALPH_DB_PATH" \
        "SELECT COUNT(*) FROM tasks
         WHERE spec_ref = 'dj-spec'
           AND scope_repo = 'test/repo'
           AND scope_branch = 'main'")
    [[ "$total" -eq 4 ]]

    # At least 2 should be open (the winner's tasks), at most 4
    local open_count
    open_count=$(sqlite3 "$RALPH_DB_PATH" \
        "SELECT COUNT(*) FROM tasks
         WHERE spec_ref = 'dj-spec'
           AND scope_repo = 'test/repo'
           AND scope_branch = 'main'
           AND status = 'open'")
    [[ "$open_count" -ge 2 ]]
    [[ "$open_count" -le 4 ]]
}

# ---------------------------------------------------------------------------
# Pre-existing tasks with parallel syncs
# ---------------------------------------------------------------------------
@test "concurrent plan-sync: pre-existing tasks handled correctly" {
    # Seed the database with tasks
    "$SCRIPT_DIR/lib/task" create cps-pre-01 "Pre-existing A" -r pre-spec >/dev/null
    "$SCRIPT_DIR/lib/task" create cps-pre-02 "Pre-existing B" -r pre-spec >/dev/null

    # Both syncs reference the same pre-existing task plus a new one each
    local input1='{"id":"cps-pre-01","t":"Updated A","p":0,"spec":"pre-spec"}
{"id":"cps-pre-03","t":"New from sync 1","p":1,"spec":"pre-spec"}'

    local input2='{"id":"cps-pre-01","t":"Updated A v2","p":1,"spec":"pre-spec"}
{"id":"cps-pre-04","t":"New from sync 2","p":1,"spec":"pre-spec"}'

    run_parallel_syncs "$input1" "$input2"

    local rc1 rc2
    rc1=$(cat "$TEST_WORK_DIR/sync1.rc")
    rc2=$(cat "$TEST_WORK_DIR/sync2.rc")

    # Both should succeed
    [[ "$rc1" -eq 0 ]]
    [[ "$rc2" -eq 0 ]]

    # No duplicate slugs
    local dupes
    dupes=$(count_duplicate_slugs)
    [[ "$dupes" -eq 0 ]]

    # cps-pre-01 should exist exactly once
    local pre01_count
    pre01_count=$(sqlite3 "$RALPH_DB_PATH" \
        "SELECT COUNT(*) FROM tasks
         WHERE slug = 'cps-pre-01'
           AND scope_repo = 'test/repo'
           AND scope_branch = 'main'")
    [[ "$pre01_count" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# Three concurrent syncs
# ---------------------------------------------------------------------------
@test "concurrent plan-sync: three parallel syncs with overlapping tasks" {
    local input1='{"id":"cps-tri-01","t":"Shared A","p":1,"spec":"tri-spec"}
{"id":"cps-tri-02","t":"Only sync 1","p":2,"spec":"tri-spec"}'

    local input2='{"id":"cps-tri-01","t":"Shared A v2","p":0,"spec":"tri-spec"}
{"id":"cps-tri-03","t":"Only sync 2","p":2,"spec":"tri-spec"}'

    local input3='{"id":"cps-tri-01","t":"Shared A v3","p":1,"spec":"tri-spec"}
{"id":"cps-tri-04","t":"Only sync 3","p":2,"spec":"tri-spec"}'

    run_parallel_syncs "$input1" "$input2" "$input3"

    local rc1 rc2 rc3
    rc1=$(cat "$TEST_WORK_DIR/sync1.rc")
    rc2=$(cat "$TEST_WORK_DIR/sync2.rc")
    rc3=$(cat "$TEST_WORK_DIR/sync3.rc")

    # All should succeed
    [[ "$rc1" -eq 0 ]]
    [[ "$rc2" -eq 0 ]]
    [[ "$rc3" -eq 0 ]]

    # No duplicate slugs
    local dupes
    dupes=$(count_duplicate_slugs)
    [[ "$dupes" -eq 0 ]]

    # The shared task exists exactly once
    local shared_count
    shared_count=$(sqlite3 "$RALPH_DB_PATH" \
        "SELECT COUNT(*) FROM tasks
         WHERE slug = 'cps-tri-01'
           AND scope_repo = 'test/repo'
           AND scope_branch = 'main'")
    [[ "$shared_count" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# Concurrent syncs with dependencies
# ---------------------------------------------------------------------------
@test "concurrent plan-sync: overlapping syncs with dependencies maintain FK integrity" {
    local input1='{"id":"cps-dep-01","t":"Blocker","p":0,"spec":"dep-spec"}
{"id":"cps-dep-02","t":"Depends on blocker","p":1,"spec":"dep-spec","deps":["cps-dep-01"]}'

    local input2='{"id":"cps-dep-01","t":"Blocker updated","p":0,"spec":"dep-spec"}
{"id":"cps-dep-03","t":"Also depends on blocker","p":1,"spec":"dep-spec","deps":["cps-dep-01"]}'

    run_parallel_syncs "$input1" "$input2"

    local rc1 rc2
    rc1=$(cat "$TEST_WORK_DIR/sync1.rc")
    rc2=$(cat "$TEST_WORK_DIR/sync2.rc")

    # Both should succeed
    [[ "$rc1" -eq 0 ]]
    [[ "$rc2" -eq 0 ]]

    # No duplicate slugs
    local dupes
    dupes=$(count_duplicate_slugs)
    [[ "$dupes" -eq 0 ]]

    # The blocker task exists exactly once
    local blocker_count
    blocker_count=$(sqlite3 "$RALPH_DB_PATH" \
        "SELECT COUNT(*) FROM tasks
         WHERE slug = 'cps-dep-01'
           AND scope_repo = 'test/repo'
           AND scope_branch = 'main'")
    [[ "$blocker_count" -eq 1 ]]

    # Foreign key integrity: no orphaned task_deps rows
    local orphan_deps
    orphan_deps=$(sqlite3 "$RALPH_DB_PATH" \
        "SELECT COUNT(*) FROM task_deps d
         WHERE NOT EXISTS (SELECT 1 FROM tasks t WHERE t.id = d.task_id)
            OR NOT EXISTS (SELECT 1 FROM tasks t WHERE t.id = d.blocked_by)")
    [[ "$orphan_deps" -eq 0 ]]
}
