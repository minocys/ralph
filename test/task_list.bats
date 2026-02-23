#!/usr/bin/env bats
# test/task_list.bats — Tests for the task list command
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
# Default list (excludes deleted)
# ---------------------------------------------------------------------------
@test "task list shows header when tasks exist" {
    "$SCRIPT_DIR/task" create "list-01" "First task" -p 1 -c "feat" > /dev/null
    run "$SCRIPT_DIR/task" list
    assert_success
    assert_output --partial "ID"
    assert_output --partial "TITLE"
    assert_output --partial "AGENT"
}

@test "task list shows created tasks" {
    "$SCRIPT_DIR/task" create "list-01" "First task" -p 1 -c "feat" > /dev/null
    "$SCRIPT_DIR/task" create "list-02" "Second task" -p 2 -c "bug" > /dev/null
    run "$SCRIPT_DIR/task" list
    assert_success
    assert_output --partial "list-01"
    assert_output --partial "First task"
    assert_output --partial "list-02"
    assert_output --partial "Second task"
}

@test "task list excludes deleted tasks by default" {
    "$SCRIPT_DIR/task" create "alive-01" "Alive task" > /dev/null
    "$SCRIPT_DIR/task" create "dead-01" "Dead task" > /dev/null
    # Soft delete by updating status directly
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status = 'deleted', deleted_at = now() WHERE slug = 'dead-01' AND scope_repo = 'test/repo' AND scope_branch = 'main'" > /dev/null

    run "$SCRIPT_DIR/task" list
    assert_success
    assert_output --partial "alive-01"
    refute_output --partial "dead-01"
}

@test "task list returns empty output with no tasks" {
    run "$SCRIPT_DIR/task" list
    assert_success
    # No header printed when no tasks
    assert_output ""
}

# ---------------------------------------------------------------------------
# --status filter
# ---------------------------------------------------------------------------
@test "task list --status filters by single status" {
    "$SCRIPT_DIR/task" create "open-01" "Open task" > /dev/null
    "$SCRIPT_DIR/task" create "active-01" "Active task" > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status = 'active' WHERE slug = 'active-01' AND scope_repo = 'test/repo' AND scope_branch = 'main'" > /dev/null

    run "$SCRIPT_DIR/task" list --status "open"
    assert_success
    assert_output --partial "open-01"
    refute_output --partial "active-01"
}

@test "task list --status filters by comma-separated statuses" {
    "$SCRIPT_DIR/task" create "s-open" "Open task" > /dev/null
    "$SCRIPT_DIR/task" create "s-active" "Active task" > /dev/null
    "$SCRIPT_DIR/task" create "s-done" "Done task" > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status = 'active' WHERE slug = 's-active' AND scope_repo = 'test/repo' AND scope_branch = 'main'" > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status = 'done' WHERE slug = 's-done' AND scope_repo = 'test/repo' AND scope_branch = 'main'" > /dev/null

    run "$SCRIPT_DIR/task" list --status "open,active"
    assert_success
    assert_output --partial "s-open"
    assert_output --partial "s-active"
    refute_output --partial "s-done"
}

@test "task list --status deleted shows deleted tasks" {
    "$SCRIPT_DIR/task" create "del-01" "Deleted task" > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status = 'deleted', deleted_at = now() WHERE slug = 'del-01' AND scope_repo = 'test/repo' AND scope_branch = 'main'" > /dev/null

    run "$SCRIPT_DIR/task" list --status "deleted"
    assert_success
    assert_output --partial "del-01"
}

