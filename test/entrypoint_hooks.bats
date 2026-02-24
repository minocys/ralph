#!/usr/bin/env bats
# test/entrypoint_hooks.bats — hooks configuration tests for docker/entrypoint.sh

load test_helper

# Helper: run the hooks section from entrypoint.sh in a subshell.
# Uses _TEST_RALPH_DIR as RALPH_DIR and _TEST_HOME as HOME.
_run_hooks_section() {
    local script
    script=$(cat <<'SCRIPT'
set -euo pipefail
RALPH_DIR="$_TEST_RALPH_DIR"
HOME="$_TEST_HOME"

_settings_file="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
if [ ! -f "$_settings_file" ]; then
    echo '{}' > "$_settings_file"
fi
jq --arg ralph "$RALPH_DIR" \
    '.hooks = ((.hooks // {}) * {
        "PreCompact": [{"matcher":"*","hooks":[{"type":"command","command":("bash " + $ralph + "/hooks/precompact.sh")}]}],
        "SessionEnd": [{"matcher":"*","hooks":[{"type":"command","command":("bash " + $ralph + "/hooks/session_end.sh")}]}]
    })' "$_settings_file" > "${_settings_file}.tmp" && mv "${_settings_file}.tmp" "$_settings_file"
echo "entrypoint: configured hooks in $_settings_file" >&2
SCRIPT
)
    run bash -c "$script"
}

setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    export TEST_WORK_DIR

    # Fake RALPH_DIR with hooks
    export _TEST_RALPH_DIR="$TEST_WORK_DIR/ralph"
    mkdir -p "$_TEST_RALPH_DIR/hooks"
    echo '#!/bin/bash' > "$_TEST_RALPH_DIR/hooks/precompact.sh"
    echo '#!/bin/bash' > "$_TEST_RALPH_DIR/hooks/session_end.sh"

    # Fake HOME so we don't touch the real ~/.claude
    export _TEST_HOME="$TEST_WORK_DIR/home"
    mkdir -p "$_TEST_HOME"
}

teardown() {
    if [[ -d "$TEST_WORK_DIR" ]]; then
        rm -rf "$TEST_WORK_DIR"
    fi
}

# --- settings.json creation ---

@test "entrypoint creates settings.json when none exists" {
    _run_hooks_section
    assert_success
    assert [ -f "$_TEST_HOME/.claude/settings.json" ]
}

@test "entrypoint creates ~/.claude directory if missing" {
    rmdir "$_TEST_HOME" 2>/dev/null || rm -rf "$_TEST_HOME"
    mkdir -p "$_TEST_HOME"
    # ~/.claude does not exist
    _run_hooks_section
    assert_success
    assert [ -d "$_TEST_HOME/.claude" ]
    assert [ -f "$_TEST_HOME/.claude/settings.json" ]
}

# --- hook configuration ---

@test "entrypoint configures PreCompact hook in settings.json" {
    _run_hooks_section
    assert_success
    local cmd
    cmd=$(jq -r '.hooks.PreCompact[0].hooks[0].command' "$_TEST_HOME/.claude/settings.json")
    [[ "$cmd" == *"/hooks/precompact.sh" ]]
}

@test "entrypoint configures SessionEnd hook in settings.json" {
    _run_hooks_section
    assert_success
    local cmd
    cmd=$(jq -r '.hooks.SessionEnd[0].hooks[0].command' "$_TEST_HOME/.claude/settings.json")
    [[ "$cmd" == *"/hooks/session_end.sh" ]]
}

@test "entrypoint hook commands reference RALPH_DIR path" {
    _run_hooks_section
    assert_success
    local pre_cmd end_cmd
    pre_cmd=$(jq -r '.hooks.PreCompact[0].hooks[0].command' "$_TEST_HOME/.claude/settings.json")
    end_cmd=$(jq -r '.hooks.SessionEnd[0].hooks[0].command' "$_TEST_HOME/.claude/settings.json")
    [[ "$pre_cmd" == "bash $_TEST_RALPH_DIR/hooks/precompact.sh" ]]
    [[ "$end_cmd" == "bash $_TEST_RALPH_DIR/hooks/session_end.sh" ]]
}

@test "entrypoint hooks use wildcard matcher" {
    _run_hooks_section
    assert_success
    local pre_matcher end_matcher
    pre_matcher=$(jq -r '.hooks.PreCompact[0].matcher' "$_TEST_HOME/.claude/settings.json")
    end_matcher=$(jq -r '.hooks.SessionEnd[0].matcher' "$_TEST_HOME/.claude/settings.json")
    [[ "$pre_matcher" == "*" ]]
    [[ "$end_matcher" == "*" ]]
}

@test "entrypoint hooks use command type" {
    _run_hooks_section
    assert_success
    local pre_type end_type
    pre_type=$(jq -r '.hooks.PreCompact[0].hooks[0].type' "$_TEST_HOME/.claude/settings.json")
    end_type=$(jq -r '.hooks.SessionEnd[0].hooks[0].type' "$_TEST_HOME/.claude/settings.json")
    [[ "$pre_type" == "command" ]]
    [[ "$end_type" == "command" ]]
}

# --- merge with existing settings ---

@test "entrypoint preserves existing settings when merging hooks" {
    mkdir -p "$_TEST_HOME/.claude"
    echo '{"env":{"FOO":"bar"},"permissions":{"allow":["Read"]}}' > "$_TEST_HOME/.claude/settings.json"

    _run_hooks_section
    assert_success

    local foo perms
    foo=$(jq -r '.env.FOO' "$_TEST_HOME/.claude/settings.json")
    perms=$(jq -r '.permissions.allow[0]' "$_TEST_HOME/.claude/settings.json")
    [[ "$foo" == "bar" ]]
    [[ "$perms" == "Read" ]]
    # Hooks should also be present
    local cmd
    cmd=$(jq -r '.hooks.PreCompact[0].hooks[0].command' "$_TEST_HOME/.claude/settings.json")
    [[ "$cmd" == *"/hooks/precompact.sh" ]]
}

@test "entrypoint overwrites existing hook configuration" {
    mkdir -p "$_TEST_HOME/.claude"
    echo '{"hooks":{"PreCompact":[{"matcher":"*","hooks":[{"type":"command","command":"bash /old/path/precompact.sh"}]}]}}' > "$_TEST_HOME/.claude/settings.json"

    _run_hooks_section
    assert_success

    local cmd
    cmd=$(jq -r '.hooks.PreCompact[0].hooks[0].command' "$_TEST_HOME/.claude/settings.json")
    [[ "$cmd" == "bash $_TEST_RALPH_DIR/hooks/precompact.sh" ]]
}

# --- idempotency ---

@test "entrypoint hook configuration is idempotent" {
    _run_hooks_section
    assert_success

    local first_json
    first_json=$(cat "$_TEST_HOME/.claude/settings.json")

    # Run again
    _run_hooks_section
    assert_success

    local second_json
    second_json=$(cat "$_TEST_HOME/.claude/settings.json")

    [[ "$first_json" == "$second_json" ]]
}

# --- logging ---

@test "entrypoint logs hook configuration to stderr" {
    _run_hooks_section
    assert_success
    assert_output --partial "configured hooks in"
}
