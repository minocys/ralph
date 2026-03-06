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

# ===========================================================================
# --all --confirm: functional tests
# Spec: specs/task-batch-delete.md#delete-all
# ===========================================================================

# Helper: create tasks in open, active, done, and deleted statuses.
# Creates 7 tasks:
#   ad/open-1, ad/open-2    — status open
#   ad/active-1              — status active
#   ad/done-1, ad/done-2     — status done
#   ad/deleted-1, ad/deleted-2 — status deleted (pre-existing)
_setup_all_status_tasks() {
    "$SCRIPT_DIR/lib/task" create "ad/open-1"    "Open task 1"
    "$SCRIPT_DIR/lib/task" create "ad/open-2"    "Open task 2"
    "$SCRIPT_DIR/lib/task" create "ad/active-1"  "Active task"
    "$SCRIPT_DIR/lib/task" create "ad/done-1"    "Done task 1"
    "$SCRIPT_DIR/lib/task" create "ad/done-2"    "Done task 2"
    "$SCRIPT_DIR/lib/task" create "ad/deleted-1" "Deleted task 1"
    "$SCRIPT_DIR/lib/task" create "ad/deleted-2" "Deleted task 2"

    # Set statuses via direct SQL
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active' WHERE slug='ad/active-1' AND scope_repo='test/repo' AND scope_branch='main';"
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='done' WHERE slug IN ('ad/done-1','ad/done-2') AND scope_repo='test/repo' AND scope_branch='main';"
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='deleted', deleted_at=datetime('now') WHERE slug IN ('ad/deleted-1','ad/deleted-2') AND scope_repo='test/repo' AND scope_branch='main';"
}

