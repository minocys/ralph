#!/usr/bin/env bats
# test/task_scope_isolation.bats — Scope isolation tests for task commands
# Verifies that tasks created in one scope (repo/branch) are invisible to
# commands running in a different scope.
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

    # Define two distinct scopes for isolation testing
    export SCOPE_A_REPO="owner/repo-alpha"
    export SCOPE_A_BRANCH="main"
    export SCOPE_B_REPO="owner/repo-beta"
    export SCOPE_B_BRANCH="main"
}

teardown() {
    if [[ -n "${TEST_SCHEMA:-}" ]] && [[ -n "${RALPH_DB_URL_ORIG:-}" ]]; then
        psql "$RALPH_DB_URL_ORIG" -tAX -c "DROP SCHEMA IF EXISTS $TEST_SCHEMA CASCADE" >/dev/null 2>&1
    fi
    [[ -d "${TEST_WORK_DIR:-}" ]] && rm -rf "$TEST_WORK_DIR"
    [[ -d "${STUB_DIR:-}" ]] && rm -rf "$STUB_DIR"
}

# ---------------------------------------------------------------------------
# Scope helper: run task command in scope A
# ---------------------------------------------------------------------------
task_in_scope_a() {
    RALPH_SCOPE_REPO="$SCOPE_A_REPO" RALPH_SCOPE_BRANCH="$SCOPE_A_BRANCH" \
        "$SCRIPT_DIR/task" "$@"
}

# ---------------------------------------------------------------------------
# Scope helper: run task command in scope B
# ---------------------------------------------------------------------------
task_in_scope_b() {
    RALPH_SCOPE_REPO="$SCOPE_B_REPO" RALPH_SCOPE_BRANCH="$SCOPE_B_BRANCH" \
        "$SCRIPT_DIR/task" "$@"
}

# ===========================================================================
# task list — scope isolation
# ===========================================================================

@test "task list only shows tasks from current scope" {
    # Create tasks in scope A
    task_in_scope_a create "iso-01" "Alpha task" -p 1 -c "feat"

    # Create tasks in scope B
    task_in_scope_b create "iso-02" "Beta task" -p 1 -c "feat"

    # List in scope A — should see only Alpha
    run task_in_scope_a list
    assert_success
    assert_output --partial "iso-01"
    assert_output --partial "Alpha task"
    refute_output --partial "iso-02"
    refute_output --partial "Beta task"

    # List in scope B — should see only Beta
    run task_in_scope_b list
    assert_success
    assert_output --partial "iso-02"
    assert_output --partial "Beta task"
    refute_output --partial "iso-01"
    refute_output --partial "Alpha task"
}

@test "task list --markdown only shows tasks from current scope" {
    task_in_scope_a create "md-01" "Alpha md" -p 0
    task_in_scope_b create "md-02" "Beta md" -p 0

    run task_in_scope_a list --markdown
    assert_success
    assert_output --partial "## Task md-01"
    assert_output --partial "title: Alpha md"
    refute_output --partial "md-02"
    refute_output --partial "Beta md"
}

@test "task list returns empty when no tasks in current scope" {
    # Create tasks only in scope A
    task_in_scope_a create "only-a" "Only in A" -p 1

    # List in scope B — should be empty
    run task_in_scope_b list
    assert_success
    assert_output ""
}

@test "same slug in different scopes are independent in list" {
    task_in_scope_a create "shared-slug" "Alpha version" -p 1
    task_in_scope_b create "shared-slug" "Beta version" -p 1

    run task_in_scope_a list --markdown
    assert_success
    assert_output --partial "title: Alpha version"
    refute_output --partial "Beta version"

    run task_in_scope_b list --markdown
    assert_success
    assert_output --partial "title: Beta version"
    refute_output --partial "Alpha version"
}

# ===========================================================================
# task peek — scope isolation
# ===========================================================================

@test "task peek only shows tasks from current scope" {
    task_in_scope_a create "peek-a" "Peek Alpha" -p 1
    task_in_scope_b create "peek-b" "Peek Beta" -p 1

    run task_in_scope_a peek
    assert_success
    assert_output --partial "## Task peek-a"
    assert_output --partial "title: Peek Alpha"
    refute_output --partial "peek-b"
    refute_output --partial "Peek Beta"

    run task_in_scope_b peek
    assert_success
    assert_output --partial "## Task peek-b"
    assert_output --partial "title: Peek Beta"
    refute_output --partial "peek-a"
    refute_output --partial "Peek Alpha"
}

@test "task peek returns empty when no tasks in current scope" {
    task_in_scope_a create "peek-only-a" "Only in A" -p 0

    run task_in_scope_b peek
    assert_success
    assert_output ""
}

@test "task peek active tasks scoped to current scope" {
    task_in_scope_a create "peek-act-a" "Active Alpha" -p 0
    task_in_scope_b create "peek-act-b" "Active Beta" -p 0

    # Claim in scope A to make it active
    task_in_scope_a claim --agent "ag01" >/dev/null

    # Peek in scope A should show active task
    run task_in_scope_a peek
    assert_success
    assert_output --partial "status: active"
    assert_output --partial "peek-act-a"
    refute_output --partial "peek-act-b"

    # Peek in scope B should show open task only
    run task_in_scope_b peek
    assert_success
    assert_output --partial "status: open"
    assert_output --partial "peek-act-b"
    refute_output --partial "peek-act-a"
}

