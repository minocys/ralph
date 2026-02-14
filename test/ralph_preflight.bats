#!/usr/bin/env bats
# test/ralph_preflight.bats — preflight check tests for ralph.sh

load test_helper

@test "missing specs/ directory exits 1" {
    rm -rf "$TEST_WORK_DIR/specs"
    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_failure
    assert_output --partial "No specs found"
}

@test "empty specs/ directory exits 1" {
    rm -rf "$TEST_WORK_DIR/specs"
    mkdir -p "$TEST_WORK_DIR/specs"
    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_failure
    assert_output --partial "No specs found"
}

@test "missing IMPLEMENTATION_PLAN.json in build mode exits 1" {
    rm -f "$TEST_WORK_DIR/IMPLEMENTATION_PLAN.json"
    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_failure
    assert_output --partial "IMPLEMENTATION_PLAN.json not found"
}

@test "missing plan file is OK in plan mode" {
    rm -f "$TEST_WORK_DIR/IMPLEMENTATION_PLAN.json"
    run "$SCRIPT_DIR/ralph.sh" --plan -n 1
    assert_success
}
