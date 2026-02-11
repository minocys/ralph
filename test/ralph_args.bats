#!/usr/bin/env bats
# test/ralph_args.bats — argument parsing tests for ralph.sh

load test_helper

@test "--help prints usage and exits 0" {
    run "$SCRIPT_DIR/ralph.sh" --help
    assert_success
    assert_output --partial "Usage"
}

@test "-h is an alias for --help" {
    run "$SCRIPT_DIR/ralph.sh" -h
    assert_success
    assert_output --partial "Usage"
}

@test "unknown flag exits 1 with error" {
    run "$SCRIPT_DIR/ralph.sh" --bogus
    assert_failure
    assert_output --partial "Unknown option"
}

@test "--max-iterations without value exits 1" {
    run "$SCRIPT_DIR/ralph.sh" -n
    assert_failure
    assert_output --partial "requires a number"
}

@test "--plan sets plan mode" {
    run "$SCRIPT_DIR/ralph.sh" --plan -n 1
    assert_output --partial "Mode:   plan"
}

@test "-p is an alias for --plan" {
    run "$SCRIPT_DIR/ralph.sh" -p -n 1
    assert_output --partial "Mode:   plan"
}

@test "--danger flag is accepted" {
    run "$SCRIPT_DIR/ralph.sh" --danger -n 1
    assert_output --partial "NO (--dangerously-skip-permissions)"
}

@test "multiple flags combine correctly" {
    run "$SCRIPT_DIR/ralph.sh" --plan -n 2 --danger
    assert_output --partial "Mode:   plan"
    assert_output --partial "NO (--dangerously-skip-permissions)"
    assert_output --partial "Max:    2 iterations"
}
