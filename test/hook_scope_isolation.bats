#!/usr/bin/env bats
# test/hook_scope_isolation.bats — Verify hooks inherit scope env vars from loop
# When RALPH_SCOPE_REPO and RALPH_SCOPE_BRANCH are set before running a hook,
# the hook's task commands (list, fail) must use the correct scope.
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

    # Hook environment variables
    export RALPH_TASK_SCRIPT="$SCRIPT_DIR/lib/task"
    export RALPH_AGENT_ID="a1b2"

    # Two distinct scopes
    export SCOPE_A_REPO="owner/hook-alpha"
    export SCOPE_A_BRANCH="main"
    export SCOPE_B_REPO="owner/hook-beta"
    export SCOPE_B_BRANCH="main"

    # Ensure schema is initialized
    "$SCRIPT_DIR/lib/task" create "hs-setup" "schema init" >/dev/null 2>&1
    psql "$RALPH_DB_URL" -tAX -c "DELETE FROM tasks WHERE slug='hs-setup';" >/dev/null 2>&1
}

teardown() {
    if [[ -n "${TEST_SCHEMA:-}" ]] && [[ -n "${RALPH_DB_URL_ORIG:-}" ]]; then
        psql "$RALPH_DB_URL_ORIG" -tAX -c "DROP SCHEMA IF EXISTS $TEST_SCHEMA CASCADE" >/dev/null 2>&1
    fi
    [[ -d "${TEST_WORK_DIR:-}" ]] && rm -rf "$TEST_WORK_DIR"
    [[ -d "${STUB_DIR:-}" ]] && rm -rf "$STUB_DIR"
}

# ---------------------------------------------------------------------------
# Scope helpers: create tasks and run hooks in specific scopes
# ---------------------------------------------------------------------------
task_in_scope_a() {
    RALPH_SCOPE_REPO="$SCOPE_A_REPO" RALPH_SCOPE_BRANCH="$SCOPE_A_BRANCH" \
        "$SCRIPT_DIR/lib/task" "$@"
}

task_in_scope_b() {
    RALPH_SCOPE_REPO="$SCOPE_B_REPO" RALPH_SCOPE_BRANCH="$SCOPE_B_BRANCH" \
        "$SCRIPT_DIR/lib/task" "$@"
}

hook_precompact_in_scope_a() {
    RALPH_SCOPE_REPO="$SCOPE_A_REPO" RALPH_SCOPE_BRANCH="$SCOPE_A_BRANCH" \
        "$SCRIPT_DIR/hooks/precompact.sh" "$@"
}

hook_precompact_in_scope_b() {
    RALPH_SCOPE_REPO="$SCOPE_B_REPO" RALPH_SCOPE_BRANCH="$SCOPE_B_BRANCH" \
        "$SCRIPT_DIR/hooks/precompact.sh" "$@"
}

hook_session_end_in_scope_a() {
    RALPH_SCOPE_REPO="$SCOPE_A_REPO" RALPH_SCOPE_BRANCH="$SCOPE_A_BRANCH" \
        "$SCRIPT_DIR/hooks/session_end.sh" "$@"
}

hook_session_end_in_scope_b() {
    RALPH_SCOPE_REPO="$SCOPE_B_REPO" RALPH_SCOPE_BRANCH="$SCOPE_B_BRANCH" \
        "$SCRIPT_DIR/hooks/session_end.sh" "$@"
}

# ===========================================================================
# PreCompact hook — scope isolation
# ===========================================================================

@test "precompact hook only fails active task in its own scope" {
    # Create active tasks in both scopes, assigned to our agent
    task_in_scope_a create "hpc-01" "Alpha task"
    psql "$RALPH_DB_URL" -tAX -c \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='hpc-01' AND scope_repo='$SCOPE_A_REPO' AND scope_branch='$SCOPE_A_BRANCH';" >/dev/null

    task_in_scope_b create "hpc-02" "Beta task"
    psql "$RALPH_DB_URL" -tAX -c \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='hpc-02' AND scope_repo='$SCOPE_B_REPO' AND scope_branch='$SCOPE_B_BRANCH';" >/dev/null

    # Run precompact hook in scope A
    run hook_precompact_in_scope_a
    assert_success

    # Scope A task must be failed (back to open)
    local status_a
    status_a=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE slug='hpc-01' AND scope_repo='$SCOPE_A_REPO' AND scope_branch='$SCOPE_A_BRANCH';")
    [ "$status_a" = "open" ]

    # Scope B task must remain active (untouched by scope A hook)
    local status_b
    status_b=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE slug='hpc-02' AND scope_repo='$SCOPE_B_REPO' AND scope_branch='$SCOPE_B_BRANCH';")
    [ "$status_b" = "active" ]
}

