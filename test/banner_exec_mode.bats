#!/usr/bin/env bats
# test/banner_exec_mode.bats — print_banner() execution mode display tests

_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
_SCRIPT_DIR="$(cd "$_TEST_DIR/.." && pwd)"

load "$_TEST_DIR/libs/bats-support/load"
load "$_TEST_DIR/libs/bats-assert/load"

# Source output.sh and set required globals
_setup_banner() {
    . "$_SCRIPT_DIR/lib/output.sh"
    MODE="build"
    COMMAND="/ralph-build"
    CURRENT_BRANCH="main"
    DANGER=false
    ACTIVE_BACKEND="anthropic"
    AGENT_ID=""
    MODEL_ALIAS=""
    RESOLVED_MODEL=""
    MAX_ITERATIONS=0
}

# --- execution mode display ---

@test "print_banner displays Exec: local when RALPH_EXEC_MODE=local" {
    _setup_banner
    export RALPH_EXEC_MODE="local"
    run print_banner
    assert_success
    assert_output --partial "Exec:   local"
}

@test "print_banner displays Exec: docker when RALPH_EXEC_MODE=docker" {
    _setup_banner
    export RALPH_EXEC_MODE="docker"
    run print_banner
    assert_success
    assert_output --partial "Exec:   docker"
}

@test "print_banner defaults to local when RALPH_EXEC_MODE is unset" {
    _setup_banner
    unset RALPH_EXEC_MODE
    run print_banner
    assert_success
    assert_output --partial "Exec:   local"
}

@test "print_banner shows Exec line after Agent line" {
    _setup_banner
    export RALPH_EXEC_MODE="docker"
    AGENT_ID="a1b2"
    run print_banner
    assert_success
    # Exec line should appear in output
    assert_output --partial "Agent:  a1b2"
    assert_output --partial "Exec:   docker"
}
