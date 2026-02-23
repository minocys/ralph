#!/usr/bin/env bats
# test/task_scope_derivation.bats — Tests for get_scope() in task CLI
# Tests scope derivation from env vars and git, URL parsing, and error cases.

load test_helper

# ---------------------------------------------------------------------------
# Helpers: git stubs
# ---------------------------------------------------------------------------

# Create a git stub that reports inside work tree, returns a remote URL and branch
create_git_stub() {
    local remote_url="${1:-https://github.com/owner/repo.git}"
    local branch="${2:-main}"
    cat > "$STUB_DIR/git" <<GITSTUB
#!/bin/bash
case "\$*" in
    "rev-parse --is-inside-work-tree")
        echo "true"
        exit 0
        ;;
    "remote get-url origin")
        echo "$remote_url"
        exit 0
        ;;
    "branch --show-current")
        echo "$branch"
        exit 0
        ;;
esac
exit 1
GITSTUB
    chmod +x "$STUB_DIR/git"
}

# Create a git stub that says "not in a git repo"
create_git_stub_not_repo() {
    cat > "$STUB_DIR/git" <<'GITSTUB'
#!/bin/bash
case "$*" in
    "rev-parse --is-inside-work-tree")
        echo "fatal: not a git repository" >&2
        exit 128
        ;;
esac
exit 1
GITSTUB
    chmod +x "$STUB_DIR/git"
}

# Create a git stub with no origin remote
create_git_stub_no_origin() {
    cat > "$STUB_DIR/git" <<'GITSTUB'
#!/bin/bash
case "$*" in
    "rev-parse --is-inside-work-tree")
        echo "true"
        exit 0
        ;;
    "remote get-url origin")
        echo "fatal: No such remote 'origin'" >&2
        exit 2
        ;;
esac
exit 1
GITSTUB
    chmod +x "$STUB_DIR/git"
}

# Create a git stub that reports detached HEAD (empty branch output)
create_git_stub_detached() {
    local remote_url="${1:-https://github.com/owner/repo.git}"
    cat > "$STUB_DIR/git" <<GITSTUB
#!/bin/bash
case "\$*" in
    "rev-parse --is-inside-work-tree")
        echo "true"
        exit 0
        ;;
    "remote get-url origin")
        echo "$remote_url"
        exit 0
        ;;
    "branch --show-current")
        echo ""
        exit 0
        ;;
esac
exit 1
GITSTUB
    chmod +x "$STUB_DIR/git"
}

setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export TEST_WORK_DIR STUB_DIR
    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"

    # Ensure scope env vars are unset by default
    unset RALPH_SCOPE_REPO
    unset RALPH_SCOPE_BRANCH

    cd "$TEST_WORK_DIR"
}

teardown() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    [[ -d "${TEST_WORK_DIR:-}" ]] && rm -rf "$TEST_WORK_DIR"
    [[ -d "${STUB_DIR:-}" ]] && rm -rf "$STUB_DIR"
}

# ---------------------------------------------------------------------------
# Env var override tests
# ---------------------------------------------------------------------------

@test "RALPH_SCOPE_REPO overrides git-derived repo" {
    create_git_stub "https://github.com/fallback/should-not-use.git" "main"
    export RALPH_SCOPE_REPO="override/repo"
    run "$SCRIPT_DIR/task" _get-scope
    assert_success
    assert_line "repo:override/repo"
    assert_line "branch:main"
}

@test "RALPH_SCOPE_BRANCH overrides git-derived branch" {
    create_git_stub "https://github.com/owner/repo.git" "should-not-use"
    export RALPH_SCOPE_BRANCH="override-branch"
    run "$SCRIPT_DIR/task" _get-scope
    assert_success
    assert_line "repo:owner/repo"
    assert_line "branch:override-branch"
}

@test "both env vars set — git not called" {
    # git stub returns errors — proves git is never invoked
    create_git_stub_not_repo
    export RALPH_SCOPE_REPO="env/repo"
    export RALPH_SCOPE_BRANCH="env-branch"
    run "$SCRIPT_DIR/task" _get-scope
    assert_success
    assert_line "repo:env/repo"
    assert_line "branch:env-branch"
}

