#!/usr/bin/env bats
# test/worktree_cleanup.bats — cleanup_worktree tests for lib/worktree.sh

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
        cd "$TEST_WORK_DIR" 2>/dev/null && \
            git worktree list --porcelain 2>/dev/null | grep "^worktree " | grep -v "^worktree $TEST_WORK_DIR$" | sed 's/^worktree //' | while read -r wt; do
                git worktree remove --force "$wt" 2>/dev/null || true
            done
        cd /
        rm -rf "$TEST_WORK_DIR"
    fi
}

# --- basic removal ---

@test "cleanup_worktree removes an existing worktree" {
    cd "$TEST_WORK_DIR"
    create_worktree "sess-100" "aa11" >/dev/null
    assert [ -d ".ralph/worktrees/sess-100" ]
    run cleanup_worktree ".ralph/worktrees/sess-100"
    assert_success
    assert [ ! -d ".ralph/worktrees/sess-100" ]
}

@test "cleanup_worktree logs removal to stderr" {
    cd "$TEST_WORK_DIR"
    create_worktree "sess-101" "bb22" >/dev/null
    run cleanup_worktree ".ralph/worktrees/sess-101"
    assert_success
    assert_output --partial "worktree: removed"
    assert_output --partial ".ralph/worktrees/sess-101"
}

# --- branch preservation ---

@test "cleanup_worktree preserves the branch after removal" {
    cd "$TEST_WORK_DIR"
    create_worktree "sess-102" "cc33" >/dev/null
    cleanup_worktree ".ralph/worktrees/sess-102" 2>/dev/null
    run git branch --list "ralph/cc33"
    assert_output --partial "ralph/cc33"
}

# --- best-effort semantics ---

@test "cleanup_worktree returns 0 for nonexistent path" {
    cd "$TEST_WORK_DIR"
    run cleanup_worktree ".ralph/worktrees/does-not-exist"
    assert_success
    assert_output --partial "failed to remove"
}

@test "cleanup_worktree returns 0 when path is empty" {
    cd "$TEST_WORK_DIR"
    run cleanup_worktree ""
    assert_success
    assert_output --partial "requires"
}

@test "cleanup_worktree returns 0 even on failure" {
    cd "$TEST_WORK_DIR"
    run cleanup_worktree "/nonexistent/path/somewhere"
    assert_success
}

# --- dirty worktree removal ---

@test "cleanup_worktree removes worktree with uncommitted changes" {
    cd "$TEST_WORK_DIR"
    create_worktree "sess-103" "dd44" >/dev/null
    # Make the worktree dirty
    echo "dirty" > ".ralph/worktrees/sess-103/dirty-file.txt"
    run cleanup_worktree ".ralph/worktrees/sess-103"
    assert_success
    assert [ ! -d ".ralph/worktrees/sess-103" ]
}

# --- return code ---

@test "cleanup_worktree always returns 0" {
    cd "$TEST_WORK_DIR"
    # Valid removal
    create_worktree "sess-104" "ee55" >/dev/null
    run cleanup_worktree ".ralph/worktrees/sess-104"
    assert_success

    # Invalid path
    run cleanup_worktree "/bogus/path"
    assert_success

    # Empty arg
    run cleanup_worktree ""
    assert_success
}