# ===========================================================================
# task claim — scope isolation
# ===========================================================================

@test "task claim only claims tasks from current scope" {
    task_in_scope_a create "claim-a" "Claim Alpha" -p 0
    task_in_scope_b create "claim-b" "Claim Beta" -p 0

    # Claim in scope A — should get claim-a
    run task_in_scope_a claim --agent "ag01"
    assert_success
    assert_output --partial "id: claim-a"
    assert_output --partial "title: Claim Alpha"
    refute_output --partial "claim-b"

    # Claim in scope B — should get claim-b
    run task_in_scope_b claim --agent "ag02"
    assert_success
    assert_output --partial "id: claim-b"
    assert_output --partial "title: Claim Beta"
    refute_output --partial "claim-a"
}

@test "task claim exits 2 when no tasks in current scope" {
    task_in_scope_a create "claim-only-a" "Only in A" -p 0

    # Claim in scope B — no tasks available
    run task_in_scope_b claim --agent "ag01"
    assert_failure 2
}

@test "targeted claim rejects task from different scope" {
    task_in_scope_a create "cross-claim" "Cross scope task" -p 0

    # Try targeted claim from scope B — slug doesn't exist in scope B
    run task_in_scope_b claim "cross-claim" --agent "ag01"
    assert_failure 2
}

# ===========================================================================
# task plan-export — scope isolation
# ===========================================================================

@test "plan-export only shows tasks from current scope" {
    # Insert via plan-sync to set spec_ref
    local input_a='{"id":"pe-a1","t":"Export Alpha 1","p":1,"spec":"alpha.md"}
{"id":"pe-a2","t":"Export Alpha 2","p":2,"spec":"alpha.md"}'

    local input_b='{"id":"pe-b1","t":"Export Beta 1","p":1,"spec":"beta.md"}'

    printf "%s\n" "$input_a" | task_in_scope_a plan-sync >/dev/null
    printf "%s\n" "$input_b" | task_in_scope_b plan-sync >/dev/null

    # plan-export in scope A
    run task_in_scope_a plan-export
    assert_success
    assert_output --partial "pe-a1"
    assert_output --partial "pe-a2"
    refute_output --partial "pe-b1"

    # plan-export --markdown in scope A
    run task_in_scope_a plan-export --markdown
    assert_success
    assert_output --partial "## Task pe-a1"
    assert_output --partial "## Task pe-a2"
    refute_output --partial "pe-b1"
}

@test "plan-export returns empty when no tasks in current scope" {
    local input_a='{"id":"pe-only-a","t":"Only Alpha","p":1,"spec":"alpha.md"}'
    printf "%s\n" "$input_a" | task_in_scope_a plan-sync >/dev/null

    run task_in_scope_b plan-export
    assert_success
    assert_output ""
}

# ===========================================================================
# task plan-status — scope isolation
# ===========================================================================

@test "plan-status counts only tasks from current scope" {
    # Create 2 open tasks in scope A
    task_in_scope_a create "ps-a1" "Status Alpha 1" -p 1
    task_in_scope_a create "ps-a2" "Status Alpha 2" -p 2

    # Create 1 open task in scope B
    task_in_scope_b create "ps-b1" "Status Beta 1" -p 1

    # plan-status in scope A should show 2 open
    run task_in_scope_a plan-status
    assert_success
    [[ "$output" == *"2 open"* ]]

    # plan-status in scope B should show 1 open
    run task_in_scope_b plan-status
    assert_success
    [[ "$output" == *"1 open"* ]]
}

@test "plan-status shows zeros when no tasks in current scope" {
    task_in_scope_a create "ps-only-a" "Only in A" -p 1

    run task_in_scope_b plan-status
    assert_success
    [[ "$output" == *"0 open"* ]]
    [[ "$output" == *"0 active"* ]]
    [[ "$output" == *"0 done"* ]]
}

# ===========================================================================
# task plan-sync — scope isolation
# ===========================================================================

@test "plan-sync in scope B does not delete tasks in scope A" {
    # Sync tasks in scope A
    local input_a='{"id":"sync-a1","t":"Sync Alpha 1","p":1,"spec":"shared.md"}
{"id":"sync-a2","t":"Sync Alpha 2","p":2,"spec":"shared.md"}'
    printf "%s\n" "$input_a" | task_in_scope_a plan-sync >/dev/null

    # Sync different tasks in scope B with the SAME spec_ref
    local input_b='{"id":"sync-b1","t":"Sync Beta 1","p":1,"spec":"shared.md"}'
    printf "%s\n" "$input_b" | task_in_scope_b plan-sync >/dev/null

    # Verify scope A tasks are untouched
    run task_in_scope_a list
    assert_success
    assert_output --partial "sync-a1"
    assert_output --partial "sync-a2"

    # Verify scope B has its own task
    run task_in_scope_b list
    assert_success
    assert_output --partial "sync-b1"
    refute_output --partial "sync-a1"
    refute_output --partial "sync-a2"
}