# ---------------------------------------------------------------------------
# Priority ordering
# ---------------------------------------------------------------------------
@test "task list orders by priority ascending then created_at" {
    "$SCRIPT_DIR/task" create "low-01" "Low priority" -p 3 > /dev/null
    "$SCRIPT_DIR/task" create "high-01" "High priority" -p 0 > /dev/null
    "$SCRIPT_DIR/task" create "mid-01" "Mid priority" -p 1 > /dev/null

    run "$SCRIPT_DIR/task" list
    assert_success
    # high-01 (p=0) should appear before mid-01 (p=1) before low-01 (p=3)
    local high_line mid_line low_line
    high_line=$(echo "$output" | grep -n "high-01" | cut -d: -f1)
    mid_line=$(echo "$output" | grep -n "mid-01" | cut -d: -f1)
    low_line=$(echo "$output" | grep -n "low-01" | cut -d: -f1)
    [ "$high_line" -lt "$mid_line" ]
    [ "$mid_line" -lt "$low_line" ]
}

# ---------------------------------------------------------------------------
# --markdown output
# ---------------------------------------------------------------------------
@test "task list --markdown outputs markdown-KV format" {
    "$SCRIPT_DIR/task" create "json-01" "JSON task" -p 1 -c "feat" -d "A description" > /dev/null

    run "$SCRIPT_DIR/task" list --markdown
    assert_success
    assert_output --partial "## Task json-01"
    assert_output --partial "id: json-01"
    assert_output --partial "title: JSON task"
    assert_output --partial "priority: 1"
    assert_output --partial "status: open"
    assert_output --partial "category: feat"
}

@test "task list --markdown includes full-name keys" {
    "$SCRIPT_DIR/task" create "json-02" "JSON keys test" -p 1 -c "feat" > /dev/null

    run "$SCRIPT_DIR/task" list --markdown
    assert_success
    assert_output --partial "id: json-02"
    assert_output --partial "title: JSON keys test"
    assert_output --partial "priority: 1"
    assert_output --partial "status: open"
    assert_output --partial "category: feat"
}

@test "task list --markdown includes steps and deps" {
    "$SCRIPT_DIR/task" create "blocker-x" "Blocker" > /dev/null
    "$SCRIPT_DIR/task" create "json-03" "Task with steps and deps" --deps "blocker-x" > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET steps = ARRAY['Do thing']::TEXT[] WHERE slug = 'json-03' AND scope_repo = 'test/repo' AND scope_branch = 'main'" >/dev/null

    run "$SCRIPT_DIR/task" list --markdown
    assert_success
    assert_output --partial "deps: blocker-x"
    assert_output --partial "steps:"
    assert_output --partial "- Do thing"
}

@test "task list --markdown with --status combines both flags" {
    "$SCRIPT_DIR/task" create "combo-01" "Open" > /dev/null
    "$SCRIPT_DIR/task" create "combo-02" "Done" > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status = 'done' WHERE slug = 'combo-02' AND scope_repo = 'test/repo' AND scope_branch = 'main'" > /dev/null

    run "$SCRIPT_DIR/task" list --status "done" --markdown
    assert_success
    refute_output --partial "combo-01"
    assert_output --partial "## Task combo-02"
    assert_output --partial "status: done"
}

@test "task list --markdown separates multiple tasks with blank lines" {
    "$SCRIPT_DIR/task" create "sep-01" "First" -p 0 > /dev/null
    "$SCRIPT_DIR/task" create "sep-02" "Second" -p 1 > /dev/null

    run "$SCRIPT_DIR/task" list --markdown
    assert_success
    assert_output --partial "## Task sep-01"
    assert_output --partial "## Task sep-02"
    # Blank line separates the two task sections
    [[ "$output" == *$'\n\n'"## Task"* ]]
}

@test "task list --markdown returns empty output with no tasks" {
    run "$SCRIPT_DIR/task" list --markdown
    assert_success
    assert_output ""
}

# ---------------------------------------------------------------------------
# Table vs markdown-KV format contrast
# ---------------------------------------------------------------------------
@test "task list table format does not contain markdown-KV markers" {
    "$SCRIPT_DIR/task" create "fmt-01" "Format test" -p 1 -c "feat" > /dev/null

    run "$SCRIPT_DIR/task" list
    assert_success
    # Table format must NOT contain markdown-KV section headers or key: value lines
    refute_output --partial "## Task"
    refute_output --partial "id: fmt-01"
    refute_output --partial "title: Format test"
    # Table format MUST contain columnar header
    assert_output --partial "ID"
    assert_output --partial "TITLE"
    assert_output --partial "AGENT"
}

