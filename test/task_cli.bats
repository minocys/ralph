#!/usr/bin/env bats
# test/task_cli.bats — CLI skeleton tests for the task script

load test_helper

# ---------------------------------------------------------------------------
# Help output
# ---------------------------------------------------------------------------
@test "task --help prints usage and exits 0" {
    run "$SCRIPT_DIR/lib/task" --help
    assert_success
    assert_output --partial "Usage: ralph task <command>"
}

@test "task -h is an alias for --help" {
    run "$SCRIPT_DIR/lib/task" -h
    assert_success
    assert_output --partial "Usage: ralph task <command>"
}

@test "task --help lists plan-sync command" {
    run "$SCRIPT_DIR/lib/task" --help
    assert_success
    assert_output --partial "plan-sync"
}

@test "task --help lists claim command" {
    run "$SCRIPT_DIR/lib/task" --help
    assert_success
    assert_output --partial "claim"
}

@test "task --help lists agent commands" {
    run "$SCRIPT_DIR/lib/task" --help
    assert_success
    assert_output --partial "agent register"
    assert_output --partial "agent list"
    assert_output --partial "agent deregister"
}

@test "task --help lists database path info" {
    run "$SCRIPT_DIR/lib/task" --help
    assert_success
    assert_output --partial "git root"
}

# ---------------------------------------------------------------------------
# Missing subcommand
# ---------------------------------------------------------------------------
@test "task with no subcommand prints help to stderr and exits 1" {
    run "$SCRIPT_DIR/lib/task"
    assert_failure
    assert_output --partial "Error: missing command"
    assert_output --partial "Usage: ralph task <command>"
}

# ---------------------------------------------------------------------------
# Unknown subcommand
# ---------------------------------------------------------------------------
@test "task with unknown subcommand exits 1" {
    # Unknown commands don't need RALPH_DB_URL since they fail before db_check
    run "$SCRIPT_DIR/lib/task" bogus-command
    assert_failure
    assert_output --partial "Error: unknown command 'bogus-command'"
}

@test "task plan-export exits 1 with redirect to list --all" {
    run "$SCRIPT_DIR/lib/task" plan-export
    assert_failure
    assert_output --partial "Error: unknown command 'plan-export'"
    assert_output --partial "ralph task list --all"
}

# ---------------------------------------------------------------------------
# Default RALPH_DB_PATH: commands work without explicit path (auto-creates DB)
# ---------------------------------------------------------------------------
@test "task create without explicit RALPH_DB_PATH still validates args" {
    cp "$SCRIPT_DIR/lib/task" "$TEST_WORK_DIR/task"
    chmod +x "$TEST_WORK_DIR/task"
    unset RALPH_DB_PATH 2>/dev/null || true
    run "$TEST_WORK_DIR/task" create
    assert_failure
    assert_output --partial "missing task ID"
}

@test "task list without explicit RALPH_DB_PATH succeeds" {
    cp "$SCRIPT_DIR/lib/task" "$TEST_WORK_DIR/task"
    chmod +x "$TEST_WORK_DIR/task"
    unset RALPH_DB_PATH 2>/dev/null || true
    run "$TEST_WORK_DIR/task" list
    assert_success
}

@test "task claim without explicit RALPH_DB_PATH exits 2 (no tasks)" {
    cp "$SCRIPT_DIR/lib/task" "$TEST_WORK_DIR/task"
    chmod +x "$TEST_WORK_DIR/task"
    unset RALPH_DB_PATH 2>/dev/null || true
    run "$TEST_WORK_DIR/task" claim
    [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Agent subcommand routing
# ---------------------------------------------------------------------------
@test "task agent without subcommand exits 1" {
    run "$SCRIPT_DIR/lib/task" agent
    assert_failure
    assert_output --partial "missing agent subcommand"
}

# ---------------------------------------------------------------------------
# Help does not require RALPH_DB_PATH
# ---------------------------------------------------------------------------
@test "task --help works without RALPH_DB_PATH" {
    unset RALPH_DB_PATH 2>/dev/null || true
    run "$SCRIPT_DIR/lib/task" --help
    assert_success
    assert_output --partial "Usage: ralph task <command>"
}
