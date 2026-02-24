#!/usr/bin/env bats
# test/ralph_preflight.bats — preflight check tests for ralph.sh

load test_helper

@test "missing specs/ directory exits 1" {
    rm -rf "$TEST_WORK_DIR/specs"
    run "$SCRIPT_DIR/ralph.sh" build -n 1
    assert_failure
    assert_output --partial "No specs found"
}

@test "empty specs/ directory exits 1" {
    rm -rf "$TEST_WORK_DIR/specs"
    mkdir -p "$TEST_WORK_DIR/specs"
    run "$SCRIPT_DIR/ralph.sh" build -n 1
    assert_failure
    assert_output --partial "No specs found"
}

