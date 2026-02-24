#!/usr/bin/env bats
# test/ralph_args.bats — argument parsing and subcommand dispatch tests for ralph.sh

load test_helper

# ---------------------------------------------------------------------------
# Top-level help
# ---------------------------------------------------------------------------
@test "ralph --help prints subcommand list and exits 0" {
    run "$SCRIPT_DIR/ralph.sh" --help
    assert_success
    assert_output --partial "plan"
    assert_output --partial "build"
    assert_output --partial "task"
}

@test "ralph -h is an alias for --help" {
    run "$SCRIPT_DIR/ralph.sh" -h
    assert_success
    assert_output --partial "plan"
    assert_output --partial "build"
    assert_output --partial "task"
}

@test "ralph with no arguments prints help and exits 0" {
    run "$SCRIPT_DIR/ralph.sh"
    assert_success
    assert_output --partial "plan"
    assert_output --partial "build"
    assert_output --partial "task"
}

@test "ralph --help includes per-command help hint" {
    run "$SCRIPT_DIR/ralph.sh" --help
    assert_success
    assert_output --partial "ralph <command> --help"
}

# ---------------------------------------------------------------------------
# Unknown subcommand
# ---------------------------------------------------------------------------
@test "unknown subcommand exits 1 with error to stderr" {
    run "$SCRIPT_DIR/ralph.sh" bogus
    assert_failure
    assert_output --partial "unknown command 'bogus'"
}

@test "unknown flag exits 1 with error" {
    run "$SCRIPT_DIR/ralph.sh" --bogus
    assert_failure
    assert_output --partial "unknown command '--bogus'"
}

# ---------------------------------------------------------------------------
# Subcommand detection: task
# ---------------------------------------------------------------------------
@test "ralph task routes to lib/task" {
    run "$SCRIPT_DIR/ralph.sh" task --help
    assert_success
    assert_output --partial "Usage: ralph task <command>"
}

@test "ralph task passes remaining args to lib/task" {
    run "$SCRIPT_DIR/ralph.sh" task --help
    assert_success
    assert_output --partial "plan-sync"
}

# ---------------------------------------------------------------------------
# Subcommand detection: plan
# ---------------------------------------------------------------------------
@test "ralph plan sets plan mode" {
    run "$SCRIPT_DIR/ralph.sh" plan -n 1
    assert_output --partial "Mode:   plan"
}

@test "ralph plan --help prints plan-specific flags and exits 0" {
    run "$SCRIPT_DIR/ralph.sh" plan --help
    assert_success
    assert_output --partial "--max-iterations"
    assert_output --partial "--model"
    assert_output --partial "--danger"
}

@test "ralph plan -n defaults to 1" {
    run "$SCRIPT_DIR/ralph.sh" plan
    assert_output --partial "Max:    1 iteration"
}

@test "ralph plan -n 0 is rejected" {
    run "$SCRIPT_DIR/ralph.sh" plan -n 0
    assert_failure
    assert_output --partial "plan mode requires"
}

@test "ralph plan -n 3 sets 3 iterations" {
    run "$SCRIPT_DIR/ralph.sh" plan -n 3
    assert_output --partial "Max:    3 iterations"
}

# ---------------------------------------------------------------------------
# Subcommand detection: build
# ---------------------------------------------------------------------------
@test "ralph build sets build mode" {
    run "$SCRIPT_DIR/ralph.sh" build -n 1
    assert_output --partial "Mode:   build"
}

@test "ralph build --help prints build-specific flags and exits 0" {
    run "$SCRIPT_DIR/ralph.sh" build --help
    assert_success
    assert_output --partial "--max-iterations"
    assert_output --partial "--model"
    assert_output --partial "--danger"
}

@test "ralph build -n defaults to 0 (unlimited)" {
    run "$SCRIPT_DIR/ralph.sh" build -n 1
    # With -n 1, it should show iterations limit
    assert_output --partial "Max:    1 iteration"
}

# ---------------------------------------------------------------------------
# Shared flags after subcommand
# ---------------------------------------------------------------------------
@test "ralph plan --danger flag is accepted" {
    run "$SCRIPT_DIR/ralph.sh" plan -n 1 --danger
    assert_output --partial "NO (--dangerously-skip-permissions)"
}

@test "ralph build --danger flag is accepted" {
    run "$SCRIPT_DIR/ralph.sh" build -n 1 --danger
    assert_output --partial "NO (--dangerously-skip-permissions)"
}

@test "ralph plan -n without value exits 1" {
    run "$SCRIPT_DIR/ralph.sh" plan -n
    assert_failure
    assert_output --partial "requires a number"
}

@test "ralph build -n without value exits 1" {
    run "$SCRIPT_DIR/ralph.sh" build -n
    assert_failure
    assert_output --partial "requires a number"
}

@test "ralph plan with multiple flags combines correctly" {
    run "$SCRIPT_DIR/ralph.sh" plan -n 2 --danger
    assert_output --partial "Mode:   plan"
    assert_output --partial "NO (--dangerously-skip-permissions)"
    assert_output --partial "Max:    2 iterations"
}

@test "ralph build with multiple flags combines correctly" {
    run "$SCRIPT_DIR/ralph.sh" build -n 2 --danger
    assert_output --partial "Mode:   build"
    assert_output --partial "NO (--dangerously-skip-permissions)"
    assert_output --partial "Max:    2 iterations"
}

# ---------------------------------------------------------------------------
# Backward compat: --plan/-p flags still work during transition
# ---------------------------------------------------------------------------
@test "--plan flag still works as backward compat" {
    run "$SCRIPT_DIR/ralph.sh" --plan -n 1
    assert_output --partial "Mode:   plan"
}

@test "-p flag still works as backward compat" {
    run "$SCRIPT_DIR/ralph.sh" -p -n 1
    assert_output --partial "Mode:   plan"
}