@test "precompact hook outputs continue:true when no active task in scope" {
    # Create active task only in scope B
    task_in_scope_b create "hpc-03" "Beta only"
    psql "$RALPH_DB_URL" -tAX -c \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='hpc-03' AND scope_repo='$SCOPE_B_REPO' AND scope_branch='$SCOPE_B_BRANCH';" >/dev/null

    # Run precompact hook in scope A (nothing active here)
    run hook_precompact_in_scope_a
    assert_success
    echo "$output" | jq -e '.continue == true'

    # Scope B task must remain active
    local status_b
    status_b=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE slug='hpc-03' AND scope_repo='$SCOPE_B_REPO' AND scope_branch='$SCOPE_B_BRANCH';")
    [ "$status_b" = "active" ]
}

@test "precompact hook outputs continue:false JSON for active task in scope" {
    task_in_scope_a create "hpc-04" "Alpha active"
    psql "$RALPH_DB_URL" -tAX -c \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='hpc-04' AND scope_repo='$SCOPE_A_REPO' AND scope_branch='$SCOPE_A_BRANCH';" >/dev/null

    run bash -c 'RALPH_SCOPE_REPO="$SCOPE_A_REPO" RALPH_SCOPE_BRANCH="$SCOPE_A_BRANCH" "$SCRIPT_DIR/hooks/precompact.sh" 2>/dev/null'
    assert_success
    echo "$output" | jq -e '.continue == false'
    echo "$output" | jq -e '.stopReason == "Context Limit Reached"'
}

# ===========================================================================
# SessionEnd hook — scope isolation
# ===========================================================================

@test "session end hook only fails active task in its own scope" {
    # Create active tasks in both scopes, assigned to our agent
    task_in_scope_a create "hse-01" "Alpha task"
    psql "$RALPH_DB_URL" -tAX -c \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='hse-01' AND scope_repo='$SCOPE_A_REPO' AND scope_branch='$SCOPE_A_BRANCH';" >/dev/null

    task_in_scope_b create "hse-02" "Beta task"
    psql "$RALPH_DB_URL" -tAX -c \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='hse-02' AND scope_repo='$SCOPE_B_REPO' AND scope_branch='$SCOPE_B_BRANCH';" >/dev/null

    # Run session_end hook in scope A
    run hook_session_end_in_scope_a
    assert_success

    # Scope A task must be failed (back to open)
    local status_a
    status_a=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE slug='hse-01' AND scope_repo='$SCOPE_A_REPO' AND scope_branch='$SCOPE_A_BRANCH';")
    [ "$status_a" = "open" ]

    # Scope B task must remain active (untouched by scope A hook)
    local status_b
    status_b=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE slug='hse-02' AND scope_repo='$SCOPE_B_REPO' AND scope_branch='$SCOPE_B_BRANCH';")
    [ "$status_b" = "active" ]
}

@test "session end hook is a no-op when no active task in scope" {
    # Create active task only in scope B
    task_in_scope_b create "hse-03" "Beta only"
    psql "$RALPH_DB_URL" -tAX -c \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='hse-03' AND scope_repo='$SCOPE_B_REPO' AND scope_branch='$SCOPE_B_BRANCH';" >/dev/null

    # Run session_end hook in scope A (nothing active here)
    run hook_session_end_in_scope_a
    assert_success

    # Scope B task must remain active
    local status_b
    status_b=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM tasks WHERE slug='hse-03' AND scope_repo='$SCOPE_B_REPO' AND scope_branch='$SCOPE_B_BRANCH';")
    [ "$status_b" = "active" ]
}

@test "session end hook increments retry_count only for task in scope" {
    # Create active tasks in both scopes
    task_in_scope_a create "hse-04" "Alpha retry"
    psql "$RALPH_DB_URL" -tAX -c \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='hse-04' AND scope_repo='$SCOPE_A_REPO' AND scope_branch='$SCOPE_A_BRANCH';" >/dev/null

    task_in_scope_b create "hse-05" "Beta retry"
    psql "$RALPH_DB_URL" -tAX -c \
        "UPDATE tasks SET status='active', assignee='$RALPH_AGENT_ID' WHERE slug='hse-05' AND scope_repo='$SCOPE_B_REPO' AND scope_branch='$SCOPE_B_BRANCH';" >/dev/null

    # Run session_end hook in scope A
    run hook_session_end_in_scope_a
    assert_success

    # Scope A retry_count must be incremented
    local retry_a
    retry_a=$(psql "$RALPH_DB_URL" -tAX -c "SELECT retry_count FROM tasks WHERE slug='hse-04' AND scope_repo='$SCOPE_A_REPO' AND scope_branch='$SCOPE_A_BRANCH';")
    [ "$retry_a" = "1" ]

    # Scope B retry_count must remain 0 (untouched)
    local retry_b
    retry_b=$(psql "$RALPH_DB_URL" -tAX -c "SELECT retry_count FROM tasks WHERE slug='hse-05' AND scope_repo='$SCOPE_B_REPO' AND scope_branch='$SCOPE_B_BRANCH';")
    [ "$retry_b" = "0" ]
}