# ---------------------------------------------------------------------------
# HTTPS URL format tests
# ---------------------------------------------------------------------------

@test "HTTPS URL with .git suffix extracts owner/repo" {
    create_git_stub "https://github.com/owner/repo.git" "main"
    run "$SCRIPT_DIR/task" _get-scope
    assert_success
    assert_line "repo:owner/repo"
}

@test "HTTPS URL without .git suffix extracts owner/repo" {
    create_git_stub "https://github.com/owner/repo" "main"
    run "$SCRIPT_DIR/task" _get-scope
    assert_success
    assert_line "repo:owner/repo"
}

@test "HTTPS URL with different host extracts owner/repo" {
    create_git_stub "https://gitlab.com/myorg/myproject.git" "main"
    run "$SCRIPT_DIR/task" _get-scope
    assert_success
    assert_line "repo:myorg/myproject"
}

# ---------------------------------------------------------------------------
# SSH URL format tests
# ---------------------------------------------------------------------------

@test "SSH SCP-style URL with .git suffix extracts owner/repo" {
    create_git_stub "git@github.com:owner/repo.git" "main"
    run "$SCRIPT_DIR/task" _get-scope
    assert_success
    assert_line "repo:owner/repo"
}

@test "SSH SCP-style URL without .git suffix extracts owner/repo" {
    create_git_stub "git@github.com:owner/repo" "main"
    run "$SCRIPT_DIR/task" _get-scope
    assert_success
    assert_line "repo:owner/repo"
}

@test "SSH scheme URL with .git suffix extracts owner/repo" {
    create_git_stub "ssh://git@github.com/owner/repo.git" "main"
    run "$SCRIPT_DIR/task" _get-scope
    assert_success
    assert_line "repo:owner/repo"
}

@test "SSH scheme URL without .git suffix extracts owner/repo" {
    create_git_stub "ssh://git@github.com/owner/repo" "main"
    run "$SCRIPT_DIR/task" _get-scope
    assert_success
    assert_line "repo:owner/repo"
}

# ---------------------------------------------------------------------------
# Branch derivation
# ---------------------------------------------------------------------------

@test "branch derived from git branch --show-current" {
    create_git_stub "https://github.com/owner/repo.git" "feature/my-branch"
    run "$SCRIPT_DIR/task" _get-scope
    assert_success
    assert_line "branch:feature/my-branch"
}

@test "branch with slashes preserved" {
    create_git_stub "https://github.com/owner/repo.git" "ryan/oto-226-scoped-tasks"
    run "$SCRIPT_DIR/task" _get-scope
    assert_success
    assert_line "branch:ryan/oto-226-scoped-tasks"
}

# ---------------------------------------------------------------------------
# Error cases
# ---------------------------------------------------------------------------

@test "error: not in a git repository" {
    create_git_stub_not_repo
    run "$SCRIPT_DIR/task" _get-scope
    assert_failure
    assert_output --partial 'Error: not inside a git repository. Run: git init'
}

@test "error: no origin remote" {
    create_git_stub_no_origin
    run "$SCRIPT_DIR/task" _get-scope
    assert_failure
    assert_output --partial 'Error: no git remote "origin" found. Run: git remote add origin <url>'
}

@test "error: detached HEAD state" {
    create_git_stub_detached "https://github.com/owner/repo.git"
    run "$SCRIPT_DIR/task" _get-scope
    assert_failure
    assert_output --partial 'Error: detached HEAD state. Run: git checkout <branch>'
}

@test "error: RALPH_SCOPE_REPO set but not in git repo for branch" {
    create_git_stub_not_repo
    export RALPH_SCOPE_REPO="env/repo"
    run "$SCRIPT_DIR/task" _get-scope
    assert_failure
    assert_output --partial 'Error: not inside a git repository. Run: git init'
}
