#!/usr/bin/env bats
# test/task_batch_delete.bats — Tests for batch delete argument validation
# Spec: specs/task-batch-delete.md#requirements

load test_helper

# ---------------------------------------------------------------------------
# Positional ID + flag mutual exclusion
# ---------------------------------------------------------------------------
@test "batch delete: positional ID + --status exits 1 with usage error" {
    run "$SCRIPT_DIR/lib/task" delete "test/01" --status open
    assert_failure
    [ "$status" -eq 1 ]
}

@test "batch delete: positional ID + --all exits 1 with usage error" {
    run "$SCRIPT_DIR/lib/task" delete "test/01" --all --confirm
    assert_failure
    [ "$status" -eq 1 ]
}

@test "batch delete: positional ID + --spec exits 1 with usage error" {
    run "$SCRIPT_DIR/lib/task" delete "test/01" --spec task-cli.md
    assert_failure
    [ "$status" -eq 1 ]
}

@test "batch delete: positional ID + --category exits 1 with usage error" {
    run "$SCRIPT_DIR/lib/task" delete "test/01" --category feat
    assert_failure
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# --spec alone without --status or --all
# ---------------------------------------------------------------------------
@test "batch delete: --spec alone without --status or --all exits 1" {
    run "$SCRIPT_DIR/lib/task" delete --spec task-cli.md
    assert_failure
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# --category alone without --status or --all
# ---------------------------------------------------------------------------
@test "batch delete: --category alone without --status or --all exits 1" {
    run "$SCRIPT_DIR/lib/task" delete --category feat
    assert_failure
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# --all without --confirm
# ---------------------------------------------------------------------------
@test "batch delete: --all without --confirm exits 1 with specific error" {
    run "$SCRIPT_DIR/lib/task" delete --all
    assert_failure
    [ "$status" -eq 1 ]
    assert_output --partial "Error: --all requires --confirm flag"
}

# ---------------------------------------------------------------------------
# --all + --status mutual exclusion
# ---------------------------------------------------------------------------
@test "batch delete: --all + --status exits 1 with usage error" {
    run "$SCRIPT_DIR/lib/task" delete --all --confirm --status open
    assert_failure
    [ "$status" -eq 1 ]
}

@test "batch delete: --status + --all exits 1 with usage error" {
    run "$SCRIPT_DIR/lib/task" delete --status open --all --confirm
    assert_failure
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# --status deleted is rejected
# ---------------------------------------------------------------------------
@test "batch delete: --status deleted exits 1" {
    run "$SCRIPT_DIR/lib/task" delete --status deleted
    assert_failure
    [ "$status" -eq 1 ]
}

@test "batch delete: --status with deleted in csv exits 1" {
    run "$SCRIPT_DIR/lib/task" delete --status open,deleted
    assert_failure
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# --spec and --category alone together still require --status or --all
# ---------------------------------------------------------------------------
@test "batch delete: --spec + --category without --status or --all exits 1" {
    run "$SCRIPT_DIR/lib/task" delete --spec task-cli.md --category feat
    assert_failure
    [ "$status" -eq 1 ]
}
