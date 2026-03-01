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
    git config user.email "test@test.com"
    git config user.name "Test"
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
    git config user.email "test@test.com"
    git config user.name "Test"
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

# =============================================================================
# Edge-case tests (sandbox-identity/03)
# =============================================================================

# --- git detection edge cases: verify exit code is exactly 1 ---

@test "derive_sandbox_name: not in git repo exits with code 1" {
    _load_docker_functions
    unset RALPH_SCOPE_REPO
    unset RALPH_SCOPE_BRANCH
    cd "$TEST_WORK_DIR"
    run derive_sandbox_name
    [ "$status" -eq 1 ]
    assert_output --partial "not inside a git repository"
}

@test "derive_sandbox_name: no origin remote exits with code 1" {
    _load_docker_functions
    unset RALPH_SCOPE_REPO
    export RALPH_SCOPE_BRANCH="main"
    cd "$TEST_WORK_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    git commit --allow-empty -m "init" -q
    run derive_sandbox_name
    [ "$status" -eq 1 ]
    assert_output --partial 'no git remote "origin" found'
}

@test "derive_sandbox_name: detached HEAD exits with code 1 and suggests checkout" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="owner/repo"
    unset RALPH_SCOPE_BRANCH
    cd "$TEST_WORK_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    git commit --allow-empty -m "init" -q
    git checkout --detach -q
    run derive_sandbox_name
    [ "$status" -eq 1 ]
    assert_output --partial "detached HEAD state"
    assert_output --partial "Checkout a branch first"
}

@test "derive_sandbox_name: error messages are written to stderr" {
    _load_docker_functions
    unset RALPH_SCOPE_REPO
    unset RALPH_SCOPE_BRANCH
    cd "$TEST_WORK_DIR"
    # Capture only stderr
    run bash -c '. "$SCRIPT_DIR/lib/docker.sh"; derive_sandbox_name 2>/dev/null'
    assert_failure
    # stdout should be empty since errors go to stderr
    assert_output ""
}

# --- branch with deep nested slashes ---

@test "derive_sandbox_name: branch feature/auth/v2 produces correct name" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="minocys/ralph-docker"
    export RALPH_SCOPE_BRANCH="feature/auth/v2"
    derive_sandbox_name
    [ "$SANDBOX_NAME" = "ralph-minocys-ralph-docker-feature-auth-v2" ]
}

@test "derive_sandbox_name: branch with many nested slashes" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="acme/web"
    export RALPH_SCOPE_BRANCH="feat/scope/auth/oauth2/v3"
    derive_sandbox_name
    [ "$SANDBOX_NAME" = "ralph-acme-web-feat-scope-auth-oauth2-v3" ]
}

@test "derive_sandbox_name: branch with trailing slash is sanitized" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="owner/repo"
    export RALPH_SCOPE_BRANCH="feature/"
    derive_sandbox_name
    [ "$SANDBOX_NAME" = "ralph-owner-repo-feature" ]
}

@test "derive_sandbox_name: branch with leading slash is sanitized" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="owner/repo"
    export RALPH_SCOPE_BRANCH="/feature"
    derive_sandbox_name
    [ "$SANDBOX_NAME" = "ralph-owner-repo-feature" ]
}

# --- truncation edge cases ---

@test "derive_sandbox_name: name at exactly 63 chars is not truncated" {
    _load_docker_functions
    # "ralph-" = 6 chars, need repo + branch components to total 57 chars
    # repo: "aaa/bbbbbbbbbbbbbbbbbbbbb" sanitized = "aaa-bbbbbbbbbbbbbbbbbbbbb" (25 chars)
    # branch: "ccccccccccccccccccccccccccccccc" (31 chars)
    # total: 6 + 25 + 1 (dash) + 31 = 63
    export RALPH_SCOPE_REPO="aaa/bbbbbbbbbbbbbbbbbbbbb"
    export RALPH_SCOPE_BRANCH="ccccccccccccccccccccccccccccccc"
    derive_sandbox_name
    [ "${#SANDBOX_NAME}" -eq 63 ]
    [ "$SANDBOX_NAME" = "ralph-aaa-bbbbbbbbbbbbbbbbbbbbb-ccccccccccccccccccccccccccccccc" ]
}

@test "derive_sandbox_name: name at 64 chars is truncated to 63" {
    _load_docker_functions
    # Same as above but one char longer in branch
    export RALPH_SCOPE_REPO="aaa/bbbbbbbbbbbbbbbbbbbbb"
    export RALPH_SCOPE_BRANCH="cccccccccccccccccccccccccccccccc"
    derive_sandbox_name
    [ "${#SANDBOX_NAME}" -le 63 ]
}

@test "derive_sandbox_name: truncation strips trailing dashes recursively" {
    _load_docker_functions
    # Craft a name where char 63 falls on a dash boundary after sanitization
    # "ralph-" (6) + repo part + "-" + branch part
    # Make it so truncation at 63 hits a dash that was produced by sanitization
    export RALPH_SCOPE_REPO="aaaaaaaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    export RALPH_SCOPE_BRANCH="x/cccccccccc"
    derive_sandbox_name
    # Verify no trailing dash
    [[ "$SANDBOX_NAME" != *- ]]
    [ "${#SANDBOX_NAME}" -le 63 ]
}

