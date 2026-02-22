#!/usr/bin/env bats
# test/task_plan_sync.bats — Tests for the task plan-sync command
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
# Empty input
# ---------------------------------------------------------------------------
@test "plan-sync with empty stdin prints zero summary" {
    run bash -c 'echo "" | "$SCRIPT_DIR/task" plan-sync'
    assert_success
    assert_output "inserted: 0, updated: 0, deleted: 0, skipped (done): 0"
}

# ---------------------------------------------------------------------------
# Insert new tasks
# ---------------------------------------------------------------------------
@test "plan-sync inserts new tasks" {
    local input
    input='{"id":"ps-01","t":"First task","p":1,"cat":"feat","spec":"my-spec"}
{"id":"ps-02","t":"Second task","p":2,"cat":"feat","spec":"my-spec"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync' -- "$input"
    assert_success
    assert_output "inserted: 2, updated: 0, deleted: 0, skipped (done): 0"

    # Verify tasks exist in DB
    run "$SCRIPT_DIR/task" show ps-01
    assert_success
    assert_output --partial "First task"

    run "$SCRIPT_DIR/task" show ps-02
    assert_success
    assert_output --partial "Second task"
}

# ---------------------------------------------------------------------------
# Insert with steps and deps
# ---------------------------------------------------------------------------
@test "plan-sync inserts tasks with steps and dependencies" {
    # Create blocker task first (with same spec_ref so it won't be deleted)
    "$SCRIPT_DIR/task" create ps-dep-01 "Blocker task" -r my-spec >/dev/null

    local input
    input='{"id":"ps-dep-01","t":"Blocker task","spec":"my-spec"}
{"id":"ps-dep-02","t":"Dependent task","p":1,"spec":"my-spec","steps":["Step one","Step two"],"deps":["ps-dep-01"]}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync' -- "$input"
    assert_success
    assert_output "inserted: 1, updated: 1, deleted: 0, skipped (done): 0"

    # Verify steps
    run "$SCRIPT_DIR/task" show ps-dep-02
    assert_success
    assert_output --partial "Step one"
    assert_output --partial "Step two"

    # Verify deps
    run "$SCRIPT_DIR/task" deps ps-dep-02
    assert_success
    assert_output --partial "ps-dep-01"
}

# ---------------------------------------------------------------------------
# Update existing tasks
# ---------------------------------------------------------------------------
@test "plan-sync updates existing non-done tasks" {
    # Create a task first
    "$SCRIPT_DIR/task" create ps-upd-01 "Original title" -p 2 -c feat -r my-spec >/dev/null

    local input
    input='{"id":"ps-upd-01","t":"Updated title","p":0,"cat":"fix","spec":"my-spec"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync' -- "$input"
    assert_success
    assert_output "inserted: 0, updated: 1, deleted: 0, skipped (done): 0"

    # Verify task was updated
    run "$SCRIPT_DIR/task" show ps-upd-01
    assert_success
    assert_output --partial "Updated title"
    assert_output --partial "Priority:    0"
}

# ---------------------------------------------------------------------------
# Update replaces steps and deps
# ---------------------------------------------------------------------------
@test "plan-sync update replaces steps and deps" {
    # Create tasks with steps
    "$SCRIPT_DIR/task" create ps-rep-01 "Blocker A" -r my-spec >/dev/null
    "$SCRIPT_DIR/task" create ps-rep-02 "Blocker B" -r my-spec >/dev/null
    "$SCRIPT_DIR/task" create ps-rep-03 "Main task" -r my-spec --deps "ps-rep-01" >/dev/null
    # Set initial steps directly via SQL (create command updated separately)
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET steps = ARRAY['Old step']::TEXT[] WHERE slug = 'ps-rep-03' AND scope_repo = 'test/repo' AND scope_branch = 'main'" >/dev/null

    local input
    input='{"id":"ps-rep-01","t":"Blocker A","spec":"my-spec"}
{"id":"ps-rep-02","t":"Blocker B","spec":"my-spec"}
{"id":"ps-rep-03","t":"Main task","spec":"my-spec","steps":["New step 1","New step 2"],"deps":["ps-rep-02"]}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync' -- "$input"
    assert_success
    assert_output "inserted: 0, updated: 3, deleted: 0, skipped (done): 0"

    # Verify new steps replaced old
    run "$SCRIPT_DIR/task" show ps-rep-03
    assert_success
    assert_output --partial "New step 1"
    assert_output --partial "New step 2"
    refute_output --partial "Old step"

    # Verify deps changed: blocked by ps-rep-02, not ps-rep-01
    run "$SCRIPT_DIR/task" deps ps-rep-03
    assert_success
    assert_output --partial "ps-rep-02"
    refute_output --partial "ps-rep-01"
}

# ---------------------------------------------------------------------------
# Skip done tasks
# ---------------------------------------------------------------------------
@test "plan-sync skips done tasks" {
    # Create and complete a task
    "$SCRIPT_DIR/task" create ps-done-01 "Done task" -p 1 -r my-spec >/dev/null
    export RALPH_AGENT_ID="test-agent"
    "$SCRIPT_DIR/task" claim --agent test-agent >/dev/null
    "$SCRIPT_DIR/task" done ps-done-01 >/dev/null

    local input
    input='{"id":"ps-done-01","t":"Tried to update done task","p":0,"spec":"my-spec"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync' -- "$input"
    assert_success
    assert_output "inserted: 0, updated: 0, deleted: 0, skipped (done): 1"

    # Verify task was NOT updated
    run "$SCRIPT_DIR/task" show ps-done-01
    assert_success
    assert_output --partial "Done task"
    refute_output --partial "Tried to update"
}

# ---------------------------------------------------------------------------
# Soft delete removed tasks
# ---------------------------------------------------------------------------
@test "plan-sync soft-deletes tasks removed from plan" {
    # Create tasks in DB
    "$SCRIPT_DIR/task" create ps-del-01 "Keep this" -r my-spec >/dev/null
    "$SCRIPT_DIR/task" create ps-del-02 "Remove this" -r my-spec >/dev/null

    # Sync with only ps-del-01 — ps-del-02 should be deleted
    local input
    input='{"id":"ps-del-01","t":"Keep this","spec":"my-spec"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync' -- "$input"
    assert_success
    assert_output "inserted: 0, updated: 1, deleted: 1, skipped (done): 0"

    # Verify ps-del-02 is soft deleted
    run "$SCRIPT_DIR/task" show ps-del-02
    assert_success
    assert_output --partial "Status:      deleted"
}

# ---------------------------------------------------------------------------
# Done tasks not deleted when removed from plan
# ---------------------------------------------------------------------------
@test "plan-sync does not delete done tasks removed from plan" {
    # Create and complete a task
    "$SCRIPT_DIR/task" create ps-keep-01 "Completed work" -p 1 -r my-spec >/dev/null
    "$SCRIPT_DIR/task" create ps-keep-02 "Still open" -p 2 -r my-spec >/dev/null
    export RALPH_AGENT_ID="test-agent"
    "$SCRIPT_DIR/task" claim --agent test-agent >/dev/null
    "$SCRIPT_DIR/task" done ps-keep-01 >/dev/null

    # Sync with neither task in stdin — only open one should be deleted
    local input
    input='{"id":"ps-keep-03","t":"New task","spec":"my-spec"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync' -- "$input"
    assert_success
    # ps-keep-01 is done (not deleted), ps-keep-02 is open (deleted), ps-keep-03 is new (inserted)
    assert_output "inserted: 1, updated: 0, deleted: 1, skipped (done): 0"

    # Done task should still be done (not deleted)
    run "$SCRIPT_DIR/task" show ps-keep-01
    assert_success
    assert_output --partial "Status:      done"
}

# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------
@test "plan-sync is idempotent — second run produces no changes" {
    local input
    input='{"id":"ps-idem-01","t":"Idempotent task","p":1,"cat":"feat","spec":"my-spec","steps":["Do something"]}'

    # First sync
    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync' -- "$input"
    assert_success
    assert_output "inserted: 1, updated: 0, deleted: 0, skipped (done): 0"

    # Second sync with same input — task exists, gets updated (but values are the same)
    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync' -- "$input"
    assert_success
    assert_output "inserted: 0, updated: 1, deleted: 0, skipped (done): 0"

    # Verify task is still correct
    run "$SCRIPT_DIR/task" show ps-idem-01
    assert_success
    assert_output --partial "Idempotent task"
    assert_output --partial "Do something"
}

# ---------------------------------------------------------------------------
# Multiple spec_refs
# ---------------------------------------------------------------------------
@test "plan-sync handles multiple spec_refs independently" {
    # Create tasks in two different spec_ref groups
    "$SCRIPT_DIR/task" create ps-multi-01 "Spec A task 1" -r spec-a >/dev/null
    "$SCRIPT_DIR/task" create ps-multi-02 "Spec A task 2" -r spec-a >/dev/null
    "$SCRIPT_DIR/task" create ps-multi-03 "Spec B task 1" -r spec-b >/dev/null

    # Sync: keep ps-multi-01 from spec-a, delete ps-multi-02, keep ps-multi-03 from spec-b
    local input
    input='{"id":"ps-multi-01","t":"Spec A task 1","spec":"spec-a"}
{"id":"ps-multi-03","t":"Spec B task 1","spec":"spec-b"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync' -- "$input"
    assert_success
    assert_output "inserted: 0, updated: 2, deleted: 1, skipped (done): 0"

    # ps-multi-02 should be deleted
    run "$SCRIPT_DIR/task" show ps-multi-02
    assert_success
    assert_output --partial "Status:      deleted"

    # Others should still be active
    run "$SCRIPT_DIR/task" show ps-multi-01
    assert_success
    assert_output --partial "Status:      open"
}

# ---------------------------------------------------------------------------
# Tasks without spec_ref are not deleted
# ---------------------------------------------------------------------------
@test "plan-sync does not delete tasks without matching spec_ref" {
    # Create a task with no spec_ref
    "$SCRIPT_DIR/task" create ps-nospec-01 "No spec task" >/dev/null

    # Sync with a different spec_ref
    local input
    input='{"id":"ps-other-01","t":"Other spec task","spec":"other-spec"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync' -- "$input"
    assert_success
    assert_output "inserted: 1, updated: 0, deleted: 0, skipped (done): 0"

    # The no-spec task should remain untouched
    run "$SCRIPT_DIR/task" show ps-nospec-01
    assert_success
    assert_output --partial "Status:      open"
}

# ---------------------------------------------------------------------------
# Special characters in task data
# ---------------------------------------------------------------------------
@test "plan-sync handles special characters in titles and descriptions" {
    local input
    input='{"id":"ps-special-01","t":"Task with '\''quotes'\'' and \"doubles\"","d":"Description with <html> & symbols","p":1,"spec":"my-spec"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync' -- "$input"
    assert_success
    assert_output "inserted: 1, updated: 0, deleted: 0, skipped (done): 0"

    run "$SCRIPT_DIR/task" show ps-special-01
    assert_success
    assert_output --partial "quotes"
}

# ---------------------------------------------------------------------------
# Mixed operations in single sync
# ---------------------------------------------------------------------------
@test "plan-sync performs insert, update, delete, and skip in a single run" {
    # Set up: existing task (will be updated), done task (will be skipped),
    # task to delete (not in stdin), new task (to insert)
    "$SCRIPT_DIR/task" create ps-mix-01 "To update" -p 2 -r mix-spec >/dev/null
    "$SCRIPT_DIR/task" create ps-mix-02 "To delete" -p 2 -r mix-spec >/dev/null
    "$SCRIPT_DIR/task" create ps-mix-03 "Already done" -p 1 -r mix-spec >/dev/null
    export RALPH_AGENT_ID="test-agent"
    "$SCRIPT_DIR/task" claim --agent test-agent >/dev/null
    "$SCRIPT_DIR/task" done ps-mix-03 >/dev/null

    # Sync: update ps-mix-01, skip ps-mix-03 (done), delete ps-mix-02 (not in stdin), insert ps-mix-04
    local input
    input='{"id":"ps-mix-01","t":"Updated title","p":0,"spec":"mix-spec"}
{"id":"ps-mix-03","t":"Try update done","spec":"mix-spec"}
{"id":"ps-mix-04","t":"Brand new task","p":1,"spec":"mix-spec"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync' -- "$input"
    assert_success
    assert_output "inserted: 1, updated: 1, deleted: 1, skipped (done): 1"

    # Verify results
    run "$SCRIPT_DIR/task" show ps-mix-01
    assert_output --partial "Updated title"
    assert_output --partial "Priority:    0"

    run "$SCRIPT_DIR/task" show ps-mix-02
    assert_output --partial "Status:      deleted"

    run "$SCRIPT_DIR/task" show ps-mix-03
    assert_output --partial "Status:      done"
    assert_output --partial "Already done"

    run "$SCRIPT_DIR/task" show ps-mix-04
    assert_output --partial "Brand new task"
}

# --- Input validation (plan-sync-validation.md) ---

@test "plan-sync rejects invalid JSON line" {
    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync 2>"$TEST_WORK_DIR/stderr"' -- "not json at all"
    [ "$status" -eq 1 ]
    grep "line 1" "$TEST_WORK_DIR/stderr"
    grep "invalid JSON" "$TEST_WORK_DIR/stderr"
    refute_output --partial "inserted:"
}

@test "plan-sync rejects JSON missing id field" {
    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync 2>"$TEST_WORK_DIR/stderr"' -- '{"t":"No id"}'
    [ "$status" -eq 1 ]
    grep "line 1" "$TEST_WORK_DIR/stderr"
    grep '"id"' "$TEST_WORK_DIR/stderr"
    grep "missing or empty" "$TEST_WORK_DIR/stderr"
    refute_output --partial "inserted:"
}

@test "plan-sync rejects JSON with empty id field" {
    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync 2>"$TEST_WORK_DIR/stderr"' -- '{"id":"","t":"Empty id"}'
    [ "$status" -eq 1 ]
    grep "line 1" "$TEST_WORK_DIR/stderr"
    grep '"id"' "$TEST_WORK_DIR/stderr"
    grep "missing or empty" "$TEST_WORK_DIR/stderr"
}

@test "plan-sync rejects JSON missing t (title) field" {
    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync 2>"$TEST_WORK_DIR/stderr"' -- '{"id":"val-01"}'
    [ "$status" -eq 1 ]
    grep "line 1" "$TEST_WORK_DIR/stderr"
    grep '"t"' "$TEST_WORK_DIR/stderr"
    grep "missing or empty" "$TEST_WORK_DIR/stderr"
    refute_output --partial "inserted:"
}

@test "plan-sync rejects JSON with empty t (title) field" {
    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync 2>"$TEST_WORK_DIR/stderr"' -- '{"id":"val-01","t":""}'
    [ "$status" -eq 1 ]
    grep "line 1" "$TEST_WORK_DIR/stderr"
    grep '"t"' "$TEST_WORK_DIR/stderr"
    grep "missing or empty" "$TEST_WORK_DIR/stderr"
}

@test "plan-sync rejects negative priority" {
    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync 2>"$TEST_WORK_DIR/stderr"' -- '{"id":"val-01","t":"Good title","p":-1}'
    [ "$status" -eq 1 ]
    grep "line 1" "$TEST_WORK_DIR/stderr"
    grep '"p"' "$TEST_WORK_DIR/stderr"
    grep "non-negative integer" "$TEST_WORK_DIR/stderr"
    grep -- "-1" "$TEST_WORK_DIR/stderr"
}

@test "plan-sync rejects non-integer priority" {
    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync 2>"$TEST_WORK_DIR/stderr"' -- '{"id":"val-01","t":"Good title","p":"high"}'
    [ "$status" -eq 1 ]
    grep "line 1" "$TEST_WORK_DIR/stderr"
    grep '"p"' "$TEST_WORK_DIR/stderr"
    grep "non-negative integer" "$TEST_WORK_DIR/stderr"
    grep "high" "$TEST_WORK_DIR/stderr"
}

@test "plan-sync rejects float priority" {
    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync 2>"$TEST_WORK_DIR/stderr"' -- '{"id":"val-01","t":"Good title","p":1.5}'
    [ "$status" -eq 1 ]
    grep "line 1" "$TEST_WORK_DIR/stderr"
    grep '"p"' "$TEST_WORK_DIR/stderr"
    grep "non-negative integer" "$TEST_WORK_DIR/stderr"
}

@test "plan-sync error identifies correct line number for second line" {
    local line1='{"id":"val-01","t":"Good"}'
    local line2='{"id":"","t":"Bad"}'
    local input="${line1}
${line2}"
    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync 2>"$TEST_WORK_DIR/stderr"' -- "$input"
    [ "$status" -eq 1 ]
    grep "line 2" "$TEST_WORK_DIR/stderr"
}

@test "plan-sync validation failure causes no partial writes" {
    local line1='{"id":"val-no-write-01","t":"Good task","spec":"my-spec"}'
    local line2='{"id":"","t":"Bad"}'
    local input="${line1}
${line2}"
    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync 2>"$TEST_WORK_DIR/stderr"' -- "$input"
    [ "$status" -eq 1 ]

    run bash -c '"$SCRIPT_DIR/task" show val-no-write-01 2>&1'
    [ "$status" -eq 2 ]
    echo "$output" | grep -i "not found"
}

@test "plan-sync skips empty lines during validation" {
    local input=$'\n{"id":"val-skip-01","t":"Good task","spec":"my-spec"}\n\n'
    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync' -- "$input"
    assert_success
    assert_output "inserted: 1, updated: 0, deleted: 0, skipped (done): 0"
}

@test "plan-sync accepts valid input with optional p absent" {
    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/task" plan-sync' -- '{"id":"val-opt-01","t":"No priority","spec":"my-spec"}'
    assert_success
    assert_output "inserted: 1, updated: 0, deleted: 0, skipped (done): 0"
}
