#!/usr/bin/env bats
# test/task_cli.bats — CLI skeleton tests for the task script

load test_helper

# ---------------------------------------------------------------------------
# Help output
# ---------------------------------------------------------------------------
@test "task --help prints usage and exits 0" {
    run "$SCRIPT_DIR/task" --help
    assert_success
    assert_output --partial "Usage: task <command>"
}

@test "task -h is an alias for --help" {
    run "$SCRIPT_DIR/task" -h
    assert_success
    assert_output --partial "Usage: task <command>"
}

@test "task --help lists plan-sync command" {
    run "$SCRIPT_DIR/task" --help
    assert_success
    assert_output --partial "plan-sync"
}

@test "task --help lists claim command" {
    run "$SCRIPT_DIR/task" --help
    assert_success
    assert_output --partial "claim"
}

@test "task --help lists agent commands" {
    run "$SCRIPT_DIR/task" --help
    assert_success
    assert_output --partial "agent register"
    assert_output --partial "agent list"
    assert_output --partial "agent deregister"
}

@test "task --help lists RALPH_DB_URL requirement" {
    run "$SCRIPT_DIR/task" --help
    assert_success
    assert_output --partial "RALPH_DB_URL"
}

# ---------------------------------------------------------------------------
# Missing subcommand
# ---------------------------------------------------------------------------
@test "task with no subcommand prints help to stderr and exits 1" {
    run "$SCRIPT_DIR/task"
    assert_failure
    assert_output --partial "Error: missing command"
    assert_output --partial "Usage: task <command>"
}

# ---------------------------------------------------------------------------
# Unknown subcommand
# ---------------------------------------------------------------------------
@test "task with unknown subcommand exits 1" {
    # Unknown commands don't need RALPH_DB_URL since they fail before db_check
    run "$SCRIPT_DIR/task" bogus-command
    assert_failure
    assert_output --partial "Error: unknown command 'bogus-command'"
}

# ---------------------------------------------------------------------------
# Missing RALPH_DB_URL (copy task to temp dir without .env so fallback doesn't activate)
# ---------------------------------------------------------------------------
@test "task create without RALPH_DB_URL exits 1 with error" {
    cp "$SCRIPT_DIR/task" "$TEST_WORK_DIR/task"
    chmod +x "$TEST_WORK_DIR/task"
    unset RALPH_DB_URL 2>/dev/null || true
    run "$TEST_WORK_DIR/task" create
    assert_failure
    assert_output --partial "RALPH_DB_URL"
}

@test "task list without RALPH_DB_URL exits 1 with error" {
    cp "$SCRIPT_DIR/task" "$TEST_WORK_DIR/task"
    chmod +x "$TEST_WORK_DIR/task"
    unset RALPH_DB_URL 2>/dev/null || true
    run "$TEST_WORK_DIR/task" list
    assert_failure
    assert_output --partial "RALPH_DB_URL"
}

@test "task claim without RALPH_DB_URL exits 1 with error" {
    cp "$SCRIPT_DIR/task" "$TEST_WORK_DIR/task"
    chmod +x "$TEST_WORK_DIR/task"
    unset RALPH_DB_URL 2>/dev/null || true
    run "$TEST_WORK_DIR/task" claim
    assert_failure
    assert_output --partial "RALPH_DB_URL"
}

# ---------------------------------------------------------------------------
# Agent subcommand routing (copy task to temp dir without .env)
# ---------------------------------------------------------------------------
@test "task agent without RALPH_DB_URL exits 1" {
    cp "$SCRIPT_DIR/task" "$TEST_WORK_DIR/task"
    chmod +x "$TEST_WORK_DIR/task"
    unset RALPH_DB_URL 2>/dev/null || true
    run "$TEST_WORK_DIR/task" agent
    assert_failure
    assert_output --partial "RALPH_DB_URL"
}

# ---------------------------------------------------------------------------
# Help does not require RALPH_DB_URL
# ---------------------------------------------------------------------------
@test "task --help works without RALPH_DB_URL" {
    unset RALPH_DB_URL 2>/dev/null || true
    run "$SCRIPT_DIR/task" --help
    assert_success
    assert_output --partial "Usage: task <command>"
}
