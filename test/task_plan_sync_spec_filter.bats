#!/usr/bin/env bats
# test/task_plan_sync_spec_filter.bats — Tests for --specs flag in plan-sync orphan deletion

load test_helper

# ---------------------------------------------------------------------------
# --specs does NOT delete tasks whose spec_ref is outside the pattern
# ---------------------------------------------------------------------------
@test "plan-sync --specs skips orphan deletion for non-matching spec_refs" {
    # Create tasks under two different specs
    "$SCRIPT_DIR/lib/task" create ui-tabs/01 "Tab component" -r ui-tabs.md >/dev/null
    "$SCRIPT_DIR/lib/task" create auth-oauth/01 "OAuth flow" -r auth-oauth.md >/dev/null
    "$SCRIPT_DIR/lib/task" create auth-oauth/02 "Token refresh" -r auth-oauth.md >/dev/null

    # Sync with only ui-tabs tasks, scoped to ui-tabs
    # auth-oauth tasks should NOT be deleted since they don't match --specs
    local input='{"id":"ui-tabs/01","t":"Tab component","spec":"ui-tabs.md"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/lib/task" plan-sync --specs "ui-tabs"' -- "$input"
    assert_success
    assert_output "inserted: 0, updated: 0, deleted: 0, skipped (done): 0"

    # auth-oauth tasks must remain open — not deleted
    run "$SCRIPT_DIR/lib/task" show auth-oauth/01
    assert_success
    assert_output --partial "Status:      open"

    run "$SCRIPT_DIR/lib/task" show auth-oauth/02
    assert_success
    assert_output --partial "Status:      open"
}

@test "plan-sync --specs protects tasks from unrelated specs even when absent from stdin" {
    # Create tasks for three specs
    "$SCRIPT_DIR/lib/task" create ui-tabs/01 "Tab A" -r ui-tabs.md >/dev/null
    "$SCRIPT_DIR/lib/task" create db-migrate/01 "Migration A" -r db-migrate.md >/dev/null
    "$SCRIPT_DIR/lib/task" create api-rest/01 "Endpoint A" -r api-rest.md >/dev/null

    # Sync only ui-tabs; db-migrate and api-rest are absent from stdin
    # but --specs restricts orphan deletion to ui-tabs only
    local input='{"id":"ui-tabs/01","t":"Tab A","spec":"ui-tabs.md"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/lib/task" plan-sync --specs "ui-tabs"' -- "$input"
    assert_success
    assert_output "inserted: 0, updated: 0, deleted: 0, skipped (done): 0"

    # Unrelated specs must survive
    run "$SCRIPT_DIR/lib/task" show db-migrate/01
    assert_success
    assert_output --partial "Status:      open"

    run "$SCRIPT_DIR/lib/task" show api-rest/01
    assert_success
    assert_output --partial "Status:      open"
}

# ---------------------------------------------------------------------------
# --specs DOES delete orphans within matched spec_refs
# ---------------------------------------------------------------------------
@test "plan-sync --specs deletes orphans within matched spec_ref" {
    # Create tasks under ui-tabs
    "$SCRIPT_DIR/lib/task" create ui-tabs/01 "Keep this tab" -r ui-tabs.md >/dev/null
    "$SCRIPT_DIR/lib/task" create ui-tabs/02 "Remove this tab" -r ui-tabs.md >/dev/null

    # Sync with only ui-tabs/01 — ui-tabs/02 should be deleted
    local input='{"id":"ui-tabs/01","t":"Keep this tab","spec":"ui-tabs.md"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/lib/task" plan-sync --specs "ui-tabs"' -- "$input"
    assert_success
    assert_output "inserted: 0, updated: 0, deleted: 1, skipped (done): 0"

    run "$SCRIPT_DIR/lib/task" show ui-tabs/02
    assert_success
    assert_output --partial "Status:      deleted"
}

