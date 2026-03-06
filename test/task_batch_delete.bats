#!/usr/bin/env bats
# test/task_batch_delete.bats — Tests for batch delete argument validation and --status batch delete
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

# ===========================================================================
# --status batch delete: functional tests
# Spec: specs/task-batch-delete.md#batch-delete-by-status
# ===========================================================================

# Helper: create tasks in open, active, and done statuses for batch delete tests.
# Creates 5 tasks:
#   bd/open-1, bd/open-2  — status open
#   bd/active-1           — status active
#   bd/done-1, bd/done-2  — status done
_setup_mixed_status_tasks() {
    "$SCRIPT_DIR/lib/task" create "bd/open-1" "Open task 1"
    "$SCRIPT_DIR/lib/task" create "bd/open-2" "Open task 2"
    "$SCRIPT_DIR/lib/task" create "bd/active-1" "Active task"
    "$SCRIPT_DIR/lib/task" create "bd/done-1" "Done task 1"
    "$SCRIPT_DIR/lib/task" create "bd/done-2" "Done task 2"

    # Set statuses via direct SQL (update blocks done tasks, claim needs agent)
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active' WHERE slug='bd/active-1' AND scope_repo='test/repo' AND scope_branch='main';"
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='done' WHERE slug IN ('bd/done-1','bd/done-2') AND scope_repo='test/repo' AND scope_branch='main';"
}

# ---------------------------------------------------------------------------
# --status open: only open tasks soft-deleted
# ---------------------------------------------------------------------------
@test "batch delete: --status open deletes only open tasks" {
    _setup_mixed_status_tasks

    run "$SCRIPT_DIR/lib/task" delete --status open
    assert_success
    assert_output "deleted 2 tasks"

    # Verify open tasks are now deleted
    local s1 s2
    s1=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='bd/open-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s2=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='bd/open-2' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s1" = "deleted" ]
    [ "$s2" = "deleted" ]

    # Verify active and done tasks are untouched
    local sa sd1 sd2
    sa=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='bd/active-1' AND scope_repo='test/repo' AND scope_branch='main'")
    sd1=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='bd/done-1' AND scope_repo='test/repo' AND scope_branch='main'")
    sd2=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='bd/done-2' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$sa" = "active" ]
    [ "$sd1" = "done" ]
    [ "$sd2" = "done" ]
}

# ---------------------------------------------------------------------------
# --status open,active: both statuses deleted
# ---------------------------------------------------------------------------
@test "batch delete: --status open,active deletes both statuses" {
    _setup_mixed_status_tasks

    run "$SCRIPT_DIR/lib/task" delete --status open,active
    assert_success
    assert_output "deleted 3 tasks"

    # Verify open and active tasks are deleted
    local s1 s2 sa
    s1=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='bd/open-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s2=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='bd/open-2' AND scope_repo='test/repo' AND scope_branch='main'")
    sa=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='bd/active-1' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s1" = "deleted" ]
    [ "$s2" = "deleted" ]
    [ "$sa" = "deleted" ]

    # Verify done tasks are untouched
    local sd1 sd2
    sd1=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='bd/done-1' AND scope_repo='test/repo' AND scope_branch='main'")
    sd2=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='bd/done-2' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$sd1" = "done" ]
    [ "$sd2" = "done" ]
}

# ---------------------------------------------------------------------------
# N count excludes already-deleted tasks
# ---------------------------------------------------------------------------
@test "batch delete: count excludes already-deleted tasks" {
    _setup_mixed_status_tasks

    # Pre-delete one open task via single-task delete
    "$SCRIPT_DIR/lib/task" delete "bd/open-1"

    # Now batch delete --status open should only count the remaining open task
    run "$SCRIPT_DIR/lib/task" delete --status open
    assert_success
    assert_output "deleted 1 tasks"
}

