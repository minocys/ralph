#!/usr/bin/env bats
# test/ralph_docker_dispatch.bats — Tests for --docker flag parsing in ralph.sh

load test_helper

setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    mkdir -p "$TEST_WORK_DIR/specs"
    echo "# dummy spec" > "$TEST_WORK_DIR/specs/dummy.md"

    STUB_DIR="$(mktemp -d)"

    # claude stub
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo "CLAUDE_STUB_CALLED"
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    # docker stub that logs all calls
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CMD: $*" >> "$TEST_WORK_DIR/docker_calls.log"
# Handle sandbox ls for lookup_sandbox
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[]'
    exit 0
fi
# Handle sandbox exec - just echo args to stdout for verification
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "SANDBOX_EXEC: $*"
    exit 0
fi
# Handle compose version for check_docker_installed
if [ "$1" = "compose" ] && [ "$2" = "version" ]; then
    echo "Docker Compose version v2.24.0"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"
    export TEST_WORK_DIR
    export STUB_DIR

    # Prevent detect_backend() from reading host ~/.claude/settings.json
    export HOME="$TEST_WORK_DIR"
    unset CLAUDE_CODE_USE_BEDROCK

    cd "$TEST_WORK_DIR"
}

# --- Error cases ---

@test "ralph --docker with no subcommand exits 1 with error" {
    run "$SCRIPT_DIR/ralph.sh" --docker
    assert_failure
    assert_output --partial "requires a subcommand"
}

@test "ralph --docker with no subcommand suggests usage" {
    run "$SCRIPT_DIR/ralph.sh" --docker
    assert_failure
    assert_output --partial "ralph --docker --help"
}

@test "ralph --docker with no subcommand writes to stderr" {
    run "$SCRIPT_DIR/ralph.sh" --docker
    assert_failure
    # The error message should be present in output (bats captures both stdout+stderr in run)
    assert_output --partial "Error:"
}

# --- Help ---

@test "ralph --docker --help shows docker-specific usage" {
    run "$SCRIPT_DIR/ralph.sh" --docker --help
    assert_success
    assert_output --partial "ralph --docker <command>"
    assert_output --partial "Docker sandbox"
}

@test "ralph --docker -h shows docker-specific usage" {
    run "$SCRIPT_DIR/ralph.sh" --docker -h
    assert_success
    assert_output --partial "ralph --docker <command>"
}

@test "ralph --help includes --docker in global options" {
    run "$SCRIPT_DIR/ralph.sh" --help
    assert_success
    assert_output --partial "--docker"
    assert_output --partial "Docker sandbox"
}

# --- Subcommand forwarding ---

@test "ralph --docker build captures 'build' as subcommand" {
    # Set up sandbox as running so it goes straight to exec
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    # Print args for verification
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    assert_output --partial "ralph build"
}

@test "ralph --docker plan -n 3 --model opus-4.5 passes all flags through" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker plan -n 3 --model opus-4.5
    assert_success
    assert_output --partial "ralph plan -n 3 --model opus-4.5"
}

@test "ralph --docker task list forwards task subcommand" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker task list
    assert_success
    assert_output --partial "ralph task list"
}

# --- Docker CLI preflight ---

@test "ralph --docker exits 1 when docker CLI is missing" {
    rm -f "$STUB_DIR/docker"
    # Build PATH without docker
    local new_path="$STUB_DIR"
    IFS=: read -ra dirs <<< "$PATH"
    for d in "${dirs[@]}"; do
        [ -x "$d/docker" ] && continue
        new_path="$new_path:$d"
    done
    export PATH="$new_path"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_failure
    assert_output --partial "docker CLI not found"
    assert_output --partial "https://docs.docker.com/get-docker/"
}

@test "ralph --docker preflight check runs before sandbox operations" {
    # Even with a valid subcommand, missing docker should fail immediately
    rm -f "$STUB_DIR/docker"
    local new_path="$STUB_DIR"
    IFS=: read -ra dirs <<< "$PATH"
    for d in "${dirs[@]}"; do
        [ -x "$d/docker" ] && continue
        new_path="$new_path:$d"
    done
    export PATH="$new_path"

    # Verify no sandbox operations are attempted (no docker calls logged)
    run "$SCRIPT_DIR/ralph.sh" --docker plan -n 1
    assert_failure
    assert_output --partial "Error:"
    assert_output --partial "docker CLI not found"
    # Ensure no docker call log was created (preflight exits before sandbox ops)
    assert [ ! -f "$TEST_WORK_DIR/docker_calls.log" ]
}

# --- Sandbox state handling ---

@test "ralph --docker starts stopped sandbox before exec" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CMD: $*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"stopped"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "run" ]; then
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    # Verify sandbox run was called before exec
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "sandbox run"
}

