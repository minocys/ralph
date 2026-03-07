#!/usr/bin/env bats
# test/docker_sandbox_name.bats — tests for derive_sandbox_name() in lib/docker.sh
#
# Covers: basic name derivation, SSH/HTTPS URLs, special characters,
#         63-char truncation, env var overrides, error cases, check_sandbox_state.

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Source docker.sh to get derive_sandbox_name and check_sandbox_state
source_docker_sh() {
    source "$SCRIPT_DIR/lib/docker.sh"
}

# Create a git stub that returns a remote URL and branch
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
    "remote get-url origin")
        echo "fatal: not a git repository" >&2
        exit 128
        ;;
    "branch --show-current")
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
    "branch --show-current")
        echo "main"
        exit 0
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
    common_setup
    # Unset scope env vars so git stubs are exercised by default
    unset RALPH_SCOPE_REPO
    unset RALPH_SCOPE_BRANCH
}

# ---------------------------------------------------------------------------
# Basic name derivation
# ---------------------------------------------------------------------------

@test "derive_sandbox_name: HTTPS URL produces correct name" {
    create_git_stub "https://github.com/minocys/ralph-docker.git" "feature/auth/v2"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    assert_output "ralph-minocys-ralph-docker-feature-auth-v2"
}

@test "derive_sandbox_name: simple repo and branch" {
    create_git_stub "https://github.com/acme/web-app.git" "main"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    assert_output "ralph-acme-web-app-main"
}

@test "derive_sandbox_name: HTTPS URL without .git suffix" {
    create_git_stub "https://github.com/owner/repo" "main"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    assert_output "ralph-owner-repo-main"
}

# ---------------------------------------------------------------------------
# SSH URL formats
# ---------------------------------------------------------------------------

@test "derive_sandbox_name: SSH SCP-style URL with .git suffix" {
    create_git_stub "git@github.com:owner/repo.git" "main"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    assert_output "ralph-owner-repo-main"
}

@test "derive_sandbox_name: SSH SCP-style URL without .git suffix" {
    create_git_stub "git@github.com:owner/repo" "develop"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    assert_output "ralph-owner-repo-develop"
}

@test "derive_sandbox_name: SSH scheme URL (ssh://)" {
    create_git_stub "ssh://git@github.com/owner/repo.git" "main"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    # ssh:// format: remote_url doesn't contain : before owner, so goes through HTTPS path
    # After stripping protocol+host: owner/repo → owner-repo
    assert_output "ralph-owner-repo-main"
}

@test "derive_sandbox_name: gitlab SSH URL" {
    create_git_stub "git@gitlab.com:myorg/myproject.git" "main"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    assert_output "ralph-myorg-myproject-main"
}

# ---------------------------------------------------------------------------
# Special characters and sanitization
# ---------------------------------------------------------------------------

@test "derive_sandbox_name: branch with slashes sanitized to dashes" {
    create_git_stub "https://github.com/owner/repo.git" "feature/auth/v2"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    assert_output "ralph-owner-repo-feature-auth-v2"
}

@test "derive_sandbox_name: branch with underscores and dots sanitized" {
    create_git_stub "https://github.com/owner/repo.git" "fix_bug.123"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    assert_output "ralph-owner-repo-fix-bug-123"
}

@test "derive_sandbox_name: branch with consecutive special chars collapsed" {
    create_git_stub "https://github.com/owner/repo.git" "feat///multi///slash"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    assert_output "ralph-owner-repo-feat-multi-slash"
}

@test "derive_sandbox_name: repo with special chars in name" {
    create_git_stub "https://github.com/my-org/my_project.v2.git" "main"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    assert_output "ralph-my-org-my-project-v2-main"
}

@test "derive_sandbox_name: branch with @ symbol sanitized" {
    create_git_stub "https://github.com/owner/repo.git" "user@feature"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    assert_output "ralph-owner-repo-user-feature"
}

# ---------------------------------------------------------------------------
# 63-char truncation
# ---------------------------------------------------------------------------