@test "derive_sandbox_name: very long repo+branch well over 63 chars" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="very-long-organization-name/this-is-an-extremely-long-repository-name-that-goes-on"
    export RALPH_SCOPE_BRANCH="feature/very-long-branch-name-that-also-goes-on-and-on-forever"
    derive_sandbox_name
    [ "${#SANDBOX_NAME}" -le 63 ]
    [[ "$SANDBOX_NAME" != *- ]]
    # Verify prefix is correct
    [[ "$SANDBOX_NAME" == ralph-* ]]
}

# --- determinism edge cases ---

@test "derive_sandbox_name: deterministic across separate function loads" {
    export RALPH_SCOPE_REPO="minocys/ralph-docker"
    export RALPH_SCOPE_BRANCH="feature/auth/v2"

    # First invocation
    . "$SCRIPT_DIR/lib/docker.sh"
    derive_sandbox_name
    local first="$SANDBOX_NAME"

    # Second invocation after re-sourcing
    unset SANDBOX_NAME
    . "$SCRIPT_DIR/lib/docker.sh"
    derive_sandbox_name
    [ "$first" = "$SANDBOX_NAME" ]
}

@test "derive_sandbox_name: deterministic with truncation" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="very-long-organization-name/extremely-long-repository-name-here"
    export RALPH_SCOPE_BRANCH="feature/very-long-branch-name-that-goes-on-forever"
    derive_sandbox_name
    local first="$SANDBOX_NAME"
    derive_sandbox_name
    [ "$first" = "$SANDBOX_NAME" ]
}

@test "derive_sandbox_name: different inputs produce different names" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="acme/web-app"
    export RALPH_SCOPE_BRANCH="main"
    derive_sandbox_name
    local first="$SANDBOX_NAME"

    export RALPH_SCOPE_REPO="acme/web-app"
    export RALPH_SCOPE_BRANCH="develop"
    derive_sandbox_name
    [ "$first" != "$SANDBOX_NAME" ]
}

# --- git fallback when env vars are partially set ---

@test "derive_sandbox_name: RALPH_SCOPE_REPO set but RALPH_SCOPE_BRANCH unset falls back to git branch" {
    _load_docker_functions
    export RALPH_SCOPE_REPO="override/repo"
    unset RALPH_SCOPE_BRANCH
    cd "$TEST_WORK_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    git commit --allow-empty -m "init" -q
    # git branch --show-current returns "main" or "master" on init
    local branch
    branch=$(git branch --show-current)
    derive_sandbox_name
    [ "$SANDBOX_NAME" = "ralph-override-repo-${branch}" ]
}

@test "derive_sandbox_name: RALPH_SCOPE_BRANCH set but RALPH_SCOPE_REPO unset falls back to git remote" {
    _load_docker_functions
    unset RALPH_SCOPE_REPO
    export RALPH_SCOPE_BRANCH="my-branch"
    cd "$TEST_WORK_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    git commit --allow-empty -m "init" -q
    git remote add origin https://github.com/testowner/testrepo.git
    derive_sandbox_name
    [ "$SANDBOX_NAME" = "ralph-testowner-testrepo-my-branch" ]
}

# --- git URL format handling ---

@test "derive_sandbox_name: HTTPS URL with .git suffix" {
    _load_docker_functions
    unset RALPH_SCOPE_REPO
    export RALPH_SCOPE_BRANCH="main"
    cd "$TEST_WORK_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    git commit --allow-empty -m "init" -q
    git remote add origin https://github.com/myorg/myrepo.git
    derive_sandbox_name
    [ "$SANDBOX_NAME" = "ralph-myorg-myrepo-main" ]
}

@test "derive_sandbox_name: HTTPS URL without .git suffix" {
    _load_docker_functions
    unset RALPH_SCOPE_REPO
    export RALPH_SCOPE_BRANCH="main"
    cd "$TEST_WORK_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    git commit --allow-empty -m "init" -q
    git remote add origin https://github.com/myorg/myrepo
    derive_sandbox_name
    [ "$SANDBOX_NAME" = "ralph-myorg-myrepo-main" ]
}

@test "derive_sandbox_name: SSH URL with .git suffix" {
    _load_docker_functions
    unset RALPH_SCOPE_REPO
    export RALPH_SCOPE_BRANCH="main"
    cd "$TEST_WORK_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    git commit --allow-empty -m "init" -q
    git remote add origin git@github.com:myorg/myrepo.git
    derive_sandbox_name
    [ "$SANDBOX_NAME" = "ralph-myorg-myrepo-main" ]
}

@test "derive_sandbox_name: SSH URL without .git suffix" {
    _load_docker_functions
    unset RALPH_SCOPE_REPO
    export RALPH_SCOPE_BRANCH="main"
    cd "$TEST_WORK_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    git commit --allow-empty -m "init" -q
    git remote add origin git@github.com:myorg/myrepo
    derive_sandbox_name
    [ "$SANDBOX_NAME" = "ralph-myorg-myrepo-main" ]
}

# --- lookup_sandbox edge cases ---

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