@test "ralph --docker uses -it flags on sandbox exec" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    assert_output --partial "exec -it"
}

# --- Sandbox lifecycle: not found → create + bootstrap + exec ---

@test "ralph --docker creates sandbox when not found" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CMD: $*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "create" ]; then
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "run" ]; then
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    # Simulate bootstrap marker check: not bootstrapped yet on first call
    if echo "$*" | grep -q "test -f"; then
        exit 1
    fi
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    # Verify create was called
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "sandbox create"
}

@test "ralph --docker bootstraps new sandbox before exec" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CMD: $*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "create" ]; then
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "run" ]; then
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    if echo "$*" | grep -q "test -f"; then
        exit 1
    fi
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    # Verify sequence: create → run → bootstrap exec → final exec
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "sandbox create"
    assert_output --partial "sandbox run"
    assert_output --partial "sandbox exec"
}

@test "ralph --docker create passes sandbox template and mount paths" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CMD: $*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "create" ]; then
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "run" ]; then
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    if echo "$*" | grep -q "test -f"; then
        exit 1
    fi
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    run cat "$TEST_WORK_DIR/docker_calls.log"
    # Verify template flag
    assert_output --partial "docker/sandbox-templates:claude-code"
    # Verify --name flag
    assert_output --partial "--name"
    # Verify shell agent type
    assert_output --partial "shell"
    # Verify read-only mount for ralph-docker dir
    assert_output --partial ":ro"
}

@test "ralph --docker skips bootstrap when marker exists" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CMD: $*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "create" ]; then
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "run" ]; then
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    # Bootstrap marker exists
    if echo "$*" | grep -q "test -f"; then
        exit 0
    fi
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    # Verify that bootstrap install commands were NOT run (only marker check + final exec)
    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")
    # Should have create, run, marker check exec, and final exec — but no bootstrap bash -c exec
    local bootstrap_count
    bootstrap_count=$(echo "$log" | grep -c "bash -c" || true)
    [ "$bootstrap_count" -eq 0 ]
}

# --- Sandbox lifecycle: running → exec directly ---

@test "ralph --docker execs directly when sandbox is running" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CMD: $*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    # Verify no create or run calls — only ls and exec
    run cat "$TEST_WORK_DIR/docker_calls.log"
    refute_output --partial "sandbox create"
    refute_output --partial "sandbox run"
    assert_output --partial "sandbox exec"
}

# --- Sandbox lifecycle: stopped → start + exec ---

@test "ralph --docker restarts stopped sandbox then execs" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CMD: $*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"stopped"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "run" ]; then
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    run cat "$TEST_WORK_DIR/docker_calls.log"
    # No create — sandbox already exists
    refute_output --partial "sandbox create"
    # Start it
    assert_output --partial "sandbox run"
    # Then exec
    assert_output --partial "sandbox exec"
}

# --- Exec invocation: correct args ---

@test "ralph --docker exec passes correct args to docker sandbox exec" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CMD: $*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build -n 3 --model opus-4.5 --danger
    assert_success
    # Verify full exec structure: sandbox exec -it <name> ralph <subcmd> [flags]
    assert_output --partial "sandbox exec -it ralph-test-repo-main ralph build -n 3 --model opus-4.5 --danger"
}

# --- Exit code forwarding ---

@test "ralph --docker forwards exit code 0 from sandbox exec" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
}

@test "ralph --docker forwards exit code 1 from sandbox exec" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_failure
    [ "$status" -eq 1 ]
}

@test "ralph --docker forwards exit code 130 from sandbox exec" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    exit 130
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_failure
    [ "$status" -eq 130 ]
}

# =============================================================================
# Integration tests: full flow --docker dispatch
# =============================================================================

# --- Full lifecycle: not found → create → run → bootstrap → exec ---

