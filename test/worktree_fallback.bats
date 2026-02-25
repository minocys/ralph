#!/usr/bin/env bats
# test/worktree_fallback.bats — setup_worktree fallback tests for lib/worktree.sh

_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
_SCRIPT_DIR="$(cd "$_TEST_DIR/.." && pwd)"

load "$_TEST_DIR/libs/bats-support/load"
load "$_TEST_DIR/libs/bats-assert/load"

setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    export TEST_WORK_DIR

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

# Helper: create a real git repo in TEST_WORK_DIR
_init_git_repo() {
    cd "$TEST_WORK_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "initial" > README.md
    git add README.md
    git commit -q -m "initial commit"
}

# --- git repo: successful worktree creation ---

@test "setup_worktree sets RALPH_WORK_DIR to worktree path in git repo" {
    _init_git_repo
    setup_worktree "$TEST_WORK_DIR" "sess-f01" "ab12"
    [[ "$RALPH_WORK_DIR" == "$TEST_WORK_DIR/.ralph/worktrees/sess-f01" ]]
}

@test "setup_worktree returns 0 on successful worktree creation" {
    _init_git_repo
    run setup_worktree "$TEST_WORK_DIR" "sess-f02" "cd34"
    assert_success
}

@test "setup_worktree creates worktree directory in git repo" {
    _init_git_repo
    setup_worktree "$TEST_WORK_DIR" "sess-f03" "ef56"
    assert [ -d "$TEST_WORK_DIR/.ralph/worktrees/sess-f03" ]
}

# --- non-git directory: fallback ---

@test "setup_worktree falls back to project dir when not a git repo" {
    # TEST_WORK_DIR is a plain directory, not a git repo
    setup_worktree "$TEST_WORK_DIR" "sess-f04" "1234"
    [ "$RALPH_WORK_DIR" = "$TEST_WORK_DIR" ]
}

@test "setup_worktree warns when not a git repo" {
    run setup_worktree "$TEST_WORK_DIR" "sess-f05" "5678"
    assert_success
    assert_output --partial "not a git repository"
}

@test "setup_worktree returns 0 when not a git repo" {
    run setup_worktree "$TEST_WORK_DIR" "sess-f06" "9abc"
    assert_success
}

# --- worktree creation failure: fallback ---

@test "setup_worktree falls back to project dir when worktree creation fails" {
    _init_git_repo
    # Create a worktree with the same branch to cause a conflict
    setup_worktree "$TEST_WORK_DIR" "sess-f07" "dup1"
    # Now try again with the same agent-id (branch conflict)
    setup_worktree "$TEST_WORK_DIR" "sess-f08" "dup1"
    [ "$RALPH_WORK_DIR" = "$TEST_WORK_DIR" ]
}

@test "setup_worktree warns when worktree creation fails" {
    _init_git_repo
    # First call succeeds
    setup_worktree "$TEST_WORK_DIR" "sess-f09" "dup2"
    # Second call with same branch should fail
    run setup_worktree "$TEST_WORK_DIR" "sess-f10" "dup2"
    assert_success
    assert_output --partial "worktree creation failed"
}

@test "setup_worktree returns 0 when worktree creation fails" {
    _init_git_repo
    setup_worktree "$TEST_WORK_DIR" "sess-f11" "dup3"
    run setup_worktree "$TEST_WORK_DIR" "sess-f12" "dup3"
    assert_success
}

# --- RALPH_WORK_DIR is always set ---

@test "RALPH_WORK_DIR is set even when project dir is not a git repo" {
    setup_worktree "$TEST_WORK_DIR" "sess-f13" "wxyz"
    [ -n "$RALPH_WORK_DIR" ]
}
