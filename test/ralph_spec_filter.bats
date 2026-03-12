#!/usr/bin/env bats
# test/ralph_spec_filter.bats — tests for --specs flag parsing in ralph plan/build

load test_helper

# ---------------------------------------------------------------------------
# --specs stores value in banner output
# ---------------------------------------------------------------------------
@test "ralph plan --specs 'ui-tabs' shows Specs in banner" {
    run "$SCRIPT_DIR/ralph.sh" plan -n 1 --specs 'ui-tabs'
    assert_success
    assert_output --partial "Specs:  ui-tabs"
}

@test "ralph build --specs 'ui-tabs' shows Specs in banner" {
    run "$SCRIPT_DIR/ralph.sh" build -n 1 --specs 'ui-tabs'
    assert_success
    assert_output --partial "Specs:  ui-tabs"
}

@test "ralph plan --specs with comma-separated patterns shows full value" {
    run "$SCRIPT_DIR/ralph.sh" plan -n 1 --specs 'ui-tabs,auth*'
    assert_success
    assert_output --partial "Specs:  ui-tabs,auth*"
}

@test "ralph build --specs with comma-separated patterns shows full value" {
    run "$SCRIPT_DIR/ralph.sh" build -n 1 --specs 'ui-tabs,auth*'
    assert_success
    assert_output --partial "Specs:  ui-tabs,auth*"
}

@test "ralph plan without --specs omits Specs line from banner" {
    run "$SCRIPT_DIR/ralph.sh" plan -n 1
    assert_success
    refute_output --partial "Specs:"
}

@test "ralph build without --specs omits Specs line from banner" {
    run "$SCRIPT_DIR/ralph.sh" build -n 1
    assert_success
    refute_output --partial "Specs:"
}

# ---------------------------------------------------------------------------
# empty --specs exits 1
# ---------------------------------------------------------------------------
@test "ralph plan --specs '' (empty value) exits 1 with error" {
    run "$SCRIPT_DIR/ralph.sh" plan --specs ''
    assert_failure
    assert_output --partial "Error: --specs requires a pattern"
}

@test "ralph build --specs '' (empty value) exits 1 with error" {
    run "$SCRIPT_DIR/ralph.sh" build --specs ''
    assert_failure
    assert_output --partial "Error: --specs requires a pattern"
}

@test "ralph plan --specs without value exits 1 with error" {
    run "$SCRIPT_DIR/ralph.sh" plan --specs
    assert_failure
    assert_output --partial "Error: --specs requires a pattern"
}

@test "ralph build --specs without value exits 1 with error" {
    run "$SCRIPT_DIR/ralph.sh" build --specs
    assert_failure
    assert_output --partial "Error: --specs requires a pattern"
}

# ---------------------------------------------------------------------------
# --specs appears in --help output
# ---------------------------------------------------------------------------
@test "ralph plan --help shows --specs in usage" {
    run "$SCRIPT_DIR/ralph.sh" plan --help
    assert_success
    assert_output --partial "--specs"
    assert_output --partial "spec-slug glob patterns"
}

@test "ralph build --help shows --specs in usage" {
    run "$SCRIPT_DIR/ralph.sh" build --help
    assert_success
    assert_output --partial "--specs"
    assert_output --partial "spec-slug glob patterns"
}

# ---------------------------------------------------------------------------
# --specs combined with -n and --danger
# ---------------------------------------------------------------------------
@test "ralph plan --specs combined with -n sets both" {
    run "$SCRIPT_DIR/ralph.sh" plan -n 2 --specs 'auth*'
    assert_success
    assert_output --partial "Max:    2 iterations"
    assert_output --partial "Specs:  auth*"
}

@test "ralph build --specs combined with -n sets both" {
    run "$SCRIPT_DIR/ralph.sh" build -n 2 --specs 'auth*'
    assert_success
    assert_output --partial "Max:    2 iterations"
    assert_output --partial "Specs:  auth*"
}

@test "ralph plan --specs combined with --danger sets both" {
    run "$SCRIPT_DIR/ralph.sh" plan -n 1 --specs 'ui-*' --danger
    assert_success
    assert_output --partial "Specs:  ui-*"
    assert_output --partial "NO (--dangerously-skip-permissions)"
}

@test "ralph build --specs combined with --danger sets both" {
    run "$SCRIPT_DIR/ralph.sh" build -n 1 --specs 'ui-*' --danger
    assert_success
    assert_output --partial "Specs:  ui-*"
    assert_output --partial "NO (--dangerously-skip-permissions)"
}

@test "ralph plan --specs combined with -n and --danger sets all three" {
    run "$SCRIPT_DIR/ralph.sh" plan -n 3 --specs 'task-*,spec-*' --danger
    assert_success
    assert_output --partial "Max:    3 iterations"
    assert_output --partial "Specs:  task-*,spec-*"
    assert_output --partial "NO (--dangerously-skip-permissions)"
}

@test "ralph build --specs combined with -n and --danger sets all three" {
    run "$SCRIPT_DIR/ralph.sh" build -n 3 --specs 'task-*,spec-*' --danger
    assert_success
    assert_output --partial "Max:    3 iterations"
    assert_output --partial "Specs:  task-*,spec-*"
    assert_output --partial "NO (--dangerously-skip-permissions)"
}

# ---------------------------------------------------------------------------
# Flag ordering: --specs can appear before other flags
# ---------------------------------------------------------------------------
@test "ralph plan --specs before -n works" {
    run "$SCRIPT_DIR/ralph.sh" plan --specs 'auth*' -n 2
    assert_success
    assert_output --partial "Max:    2 iterations"
    assert_output --partial "Specs:  auth*"
}

@test "ralph build --specs before --danger works" {
    run "$SCRIPT_DIR/ralph.sh" build -n 1 --specs 'auth*' --danger
    assert_success
    assert_output --partial "Specs:  auth*"
    assert_output --partial "NO (--dangerously-skip-permissions)"
}
