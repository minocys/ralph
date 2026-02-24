#!/usr/bin/env bats
# test/task_steps_simplification.bats — verify step-done command is rejected
#
# After the task-steps-simplification change, steps are informational only
# (TEXT[] on the tasks table). The step-done command no longer exists; calling
# it must fail with an unknown-command error.

load test_helper

# ---------------------------------------------------------------------------
# step-done is rejected as an unknown command
# ---------------------------------------------------------------------------
@test "task step-done with valid-looking arguments exits 1" {
    run "$SCRIPT_DIR/lib/task" step-done "my-task/01" "1"
    assert_failure
    assert_output --partial "Error: unknown command 'step-done'"
}

@test "task step-done with no arguments exits 1" {
    run "$SCRIPT_DIR/lib/task" step-done
    assert_failure
    assert_output --partial "Error: unknown command 'step-done'"
}

# ---------------------------------------------------------------------------
# help output does not mention step-done
# ---------------------------------------------------------------------------
@test "task --help does not mention step-done" {
    run "$SCRIPT_DIR/lib/task" --help
    assert_success
    refute_output --partial "step-done"
}
