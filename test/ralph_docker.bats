#!/usr/bin/env bats
# test/ralph_docker.bats — Docker prerequisite checks for ralph.sh

load test_helper

setup() {
    # Create a temp working directory so tests don't touch the real project
    TEST_WORK_DIR="$(mktemp -d)"

    # Minimal specs/ directory with a dummy spec so preflight passes
    mkdir -p "$TEST_WORK_DIR/specs"
    echo "# dummy spec" > "$TEST_WORK_DIR/specs/dummy.md"

    # Create a fake claude stub
    STUB_DIR="$(mktemp -d)"
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo "CLAUDE_STUB_CALLED"
echo "ARGS: $*"
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    # Prepend stub directory so the stub is found instead of real claude
    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"

    # Save dirs for teardown
    export TEST_WORK_DIR
    export STUB_DIR

    # Docker checks ENABLED for these tests (override test_helper default)
    export RALPH_SKIP_DOCKER=0

    # Change to the temp working directory
    cd "$TEST_WORK_DIR"
}

# --- check_docker_installed tests ---

@test "missing docker CLI exits 1 with actionable error" {
    # Remove any docker stub/binary so command -v docker fails
    rm -f "$STUB_DIR/docker"
    # Build PATH without directories containing docker
    local new_path="$STUB_DIR"
    IFS=: read -ra dirs <<< "$PATH"
    for d in "${dirs[@]}"; do
        [ -x "$d/docker" ] && continue
        new_path="$new_path:$d"
    done
    export PATH="$new_path"
    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_failure
    assert_output --partial "docker CLI not found"
    assert_output --partial "https://docs.docker.com/get-docker/"
}

@test "missing docker compose V2 plugin exits 1 with actionable error" {
    # Stub docker that succeeds for basic calls but fails for compose
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "compose" ]; then
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_failure
    assert_output --partial "docker compose V2 plugin not found"
    assert_output --partial "https://docs.docker.com/compose/install/"
}

@test "RALPH_SKIP_DOCKER=1 skips docker checks" {
    # Remove any docker stub/binary so command -v docker would fail
    rm -f "$STUB_DIR/docker"
    local new_path="$STUB_DIR"
    IFS=: read -ra dirs <<< "$PATH"
    for d in "${dirs[@]}"; do
        [ -x "$d/docker" ] && continue
        new_path="$new_path:$d"
    done
    export PATH="$new_path"
    export RALPH_SKIP_DOCKER=1
    run "$SCRIPT_DIR/ralph.sh" -n 1
    # Should NOT fail with docker error — it passes preflight and proceeds
    refute_output --partial "docker CLI not found"
    refute_output --partial "docker compose V2 plugin not found"
}

@test "docker CLI and compose V2 present passes check" {
    # Stub docker that succeeds for compose version
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "compose" ] && [ "$2" = "version" ]; then
    echo "Docker Compose version v2.24.0"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" -n 1
    # Should not contain docker errors
    refute_output --partial "docker CLI not found"
    refute_output --partial "docker compose V2 plugin not found"
}