# ---------------------------------------------------------------------------
# --all --confirm deletes open + active + done but not deleted
# ---------------------------------------------------------------------------
@test "batch delete: --all --confirm deletes open, active, done but not already-deleted" {
    _setup_all_status_tasks

    run "$SCRIPT_DIR/lib/task" delete --all --confirm
    assert_success
    assert_output "deleted 5 tasks"

    # Verify open tasks are deleted
    local s1 s2
    s1=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='ad/open-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s2=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='ad/open-2' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s1" = "deleted" ]
    [ "$s2" = "deleted" ]

    # Verify active task is deleted
    local sa
    sa=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='ad/active-1' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$sa" = "deleted" ]

    # Verify done tasks are deleted
    local sd1 sd2
    sd1=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='ad/done-1' AND scope_repo='test/repo' AND scope_branch='main'")
    sd2=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='ad/done-2' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$sd1" = "deleted" ]
    [ "$sd2" = "deleted" ]

    # Verify all 7 tasks exist in DB (soft delete preserves rows)
    local total
    total=$(sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE scope_repo='test/repo' AND scope_branch='main'")
    [ "$total" = "7" ]
}

# ---------------------------------------------------------------------------
# N count excludes already-deleted tasks
# ---------------------------------------------------------------------------
@test "batch delete: --all --confirm count excludes already-deleted tasks" {
    _setup_all_status_tasks

    # N should be 5 (7 total minus 2 already deleted)
    run "$SCRIPT_DIR/lib/task" delete --all --confirm
    assert_success
    assert_output "deleted 5 tasks"
}

# ---------------------------------------------------------------------------
# Already-deleted tasks are not re-stamped
# ---------------------------------------------------------------------------
@test "batch delete: --all --confirm does not re-stamp already-deleted tasks" {
    _setup_all_status_tasks

    # Record the original deleted_at timestamps of already-deleted tasks
    local orig_da1 orig_da2
    orig_da1=$(sqlite3 "$TEST_DB_PATH" "SELECT deleted_at FROM tasks WHERE slug='ad/deleted-1' AND scope_repo='test/repo' AND scope_branch='main'")
    orig_da2=$(sqlite3 "$TEST_DB_PATH" "SELECT deleted_at FROM tasks WHERE slug='ad/deleted-2' AND scope_repo='test/repo' AND scope_branch='main'")

    # Small delay to ensure timestamps would differ if re-stamped
    sleep 1

    "$SCRIPT_DIR/lib/task" delete --all --confirm

    # Verify timestamps are unchanged
    local new_da1 new_da2
    new_da1=$(sqlite3 "$TEST_DB_PATH" "SELECT deleted_at FROM tasks WHERE slug='ad/deleted-1' AND scope_repo='test/repo' AND scope_branch='main'")
    new_da2=$(sqlite3 "$TEST_DB_PATH" "SELECT deleted_at FROM tasks WHERE slug='ad/deleted-2' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$orig_da1" = "$new_da1" ]
    [ "$orig_da2" = "$new_da2" ]
}

# ---------------------------------------------------------------------------
# --all --confirm sets deleted_at and updated_at on newly deleted tasks
# ---------------------------------------------------------------------------
@test "batch delete: --all --confirm sets deleted_at and updated_at" {
    _setup_all_status_tasks

    "$SCRIPT_DIR/lib/task" delete --all --confirm

    # Verify deleted_at is set on previously non-deleted tasks
    local da1 da2 da3 da4 da5
    da1=$(sqlite3 "$TEST_DB_PATH" "SELECT CASE WHEN deleted_at IS NOT NULL THEN 1 ELSE 0 END FROM tasks WHERE slug='ad/open-1' AND scope_repo='test/repo' AND scope_branch='main'")
    da2=$(sqlite3 "$TEST_DB_PATH" "SELECT CASE WHEN deleted_at IS NOT NULL THEN 1 ELSE 0 END FROM tasks WHERE slug='ad/open-2' AND scope_repo='test/repo' AND scope_branch='main'")
    da3=$(sqlite3 "$TEST_DB_PATH" "SELECT CASE WHEN deleted_at IS NOT NULL THEN 1 ELSE 0 END FROM tasks WHERE slug='ad/active-1' AND scope_repo='test/repo' AND scope_branch='main'")
    da4=$(sqlite3 "$TEST_DB_PATH" "SELECT CASE WHEN deleted_at IS NOT NULL THEN 1 ELSE 0 END FROM tasks WHERE slug='ad/done-1' AND scope_repo='test/repo' AND scope_branch='main'")
    da5=$(sqlite3 "$TEST_DB_PATH" "SELECT CASE WHEN deleted_at IS NOT NULL THEN 1 ELSE 0 END FROM tasks WHERE slug='ad/done-2' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$da1" = "1" ]
    [ "$da2" = "1" ]
    [ "$da3" = "1" ]
    [ "$da4" = "1" ]
    [ "$da5" = "1" ]

    # Verify updated_at is set on affected tasks
    local ua1 ua2 ua3
    ua1=$(sqlite3 "$TEST_DB_PATH" "SELECT CASE WHEN updated_at IS NOT NULL THEN 1 ELSE 0 END FROM tasks WHERE slug='ad/open-1' AND scope_repo='test/repo' AND scope_branch='main'")
    ua2=$(sqlite3 "$TEST_DB_PATH" "SELECT CASE WHEN updated_at IS NOT NULL THEN 1 ELSE 0 END FROM tasks WHERE slug='ad/active-1' AND scope_repo='test/repo' AND scope_branch='main'")
    ua3=$(sqlite3 "$TEST_DB_PATH" "SELECT CASE WHEN updated_at IS NOT NULL THEN 1 ELSE 0 END FROM tasks WHERE slug='ad/done-1' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$ua1" = "1" ]
    [ "$ua2" = "1" ]
    [ "$ua3" = "1" ]
}

# ---------------------------------------------------------------------------
# --all --confirm with no non-deleted tasks: N=0, exit 0
# ---------------------------------------------------------------------------
@test "batch delete: --all --confirm with only deleted tasks returns 0" {
    # Create tasks then delete them all individually first
    "$SCRIPT_DIR/lib/task" create "ad/t1" "Task 1"
    "$SCRIPT_DIR/lib/task" create "ad/t2" "Task 2"
    "$SCRIPT_DIR/lib/task" delete "ad/t1"
    "$SCRIPT_DIR/lib/task" delete "ad/t2"

    run "$SCRIPT_DIR/lib/task" delete --all --confirm
    assert_success
    assert_output "deleted 0 tasks"
}

# ---------------------------------------------------------------------------
# --all --confirm --spec: narrows to one spec across all statuses
# ---------------------------------------------------------------------------
@test "batch delete: --all --confirm --spec narrows to one spec" {
    # Create tasks across two specs with mixed statuses
    "$SCRIPT_DIR/lib/task" create "as/cli-1"  "CLI task 1"   -r task-cli.md
    "$SCRIPT_DIR/lib/task" create "as/cli-2"  "CLI task 2"   -r task-cli.md
    "$SCRIPT_DIR/lib/task" create "as/cli-3"  "CLI task 3"   -r task-cli.md
    "$SCRIPT_DIR/lib/task" create "as/bd-1"   "BD task 1"    -r task-batch-delete.md
    "$SCRIPT_DIR/lib/task" create "as/bd-2"   "BD task 2"    -r task-batch-delete.md
    "$SCRIPT_DIR/lib/task" create "as/nospec" "No spec task"

    # Put CLI tasks in different statuses: open, active, done
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active' WHERE slug='as/cli-2' AND scope_repo='test/repo' AND scope_branch='main';"
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='done' WHERE slug='as/cli-3' AND scope_repo='test/repo' AND scope_branch='main';"

    # Also put one BD task as done
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='done' WHERE slug='as/bd-2' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/lib/task" delete --all --confirm --spec task-cli.md
    assert_success
    assert_output "deleted 3 tasks"

    # Verify all CLI tasks are deleted regardless of prior status
    local s1 s2 s3
    s1=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='as/cli-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s2=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='as/cli-2' AND scope_repo='test/repo' AND scope_branch='main'")
    s3=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='as/cli-3' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s1" = "deleted" ]
    [ "$s2" = "deleted" ]
    [ "$s3" = "deleted" ]

    # Verify non-CLI tasks are untouched
    local s4 s5 s6
    s4=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='as/bd-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s5=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='as/bd-2' AND scope_repo='test/repo' AND scope_branch='main'")
    s6=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='as/nospec' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s4" = "open" ]
    [ "$s5" = "done" ]
    [ "$s6" = "open" ]
}

# ---------------------------------------------------------------------------
# --all --confirm --category: narrows to one category across all statuses
# ---------------------------------------------------------------------------
@test "batch delete: --all --confirm --category narrows to one category" {
    # Create tasks across two categories with mixed statuses
    "$SCRIPT_DIR/lib/task" create "ac/feat-1"  "Feat task 1"  -c feat
    "$SCRIPT_DIR/lib/task" create "ac/feat-2"  "Feat task 2"  -c feat
    "$SCRIPT_DIR/lib/task" create "ac/feat-3"  "Feat task 3"  -c feat
    "$SCRIPT_DIR/lib/task" create "ac/test-1"  "Test task 1"  -c test
    "$SCRIPT_DIR/lib/task" create "ac/test-2"  "Test task 2"  -c test
    "$SCRIPT_DIR/lib/task" create "ac/nocat"   "No cat task"

    # Mix statuses for feat tasks: open, active, done
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active' WHERE slug='ac/feat-2' AND scope_repo='test/repo' AND scope_branch='main';"
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='done' WHERE slug='ac/feat-3' AND scope_repo='test/repo' AND scope_branch='main';"

    # Also put one test task as active
    sqlite3 "$TEST_DB_PATH" "UPDATE tasks SET status='active' WHERE slug='ac/test-2' AND scope_repo='test/repo' AND scope_branch='main';"

    run "$SCRIPT_DIR/lib/task" delete --all --confirm --category feat
    assert_success
    assert_output "deleted 3 tasks"

    # Verify all feat tasks are deleted regardless of prior status
    local s1 s2 s3
    s1=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='ac/feat-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s2=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='ac/feat-2' AND scope_repo='test/repo' AND scope_branch='main'")
    s3=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='ac/feat-3' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s1" = "deleted" ]
    [ "$s2" = "deleted" ]
    [ "$s3" = "deleted" ]

    # Verify non-feat tasks are untouched
    local s4 s5 s6
    s4=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='ac/test-1' AND scope_repo='test/repo' AND scope_branch='main'")
    s5=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='ac/test-2' AND scope_repo='test/repo' AND scope_branch='main'")
    s6=$(sqlite3 "$TEST_DB_PATH" "SELECT status FROM tasks WHERE slug='ac/nocat' AND scope_repo='test/repo' AND scope_branch='main'")
    [ "$s4" = "open" ]
    [ "$s5" = "active" ]
    [ "$s6" = "open" ]
}
