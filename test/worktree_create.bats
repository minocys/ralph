#!/usr/bin/env bats
# test/worktree_create.bats — create_worktree tests for lib/worktree.sh

_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
_SCRIPT_DIR="$(cd "$_TEST_DIR/.." && pwd)"

load "$_TEST_DIR/libs/bats-support/load"
load "$_TEST_DIR/libs/bats-assert/load"

setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    export TEST_WORK_DIR

    # Create a real git repo for worktree tests
    cd "$TEST_WORK_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "initial" > README.md
    git add README.md
    git commit -q -m "initial commit"

    # Source the worktree lib
    . "$_SCRIPT_DIR/lib/worktree.sh"
}

teardown() {
    if [[ -d "$TEST_WORK_DIR" ]]; then
        # Clean up worktrees before removing the directory
        cd "$TEST_WORK_DIR" 2>/dev/null && \
            git worktree list --porcelain 2>/dev/null | grep "^worktree " | grep -v "^worktree $TEST_WORK_DIR$" | sed 's/^worktree //' | while read -r wt; do
                git worktree remove --force "$wt" 2>/dev/null || true
            done
        cd /
        rm -rf "$TEST_WORK_DIR"
    fi
}

# --- basic creation ---

@test "create_worktree creates worktree directory" {
    cd "$TEST_WORK_DIR"
    run create_worktree "sess-001" "a1b2"
    assert_success
    assert [ -d ".ralph/worktrees/sess-001" ]
}

@test "create_worktree returns worktree path on stdout" {
    cd "$TEST_WORK_DIR"
    run create_worktree "sess-002" "c3d4"
    assert_success
    assert_output --partial ".ralph/worktrees/sess-002"
}

@test "create_worktree creates branch ralph/<agent-id>" {
    cd "$TEST_WORK_DIR"
    create_worktree "sess-003" "e5f6" >/dev/null
    run git branch --list "ralph/e5f6"
    assert_output --partial "ralph/e5f6"
}

@test "create_worktree logs path to stderr" {
    cd "$TEST_WORK_DIR"
    run create_worktree "sess-004" "1a2b"
    assert_success
    assert_output --partial "worktree: created"
    assert_output --partial "ralph/1a2b"
}

# --- worktree contents ---

@test "worktree contains files from HEAD" {
    cd "$TEST_WORK_DIR"
    create_worktree "sess-005" "3c4d" >/dev/null
    assert [ -f ".ralph/worktrees/sess-005/README.md" ]
}

@test "worktree is on the correct branch" {
    cd "$TEST_WORK_DIR"
    create_worktree "sess-006" "5e6f" >/dev/null
    run git -C ".ralph/worktrees/sess-006" branch --show-current
    assert_success
    assert_output "ralph/5e6f"
}

# --- directory creation ---

@test "create_worktree creates .ralph/worktrees/ if missing" {
    cd "$TEST_WORK_DIR"
    assert [ ! -d ".ralph/worktrees" ]
    run create_worktree "sess-007" "7a8b"
    assert_success
    assert [ -d ".ralph/worktrees" ]
}

# --- error handling ---

@test "create_worktree fails without session-id" {
    cd "$TEST_WORK_DIR"
    run create_worktree "" "abcd"
    assert_failure
    assert_output --partial "requires"
}

@test "create_worktree fails without agent-id" {
    cd "$TEST_WORK_DIR"
    run create_worktree "sess-008" ""
    assert_failure
    assert_output --partial "requires"
}

@test "create_worktree fails when branch already exists" {
    cd "$TEST_WORK_DIR"
    create_worktree "sess-009" "dup1" >/dev/null
    # Try to create another worktree with the same branch name
    run create_worktree "sess-010" "dup1"
    assert_failure
}

# --- return code ---

@test "create_worktree returns 0 on success" {
    cd "$TEST_WORK_DIR"
    run create_worktree "sess-011" "ok01"
    assert_success
}

@test "create_worktree returns 1 on failure" {
    cd "$TEST_WORK_DIR"
    run create_worktree "" ""
    assert_failure
}
