#!/usr/bin/env bats
# test/ralph_sandbox_identity.bats — Tests for derive_sandbox_name() and lookup_sandbox()

load test_helper

# Helper: source lib/docker.sh to get all functions
_load_docker_functions() {
    . "$SCRIPT_DIR/lib/docker.sh"
}

# --- _sanitize_name_component tests ---

@test "sanitize replaces slashes with dashes" {
    _load_docker_functions
    run _sanitize_name_component "owner/repo"
    assert_success
    assert_output "owner-repo"
}

@test "sanitize replaces special characters with dashes" {
    _load_docker_functions
    run _sanitize_name_component "feature/auth@v2!beta"
    assert_success
    assert_output "feature-auth-v2-beta"
}

@test "sanitize collapses consecutive dashes" {
    _load_docker_functions
    run _sanitize_name_component "a---b"
    assert_success
    assert_output "a-b"
}

@test "sanitize strips leading dashes" {
    _load_docker_functions
    run _sanitize_name_component "-leading"
    assert_success
    assert_output "leading"
}

@test "sanitize strips trailing dashes" {
    _load_docker_functions
    run _sanitize_name_component "trailing-"
    assert_success
    assert_output "trailing"
}

@test "sanitize handles multiple special chars producing consecutive dashes" {
    _load_docker_functions
    run _sanitize_name_component "a//b..c"
    assert_success
    assert_output "a-b-c"
}

@test "sanitize preserves alphanumeric characters" {
    _load_docker_functions
    run _sanitize_name_component "abcXYZ123"
    assert_success
    assert_output "abcXYZ123"
}

@test "sanitize handles string of only special characters" {
    _load_docker_functions
    run _sanitize_name_component "///---"
    assert_success
    assert_output ""
}

# --- derive_sandbox_name tests with env var overrides ---

@test "derive_sandbox_name: basic repo and branch via env vars" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="minocys/ralph-docker"
    export RALPH_SCOPE_BRANCH="feature/auth/v2"
    derive_sandbox_name
    [ "$SANDBOX_NAME" = "ralph-minocys-ralph-docker-feature-auth-v2" ]
}

@test "derive_sandbox_name: simple repo and main branch" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="acme/web-app"
    export RALPH_SCOPE_BRANCH="main"
    derive_sandbox_name
    [ "$SANDBOX_NAME" = "ralph-acme-web-app-main" ]
}

@test "derive_sandbox_name: repo with SSH-style path" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="org/my.project"
    export RALPH_SCOPE_BRANCH="develop"
    derive_sandbox_name
    [ "$SANDBOX_NAME" = "ralph-org-my-project-develop" ]
}

@test "derive_sandbox_name: branch with dots and underscores" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="owner/repo"
    export RALPH_SCOPE_BRANCH="release/v1.2.3_rc1"
    derive_sandbox_name
    [ "$SANDBOX_NAME" = "ralph-owner-repo-release-v1-2-3-rc1" ]
}

@test "derive_sandbox_name: deterministic — same inputs produce same name" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="minocys/ralph-docker"
    export RALPH_SCOPE_BRANCH="feature/auth/v2"
    derive_sandbox_name
    local first="$SANDBOX_NAME"
    derive_sandbox_name
    [ "$first" = "$SANDBOX_NAME" ]
}

# --- truncation tests ---

@test "derive_sandbox_name: truncates to 63 characters" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="very-long-organization-name/extremely-long-repository-name-here"
    export RALPH_SCOPE_BRANCH="feature/very-long-branch-name-that-goes-on-forever"
    derive_sandbox_name
    [ "${#SANDBOX_NAME}" -le 63 ]
}

@test "derive_sandbox_name: truncation does not leave trailing dash" {
    _load_docker_functions
    # Craft input so 63rd char would be a dash
    export RALPH_SCOPE_REPO="aaaaaaaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbbbbbbb"
    export RALPH_SCOPE_BRANCH="ccccccccccccccccccccc"
    derive_sandbox_name
    # Verify no trailing dash
    [[ "$SANDBOX_NAME" != *- ]]
    [ "${#SANDBOX_NAME}" -le 63 ]
}