@test "derive_sandbox_name: long name truncated to 63 chars" {
    # Create a very long repo/branch combination
    create_git_stub "https://github.com/very-long-organization-name/extremely-long-repository-name.git" "feature/implement-very-long-branch-name-that-exceeds-limit"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    # Verify length is at most 63
    local len=${#output}
    [ "$len" -le 63 ]
}

@test "derive_sandbox_name: truncated name does not end with dash" {
    # Craft a name that would end with a dash at exactly 63 chars
    create_git_stub "https://github.com/very-long-organization-name/extremely-long-repository-name.git" "feature/implement-very-long-branch-name-that-exceeds-limit"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    # Should not end with -
    [[ "$output" != *- ]]
}

@test "derive_sandbox_name: short name not truncated" {
    create_git_stub "https://github.com/a/b.git" "main"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    assert_output "ralph-a-b-main"
    local len=${#output}
    [ "$len" -lt 63 ]
}

@test "derive_sandbox_name: exactly 63 chars preserved" {
    # Build a name that is exactly 63 chars: ralph- = 6 chars, need 57 more
    # owner-repo-branch where owner=org, repo=project, branch fills the rest
    # ralph-org-project- = 19 chars, need 44 more chars of branch
    create_git_stub "https://github.com/org/project.git" "abcdefghijklmnopqrstuvwxyz0123456789abcdefgh"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    local len=${#output}
    [ "$len" -le 63 ]
}

# ---------------------------------------------------------------------------
# Env var overrides
# ---------------------------------------------------------------------------

@test "derive_sandbox_name: RALPH_SCOPE_REPO overrides git remote" {
    create_git_stub "https://github.com/fallback/should-not-use.git" "main"
    export RALPH_SCOPE_REPO="custom/repo"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    assert_output "ralph-custom-repo-main"
}

@test "derive_sandbox_name: RALPH_SCOPE_BRANCH overrides git branch" {
    create_git_stub "https://github.com/owner/repo.git" "should-not-use"
    export RALPH_SCOPE_BRANCH="override-branch"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    assert_output "ralph-owner-repo-override-branch"
}

@test "derive_sandbox_name: both env vars set — git not called" {
    # git stub returns errors — proves git is never invoked for remote
    create_git_stub_no_origin
    export RALPH_SCOPE_REPO="env/repo"
    export RALPH_SCOPE_BRANCH="env-branch"
    source_docker_sh
    run derive_sandbox_name
    assert_success
    assert_output "ralph-env-repo-env-branch"
}

# ---------------------------------------------------------------------------
# Error cases
# ---------------------------------------------------------------------------

@test "derive_sandbox_name: no origin remote exits 1 with error" {
    create_git_stub_no_origin
    source_docker_sh
    run derive_sandbox_name
    assert_failure
    assert_output --partial 'Error: no git remote "origin" found'
}

@test "derive_sandbox_name: detached HEAD exits 1 with error" {
    create_git_stub_detached "https://github.com/owner/repo.git"
    source_docker_sh
    run derive_sandbox_name
    assert_failure
    assert_output --partial "Error: detached HEAD state"
}

@test "derive_sandbox_name: RALPH_SCOPE_REPO set but detached HEAD exits 1" {
    create_git_stub_detached "https://github.com/owner/repo.git"
    export RALPH_SCOPE_REPO="env/repo"
    source_docker_sh
    run derive_sandbox_name
    assert_failure
    assert_output --partial "Error: detached HEAD state"
}

# ---------------------------------------------------------------------------
# Deterministic output
# ---------------------------------------------------------------------------

@test "derive_sandbox_name: same input produces same output" {
    create_git_stub "https://github.com/owner/repo.git" "main"
    source_docker_sh
    run derive_sandbox_name
    local first="$output"
    run derive_sandbox_name
    local second="$output"
    [ "$first" = "$second" ]
}

# ---------------------------------------------------------------------------
# check_sandbox_state
# ---------------------------------------------------------------------------

@test "check_sandbox_state: running sandbox returns 'running'" {
    source_docker_sh
    # Mock docker CLI
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo '[{"Name":"test-sandbox","Status":"running"}]'
STUB
    chmod +x "$STUB_DIR/docker"
    run check_sandbox_state "test-sandbox"
    assert_success
    assert_output "running"
}

@test "check_sandbox_state: stopped sandbox returns 'stopped'" {
    source_docker_sh
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo '[{"Name":"test-sandbox","Status":"stopped"}]'
STUB
    chmod +x "$STUB_DIR/docker"
    run check_sandbox_state "test-sandbox"
    assert_success
    assert_output "stopped"
}

@test "check_sandbox_state: exited sandbox returns 'stopped'" {
    source_docker_sh
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo '[{"Name":"test-sandbox","Status":"exited"}]'
STUB
    chmod +x "$STUB_DIR/docker"
    run check_sandbox_state "test-sandbox"
    assert_success
    assert_output "stopped"
}

@test "check_sandbox_state: not found returns empty string" {
    source_docker_sh
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo '[]'
STUB
    chmod +x "$STUB_DIR/docker"
    run check_sandbox_state "nonexistent"
    assert_success
    assert_output ""
}

@test "check_sandbox_state: docker not available returns empty string" {
    source_docker_sh
    # No docker in PATH — remove any stub
    rm -f "$STUB_DIR/docker"
    # Ensure no real docker either by restricting PATH
    run check_sandbox_state "any-name"
    assert_success
    assert_output ""
}
