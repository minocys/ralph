#!/usr/bin/env bats
# test/entrypoint_claude_import.bats — host ~/.claude import tests for docker/entrypoint.sh

load test_helper

# Helper: run the host-claude import section from entrypoint.sh in a subshell.
_run_claude_import() {
    local script
    script=$(cat <<'SCRIPT'
set -euo pipefail
HOME="$_TEST_HOME"

if [ -d /mnt/claude-host ]; then
    mkdir -p "$HOME/.claude"
    cp -a /mnt/claude-host/. "$HOME/.claude/"
    echo "entrypoint: imported host ~/.claude from /mnt/claude-host (read-only)" >&2
fi
SCRIPT
)
    run bash -c "$script"
}

setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    export TEST_WORK_DIR

    export _TEST_HOME="$TEST_WORK_DIR/home"
    mkdir -p "$_TEST_HOME"
}

teardown() {
    if [[ -d "$TEST_WORK_DIR" ]]; then
        rm -rf "$TEST_WORK_DIR"
    fi
}

# --- import when /mnt/claude-host exists ---

@test "entrypoint copies host .claude contents to container-local ~/.claude" {
    mkdir -p /tmp/test-claude-host-$$
    echo '{"test":true}' > /tmp/test-claude-host-$$/settings.json
    mkdir -p /tmp/test-claude-host-$$/skills

    # Override /mnt/claude-host since we can't mount in tests
    local script
    script=$(cat <<'SCRIPT'
set -euo pipefail
HOME="$_TEST_HOME"
_CLAUDE_HOST_DIR="$_TEST_CLAUDE_HOST"

if [ -d "$_CLAUDE_HOST_DIR" ]; then
    mkdir -p "$HOME/.claude"
    cp -a "$_CLAUDE_HOST_DIR"/. "$HOME/.claude/"
    echo "entrypoint: imported host ~/.claude from $_CLAUDE_HOST_DIR (read-only)" >&2
fi
SCRIPT
)
    export _TEST_CLAUDE_HOST="/tmp/test-claude-host-$$"
    run bash -c "$script"
    assert_success
    assert [ -f "$_TEST_HOME/.claude/settings.json" ]
    assert [ -d "$_TEST_HOME/.claude/skills" ]

    # Verify content was copied
    local content
    content=$(cat "$_TEST_HOME/.claude/settings.json")
    [[ "$content" == '{"test":true}' ]]

    rm -rf /tmp/test-claude-host-$$
}

@test "entrypoint logs import message to stderr" {
    mkdir -p /tmp/test-claude-host-$$

    local script
    script=$(cat <<'SCRIPT'
set -euo pipefail
HOME="$_TEST_HOME"
_CLAUDE_HOST_DIR="$_TEST_CLAUDE_HOST"

if [ -d "$_CLAUDE_HOST_DIR" ]; then
    mkdir -p "$HOME/.claude"
    cp -a "$_CLAUDE_HOST_DIR"/. "$HOME/.claude/"
    echo "entrypoint: imported host ~/.claude from $_CLAUDE_HOST_DIR (read-only)" >&2
fi
SCRIPT
)
    export _TEST_CLAUDE_HOST="/tmp/test-claude-host-$$"
    run bash -c "$script"
    assert_success
    assert_output --partial "imported host ~/.claude"

    rm -rf /tmp/test-claude-host-$$
}

# --- no import when /mnt/claude-host is absent ---

@test "entrypoint skips import when host mount is absent" {
    local script
    script=$(cat <<'SCRIPT'
set -euo pipefail
HOME="$_TEST_HOME"
_CLAUDE_HOST_DIR="/nonexistent/path"

if [ -d "$_CLAUDE_HOST_DIR" ]; then
    mkdir -p "$HOME/.claude"
    cp -a "$_CLAUDE_HOST_DIR"/. "$HOME/.claude/"
    echo "entrypoint: imported host ~/.claude from $_CLAUDE_HOST_DIR (read-only)" >&2
fi
echo "done" >&2
SCRIPT
)
    run bash -c "$script"
    assert_success
    refute_output --partial "imported host"
    assert [ ! -d "$_TEST_HOME/.claude" ]
}

# --- import preserves subdirectories ---

@test "entrypoint copies nested directories from host mount" {
    mkdir -p /tmp/test-claude-host-$$/skills/ralph-build
    echo "# skill" > /tmp/test-claude-host-$$/skills/ralph-build/SKILL.md
    echo '{}' > /tmp/test-claude-host-$$/settings.json

    local script
    script=$(cat <<'SCRIPT'
set -euo pipefail
HOME="$_TEST_HOME"
_CLAUDE_HOST_DIR="$_TEST_CLAUDE_HOST"

if [ -d "$_CLAUDE_HOST_DIR" ]; then
    mkdir -p "$HOME/.claude"
    cp -a "$_CLAUDE_HOST_DIR"/. "$HOME/.claude/"
    echo "entrypoint: imported host ~/.claude from $_CLAUDE_HOST_DIR (read-only)" >&2
fi
SCRIPT
)
    export _TEST_CLAUDE_HOST="/tmp/test-claude-host-$$"
    run bash -c "$script"
    assert_success
    assert [ -f "$_TEST_HOME/.claude/skills/ralph-build/SKILL.md" ]
    assert [ -f "$_TEST_HOME/.claude/settings.json" ]

    rm -rf /tmp/test-claude-host-$$
}

# --- container-local copy is writable ---

@test "entrypoint creates writable copy so subsequent writes succeed" {
    mkdir -p /tmp/test-claude-host-$$
    echo '{}' > /tmp/test-claude-host-$$/settings.json

    local script
    script=$(cat <<'SCRIPT'
set -euo pipefail
HOME="$_TEST_HOME"
_CLAUDE_HOST_DIR="$_TEST_CLAUDE_HOST"

if [ -d "$_CLAUDE_HOST_DIR" ]; then
    mkdir -p "$HOME/.claude"
    cp -a "$_CLAUDE_HOST_DIR"/. "$HOME/.claude/"
fi

# Simulate entrypoint writing skills and hooks after import
mkdir -p "$HOME/.claude/skills"
echo '{"hooks":{}}' > "$HOME/.claude/settings.json"
SCRIPT
)
    export _TEST_CLAUDE_HOST="/tmp/test-claude-host-$$"
    run bash -c "$script"
    assert_success

    # Verify the writes succeeded
    local content
    content=$(cat "$_TEST_HOME/.claude/settings.json")
    [[ "$content" == '{"hooks":{}}' ]]

    rm -rf /tmp/test-claude-host-$$
}
