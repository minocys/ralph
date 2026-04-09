#!/usr/bin/env bats
# test/docker_sandbox_create.bats — tests for sandbox_create() in lib/docker.sh
#
# Covers: docker sandbox create invocation with template, name, agent type,
# target repo mount (read-write), ralph repo mount (read-only).

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

source_docker_sh() {
    source "$SCRIPT_DIR/lib/docker.sh"
}

# Create a docker mock that logs calls and succeeds
create_docker_stub() {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "$*" >> "$STUB_DIR_PATH/docker.log"
exit 0
STUB
    # Inject the actual STUB_DIR path (can't use single-quoted heredoc for this)
    sed -i.bak "s|\$STUB_DIR_PATH|$STUB_DIR|g" "$STUB_DIR/docker"
    rm -f "$STUB_DIR/docker.bak"
    chmod +x "$STUB_DIR/docker"
    > "$STUB_DIR/docker.log"
}

# Create a docker mock that fails with a specific exit code
create_docker_stub_fail() {
    local exit_code="${1:-1}"
    cat > "$STUB_DIR/docker" <<STUB
#!/bin/bash
echo "\$*" >> "$STUB_DIR/docker.log"
exit $exit_code
STUB
    chmod +x "$STUB_DIR/docker"
    > "$STUB_DIR/docker.log"
}

setup() {
    common_setup
    create_docker_stub
}

# ---------------------------------------------------------------------------
# sandbox_create — basic invocation
# ---------------------------------------------------------------------------
@test "sandbox_create calls docker sandbox create with correct template" {
    source_docker_sh
    sandbox_create "my-sandbox" "/path/to/target" "/path/to/ralph"
    run cat "$STUB_DIR/docker.log"
    assert_output --partial "sandbox create"
    assert_output --partial "docker/sandbox-templates:claude-code"
}

@test "sandbox_create passes --name flag with sandbox name" {
    source_docker_sh
    sandbox_create "ralph-owner-repo-main" "/path/to/target" "/path/to/ralph"
    run cat "$STUB_DIR/docker.log"
    assert_output --partial "--name ralph-owner-repo-main"
}

@test "sandbox_create uses shell agent type" {
    source_docker_sh
    sandbox_create "my-sandbox" "/path/to/target" "/path/to/ralph"
    run cat "$STUB_DIR/docker.log"
    assert_output --partial "shell"
}

# ---------------------------------------------------------------------------
# sandbox_create — mount points
# ---------------------------------------------------------------------------
@test "sandbox_create mounts target repo dir read-write" {
    source_docker_sh
    sandbox_create "my-sandbox" "/home/user/project" "/opt/ralph-docker"
    run cat "$STUB_DIR/docker.log"
    # Target repo dir should appear as a positional arg (read-write, no :ro suffix)
    assert_output --partial "/home/user/project"
    # Must NOT have :ro on the target dir
    refute_output --partial "/home/user/project:ro"
}

@test "sandbox_create mounts ralph repo dir read-only" {
    source_docker_sh
    sandbox_create "my-sandbox" "/home/user/project" "/opt/ralph-docker"
    run cat "$STUB_DIR/docker.log"
    assert_output --partial "/opt/ralph-docker:ro"
}

# ---------------------------------------------------------------------------
# sandbox_create — full command structure
# ---------------------------------------------------------------------------
@test "sandbox_create builds complete command in correct order" {
    source_docker_sh
    sandbox_create "ralph-test-repo-feat" "/Users/dev/myapp" "/Users/dev/ralph"
    run cat "$STUB_DIR/docker.log"
    # Full expected command:
    # sandbox create -t docker/sandbox-templates:claude-code --name ralph-test-repo-feat shell /Users/dev/myapp /Users/dev/ralph:ro
    assert_output --partial "sandbox create -t docker/sandbox-templates:claude-code --name ralph-test-repo-feat shell /Users/dev/myapp /Users/dev/ralph:ro"
}

@test "sandbox_create handles paths with spaces" {
    source_docker_sh
    sandbox_create "my-sandbox" "/Users/dev/my project" "/Users/dev/ralph docker"
    run cat "$STUB_DIR/docker.log"
    # Verify both paths appear in the command
    assert_output --partial "/Users/dev/my project"
    assert_output --partial "/Users/dev/ralph docker:ro"
}

# ---------------------------------------------------------------------------
# sandbox_create — error handling
# ---------------------------------------------------------------------------
@test "sandbox_create returns non-zero when docker fails" {
    create_docker_stub_fail 1
    source_docker_sh
    run sandbox_create "my-sandbox" "/path/to/target" "/path/to/ralph"
    assert_failure
}

@test "sandbox_create returns 0 on success" {
    source_docker_sh
    run sandbox_create "my-sandbox" "/path/to/target" "/path/to/ralph"
    assert_success
}

# ---------------------------------------------------------------------------
# sandbox_create — argument validation
# ---------------------------------------------------------------------------
@test "sandbox_create exits 1 when sandbox name is empty" {
    source_docker_sh
    run sandbox_create "" "/path/to/target" "/path/to/ralph"
    assert_failure
    assert_output --partial "sandbox name is required"
}

@test "sandbox_create exits 1 when target repo dir is empty" {
    source_docker_sh
    run sandbox_create "my-sandbox" "" "/path/to/ralph"
    assert_failure
    assert_output --partial "target repo directory is required"
}

@test "sandbox_create exits 1 when ralph dir is empty" {
    source_docker_sh
    run sandbox_create "my-sandbox" "/path/to/target" ""
    assert_failure
    assert_output --partial "ralph directory is required"
}
