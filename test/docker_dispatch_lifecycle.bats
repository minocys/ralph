#!/usr/bin/env bats
# test/docker_dispatch_lifecycle.bats — integration tests for sandbox lifecycle
# in --docker dispatch (create → run → bootstrap → exec flow)
#
# Covers:
#   - Not-found state: create + run + bootstrap + exec
#   - Stopped state: run + bootstrap marker check + exec
#   - Running state: bootstrap marker check + exec
#   - Bootstrap skip when marker exists
#   - Bootstrap runs when marker missing (even for stopped/running)
#   - Exit code forwarding through full lifecycle
#   - Correct ordering of docker commands in each lifecycle branch

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a docker mock that simulates full sandbox lifecycle.
# $1: sandbox state — "running", "stopped", or "none" (no sandbox)
# $2: bootstrap marker — "exists" or "missing"
# $3: optional exit code for exec ralph command (default 0)
#
# The mock tracks all docker invocations to $STUB_DIR/docker.log.
# NOTE: No `local` keyword — mock scripts are not inside functions.
create_lifecycle_mock() {
    local state="${1:-running}"
    local marker="${2:-exists}"
    local exec_exit="${3:-0}"
    cat > "$STUB_DIR/docker" <<STUB
#!/bin/bash
# Log every docker call for verification
echo "\$*" >> "$STUB_DIR/docker.log"
case "\$1" in
    sandbox)
        case "\$2" in
            ls)
                case "$state" in
                    running)
                        echo '[{"Name":"ralph-test-repo-main","Status":"running"}]'
                        ;;
                    stopped)
                        echo '[{"Name":"ralph-test-repo-main","Status":"stopped"}]'
                        ;;
                    none)
                        echo '[]'
                        ;;
                esac
                ;;
            create)
                # Sandbox creation — just succeed
                exit 0
                ;;
            run)
                # Start sandbox — just succeed
                exit 0
                ;;
            exec)
                # Detect bootstrap marker check: "test -f" ...bootstrapped
                # Must match "test -f" specifically to avoid matching the
                # bootstrap script content which contains "touch ...bootstrapped"
                all_args="\$*"
                if echo "\$all_args" | grep -q "test -f.*\.bootstrapped"; then
                    echo "BOOTSTRAP_CHECK" >> "$STUB_DIR/docker.log"
                    if [ "$marker" = "exists" ]; then
                        exit 0  # marker found
                    else
                        exit 1  # marker not found
                    fi
                fi
                # Detect bootstrap script execution (bash -c with set -euo)
                if echo "\$all_args" | grep -q "set -euo pipefail"; then
                    echo "BOOTSTRAP_RAN" >> "$STUB_DIR/docker.log"
                    exit 0
                fi
                # Regular exec (ralph command) — output and exit
                echo "EXEC_ARGS: \$*"
                exit $exec_exit
                ;;
        esac
        ;;
esac
exit 0
STUB
    chmod +x "$STUB_DIR/docker"
    # Clear log
    > "$STUB_DIR/docker.log"
}

# ---------------------------------------------------------------------------
# Not-found state: create + run + bootstrap + exec
# ---------------------------------------------------------------------------

@test "lifecycle: not-found sandbox triggers create then run then bootstrap then exec" {
    create_lifecycle_mock none missing
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    # Verify docker.log has create, run, bootstrap check, bootstrap run, and exec
    run cat "$STUB_DIR/docker.log"
    assert_output --partial "sandbox create"
    assert_output --partial "sandbox run"
    assert_output --partial "BOOTSTRAP_CHECK"
    assert_output --partial "BOOTSTRAP_RAN"
}

@test "lifecycle: not-found sandbox calls create with correct template and args" {
    create_lifecycle_mock none missing
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    run grep "sandbox create" "$STUB_DIR/docker.log"
    assert_success
    assert_output --partial "docker/sandbox-templates:claude-code"
    assert_output --partial "--name"
    assert_output --partial "shell"
    assert_output --partial ":ro"
}

@test "lifecycle: not-found sandbox calls run after create" {
    create_lifecycle_mock none missing
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    # Verify ordering: create appears before run in the log
    create_line=$(grep -n "sandbox create" "$STUB_DIR/docker.log" | head -1 | cut -d: -f1)
    run_line=$(grep -n "sandbox run" "$STUB_DIR/docker.log" | head -1 | cut -d: -f1)
    [ -n "$create_line" ]
    [ -n "$run_line" ]
    [ "$create_line" -lt "$run_line" ]
}

@test "lifecycle: not-found sandbox with marker already existing skips bootstrap script" {
    create_lifecycle_mock none exists
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    # Bootstrap check happens but bootstrap script does NOT run
    run grep "BOOTSTRAP_CHECK" "$STUB_DIR/docker.log"
    assert_success
    run grep "BOOTSTRAP_RAN" "$STUB_DIR/docker.log"
    assert_failure  # Should NOT have run bootstrap
}

# ---------------------------------------------------------------------------
# Stopped state: run + bootstrap marker check + exec
# ---------------------------------------------------------------------------

@test "lifecycle: stopped sandbox calls run to start it" {
    create_lifecycle_mock stopped exists
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    run grep "sandbox run" "$STUB_DIR/docker.log"
    assert_success
}

@test "lifecycle: stopped sandbox does not call create" {
    create_lifecycle_mock stopped exists
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    run grep "sandbox create" "$STUB_DIR/docker.log"
    assert_failure
}

@test "lifecycle: stopped sandbox checks bootstrap marker" {
    create_lifecycle_mock stopped exists
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    run grep "BOOTSTRAP_CHECK" "$STUB_DIR/docker.log"
    assert_success
}

