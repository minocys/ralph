#!/usr/bin/env bats
# test/sandbox_signal_handling.bats — tests for sandbox signal handling spec
#
# Covers:
#   1. --docker path does NOT source lib/signals.sh (runtime + static)
#   2. Exit code forwarding (0, non-zero, 130/SIGINT)
#   3. Docker dispatch uses exec (not background subshell)

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a docker mock that simulates a running sandbox and exits with
# a configurable code on sandbox exec.
# $1: exit code for sandbox exec (default 0)
create_docker_mock_signal() {
    local exit_code="${1:-0}"
    cat > "$STUB_DIR/docker" <<STUB
#!/bin/bash
echo "\$*" >> "$STUB_DIR/docker.log"
case "\$1" in
    sandbox)
        case "\$2" in
            ls)
                echo '[{"Name":"ralph-test-repo-main","Status":"running"}]'
                ;;
            exec)
                exit $exit_code
                ;;
        esac
        ;;
esac
exit 0
STUB
    chmod +x "$STUB_DIR/docker"
    > "$STUB_DIR/docker.log"
}

# ---------------------------------------------------------------------------
# 1. --docker path does NOT source lib/signals.sh
# ---------------------------------------------------------------------------

@test "signal handling: --docker case block does not reference signals.sh" {
    # Static analysis: the --docker case in ralph.sh must not source signals.sh
    run grep -A 60 "^    --docker)" "$SCRIPT_DIR/ralph.sh"
    assert_success
    refute_output --partial "signals.sh"
}

@test "signal handling: plan/build source signals.sh but --docker does not" {
    # Verify plan and build DO source signals.sh (positive control),
    # confirming the file is used elsewhere but intentionally excluded from --docker.
    run grep -A 30 "^    plan)" "$SCRIPT_DIR/ralph.sh"
    assert_success
    assert_output --partial "signals.sh"

    run grep -A 30 "^    build)" "$SCRIPT_DIR/ralph.sh"
    assert_success
    assert_output --partial "signals.sh"

    # Verify --docker does NOT
    run grep -A 60 "^    --docker)" "$SCRIPT_DIR/ralph.sh"
    assert_success
    refute_output --partial "signals.sh"
}

@test "signal handling: --docker does not define setup_signal_handlers" {
    # Runtime test: run --docker with a mock that captures env.
    # We wrap ralph.sh in a subshell that checks if setup_signal_handlers is
    # defined as a function after the --docker case sources its libs.
    create_docker_mock_signal 0

    # Inject a check: replace exec with a function-existence test.
    # We use a wrapper script that sources ralph.sh's --docker code path
    # and inspects whether signal functions are defined.
    local wrapper="$STUB_DIR/signal_check.sh"
    cat > "$wrapper" <<'WRAPPER'
#!/bin/bash
# Override exec to prevent actual process replacement
exec() {
    # Instead of exec'ing, just check for signal handler functions
    if declare -f setup_signal_handlers >/dev/null 2>&1; then
        echo "SIGNAL_HANDLERS_DEFINED"
    else
        echo "NO_SIGNAL_HANDLERS"
    fi
    if declare -f handle_int >/dev/null 2>&1; then
        echo "HANDLE_INT_DEFINED"
    else
        echo "NO_HANDLE_INT"
    fi
    if declare -f handle_term >/dev/null 2>&1; then
        echo "HANDLE_TERM_DEFINED"
    else
        echo "NO_HANDLE_TERM"
    fi
    builtin exit 0
}
WRAPPER
    chmod +x "$wrapper"

    # Source the wrapper (which overrides exec), then source ralph.sh
    run bash -c "source '$wrapper'; source '$SCRIPT_DIR/ralph.sh' --docker plan"
    # The wrapper's exec override should have run, reporting NO signal handlers
    assert_output --partial "NO_SIGNAL_HANDLERS"
    assert_output --partial "NO_HANDLE_INT"
    assert_output --partial "NO_HANDLE_TERM"
    refute_output --partial "SIGNAL_HANDLERS_DEFINED"
    refute_output --partial "HANDLE_INT_DEFINED"
    refute_output --partial "HANDLE_TERM_DEFINED"
}