@test "integration: full flow from --docker build to exec verifies correct ordering" {
    # Comprehensive stub that logs each step with a sequence number
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "STEP: $1 $2" >> "$TEST_WORK_DIR/docker_calls.log"
echo "FULL: $*" >> "$TEST_WORK_DIR/docker_calls.log"

# sandbox ls: no sandbox exists
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[]'
    exit 0
fi

# sandbox create: succeed
if [ "$1" = "sandbox" ] && [ "$2" = "create" ]; then
    exit 0
fi

# sandbox run: succeed
if [ "$1" = "sandbox" ] && [ "$2" = "run" ]; then
    exit 0
fi

# sandbox exec: marker check fails (not bootstrapped), bootstrap succeeds, final exec succeeds
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    if echo "$*" | grep -q "test -f"; then
        exit 1
    fi
    echo "EXEC_ARGS: $*"
    exit 0
fi

exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    # Verify the complete sequence by line ordering in log
    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")

    # Extract STEP lines for ordering verification
    local steps
    steps=$(echo "$log" | grep "^STEP:" | cut -d' ' -f2-)

    # 1. sandbox ls (lookup)
    local ls_line create_line run_line exec_marker_line exec_bootstrap_line exec_final_line
    ls_line=$(echo "$log" | grep -n "^STEP: sandbox ls" | head -1 | cut -d: -f1)
    create_line=$(echo "$log" | grep -n "^STEP: sandbox create" | head -1 | cut -d: -f1)
    run_line=$(echo "$log" | grep -n "^STEP: sandbox run" | head -1 | cut -d: -f1)

    # All exec calls (marker check, bootstrap, and final exec)
    local exec_lines
    exec_lines=$(echo "$log" | grep -n "^STEP: sandbox exec" | cut -d: -f1)
    local first_exec_line last_exec_line
    first_exec_line=$(echo "$exec_lines" | head -1)
    last_exec_line=$(echo "$exec_lines" | tail -1)

    # Verify ordering: ls < create < run < exec calls
    [ "$ls_line" -lt "$create_line" ]
    [ "$create_line" -lt "$run_line" ]
    [ "$run_line" -lt "$first_exec_line" ]

    # Verify the final exec contains the ralph command
    assert_output --partial "ralph build"
}

@test "integration: full flow includes bootstrap marker check before exec" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "$*" >> "$TEST_WORK_DIR/docker_calls.log"

if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "create" ]; then
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "run" ]; then
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    if echo "$*" | grep -q "test -f"; then
        exit 1
    fi
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    # Verify the bootstrap marker check (test -f) was attempted
    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")
    echo "$log" | grep -q "test -f"
}

# --- Task subcommand passthrough ---

@test "integration: --docker task claim id passes through to sandbox exec" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker task claim my-task-01
    assert_success
    assert_output --partial "ralph task claim my-task-01"
}

@test "integration: --docker task show id passes through to sandbox exec" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker task show my-task-01
    assert_success
    assert_output --partial "ralph task show my-task-01"
}

# --- Failed sandbox create exits with error ---

@test "integration: --docker exits with error when sandbox create fails" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CMD: $*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "create" ]; then
    echo "Error: failed to create sandbox" >&2
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_failure
}

@test "integration: --docker does not exec when sandbox create fails" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CMD: $*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "create" ]; then
    echo "Error: disk space exhausted" >&2
    exit 1
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_failure
    # Verify exec was never called (create failed before exec)
    if [ -f "$TEST_WORK_DIR/docker_calls.log" ]; then
        local log
        log=$(cat "$TEST_WORK_DIR/docker_calls.log")
        local exec_count
        exec_count=$(echo "$log" | grep -c "sandbox exec" || true)
        [ "$exec_count" -eq 0 ]
    fi
}

@test "integration: --docker exits with error when sandbox run fails" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CMD: $*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "create" ]; then
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "run" ]; then
    echo "Error: sandbox failed to start" >&2
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_failure
}

# --- Multiple invocations reuse existing running sandbox ---

@test "integration: running sandbox is reused without create or run" {
    # Simulate a sandbox that is already running (from a previous invocation)
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CMD: $*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    # First invocation: build
    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")

    # No sandbox create or run should be called
    local create_count run_count
    create_count=$(echo "$log" | grep -c "sandbox create" || true)
    run_count=$(echo "$log" | grep -c "sandbox run" || true)
    [ "$create_count" -eq 0 ]
    [ "$run_count" -eq 0 ]

    # Only ls and exec should be called
    echo "$log" | grep -q "sandbox ls"
    echo "$log" | grep -q "sandbox exec"
}

@test "integration: second invocation to running sandbox skips create and bootstrap" {
    # Simulate two sequential invocations to a running sandbox
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CMD: $*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    # First invocation
    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    assert_output --partial "ralph build"

    # Reset log for second invocation
    : > "$TEST_WORK_DIR/docker_calls.log"

    # Second invocation with different subcommand
    run "$SCRIPT_DIR/ralph.sh" --docker plan -n 1
    assert_success
    assert_output --partial "ralph plan -n 1"

    # Verify second invocation also skipped create, run, and bootstrap
    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")
    local create_count run_count bash_c_count
    create_count=$(echo "$log" | grep -c "sandbox create" || true)
    run_count=$(echo "$log" | grep -c "sandbox run" || true)
    bash_c_count=$(echo "$log" | grep -c "bash -c" || true)
    [ "$create_count" -eq 0 ]
    [ "$run_count" -eq 0 ]
    [ "$bash_c_count" -eq 0 ]
}

@test "integration: sandbox name is derived consistently across invocations" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CMD: $*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    # First invocation
    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    # The exec call should reference the consistent sandbox name
    assert_output --partial "ralph-test-repo-main"

    # Second invocation
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    assert_output --partial "ralph-test-repo-main"
}
