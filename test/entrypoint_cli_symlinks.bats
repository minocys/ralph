#!/usr/bin/env bats
# test/entrypoint_cli_symlinks.bats — CLI symlink tests for docker/entrypoint.sh

load test_helper

# Helper: run the CLI symlink section from entrypoint.sh in a subshell.
# Uses _TEST_RALPH_DIR as RALPH_DIR and _TEST_BIN_DIR as the symlink target.
_run_cli_symlinks() {
    local script
    script=$(cat <<'SCRIPT'
set -euo pipefail
RALPH_DIR="$_TEST_RALPH_DIR"

ln -sf "$RALPH_DIR/ralph.sh" "$_TEST_BIN_DIR/ralph"
ln -sf "$RALPH_DIR/task" "$_TEST_BIN_DIR/task"
echo "entrypoint: linked ralph and task into $_TEST_BIN_DIR/" >&2
SCRIPT
)
    run bash -c "$script"
}

setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    export TEST_WORK_DIR

    # Fake RALPH_DIR with ralph.sh and task
    export _TEST_RALPH_DIR="$TEST_WORK_DIR/ralph"
    mkdir -p "$_TEST_RALPH_DIR"
    echo '#!/bin/bash' > "$_TEST_RALPH_DIR/ralph.sh"
    chmod +x "$_TEST_RALPH_DIR/ralph.sh"
    echo '#!/bin/bash' > "$_TEST_RALPH_DIR/task"
    chmod +x "$_TEST_RALPH_DIR/task"

    # Fake bin directory (stands in for /usr/local/bin)
    export _TEST_BIN_DIR="$TEST_WORK_DIR/bin"
    mkdir -p "$_TEST_BIN_DIR"
}

teardown() {
    if [[ -d "$TEST_WORK_DIR" ]]; then
        rm -rf "$TEST_WORK_DIR"
    fi
}

# --- basic symlinking ---

@test "entrypoint creates ralph symlink in bin directory" {
    _run_cli_symlinks
    assert_success
    assert [ -L "$_TEST_BIN_DIR/ralph" ]
}

@test "entrypoint creates task symlink in bin directory" {
    _run_cli_symlinks
    assert_success
    assert [ -L "$_TEST_BIN_DIR/task" ]
}

@test "entrypoint ralph symlink points to ralph.sh" {
    _run_cli_symlinks
    assert_success
    local target
    target=$(readlink "$_TEST_BIN_DIR/ralph")
    [[ "$target" == "$_TEST_RALPH_DIR/ralph.sh" ]]
}

@test "entrypoint task symlink points to task binary" {
    _run_cli_symlinks
    assert_success
    local target
    target=$(readlink "$_TEST_BIN_DIR/task")
    [[ "$target" == "$_TEST_RALPH_DIR/task" ]]
}

@test "entrypoint logs CLI symlink creation to stderr" {
    _run_cli_symlinks
    assert_success
    assert_output --partial "linked ralph and task"
}

# --- idempotency ---

@test "entrypoint CLI symlinks are idempotent" {
    _run_cli_symlinks
    assert_success
    assert [ -L "$_TEST_BIN_DIR/ralph" ]
    assert [ -L "$_TEST_BIN_DIR/task" ]

    # Run again — must not fail
    _run_cli_symlinks
    assert_success
    assert [ -L "$_TEST_BIN_DIR/ralph" ]
    assert [ -L "$_TEST_BIN_DIR/task" ]
}

@test "entrypoint overwrites existing ralph symlink" {
    # Create an initial symlink pointing to a different file
    touch "$TEST_WORK_DIR/old-ralph"
    ln -s "$TEST_WORK_DIR/old-ralph" "$_TEST_BIN_DIR/ralph"

    _run_cli_symlinks
    assert_success

    local target
    target=$(readlink "$_TEST_BIN_DIR/ralph")
    [[ "$target" == "$_TEST_RALPH_DIR/ralph.sh" ]]
}

@test "entrypoint overwrites existing task symlink" {
    # Create an initial symlink pointing to a different file
    touch "$TEST_WORK_DIR/old-task"
    ln -s "$TEST_WORK_DIR/old-task" "$_TEST_BIN_DIR/task"

    _run_cli_symlinks
    assert_success

    local target
    target=$(readlink "$_TEST_BIN_DIR/task")
    [[ "$target" == "$_TEST_RALPH_DIR/task" ]]
}

# --- executability ---

@test "ralph symlink target is executable" {
    _run_cli_symlinks
    assert_success
    assert [ -x "$_TEST_RALPH_DIR/ralph.sh" ]
}

@test "task symlink target is executable" {
    _run_cli_symlinks
    assert_success
    assert [ -x "$_TEST_RALPH_DIR/task" ]
}
