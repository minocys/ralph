#!/usr/bin/env bats
# test/task_plan_status_spec_filter.bats — Tests for --specs flag on plan-status

load test_helper

# ---------------------------------------------------------------------------
# Helper: task IDs use {spec-slug}/{seq} format. The spec-slug portion
# (before the first '/') is what --specs glob patterns match against.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# --specs counts only matching tasks
# ---------------------------------------------------------------------------
@test "plan-status --specs counts only tasks whose spec-slug matches" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab component" -p 1
    "$SCRIPT_DIR/lib/task" create "ui-tabs/02" "Tab styles" -p 2
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth flow" -p 1

    run "$SCRIPT_DIR/lib/task" plan-status --specs "ui-tabs"
    assert_success
    [[ "$output" == *"2 open"* ]]
    [[ "$output" == *"0 active"* ]]
    [[ "$output" == *"0 done"* ]]
    [[ "$output" == *"0 blocked"* ]]
    [[ "$output" == *"0 deleted"* ]]
}

# ---------------------------------------------------------------------------
# --specs with comma-separated patterns
# ---------------------------------------------------------------------------
@test "plan-status --specs with comma-separated patterns counts union" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab component" -p 1
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth flow" -p 1
    "$SCRIPT_DIR/lib/task" create "db-migrate/01" "Migration" -p 1

    run "$SCRIPT_DIR/lib/task" plan-status --specs "ui-tabs,auth-oauth"
    assert_success
    [[ "$output" == *"2 open"* ]]
}

# ---------------------------------------------------------------------------
# --specs with glob wildcard
# ---------------------------------------------------------------------------
@test "plan-status --specs with glob wildcard matches multiple spec-slugs" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tabs" -p 1
    "$SCRIPT_DIR/lib/task" create "ui-modal/01" "Modal" -p 1
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth" -p 1

    run "$SCRIPT_DIR/lib/task" plan-status --specs "ui-*"
    assert_success
    [[ "$output" == *"2 open"* ]]
}

# ---------------------------------------------------------------------------
# --specs with no matching tasks shows all zeros
# ---------------------------------------------------------------------------
@test "plan-status --specs with no matching tasks shows all zeros" {
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth flow" -p 1
    "$SCRIPT_DIR/lib/task" create "db-migrate/01" "Migration" -p 2

    run "$SCRIPT_DIR/lib/task" plan-status --specs "ui-tabs"
    assert_success
    [[ "$output" == *"0 open"* ]]
    [[ "$output" == *"0 active"* ]]
    [[ "$output" == *"0 done"* ]]
    [[ "$output" == *"0 blocked"* ]]
    [[ "$output" == *"0 deleted"* ]]
}

# ---------------------------------------------------------------------------
# --specs on empty database shows all zeros
# ---------------------------------------------------------------------------
@test "plan-status --specs on empty database shows all zeros" {
    run "$SCRIPT_DIR/lib/task" plan-status --specs "ui-tabs"
    assert_success
    [[ "$output" == *"0 open"* ]]
    [[ "$output" == *"0 active"* ]]
    [[ "$output" == *"0 done"* ]]
    [[ "$output" == *"0 blocked"* ]]
    [[ "$output" == *"0 deleted"* ]]
}

# ---------------------------------------------------------------------------
# Without --specs counts all tasks (backward compatible)
# ---------------------------------------------------------------------------
@test "plan-status without --specs counts all tasks" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab component" -p 1
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth flow" -p 1
    "$SCRIPT_DIR/lib/task" create "db-migrate/01" "Migration" -p 1

    run "$SCRIPT_DIR/lib/task" plan-status
    assert_success
    [[ "$output" == *"3 open"* ]]
}

# ---------------------------------------------------------------------------
# --specs filters across all status categories
# ---------------------------------------------------------------------------
@test "plan-status --specs filters active, done, deleted, and blocked tasks" {
    # 1 open (ui-tabs)
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tab open" -p 1

    # 1 active (ui-tabs)
    "$SCRIPT_DIR/lib/task" create "ui-tabs/02" "Tab active" -p 0
    RALPH_AGENT_ID=test-agent "$SCRIPT_DIR/lib/task" claim --lease 600 >/dev/null

    # 1 done (ui-tabs)
    "$SCRIPT_DIR/lib/task" create "ui-tabs/03" "Tab done" -p 0
    RALPH_AGENT_ID=test-agent "$SCRIPT_DIR/lib/task" claim --lease 600 >/dev/null
    "$SCRIPT_DIR/lib/task" done ui-tabs/03

    # 1 deleted (ui-tabs)
    "$SCRIPT_DIR/lib/task" create "ui-tabs/04" "Tab deleted"
    "$SCRIPT_DIR/lib/task" delete ui-tabs/04

    # 1 blocked (ui-tabs)
    "$SCRIPT_DIR/lib/task" create "ui-tabs/05" "Tab blocker"
    "$SCRIPT_DIR/lib/task" create "ui-tabs/06" "Tab blocked"
    "$SCRIPT_DIR/lib/task" block ui-tabs/06 --by ui-tabs/05

    # Noise tasks (auth-oauth) — should NOT be counted with filter
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth open" -p 1
    "$SCRIPT_DIR/lib/task" create "auth-oauth/02" "OAuth another" -p 2

    run "$SCRIPT_DIR/lib/task" plan-status --specs "ui-tabs"
    assert_success
    [[ "$output" == *"2 open"* ]]    # ui-tabs/01 (open) + ui-tabs/05 (blocker, open)
    [[ "$output" == *"1 active"* ]]
    [[ "$output" == *"1 done"* ]]
    [[ "$output" == *"1 blocked"* ]]  # ui-tabs/06
    [[ "$output" == *"1 deleted"* ]]
}

# ---------------------------------------------------------------------------
# --specs with ? single-character wildcard
# ---------------------------------------------------------------------------
@test "plan-status --specs with ? wildcard matches single character" {
    "$SCRIPT_DIR/lib/task" create "ui-a/01" "UI A" -p 1
    "$SCRIPT_DIR/lib/task" create "ui-b/01" "UI B" -p 1
    "$SCRIPT_DIR/lib/task" create "ui-ab/01" "UI AB" -p 1

    run "$SCRIPT_DIR/lib/task" plan-status --specs "ui-?"
    assert_success
    # ui-a and ui-b match (single char after "ui-"), ui-ab does not
    [[ "$output" == *"2 open"* ]]
}

# ---------------------------------------------------------------------------
# --specs with mixed glob and exact patterns
# ---------------------------------------------------------------------------
@test "plan-status --specs with mixed glob and exact patterns" {
    "$SCRIPT_DIR/lib/task" create "ui-tabs/01" "Tabs" -p 1
    "$SCRIPT_DIR/lib/task" create "ui-modal/01" "Modal" -p 1
    "$SCRIPT_DIR/lib/task" create "auth-oauth/01" "OAuth" -p 1
    "$SCRIPT_DIR/lib/task" create "db-migrate/01" "DB" -p 1

    run "$SCRIPT_DIR/lib/task" plan-status --specs "ui-*,db-migrate"
    assert_success
    [[ "$output" == *"3 open"* ]]  # ui-tabs, ui-modal, db-migrate
}