@test "plan-sync orphan deletion is scoped" {
    # Sync 2 tasks in scope A
    local input_a='{"id":"orp-a1","t":"Orphan Alpha 1","p":1,"spec":"orphan.md"}
{"id":"orp-a2","t":"Orphan Alpha 2","p":2,"spec":"orphan.md"}'
    printf "%s\n" "$input_a" | task_in_scope_a plan-sync >/dev/null

    # Re-sync scope A with only 1 task — orp-a2 should be deleted
    local input_a2='{"id":"orp-a1","t":"Orphan Alpha 1","p":1,"spec":"orphan.md"}'
    run bash -c 'printf "%s\n" "$1" | RALPH_SCOPE_REPO="$2" RALPH_SCOPE_BRANCH="$3" "$SCRIPT_DIR/task" plan-sync' \
        -- "$input_a2" "$SCOPE_A_REPO" "$SCOPE_A_BRANCH"
    assert_success
    assert_output --partial "deleted: 1"

    # Verify orp-a1 survives, orp-a2 deleted in scope A
    run task_in_scope_a list
    assert_success
    assert_output --partial "orp-a1"
    refute_output --partial "orp-a2"
}

@test "plan-sync inserts tasks independently per scope" {
    local input='{"id":"same-id","t":"Task in scope","p":1,"spec":"multi.md"}'

    # Sync same ID in both scopes
    printf "%s\n" "$input" | task_in_scope_a plan-sync >/dev/null
    printf "%s\n" "$input" | task_in_scope_b plan-sync >/dev/null

    # Both scopes should have the task
    run task_in_scope_a list
    assert_success
    assert_output --partial "same-id"

    run task_in_scope_b list
    assert_success
    assert_output --partial "same-id"

    # Verify they are distinct DB rows (different UUIDs)
    local uuid_a uuid_b
    uuid_a=$(psql "$RALPH_DB_URL" -tAX -c "SELECT id FROM tasks WHERE slug='same-id' AND scope_repo='$SCOPE_A_REPO' AND scope_branch='$SCOPE_A_BRANCH'")
    uuid_b=$(psql "$RALPH_DB_URL" -tAX -c "SELECT id FROM tasks WHERE slug='same-id' AND scope_repo='$SCOPE_B_REPO' AND scope_branch='$SCOPE_B_BRANCH'")
    [[ "$uuid_a" != "$uuid_b" ]]
}

# ===========================================================================
# task show — scope isolation
# ===========================================================================

@test "task show returns task from current scope only" {
    task_in_scope_a create "show-x" "Show Alpha" -p 1 -d "Alpha description"
    task_in_scope_b create "show-x" "Show Beta" -p 2 -d "Beta description"

    # Show in scope A
    run task_in_scope_a show "show-x"
    assert_success
    assert_output --partial "Show Alpha"
    assert_output --partial "Alpha description"
    refute_output --partial "Show Beta"
    refute_output --partial "Beta description"

    # Show in scope B
    run task_in_scope_b show "show-x"
    assert_success
    assert_output --partial "Show Beta"
    assert_output --partial "Beta description"
    refute_output --partial "Show Alpha"
    refute_output --partial "Alpha description"
}

@test "task show exits 2 for slug only in other scope" {
    task_in_scope_a create "show-only-a" "Only in A"

    run task_in_scope_b show "show-only-a"
    assert_failure 2
}

# ===========================================================================
# task agent list — scope isolation
# ===========================================================================

@test "agent list only shows agents from current scope" {
    # Register agent in scope A
    run task_in_scope_a agent register
    assert_success
    local agent_a="$output"

    # Register agent in scope B
    run task_in_scope_b agent register
    assert_success
    local agent_b="$output"

    # List in scope A — should see only agent_a
    run task_in_scope_a agent list
    assert_success
    assert_output --partial "$agent_a"
    refute_output --partial "$agent_b"

    # List in scope B — should see only agent_b
    run task_in_scope_b agent list
    assert_success
    assert_output --partial "$agent_b"
    refute_output --partial "$agent_a"
}

@test "agent list returns empty when no agents in current scope" {
    # Register agent only in scope A
    run task_in_scope_a agent register
    assert_success

    # List in scope B — should be empty
    run task_in_scope_b agent list
    assert_success
    [[ -z "$output" ]]
}

@test "agent list excludes stopped agents in same scope" {
    # Register two agents in scope A
    run task_in_scope_a agent register
    assert_success
    local agent1="$output"

    run task_in_scope_a agent register
    assert_success
    local agent2="$output"

    # Stop agent1
    task_in_scope_a agent deregister "$agent1"

    # List in scope A — should only see agent2
    run task_in_scope_a agent list
    assert_success
    assert_output --partial "$agent2"
    refute_output --partial "$agent1"
}