# ---------------------------------------------------------------------------
# Exit 0 when N=0 (no tasks match the status filter)
# ---------------------------------------------------------------------------
@test "batch delete: exit 0 when no tasks match status filter" {
    _setup_mixed_status_tasks

    # Delete all open tasks first
    "$SCRIPT_DIR/lib/task" delete --status open

    # Try deleting open tasks again — none left
    run "$SCRIPT_DIR/lib/task" delete --status open
    assert_success
    assert_output "deleted 0 tasks"
}

# ---------------------------------------------------------------------------
# Done tasks are not affected by --status open
# ---------------------------------------------------------------------------
@test "batch delete: done tasks unaffected by --status open" {
    _setup_mixed_status_tasks

    "$SCRIPT_DIR/lib/task" delete --status open

    # Verify done tasks still have original status and no deleted_at
    local sd1 sd2 da1 da2
    sd1=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='bd/done-1' AND scope_repo='test/repo' AND scope_branch='main'")
    sd2=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='bd/done-2' AND scope_repo='test/repo' AND scope_branch='main'")
    da1=$(sqlite3 "$TEST_DB_PATH" "SELECT COALESCE(deleted_at, 'NULL') FROM tasks WHERE slug='bd/done-1' AND scope_repo='test/repo' AND scope_branch='main'")
    da2=$(sqlite3 "$TEST_DB_PATH" "SELECT COALESCE(deleted_at, 'NULL') FROM tasks WHERE slug='bd/done-2' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$sd1" = "done" ]
    [ "$sd2" = "done" ]
    [ "$da1" = "NULL" ]
    [ "$da2" = "NULL" ]
}

# ---------------------------------------------------------------------------
# Soft-delete semantics: deleted_at and updated_at set on batch delete
# ---------------------------------------------------------------------------
@test "batch delete: sets deleted_at and updated_at on affected tasks" {
    _setup_mixed_status_tasks

    "$SCRIPT_DIR/lib/task" delete --status open

    # Verify deleted_at is set on affected tasks
    local da1 da2
    da1=$(sqlite3 "$TEST_DB_PATH" "SELECT CASE WHEN deleted_at IS NOT NULL THEN 1 ELSE 0 END FROM tasks WHERE slug='bd/open-1' AND scope_repo='test/repo' AND scope_branch='main'")
    da2=$(sqlite3 "$TEST_DB_PATH" "SELECT CASE WHEN deleted_at IS NOT NULL THEN 1 ELSE 0 END FROM tasks WHERE slug='bd/open-2' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$da1" = "1" ]
    [ "$da2" = "1" ]

    # Verify updated_at is set on affected tasks
    local ua1 ua2
    ua1=$(sqlite3 "$TEST_DB_PATH" "SELECT CASE WHEN updated_at IS NOT NULL THEN 1 ELSE 0 END FROM tasks WHERE slug='bd/open-1' AND scope_repo='test/repo' AND scope_branch='main'")
    ua2=$(sqlite3 "$TEST_DB_PATH" "SELECT CASE WHEN updated_at IS NOT NULL THEN 1 ELSE 0 END FROM tasks WHERE slug='bd/open-2' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$ua1" = "1" ]
    [ "$ua2" = "1" ]
}

# ===========================================================================
# --spec and --category filters: functional tests
# Spec: specs/task-batch-delete.md#combinable-filters
# ===========================================================================

