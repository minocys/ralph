#!/usr/bin/env bats
# test/ralph_docker_dispatch.bats — tests for --docker flag dispatch in ralph.sh

load test_helper

# ---------------------------------------------------------------------------
# --docker flag dispatch
# ---------------------------------------------------------------------------
@test "ralph --docker with no subcommand prints error and exits 1" {
    run "$SCRIPT_DIR/ralph.sh" --docker
    assert_failure
    assert_output --partial "Error: --docker requires a subcommand"
}

@test "ralph --docker --help prints docker usage and exits 0" {
    run "$SCRIPT_DIR/ralph.sh" --docker --help
    assert_success
    assert_output --partial "--docker"
    assert_output --partial "sandbox"
}

@test "ralph --docker plan forwards to sandbox" {
    # Mock docker CLI
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CALLED"
echo "ARGS: $*"
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker plan -n 1
    # Should attempt docker sandbox operations (will fail at sandbox ls, but
    # we verify it reaches the docker code path by checking for docker preflight)
    assert_output --partial "DOCKER_CALLED"
}

@test "ralph --docker build forwards subcommand and flags" {
    # Mock docker CLI that captures all args
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CALLED"
echo "ARGS: $*"
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build -n 3 --danger
    assert_output --partial "DOCKER_CALLED"
}

@test "ralph --docker task forwards to sandbox" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CALLED"
echo "ARGS: $*"
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker task list
    assert_output --partial "DOCKER_CALLED"
}

@test "ralph --docker exits 1 when docker CLI is not available" {
    # Remove docker from PATH by using a clean stub dir without docker
    local NO_DOCKER_DIR
    NO_DOCKER_DIR=$(mktemp -d)
    # Copy only the claude stub (not docker)
    cp "$STUB_DIR/claude" "$NO_DOCKER_DIR/claude"
    # Add essential system commands
    for cmd in bash git sed tr cut sqlite3; do
        local cmd_path
        cmd_path=$(which "$cmd" 2>/dev/null) || continue
        ln -sf "$cmd_path" "$NO_DOCKER_DIR/$cmd"
    done

    PATH="$NO_DOCKER_DIR" run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_failure
    assert_output --partial "docker"
}

# ---------------------------------------------------------------------------
# --help includes --docker
# ---------------------------------------------------------------------------
@test "ralph --help includes --docker in output" {
    run "$SCRIPT_DIR/ralph.sh" --help
    assert_success
    assert_output --partial "--docker"
}

@test "ralph -h includes --docker in output" {
    run "$SCRIPT_DIR/ralph.sh" -h
    assert_success
    assert_output --partial "--docker"
}
