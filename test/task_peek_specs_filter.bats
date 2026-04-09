#!/usr/bin/env bats
# test/task_peek_specs_filter.bats — Tests for --specs flag on task peek

load test_helper

# ---------------------------------------------------------------------------
# Helper: create tasks with spec-slug prefixed IDs
# ---------------------------------------------------------------------------
# Task IDs have the form {spec-slug}/{seq}. The spec-slug is the prefix
# before the first '/'. spec_slug_where() extracts it via SQL.

# ---------------------------------------------------------------------------
# Basic filtering — single exact pattern
# ---------------------------------------------------------------------------
@test "peek --specs returns only tasks whose spec-slug matches the pattern" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab component" -p 1
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth flow" -p 1
    "$SCRIPT_DIR/lib/task" create "ui-tabs/02" "Tab styles" -p 2

    run "$SCRIPT_DIR/lib/task" peek --specs "ui-tabs"
    assert_success

    # Should contain ui-tabs tasks
    echo "$output" | grep -q '^id: ui-tabs/01'
    echo "$output" | grep -q '^id: ui-tabs/02'

    # Should NOT contain auth-oauth task
    ! echo "$output" | grep -q 'auth-oauth'
}

# ---------------------------------------------------------------------------
# Comma-separated patterns
# ---------------------------------------------------------------------------
@test "peek --specs with comma-separated patterns matches multiple spec-slugs" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab component" -p 1
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth flow" -p 1
    "$SCRIPT_DIR/lib/task" create "db-migrate/01" "Migration" -p 1

    run "$SCRIPT_DIR/lib/task" peek --specs "ui-tabs,auth-oauth"
    assert_success

    echo "$output" | grep -q '^id: ui-tabs/01'
    echo "$output" | grep -q '^id: auth-oauth/01'

    # db-migrate should not appear
    ! echo "$output" | grep -q 'db-migrate'
}

# ---------------------------------------------------------------------------
# Glob wildcard matching
# ---------------------------------------------------------------------------
@test "peek --specs with glob wildcard matches spec-slug prefix" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab component" -p 1
    "$SCRIPT_DIR/lib/task" create "ui-modal/01" "Modal" -p 1
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth flow" -p 1

    run "$SCRIPT_DIR/lib/task" peek --specs "ui-*"
    assert_success

    echo "$output" | grep -q '^id: ui-tabs/01'
    echo "$output" | grep -q '^id: ui-modal/01'

    ! echo "$output" | grep -q 'auth-oauth'
}

# ---------------------------------------------------------------------------
# No matching tasks
# ---------------------------------------------------------------------------
@test "peek --specs with no matches returns empty output and exit 0" {
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth flow" -p 1

    run "$SCRIPT_DIR/lib/task" peek --specs "ui-tabs"
    assert_success
    assert_output ""
}

# ---------------------------------------------------------------------------
# --specs filters active tasks too
# ---------------------------------------------------------------------------
@test "peek --specs filters active tasks by spec-slug" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab component" -p 0
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth flow" -p 1

    # Claim both
    "$SCRIPT_DIR/lib/task" claim --agent "a1" >/dev/null
    "$SCRIPT_DIR/lib/task" claim --agent "a2" >/dev/null

    run "$SCRIPT_DIR/lib/task" peek --specs "ui-tabs"
    assert_success

    # Only ui-tabs should appear as active
    echo "$output" | grep -q '^id: ui-tabs/01'
    ! echo "$output" | grep -q 'auth-oauth'
}

# ---------------------------------------------------------------------------
# -n limit applies to filtered claimable set
# ---------------------------------------------------------------------------
@test "peek --specs with -n limits filtered claimable tasks" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab 1" -p 1
    "$SCRIPT_DIR/lib/task" create "ui-tabs/02" "Tab 2" -p 2
    "$SCRIPT_DIR/lib/task" create "ui-tabs/03" "Tab 3" -p 3
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth" -p 0

    run "$SCRIPT_DIR/lib/task" peek --specs "ui-tabs" -n 2
    assert_success

    # Should have exactly 2 claimable sections (ui-tabs only)
    local count
    count=$(echo "$output" | grep -c '^## Task ')
    [[ "$count" -eq 2 ]]

    # The 2 shown should be priority-ordered: ui-tabs/01, ui-tabs/02
    local first second
    first=$(echo "$output" | grep '^## Task ' | sed -n '1p' | sed 's/^## Task //')
    second=$(echo "$output" | grep '^## Task ' | sed -n '2p' | sed 's/^## Task //')
    [[ "$first" == "ui-tabs/01" ]]
    [[ "$second" == "ui-tabs/02" ]]
}

# ---------------------------------------------------------------------------
# --specs omitted — all tasks returned (backward compat)
# ---------------------------------------------------------------------------
@test "peek without --specs returns all tasks (backward compatible)" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab component" -p 1
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth flow" -p 2

    run "$SCRIPT_DIR/lib/task" peek
    assert_success

    echo "$output" | grep -q '^id: ui-tabs/01'
    echo "$output" | grep -q '^id: auth-oauth/01'
}

# ---------------------------------------------------------------------------
# Mixed: --specs with both claimable and active tasks
# ---------------------------------------------------------------------------
@test "peek --specs shows filtered claimable and filtered active together" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab open" -p 1
    "$SCRIPT_DIR/lib/task" create "ui-tabs/02" "Tab active" -p 0
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth open" -p 1
    "$SCRIPT_DIR/lib/task" create "auth-oauth/02" "OAuth active" -p 0

    # Claim the p=0 tasks
    "$SCRIPT_DIR/lib/task" claim --agent "a1" >/dev/null
    "$SCRIPT_DIR/lib/task" claim --agent "a2" >/dev/null

    run "$SCRIPT_DIR/lib/task" peek --specs "ui-tabs"
    assert_success

    # Should show ui-tabs/01 (claimable) and ui-tabs/02 (active)
    echo "$output" | grep -q '^id: ui-tabs/01'
    echo "$output" | grep -q '^id: ui-tabs/02'

    # Should NOT show auth-oauth tasks
    ! echo "$output" | grep -q 'auth-oauth'
}

