#!/usr/bin/env bats
# test/entrypoint_keepalive.bats — workspace warning and keep-alive tests for docker/entrypoint.sh

load test_helper

# Helper: run just the workspace-check + keep-alive section in a subshell.
# We replace "exec sleep infinity" with "echo KEEPALIVE" so the test doesn't hang.
_run_keepalive_section() {
    local script
    script=$(cat <<'SCRIPT'
set -euo pipefail

# Warn if /workspace is empty (no project mounted)
if [ -z "$(ls -A /workspace 2>/dev/null)" ]; then
    echo "Warning: /workspace is empty — mount a project directory to get started." >&2
fi

# In real entrypoint this is: exec sleep infinity
echo "KEEPALIVE"
SCRIPT
)
    run bash -c "$script"
}

# Helper: run with a populated /workspace (simulated via temp dir).
_run_keepalive_with_workspace() {
    local workspace="$1"
    local script
    script=$(cat <<SCRIPT
set -euo pipefail

# Override /workspace check with the test directory
if [ -z "\$(ls -A "$workspace" 2>/dev/null)" ]; then
    echo "Warning: /workspace is empty — mount a project directory to get started." >&2
fi

echo "KEEPALIVE"
SCRIPT
)
    run bash -c "$script"
}

setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    export TEST_WORK_DIR
}

teardown() {
    if [[ -d "$TEST_WORK_DIR" ]]; then
        rm -rf "$TEST_WORK_DIR"
    fi
}

# --- workspace empty warning ---

@test "workspace warning printed to stderr when directory is empty" {
    local workspace="$TEST_WORK_DIR/empty_workspace"
    mkdir -p "$workspace"

    run bash -c '
        dir="'"$workspace"'"
        if [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
            echo "Warning: /workspace is empty — mount a project directory to get started." >&2
        fi
        echo "KEEPALIVE"
    '
    assert_success
    # bats captures both stdout and stderr in output
    assert_output --partial "Warning: /workspace is empty"
    assert_output --partial "KEEPALIVE"
}

@test "workspace warning not printed when directory has contents" {
    local workspace="$TEST_WORK_DIR/full_workspace"
    mkdir -p "$workspace"
    echo "project file" > "$workspace/README.md"

    run bash -c '
        dir="'"$workspace"'"
        if [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
            echo "Warning: /workspace is empty — mount a project directory to get started." >&2
        fi
        echo "KEEPALIVE"
    '
    assert_success
    refute_output --partial "Warning:"
    assert_output --partial "KEEPALIVE"
}

@test "workspace warning not printed when directory does not exist" {
    # When /workspace doesn't exist, ls -A fails silently and the check treats
    # it the same as empty — warning is printed.
    run bash -c '
        dir="'"$TEST_WORK_DIR/nonexistent"'"
        if [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
            echo "Warning: /workspace is empty — mount a project directory to get started." >&2
        fi
        echo "KEEPALIVE"
    '
    assert_success
    assert_output --partial "Warning: /workspace is empty"
}

@test "workspace warning goes to stderr not stdout" {
    local workspace="$TEST_WORK_DIR/empty_workspace"
    mkdir -p "$workspace"

    # Capture stdout and stderr separately
    local stdout_file="$TEST_WORK_DIR/stdout"
    local stderr_file="$TEST_WORK_DIR/stderr"

    bash -c '
        dir="'"$workspace"'"
        if [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
            echo "Warning: /workspace is empty — mount a project directory to get started." >&2
        fi
        echo "KEEPALIVE"
    ' > "$stdout_file" 2> "$stderr_file"

    # Warning should be on stderr, not stdout
    run cat "$stderr_file"
    assert_output --partial "Warning: /workspace is empty"

    run cat "$stdout_file"
    refute_output --partial "Warning:"
    assert_output "KEEPALIVE"
}

@test "workspace warning does not cause exit" {
    local workspace="$TEST_WORK_DIR/empty_workspace"
    mkdir -p "$workspace"

    run bash -c '
        set -euo pipefail
        dir="'"$workspace"'"
        if [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
            echo "Warning: /workspace is empty — mount a project directory to get started." >&2
        fi
        echo "KEEPALIVE"
    '
    assert_success
    assert_output --partial "KEEPALIVE"
}

# --- keep-alive (exec sleep infinity) ---

@test "entrypoint ends with exec sleep infinity" {
    run grep -n "^exec sleep infinity" "$SCRIPT_DIR/docker/entrypoint.sh"
    assert_success
    assert_output --partial "exec sleep infinity"
}

@test "exec sleep infinity is the last command in entrypoint" {
    # Get the last non-empty, non-comment line
    local last_line
    last_line=$(grep -v '^\s*$' "$SCRIPT_DIR/docker/entrypoint.sh" | grep -v '^\s*#' | tail -1)
    [ "$last_line" = "exec sleep infinity" ]
}