# Helper: create tasks with varying spec_ref and category values.
# Creates 6 open tasks across two specs and two categories:
#   sf/cli-feat-1   — spec_ref=task-cli.md, category=feat
#   sf/cli-feat-2   — spec_ref=task-cli.md, category=feat
#   sf/cli-test-1   — spec_ref=task-cli.md, category=test
#   sf/bd-feat-1    — spec_ref=task-batch-delete.md, category=feat
#   sf/bd-test-1    — spec_ref=task-batch-delete.md, category=test
#   sf/nospec-1     — no spec_ref, no category
_setup_spec_category_tasks() {
    "$SCRIPT_DIR/lib/task" create "sf/cli-feat-1"  "CLI feature 1"  -r task-cli.md -c feat
    "$SCRIPT_DIR/lib/task" create "sf/cli-feat-2"  "CLI feature 2"  -r task-cli.md -c feat
    "$SCRIPT_DIR/lib/task" create "sf/cli-test-1"  "CLI test 1"     -r task-cli.md -c test
    "$SCRIPT_DIR/lib/task" create "sf/bd-feat-1"   "BD feature 1"   -r task-batch-delete.md -c feat
    "$SCRIPT_DIR/lib/task" create "sf/bd-test-1"   "BD test 1"      -r task-batch-delete.md -c test
    "$SCRIPT_DIR/lib/task" create "sf/nospec-1"    "No spec task"
}

# ---------------------------------------------------------------------------
# --status open --spec: filters to matching spec_ref only
# ---------------------------------------------------------------------------
@test "batch delete: --status open --spec filters to matching spec_ref only" {
    _setup_spec_category_tasks

    run "$SCRIPT_DIR/lib/task" delete --status open --spec task-cli.md
    assert_success
    assert_output "deleted 3 tasks"

    # Verify task-cli.md tasks are deleted
    local s1 s2 s3
    s1=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-feat-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s2=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-feat-2' AND scope_repo='test/repo' AND scope_branch='main'")
    s3=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-test-1' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s1" = "deleted" ]
    [ "$s2" = "deleted" ]
    [ "$s3" = "deleted" ]

    # Verify task-batch-delete.md and no-spec tasks are untouched
    local s4 s5 s6
    s4=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/bd-feat-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s5=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/bd-test-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s6=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/nospec-1' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s4" = "open" ]
    [ "$s5" = "open" ]
    [ "$s6" = "open" ]
}

# ---------------------------------------------------------------------------
# --status open --category: filters to matching category only
# ---------------------------------------------------------------------------
@test "batch delete: --status open --category filters to matching category only" {
    _setup_spec_category_tasks

    run "$SCRIPT_DIR/lib/task" delete --status open --category feat
    assert_success
    assert_output "deleted 3 tasks"

    # Verify feat tasks are deleted
    local s1 s2 s3
    s1=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-feat-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s2=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-feat-2' AND scope_repo='test/repo' AND scope_branch='main'")
    s3=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/bd-feat-1' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s1" = "deleted" ]
    [ "$s2" = "deleted" ]
    [ "$s3" = "deleted" ]

    # Verify test and no-category tasks are untouched
    local s4 s5 s6
    s4=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-test-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s5=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/bd-test-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s6=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/nospec-1' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s4" = "open" ]
    [ "$s5" = "open" ]
    [ "$s6" = "open" ]
}

# ---------------------------------------------------------------------------
# --status open --spec X --category Y: AND logic
# ---------------------------------------------------------------------------
@test "batch delete: --status open --spec --category applies AND logic" {
    _setup_spec_category_tasks

    run "$SCRIPT_DIR/lib/task" delete --status open --spec task-cli.md --category feat
    assert_success
    assert_output "deleted 2 tasks"

    # Verify only task-cli.md + feat tasks are deleted
    local s1 s2
    s1=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-feat-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s2=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-feat-2' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s1" = "deleted" ]
    [ "$s2" = "deleted" ]

    # Verify task-cli.md + test is NOT deleted (wrong category)
    local s3
    s3=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-test-1' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s3" = "open" ]

    # Verify task-batch-delete.md + feat is NOT deleted (wrong spec)
    local s4
    s4=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/bd-feat-1' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s4" = "open" ]

    # Verify remaining tasks are untouched
    local s5 s6
    s5=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/bd-test-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s6=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/nospec-1' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s5" = "open" ]
    [ "$s6" = "open" ]
}