@test "derive_sandbox_name: short names are not truncated" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="me/app"
    export RALPH_SCOPE_BRANCH="main"
    derive_sandbox_name
    [ "$SANDBOX_NAME" = "ralph-me-app-main" ]
    [ "${#SANDBOX_NAME}" -lt 63 ]
}

# --- git detection error tests ---

@test "derive_sandbox_name: exits 1 when not in git repo and no env vars" {
    _load_docker_functions
    unset RALPH_SCOPE_REPO
    unset RALPH_SCOPE_BRANCH
    # cd to a temp dir that is not a git repo
    cd "$TEST_WORK_DIR"
    run derive_sandbox_name
    assert_failure
    assert_output --partial "not inside a git repository"
}

@test "derive_sandbox_name: exits 1 with 'no git remote' when origin missing" {
    _load_docker_functions
    unset RALPH_SCOPE_REPO
    export RALPH_SCOPE_BRANCH="main"
    # Create a git repo with no remote
    cd "$TEST_WORK_DIR"
    git init -q
    git commit --allow-empty -m "init" -q
    run derive_sandbox_name
    assert_failure
    assert_output --partial 'no git remote "origin" found'
}

@test "derive_sandbox_name: exits 1 with 'detached HEAD' in detached state" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="owner/repo"
    unset RALPH_SCOPE_BRANCH
    # Create a git repo and detach HEAD
    cd "$TEST_WORK_DIR"
    git init -q
    git commit --allow-empty -m "init" -q
    git checkout --detach -q
    run derive_sandbox_name
    assert_failure
    assert_output --partial "detached HEAD state"
}

# --- env var override tests ---

@test "derive_sandbox_name: RALPH_SCOPE_REPO overrides git" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="override/repo"
    export RALPH_SCOPE_BRANCH="main"
    # Even in a non-git dir, env var should work
    cd "$TEST_WORK_DIR"
    derive_sandbox_name
    [ "$SANDBOX_NAME" = "ralph-override-repo-main" ]
}

@test "derive_sandbox_name: RALPH_SCOPE_BRANCH overrides git" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="owner/repo"
    export RALPH_SCOPE_BRANCH="custom-branch"
    cd "$TEST_WORK_DIR"
    derive_sandbox_name
    [ "$SANDBOX_NAME" = "ralph-owner-repo-custom-branch" ]
}

# --- lookup_sandbox tests ---

@test "lookup_sandbox returns 'running' for a running sandbox" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-main","status":"running"}]'
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    _load_docker_functions
    run lookup_sandbox "ralph-test-main"
    assert_success
    assert_output "running"
}

@test "lookup_sandbox returns 'stopped' for a stopped sandbox" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-main","status":"stopped"}]'
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    _load_docker_functions
    run lookup_sandbox "ralph-test-main"
    assert_success
    assert_output "stopped"
}

@test "lookup_sandbox returns 'stopped' for exited sandbox" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-main","status":"exited"}]'
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    _load_docker_functions
    run lookup_sandbox "ralph-test-main"
    assert_success
    assert_output "stopped"
}

@test "lookup_sandbox returns empty for non-existent sandbox" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-other-sandbox","status":"running"}]'
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    _load_docker_functions
    run lookup_sandbox "ralph-test-main"
    assert_success
    assert_output ""
}

@test "lookup_sandbox returns empty when docker sandbox ls fails" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    _load_docker_functions
    run lookup_sandbox "ralph-test-main"
    assert_success
    assert_output ""
}

@test "lookup_sandbox returns empty when no sandboxes exist" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[]'
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    _load_docker_functions
    run lookup_sandbox "ralph-test-main"
    assert_success
    assert_output ""
}