@test "signal handling: --docker does not call setup_signal_handlers or setup_cleanup_trap" {
    # Verify the --docker case block does not invoke signal/cleanup setup.
    run grep -A 60 "^    --docker)" "$SCRIPT_DIR/ralph.sh"
    assert_success
    refute_output --partial "setup_signal_handlers"
    refute_output --partial "setup_cleanup_trap"
}

@test "signal handling: --docker does not register any trap commands" {
    # Extract the --docker case block and verify no 'trap' statements
    # (excluding comments that mention the word trap).
    local docker_block
    docker_block=$(sed -n '/^    --docker)/,/^    ;;$/p' "$SCRIPT_DIR/ralph.sh")
    # Filter to non-comment lines only and check for trap commands
    local trap_lines
    trap_lines=$(echo "$docker_block" | grep -v '^\s*#' | grep '\btrap\b' || true)
    [ -z "$trap_lines" ]
}

# ---------------------------------------------------------------------------
# 2. Exit code forwarding
# ---------------------------------------------------------------------------

@test "signal handling: exit code 0 forwarded from docker sandbox exec" {
    create_docker_mock_signal 0
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    [ "$status" -eq 0 ]
}

@test "signal handling: exit code 1 forwarded from docker sandbox exec" {
    create_docker_mock_signal 1
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_failure
    [ "$status" -eq 1 ]
}

@test "signal handling: exit code 130 (SIGINT) forwarded from docker sandbox exec" {
    create_docker_mock_signal 130
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_failure
    [ "$status" -eq 130 ]
}

@test "signal handling: arbitrary non-zero exit code forwarded" {
    create_docker_mock_signal 42
    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_failure
    [ "$status" -eq 42 ]
}

@test "signal handling: exit code forwarded for task subcommand" {
    create_docker_mock_signal 7
    run "$SCRIPT_DIR/ralph.sh" --docker task list
    assert_failure
    [ "$status" -eq 7 ]
}

@test "signal handling: exit code 0 for task subcommand" {
    create_docker_mock_signal 0
    run "$SCRIPT_DIR/ralph.sh" --docker task list
    assert_success
}

# ---------------------------------------------------------------------------
# 3. Docker dispatch uses exec (not background subshell)
# ---------------------------------------------------------------------------

@test "signal handling: --docker dispatch uses exec for docker sandbox exec" {
    # The final line of the --docker case must use 'exec' to replace the
    # shell process, ensuring exit code propagation without wrapper overhead.
    run grep -A 60 "^    --docker)" "$SCRIPT_DIR/ralph.sh"
    assert_success
    assert_output --partial "exec docker sandbox exec"
}

@test "signal handling: --docker dispatch does not use background subshell" {
    # Verify no background operator (&) or wait pattern in --docker block.
    # The plan/build paths use a pipeline+wait pattern; --docker must not.
    run grep -A 60 "^    --docker)" "$SCRIPT_DIR/ralph.sh"
    assert_success
    # No backgrounding via & (the | in claude | tee | jq & pattern)
    refute_output --partial " & "
    refute_output --partial " &$"
    # No wait command
    refute_output --partial "wait "
    refute_output --partial "wait$"
}

@test "signal handling: exec is the final command in --docker dispatch" {
    # When exec is used, the docker process replaces ralph.sh.
    # Verify that the line with exec is immediately followed by ;; (the case
    # terminator), with nothing in between except blank lines.
    local exec_line_num
    exec_line_num=$(grep -n 'exec docker sandbox exec' "$SCRIPT_DIR/ralph.sh" | head -1 | cut -d: -f1)
    [ -n "$exec_line_num" ]
    # Find the next non-blank line after exec
    local next_line
    next_line=$(tail -n +"$((exec_line_num + 1))" "$SCRIPT_DIR/ralph.sh" | grep -v '^\s*$' | head -1)
    echo "Next non-blank line after exec: '$next_line'"
    # It should be the case arm terminator ;;
    [[ "$next_line" == *";;" ]]
}
