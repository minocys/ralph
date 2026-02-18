#!/usr/bin/env bats
# test/install.bats — tests for install.sh

load test_helper

# Override setup/teardown to avoid the test_helper defaults that change
# directory and create stubs we don't need for install tests.

setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    export TEST_WORK_DIR

    # Create fake HOME so install.sh writes into our temp dir
    export REAL_HOME="$HOME"
    export HOME="$TEST_WORK_DIR/home"
    mkdir -p "$HOME"
}

teardown() {
    export HOME="$REAL_HOME"
    if [[ -d "$TEST_WORK_DIR" ]]; then
        rm -rf "$TEST_WORK_DIR"
    fi
}

# ---------------------------------------------------------------------------
# ralph symlink
# ---------------------------------------------------------------------------
@test "install.sh creates ralph symlink in ~/.local/bin" {
    run "$SCRIPT_DIR/install.sh"
    assert_success
    assert [ -L "$HOME/.local/bin/ralph" ]
    # Symlink points to ralph.sh
    local target
    target=$(readlink "$HOME/.local/bin/ralph")
    assert_equal "$target" "$SCRIPT_DIR/ralph.sh"
}

# ---------------------------------------------------------------------------
# task symlink
# ---------------------------------------------------------------------------
@test "install.sh creates task symlink in ~/.local/bin" {
    run "$SCRIPT_DIR/install.sh"
    assert_success
    assert [ -L "$HOME/.local/bin/task" ]
    # Symlink points to task
    local target
    target=$(readlink "$HOME/.local/bin/task")
    assert_equal "$target" "$SCRIPT_DIR/task"
}

@test "install.sh task symlink is executable via the link" {
    run "$SCRIPT_DIR/install.sh"
    assert_success
    # The task script itself must be executable
    assert [ -x "$SCRIPT_DIR/task" ]
    # The symlink should resolve to an executable
    assert [ -x "$HOME/.local/bin/task" ]
}

@test "install.sh updates existing task symlink" {
    # First install
    run "$SCRIPT_DIR/install.sh"
    assert_success

    # Second install should succeed (update the symlink)
    run "$SCRIPT_DIR/install.sh"
    assert_success
    assert [ -L "$HOME/.local/bin/task" ]
    assert_output --partial "Updating symlink"
}

@test "install.sh skips task if non-symlink file exists" {
    mkdir -p "$HOME/.local/bin"
    echo "existing file" > "$HOME/.local/bin/task"

    run "$SCRIPT_DIR/install.sh"
    assert_success
    assert_output --partial "Warning"
    assert_output --partial "not a symlink"
    # File should still be the original, not a symlink
    assert [ ! -L "$HOME/.local/bin/task" ]
}

@test "install.sh prints task link message" {
    run "$SCRIPT_DIR/install.sh"
    assert_success
    assert_output --partial "Linked script: task"
}