# ---------------------------------------------------------------------------
# --all --confirm --spec: deletes only tasks with that spec
# ---------------------------------------------------------------------------
@test "batch delete: --all --confirm --spec deletes only tasks with that spec" {
    _setup_spec_category_tasks

    # Move some tasks to different statuses to verify --all crosses status boundaries
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active' WHERE slug='sf/cli-feat-2' AND scope_repo='test/repo' AND scope_branch='main';"
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='done' WHERE slug='sf/cli-test-1' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/lib/task" delete --all --confirm --spec task-cli.md
    assert_success
    assert_output "deleted 3 tasks"

    # Verify all task-cli.md tasks are deleted regardless of original status
    local s1 s2 s3
    s1=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-feat-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s2=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-feat-2' AND scope_repo='test/repo' AND scope_branch='main'")
    s3=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-test-1' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s1" = "deleted" ]
    [ "$s2" = "deleted" ]
    [ "$s3" = "deleted" ]

    # Verify non-matching spec tasks are untouched
    local s4 s5 s6
    s4=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/bd-feat-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s5=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/bd-test-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s6=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/nospec-1' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s4" = "open" ]
    [ "$s5" = "open" ]
    [ "$s6" = "open" ]
}

# ---------------------------------------------------------------------------
# --all --confirm --category: deletes only tasks with that category
# ---------------------------------------------------------------------------
@test "batch delete: --all --confirm --category deletes only tasks with that category" {
    _setup_spec_category_tasks

    # Move some tasks to different statuses
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='done' WHERE slug='sf/cli-feat-2' AND scope_repo='test/repo' AND scope_branch='main';"
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active' WHERE slug='sf/bd-feat-1' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/lib/task" delete --all --confirm --category test
    assert_success
    assert_output "deleted 2 tasks"

    # Verify test-category tasks are deleted
    local s1 s2
    s1=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-test-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s2=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/bd-test-1' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s1" = "deleted" ]
    [ "$s2" = "deleted" ]

    # Verify non-test tasks are untouched
    local s3 s4 s5 s6
    s3=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-feat-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s4=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-feat-2' AND scope_repo='test/repo' AND scope_branch='main'")
    s5=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/bd-feat-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s6=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/nospec-1' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s3" = "open" ]
    [ "$s4" = "done" ]
    [ "$s5" = "active" ]
    [ "$s6" = "open" ]
}

# ---------------------------------------------------------------------------
# --all --confirm --spec --category: AND logic across all statuses
# ---------------------------------------------------------------------------
@test "batch delete: --all --confirm --spec --category applies AND logic" {
    _setup_spec_category_tasks

    # Move one matching task to done status
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='done' WHERE slug='sf/cli-feat-2' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/lib/task" delete --all --confirm --spec task-cli.md --category feat
    assert_success
    assert_output "deleted 2 tasks"

    # Verify only task-cli.md + feat tasks are deleted
    local s1 s2
    s1=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-feat-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s2=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-feat-2' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s1" = "deleted" ]
    [ "$s2" = "deleted" ]

    # Verify other tasks are untouched
    local s3 s4 s5 s6
    s3=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/cli-test-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s4=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/bd-feat-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s5=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/bd-test-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s6=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='sf/nospec-1' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s3" = "open" ]
    [ "$s4" = "open" ]
    [ "$s5" = "open" ]
    [ "$s6" = "open" ]
}

# ---------------------------------------------------------------------------
# --spec with no matching tasks returns 0 count
# ---------------------------------------------------------------------------
@test "batch delete: --status open --spec with no matches returns 0" {
    _setup_spec_category_tasks

    run "$SCRIPT_DIR/lib/task" delete --status open --spec nonexistent-spec.md
    assert_success
    assert_output "deleted 0 tasks"
}

# ---------------------------------------------------------------------------
# --category with no matching tasks returns 0 count
# ---------------------------------------------------------------------------
@test "batch delete: --status open --category with no matches returns 0" {
    _setup_spec_category_tasks

    run "$SCRIPT_DIR/lib/task" delete --status open --category nonexistent
    assert_success
    assert_output "deleted 0 tasks"
}