@test "lifecycle: stopped sandbox with missing marker runs bootstrap" {
    create_lifecycle_mock stopped missing
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    run grep "BOOTSTRAP_RAN" "$STUB_DIR/docker.log"
    assert_success
}

@test "lifecycle: stopped sandbox with existing marker skips bootstrap script" {
    create_lifecycle_mock stopped exists
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    run grep "BOOTSTRAP_RAN" "$STUB_DIR/docker.log"
    assert_failure
}

# ---------------------------------------------------------------------------
# Running state: bootstrap marker check + exec
# ---------------------------------------------------------------------------

@test "lifecycle: running sandbox skips create and run" {
    create_lifecycle_mock running exists
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    run grep "sandbox create" "$STUB_DIR/docker.log"
    assert_failure
    # sandbox run should NOT appear (only sandbox ls and sandbox exec)
    run grep "^sandbox run" "$STUB_DIR/docker.log"
    assert_failure
}

@test "lifecycle: running sandbox checks bootstrap marker" {
    create_lifecycle_mock running exists
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    run grep "BOOTSTRAP_CHECK" "$STUB_DIR/docker.log"
    assert_success
}

@test "lifecycle: running sandbox with marker skips bootstrap and proceeds to exec" {
    create_lifecycle_mock running exists
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    run grep "BOOTSTRAP_RAN" "$STUB_DIR/docker.log"
    assert_failure
    assert_output --partial "EXEC_ARGS"  || {
        # Check main output for EXEC_ARGS
        echo "$output" | grep -q "EXEC_ARGS" || {
            # The exec replaces the process, so check the original output
            run cat "$STUB_DIR/docker.log"
            assert_output --partial "ralph plan"
        }
    }
}

@test "lifecycle: running sandbox without marker runs bootstrap before exec" {
    create_lifecycle_mock running missing
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    run grep "BOOTSTRAP_RAN" "$STUB_DIR/docker.log"
    assert_success
}

# ---------------------------------------------------------------------------
# Exec invocation correctness
# ---------------------------------------------------------------------------

@test "lifecycle: exec forwards subcommand and flags" {
    create_lifecycle_mock running exists
    run "$SCRIPT_DIR/ralph.sh" --docker build -n 3 --danger
    assert_success
    assert_output --partial "ralph build -n 3 --danger"
}

@test "lifecycle: exec uses -it flags" {
    create_lifecycle_mock running exists
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    # The final exec call should have -it
    run grep "exec -it" "$STUB_DIR/docker.log"
    assert_success
}

@test "lifecycle: exec is the last docker command in log" {
    create_lifecycle_mock running exists
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    # Last line of docker.log should contain the exec with ralph command
    last_line=$(tail -1 "$STUB_DIR/docker.log")
    [[ "$last_line" == *"sandbox exec"*"ralph plan"* ]]
}

# ---------------------------------------------------------------------------
# Exit code forwarding through lifecycle
# ---------------------------------------------------------------------------

@test "lifecycle: forwards exit code 0 from sandboxed ralph" {
    create_lifecycle_mock running exists 0
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
}

@test "lifecycle: forwards non-zero exit code from sandboxed ralph" {
    create_lifecycle_mock running exists 42
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    [ "$status" -eq 42 ]
}

@test "lifecycle: forwards exit code through full not-found lifecycle" {
    create_lifecycle_mock none exists 7
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    [ "$status" -eq 7 ]
}

# ---------------------------------------------------------------------------
# Command ordering verification
# ---------------------------------------------------------------------------

@test "lifecycle: not-found sequence is ls → create → run → bootstrap-check → exec" {
    create_lifecycle_mock none exists
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    # Extract ordered line numbers from log
    ls_line=$(grep -n "sandbox ls" "$STUB_DIR/docker.log" | head -1 | cut -d: -f1)
    create_line=$(grep -n "sandbox create" "$STUB_DIR/docker.log" | head -1 | cut -d: -f1)
    run_line=$(grep -n "sandbox run" "$STUB_DIR/docker.log" | head -1 | cut -d: -f1)
    check_line=$(grep -n "BOOTSTRAP_CHECK" "$STUB_DIR/docker.log" | head -1 | cut -d: -f1)
    [ -n "$ls_line" ]
    [ -n "$create_line" ]
    [ -n "$run_line" ]
    [ -n "$check_line" ]
    [ "$ls_line" -lt "$create_line" ]
    [ "$create_line" -lt "$run_line" ]
    [ "$run_line" -lt "$check_line" ]
}

@test "lifecycle: stopped sequence is ls → run → bootstrap-check → exec" {
    create_lifecycle_mock stopped exists
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    ls_line=$(grep -n "sandbox ls" "$STUB_DIR/docker.log" | head -1 | cut -d: -f1)
    run_line=$(grep -n "sandbox run" "$STUB_DIR/docker.log" | head -1 | cut -d: -f1)
    check_line=$(grep -n "BOOTSTRAP_CHECK" "$STUB_DIR/docker.log" | head -1 | cut -d: -f1)
    [ -n "$ls_line" ]
    [ -n "$run_line" ]
    [ -n "$check_line" ]
    [ "$ls_line" -lt "$run_line" ]
    [ "$run_line" -lt "$check_line" ]
}

@test "lifecycle: running sequence is ls → bootstrap-check → exec" {
    create_lifecycle_mock running exists
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    ls_line=$(grep -n "sandbox ls" "$STUB_DIR/docker.log" | head -1 | cut -d: -f1)
    check_line=$(grep -n "BOOTSTRAP_CHECK" "$STUB_DIR/docker.log" | head -1 | cut -d: -f1)
    [ -n "$ls_line" ]
    [ -n "$check_line" ]
    [ "$ls_line" -lt "$check_line" ]
}