@test "task list --markdown omits null fields" {
    "$SCRIPT_DIR/task" create "null-01" "Minimal task" -p 2 > /dev/null

    run "$SCRIPT_DIR/task" list --markdown
    assert_success
    assert_output --partial "## Task null-01"
    assert_output --partial "title: Minimal task"
    assert_output --partial "priority: 2"
    assert_output --partial "status: open"
    # Null optional fields must be omitted
    refute_output --partial "category:"
    refute_output --partial "spec:"
    refute_output --partial "ref:"
    refute_output --partial "assignee:"
    refute_output --partial "deps:"
    refute_output --partial "steps:"
}

# ---------------------------------------------------------------------------
# Table format: assignee column
# ---------------------------------------------------------------------------
@test "task list table shows assignee when set" {
    "$SCRIPT_DIR/task" create "agent-01" "Assigned task" > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET assignee = 'a7f2' WHERE slug = 'agent-01' AND scope_repo = 'test/repo' AND scope_branch = 'main'" > /dev/null

    run "$SCRIPT_DIR/task" list
    assert_success
    assert_output --partial "a7f2"
}

# ---------------------------------------------------------------------------
# --assignee filter
# ---------------------------------------------------------------------------
@test "task list --assignee filters by assignee" {
    "$SCRIPT_DIR/task" create "asn-01" "My task" > /dev/null
    "$SCRIPT_DIR/task" create "asn-02" "Other task" > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET assignee = 'a1b2' WHERE slug = 'asn-01' AND scope_repo = 'test/repo' AND scope_branch = 'main'" > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET assignee = 'z9y8' WHERE slug = 'asn-02' AND scope_repo = 'test/repo' AND scope_branch = 'main'" > /dev/null

    run "$SCRIPT_DIR/task" list --assignee "a1b2"
    assert_success
    assert_output --partial "asn-01"
    refute_output --partial "asn-02"
}

@test "task list --assignee with --status combines both filters" {
    "$SCRIPT_DIR/task" create "asn-03" "Active mine" > /dev/null
    "$SCRIPT_DIR/task" create "asn-04" "Open mine" > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET status = 'active', assignee = 'a1b2' WHERE slug = 'asn-03' AND scope_repo = 'test/repo' AND scope_branch = 'main'" > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET assignee = 'a1b2' WHERE slug = 'asn-04' AND scope_repo = 'test/repo' AND scope_branch = 'main'" > /dev/null

    run "$SCRIPT_DIR/task" list --status "active" --assignee "a1b2"
    assert_success
    assert_output --partial "asn-03"
    refute_output --partial "asn-04"
}

@test "task list --assignee returns empty when no tasks match" {
    "$SCRIPT_DIR/task" create "asn-05" "Unassigned task" > /dev/null

    run "$SCRIPT_DIR/task" list --assignee "nobody"
    assert_success
    assert_output ""
}

@test "task list --assignee works with --markdown" {
    "$SCRIPT_DIR/task" create "asn-06" "Markdown assignee" -p 1 > /dev/null
    "$SCRIPT_DIR/task" create "asn-07" "Other agent" -p 1 > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET assignee = 'a1b2' WHERE slug = 'asn-06' AND scope_repo = 'test/repo' AND scope_branch = 'main'" > /dev/null
    psql "$RALPH_DB_URL" -tAX -c "UPDATE tasks SET assignee = 'z9y8' WHERE slug = 'asn-07' AND scope_repo = 'test/repo' AND scope_branch = 'main'" > /dev/null

    run "$SCRIPT_DIR/task" list --assignee "a1b2" --markdown
    assert_success
    assert_output --partial "## Task asn-06"
    refute_output --partial "asn-07"
}