@test "plan-sync --specs deletes orphans in matching spec while protecting others" {
    # ui-tabs tasks
    "$SCRIPT_DIR/lib/task" create ui-tabs/01 "Tab keep" -r ui-tabs.md >/dev/null
    "$SCRIPT_DIR/lib/task" create ui-tabs/02 "Tab orphan" -r ui-tabs.md >/dev/null
    # auth-oauth tasks
    "$SCRIPT_DIR/lib/task" create auth-oauth/01 "OAuth keep" -r auth-oauth.md >/dev/null
    "$SCRIPT_DIR/lib/task" create auth-oauth/02 "OAuth untouched" -r auth-oauth.md >/dev/null

    # Sync both specs in stdin but only filter for ui-tabs
    local input='{"id":"ui-tabs/01","t":"Tab keep","spec":"ui-tabs.md"}
{"id":"auth-oauth/01","t":"OAuth keep","spec":"auth-oauth.md"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/lib/task" plan-sync --specs "ui-tabs"' -- "$input"
    assert_success
    # ui-tabs/02 deleted (orphan within matched spec), auth-oauth/02 NOT deleted (spec not matched)
    assert_output "inserted: 0, updated: 0, deleted: 1, skipped (done): 0"

    run "$SCRIPT_DIR/lib/task" show ui-tabs/02
    assert_success
    assert_output --partial "Status:      deleted"

    run "$SCRIPT_DIR/lib/task" show auth-oauth/02
    assert_success
    assert_output --partial "Status:      open"
}

@test "plan-sync --specs with comma-separated patterns deletes orphans in all matched specs" {
    "$SCRIPT_DIR/lib/task" create ui-tabs/01 "Tab keep" -r ui-tabs.md >/dev/null
    "$SCRIPT_DIR/lib/task" create ui-tabs/02 "Tab orphan" -r ui-tabs.md >/dev/null
    "$SCRIPT_DIR/lib/task" create auth-oauth/01 "OAuth keep" -r auth-oauth.md >/dev/null
    "$SCRIPT_DIR/lib/task" create auth-oauth/02 "OAuth orphan" -r auth-oauth.md >/dev/null
    "$SCRIPT_DIR/lib/task" create db-migrate/01 "DB safe" -r db-migrate.md >/dev/null

    local input='{"id":"ui-tabs/01","t":"Tab keep","spec":"ui-tabs.md"}
{"id":"auth-oauth/01","t":"OAuth keep","spec":"auth-oauth.md"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/lib/task" plan-sync --specs "ui-tabs,auth-oauth"' -- "$input"
    assert_success
    assert_output "inserted: 0, updated: 0, deleted: 2, skipped (done): 0"

    run "$SCRIPT_DIR/lib/task" show ui-tabs/02
    assert_output --partial "Status:      deleted"

    run "$SCRIPT_DIR/lib/task" show auth-oauth/02
    assert_output --partial "Status:      deleted"

    # db-migrate must be untouched
    run "$SCRIPT_DIR/lib/task" show db-migrate/01
    assert_output --partial "Status:      open"
}

@test "plan-sync --specs with wildcard pattern deletes orphans across matching specs" {
    "$SCRIPT_DIR/lib/task" create ui-tabs/01 "Tab keep" -r ui-tabs.md >/dev/null
    "$SCRIPT_DIR/lib/task" create ui-tabs/02 "Tab orphan" -r ui-tabs.md >/dev/null
    "$SCRIPT_DIR/lib/task" create ui-modal/01 "Modal keep" -r ui-modal.md >/dev/null
    "$SCRIPT_DIR/lib/task" create ui-modal/02 "Modal orphan" -r ui-modal.md >/dev/null
    "$SCRIPT_DIR/lib/task" create auth-oauth/01 "OAuth safe" -r auth-oauth.md >/dev/null

    local input='{"id":"ui-tabs/01","t":"Tab keep","spec":"ui-tabs.md"}
{"id":"ui-modal/01","t":"Modal keep","spec":"ui-modal.md"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/lib/task" plan-sync --specs "ui-*"' -- "$input"
    assert_success
    assert_output "inserted: 0, updated: 0, deleted: 2, skipped (done): 0"

    run "$SCRIPT_DIR/lib/task" show ui-tabs/02
    assert_output --partial "Status:      deleted"

    run "$SCRIPT_DIR/lib/task" show ui-modal/02
    assert_output --partial "Status:      deleted"

    run "$SCRIPT_DIR/lib/task" show auth-oauth/01
    assert_output --partial "Status:      open"
}

# ---------------------------------------------------------------------------
# --specs inserts and updates regardless of pattern match
# ---------------------------------------------------------------------------
@test "plan-sync --specs inserts tasks even when spec_ref does not match pattern" {
    local input='{"id":"auth-oauth/01","t":"OAuth flow","p":1,"spec":"auth-oauth.md"}
{"id":"ui-tabs/01","t":"Tab component","p":2,"spec":"ui-tabs.md"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/lib/task" plan-sync --specs "ui-tabs"' -- "$input"
    assert_success
    assert_output "inserted: 2, updated: 0, deleted: 0, skipped (done): 0"

    # Both tasks inserted regardless of filter
    run "$SCRIPT_DIR/lib/task" show auth-oauth/01
    assert_success
    assert_output --partial "OAuth flow"

    run "$SCRIPT_DIR/lib/task" show ui-tabs/01
    assert_success
    assert_output --partial "Tab component"
}

@test "plan-sync --specs updates tasks even when spec_ref does not match pattern" {
    # Pre-create tasks
    "$SCRIPT_DIR/lib/task" create auth-oauth/01 "Old title" -p 2 -r auth-oauth.md >/dev/null

    local input='{"id":"auth-oauth/01","t":"New title","p":1,"spec":"auth-oauth.md"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/lib/task" plan-sync --specs "ui-tabs"' -- "$input"
    assert_success
    assert_output "inserted: 0, updated: 1, deleted: 0, skipped (done): 0"

    run "$SCRIPT_DIR/lib/task" show auth-oauth/01
    assert_success
    assert_output --partial "New title"
}

@test "plan-sync --specs performs mixed insert/update/delete with correct scoping" {
    # Pre-existing tasks
    "$SCRIPT_DIR/lib/task" create ui-tabs/01 "Tab to update" -p 2 -r ui-tabs.md >/dev/null
    "$SCRIPT_DIR/lib/task" create ui-tabs/02 "Tab to orphan" -r ui-tabs.md >/dev/null
    "$SCRIPT_DIR/lib/task" create auth-oauth/01 "OAuth existing" -r auth-oauth.md >/dev/null
    "$SCRIPT_DIR/lib/task" create auth-oauth/02 "OAuth safe orphan" -r auth-oauth.md >/dev/null

    # stdin: update ui-tabs/01, insert ui-tabs/03, insert auth-oauth/03
    # --specs ui-tabs: orphan deletion only for ui-tabs => ui-tabs/02 deleted
    #                  auth-oauth/02 NOT deleted (non-matching spec)
    local input='{"id":"ui-tabs/01","t":"Tab updated","p":0,"spec":"ui-tabs.md"}
{"id":"ui-tabs/03","t":"Tab new","p":1,"spec":"ui-tabs.md"}
{"id":"auth-oauth/01","t":"OAuth existing","spec":"auth-oauth.md"}
{"id":"auth-oauth/03","t":"OAuth new","p":1,"spec":"auth-oauth.md"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/lib/task" plan-sync --specs "ui-tabs"' -- "$input"
    assert_success
    # 2 inserts (ui-tabs/03, auth-oauth/03), 1 update (ui-tabs/01), 1 delete (ui-tabs/02)
    assert_output "inserted: 2, updated: 1, deleted: 1, skipped (done): 0"

    # Verify orphan deletion scoped correctly
    run "$SCRIPT_DIR/lib/task" show ui-tabs/02
    assert_output --partial "Status:      deleted"

    run "$SCRIPT_DIR/lib/task" show auth-oauth/02
    assert_output --partial "Status:      open"
}

# ---------------------------------------------------------------------------
# --specs does not delete done tasks within matched spec_refs
# ---------------------------------------------------------------------------
@test "plan-sync --specs does not delete done tasks in matched spec" {
    "$SCRIPT_DIR/lib/task" create ui-tabs/01 "Tab keep" -r ui-tabs.md >/dev/null
    "$SCRIPT_DIR/lib/task" create ui-tabs/02 "Tab done" -p 1 -r ui-tabs.md >/dev/null
    export RALPH_AGENT_ID="test-agent"
    "$SCRIPT_DIR/lib/task" claim --agent test-agent >/dev/null
    "$SCRIPT_DIR/lib/task" done ui-tabs/02 >/dev/null

    # Sync with only ui-tabs/01 — ui-tabs/02 is done and should NOT be deleted
    local input='{"id":"ui-tabs/01","t":"Tab keep","spec":"ui-tabs.md"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/lib/task" plan-sync --specs "ui-tabs"' -- "$input"
    assert_success
    assert_output "inserted: 0, updated: 0, deleted: 0, skipped (done): 0"

    run "$SCRIPT_DIR/lib/task" show ui-tabs/02
    assert_success
    assert_output --partial "Status:      done"
}

# ---------------------------------------------------------------------------
# Without --specs, orphan deletion is unchanged (deletes across all spec_refs)
# ---------------------------------------------------------------------------
@test "plan-sync without --specs deletes orphans across all spec_refs" {
    "$SCRIPT_DIR/lib/task" create ui-tabs/01 "Tab keep" -r ui-tabs.md >/dev/null
    "$SCRIPT_DIR/lib/task" create ui-tabs/02 "Tab orphan" -r ui-tabs.md >/dev/null
    "$SCRIPT_DIR/lib/task" create auth-oauth/01 "OAuth keep" -r auth-oauth.md >/dev/null
    "$SCRIPT_DIR/lib/task" create auth-oauth/02 "OAuth orphan" -r auth-oauth.md >/dev/null

    local input='{"id":"ui-tabs/01","t":"Tab keep","spec":"ui-tabs.md"}
{"id":"auth-oauth/01","t":"OAuth keep","spec":"auth-oauth.md"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/lib/task" plan-sync' -- "$input"
    assert_success
    assert_output "inserted: 0, updated: 0, deleted: 2, skipped (done): 0"

    run "$SCRIPT_DIR/lib/task" show ui-tabs/02
    assert_output --partial "Status:      deleted"

    run "$SCRIPT_DIR/lib/task" show auth-oauth/02
    assert_output --partial "Status:      deleted"
}

@test "plan-sync without --specs behaves identically to before for single spec_ref" {
    "$SCRIPT_DIR/lib/task" create my-spec/01 "Keep" -r my-spec >/dev/null
    "$SCRIPT_DIR/lib/task" create my-spec/02 "Orphan" -r my-spec >/dev/null

    local input='{"id":"my-spec/01","t":"Keep","spec":"my-spec"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/lib/task" plan-sync' -- "$input"
    assert_success
    assert_output "inserted: 0, updated: 0, deleted: 1, skipped (done): 0"

    run "$SCRIPT_DIR/lib/task" show my-spec/02
    assert_output --partial "Status:      deleted"
}

# ---------------------------------------------------------------------------
# Edge case: --specs with no matching spec_refs in stdin
# ---------------------------------------------------------------------------
@test "plan-sync --specs with no spec_ref overlap causes no orphan deletions" {
    "$SCRIPT_DIR/lib/task" create ui-tabs/01 "Existing tab" -r ui-tabs.md >/dev/null

    # stdin contains only auth-oauth, but --specs is ui-tabs
    # ui-tabs/01 has spec ui-tabs.md but is NOT in stdin — however since no
    # stdin tasks have spec ui-tabs.md, there is no orphan deletion loop for it
    local input='{"id":"auth-oauth/01","t":"OAuth new","spec":"auth-oauth.md"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/lib/task" plan-sync --specs "ui-tabs"' -- "$input"
    assert_success
    assert_output "inserted: 1, updated: 0, deleted: 0, skipped (done): 0"

    # ui-tabs/01 should still exist since no ui-tabs spec_ref appeared in stdin
    run "$SCRIPT_DIR/lib/task" show ui-tabs/01
    assert_success
    assert_output --partial "Status:      open"
}

@test "plan-sync --specs with tasks having no spec_ref does not delete them" {
    # Task with no spec_ref
    "$SCRIPT_DIR/lib/task" create orphan-01 "No spec task" >/dev/null

    local input='{"id":"ui-tabs/01","t":"Tab task","spec":"ui-tabs.md"}'

    run bash -c 'printf "%s\n" "$1" | "$SCRIPT_DIR/lib/task" plan-sync --specs "ui-tabs"' -- "$input"
    assert_success
    assert_output "inserted: 1, updated: 0, deleted: 0, skipped (done): 0"

    run "$SCRIPT_DIR/lib/task" show orphan-01
    assert_success
    assert_output --partial "Status:      open"
}