# ---------------------------------------------------------------------------
# Glob ? wildcard
# ---------------------------------------------------------------------------
@test "peek --specs with ? wildcard matches single character" {
    "$SCRIPT_DIR/lib/task" create "ui-a/01" "UI A" -p 1
    "$SCRIPT_DIR/lib/task" create "ui-b/01" "UI B" -p 1
    "$SCRIPT_DIR/lib/task" create "ui-ab/01" "UI AB" -p 1

    run "$SCRIPT_DIR/lib/task" peek --specs "ui-?"
    assert_success

    echo "$output" | grep -q '^id: ui-a/01'
    echo "$output" | grep -q '^id: ui-b/01'

    # ui-ab has 2 chars after "ui-", so ? should not match it
    ! echo "$output" | grep -q 'ui-ab'
}

# ---------------------------------------------------------------------------
# Mixed glob and exact patterns
# ---------------------------------------------------------------------------
@test "peek --specs with mixed glob and exact patterns" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tabs" -p 1
    "$SCRIPT_DIR/lib/task" create "ui-modal/01" "Modal" -p 1
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth" -p 1
    "$SCRIPT_DIR/lib/task" create "db-migrate/01" "DB" -p 1

    run "$SCRIPT_DIR/lib/task" peek --specs "ui-*,db-migrate"
    assert_success

    echo "$output" | grep -q '^id: ui-tabs/01'
    echo "$output" | grep -q '^id: ui-modal/01'
    echo "$output" | grep -q '^id: db-migrate/01'

    ! echo "$output" | grep -q 'auth-oauth'
}

# ---------------------------------------------------------------------------
# RALPH_SPEC_FILTER env var fallback
# ---------------------------------------------------------------------------
@test "peek uses RALPH_SPEC_FILTER env var when --specs is not provided" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab component" -p 1
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth flow" -p 1

    RALPH_SPEC_FILTER="ui-tabs" run "$SCRIPT_DIR/lib/task" peek
    assert_success

    echo "$output" | grep -q '^id: ui-tabs/01'
    ! echo "$output" | grep -q 'auth-oauth'
}

@test "peek --specs takes precedence over RALPH_SPEC_FILTER env var" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab component" -p 1
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth flow" -p 1
    "$SCRIPT_DIR/lib/task" create "db-migrate/01" "Migration" -p 1

    RALPH_SPEC_FILTER="ui-tabs" run "$SCRIPT_DIR/lib/task" peek --specs "auth-oauth"
    assert_success

    # --specs wins: only auth-oauth
    echo "$output" | grep -q '^id: auth-oauth/01'
    ! echo "$output" | grep -q 'ui-tabs'
    ! echo "$output" | grep -q 'db-migrate'
}

@test "peek without --specs and without RALPH_SPEC_FILTER returns all tasks" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab component" -p 1
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth flow" -p 2

    unset RALPH_SPEC_FILTER
    run "$SCRIPT_DIR/lib/task" peek
    assert_success

    echo "$output" | grep -q '^id: ui-tabs/01'
    echo "$output" | grep -q '^id: auth-oauth/01'
}

@test "peek ignores empty RALPH_SPEC_FILTER and returns all tasks" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab component" -p 1
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth flow" -p 2

    RALPH_SPEC_FILTER="" run "$SCRIPT_DIR/lib/task" peek
    assert_success

    echo "$output" | grep -q '^id: ui-tabs/01'
    echo "$output" | grep -q '^id: auth-oauth/01'
}

@test "peek RALPH_SPEC_FILTER with glob wildcard works" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab component" -p 1
    "$SCRIPT_DIR/lib/task" create "ui-modal/01" "Modal" -p 1
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth flow" -p 1

    RALPH_SPEC_FILTER="ui-*" run "$SCRIPT_DIR/lib/task" peek
    assert_success

    echo "$output" | grep -q '^id: ui-tabs/01'
    echo "$output" | grep -q '^id: ui-modal/01'
    ! echo "$output" | grep -q 'auth-oauth'
}

@test "peek RALPH_SPEC_FILTER with comma-separated patterns works" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab component" -p 1
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth flow" -p 1
    "$SCRIPT_DIR/lib/task" create "db-migrate/01" "Migration" -p 1

    RALPH_SPEC_FILTER="ui-tabs,auth-oauth" run "$SCRIPT_DIR/lib/task" peek
    assert_success

    echo "$output" | grep -q '^id: ui-tabs/01'
    echo "$output" | grep -q '^id: auth-oauth/01'
    ! echo "$output" | grep -q 'db-migrate'
}

@test "peek RALPH_SPEC_FILTER filters active tasks too" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab component" -p 0
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth flow" -p 1

    # Claim both
    "$SCRIPT_DIR/lib/task" claim --agent "a1" >/dev/null
    "$SCRIPT_DIR/lib/task" claim --agent "a2" >/dev/null

    RALPH_SPEC_FILTER="ui-tabs" run "$SCRIPT_DIR/lib/task" peek
    assert_success

    echo "$output" | grep -q '^id: ui-tabs/01'
    ! echo "$output" | grep -q 'auth-oauth'
}
