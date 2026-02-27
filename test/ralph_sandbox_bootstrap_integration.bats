#!/usr/bin/env bats
# test/ralph_sandbox_bootstrap_integration.bats — Integration tests for sandbox bootstrap via ralph.sh --docker
#
# These tests exercise the full dispatch path (ralph.sh --docker <cmd>)
# and verify bootstrap behavior end-to-end: fresh sandbox creation,
# idempotent skip when marker exists, stopped-sandbox restart, and
# bootstrap failure semantics.

load test_helper

setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    mkdir -p "$TEST_WORK_DIR/specs"
    echo "# dummy spec" > "$TEST_WORK_DIR/specs/dummy.md"

    STUB_DIR="$(mktemp -d)"

    # claude stub (not used in --docker path, but needed on PATH)
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    # pg_isready stub
    cat > "$STUB_DIR/pg_isready" <<'PGSTUB'
#!/bin/bash
exit 0
PGSTUB
    chmod +x "$STUB_DIR/pg_isready"

    # jq must be the real jq (needed for lookup_sandbox JSON parsing)
    # — it's already on the original PATH

    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"
    export TEST_WORK_DIR
    export STUB_DIR

    # Prevent detect_backend() from reading host ~/.claude/settings.json
    export HOME="$TEST_WORK_DIR"
    unset CLAUDE_CODE_USE_BEDROCK

    cd "$TEST_WORK_DIR"
}

teardown() {
    if [[ -n "$ORIGINAL_PATH" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    if [[ -d "$TEST_WORK_DIR" ]]; then
        rm -rf "$TEST_WORK_DIR"
    fi
    if [[ -d "$STUB_DIR" ]]; then
        rm -rf "$STUB_DIR"
    fi
}

# =============================================================================
# Integration: fresh sandbox gets full bootstrap
# =============================================================================

@test "fresh sandbox: full lifecycle runs create, run, bootstrap, then exec" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CMD: $*" >> "$TEST_WORK_DIR/docker_calls.log"

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

# sandbox exec
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    # Marker check: not yet bootstrapped
    if echo "$*" | grep -q "test -f"; then
        exit 1
    fi
    # Bootstrap install script or final exec — both succeed
    echo "EXEC: $*"
    exit 0
fi

exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    # Verify all lifecycle steps are present in order
    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")

    # Extract line numbers for ordering verification
    local ls_line create_line run_line first_exec_line
    ls_line=$(echo "$log" | grep -n "sandbox ls" | head -1 | cut -d: -f1)
    create_line=$(echo "$log" | grep -n "sandbox create" | head -1 | cut -d: -f1)
    run_line=$(echo "$log" | grep -n "sandbox run" | head -1 | cut -d: -f1)
    first_exec_line=$(echo "$log" | grep -n "sandbox exec" | head -1 | cut -d: -f1)

    # All steps must be present
    [ -n "$ls_line" ]
    [ -n "$create_line" ]
    [ -n "$run_line" ]
    [ -n "$first_exec_line" ]

    # Ordering: ls → create → run → exec
    [ "$ls_line" -lt "$create_line" ]
    [ "$create_line" -lt "$run_line" ]
    [ "$run_line" -lt "$first_exec_line" ]
}

@test "fresh sandbox: bootstrap installs ralph and starts postgres" {
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
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    # Verify bootstrap install script contents via the logged exec call
    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")

    # Bootstrap script copies ralph.sh to /usr/local/bin
    echo "$log" | grep -q 'cp "$RALPH_MOUNT/ralph.sh" /usr/local/bin/ralph'
    # Bootstrap script installs jq
    echo "$log" | grep -q "apt-get install.*jq"
    # Bootstrap script installs postgresql-client
    echo "$log" | grep -q "apt-get install.*postgresql-client"
    # Bootstrap script starts postgres
    echo "$log" | grep -q "compose -f ~/.ralph/docker-compose.yml up -d"
    # Bootstrap script writes marker
    echo "$log" | grep -q "touch ~/.ralph/.bootstrapped"
}

@test "fresh sandbox: bootstrap uses set -e for fail-fast" {
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
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")
    # The bootstrap exec script starts with set -e
    echo "$log" | grep -q "set -e"
}

@test "fresh sandbox: final exec runs ralph with forwarded subcommand" {
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
    echo "EXEC_OUTPUT: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker plan -n 2 --model opus-4.5
    assert_success
    # The final exec (via exec docker sandbox exec ...) should forward the subcommand
    assert_output --partial "ralph plan -n 2 --model opus-4.5"
}

# =============================================================================
# Integration: existing bootstrapped sandbox skips bootstrap
# =============================================================================

@test "bootstrapped sandbox: skips bootstrap when marker exists (new sandbox)" {
    # Even though sandbox doesn't exist yet and must be created, if the marker
    # check passes after run (i.e., sandbox was pre-bootstrapped somehow),
    # bootstrap install script should not run.
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
    # Marker exists — bootstrap already done
    if echo "$*" | grep -q "test -f"; then
        exit 0
    fi
    echo "EXEC_OUTPUT: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")

    # The install script uses "set -e" — verify it was NOT invoked
    local install_count
    install_count=$(echo "$log" | grep -c "set -e" || true)
    [ "$install_count" -eq 0 ]
}

@test "bootstrapped sandbox: running sandbox with marker goes straight to exec" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "$*" >> "$TEST_WORK_DIR/docker_calls.log"

if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_OUTPUT: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")

    # No create, no run, no bootstrap
    local create_count run_count install_count
    create_count=$(echo "$log" | grep -c "sandbox create" || true)
    run_count=$(echo "$log" | grep -c "sandbox run" || true)
    install_count=$(echo "$log" | grep -c "set -e" || true)
    [ "$create_count" -eq 0 ]
    [ "$run_count" -eq 0 ]
    [ "$install_count" -eq 0 ]

    # Only ls + exec
    echo "$log" | grep -q "sandbox ls"
    echo "$log" | grep -q "sandbox exec"
    # Final exec forwards the ralph command
    assert_output --partial "ralph build"
}

@test "bootstrapped sandbox: no bootstrap marker check for already running sandbox" {
    # When sandbox is already running, dispatch goes directly to credential
    # resolution and exec — no bootstrap_sandbox() is called at all.
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "$*" >> "$TEST_WORK_DIR/docker_calls.log"

if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_OUTPUT: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")

    # No marker check (test -f) for already running sandbox
    local marker_check_count
    marker_check_count=$(echo "$log" | grep -c "test -f" || true)
    [ "$marker_check_count" -eq 0 ]
}

# =============================================================================
# Integration: stopped sandbox restart does not re-bootstrap
# =============================================================================

@test "stopped sandbox: restart does not run bootstrap" {
    # A stopped sandbox that was previously bootstrapped should just be started
    # and exec'd — no create, no bootstrap.
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "$*" >> "$TEST_WORK_DIR/docker_calls.log"

if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"stopped"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "run" ]; then
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_OUTPUT: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")

    # No create
    local create_count
    create_count=$(echo "$log" | grep -c "sandbox create" || true)
    [ "$create_count" -eq 0 ]

    # No bootstrap (no marker check, no install script)
    local marker_count install_count
    marker_count=$(echo "$log" | grep -c "test -f" || true)
    install_count=$(echo "$log" | grep -c "set -e" || true)
    [ "$marker_count" -eq 0 ]
    [ "$install_count" -eq 0 ]

    # Run was called (restart)
    echo "$log" | grep -q "sandbox run"
    # Final exec forwards command
    assert_output --partial "ralph build"
}

@test "stopped sandbox: run is called before exec" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "STEP: $1 $2" >> "$TEST_WORK_DIR/docker_calls.log"

if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"stopped"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "run" ]; then
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_OUTPUT: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")

    local run_line exec_line
    run_line=$(echo "$log" | grep -n "sandbox run" | head -1 | cut -d: -f1)
    exec_line=$(echo "$log" | grep -n "sandbox exec" | head -1 | cut -d: -f1)

    [ -n "$run_line" ]
    [ -n "$exec_line" ]
    [ "$run_line" -lt "$exec_line" ]
}

@test "stopped sandbox: no bootstrap means postgres restarts via Docker restart policy" {
    # Verify that the stopped-sandbox restart path does NOT call docker compose up
    # (postgres restarts automatically via Docker daemon restart policy inside sandbox)
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "$*" >> "$TEST_WORK_DIR/docker_calls.log"

if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"stopped"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "run" ]; then
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_OUTPUT: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")

    # No compose up call in the dispatch path for stopped sandbox restart
    local compose_count
    compose_count=$(echo "$log" | grep -c "compose.*up" || true)
    [ "$compose_count" -eq 0 ]
}

# =============================================================================
# Integration: bootstrap failure does not write marker
# =============================================================================

@test "bootstrap failure: exec failure propagates to ralph exit" {
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
    # Marker check: not bootstrapped
    if echo "$*" | grep -q "test -f"; then
        exit 1
    fi
    # Bootstrap install script fails (simulating apt-get failure, etc.)
    if echo "$*" | grep -q "bash -c"; then
        exit 1
    fi
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    # ralph.sh should exit with failure because bootstrap_sandbox calls
    # docker sandbox exec which returns non-zero
    assert_failure
}

@test "bootstrap failure: marker is not written when install script fails" {
    # The bootstrap script uses set -e. If any command fails (e.g., apt-get),
    # the script exits before reaching 'touch ~/.ralph/.bootstrapped'.
    # We verify the script structure: set -e is present, and the marker write
    # comes after all install commands (so a mid-script failure prevents it).
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
    # Succeed to capture the script contents
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")

    # The bootstrap script is multi-line in the log (docker stub logs all args).
    # Verify key structural properties across the full log:

    # 1. set -e is present (fail-fast)
    echo "$log" | grep -q "set -e"
    # 2. touch marker is present
    echo "$log" | grep -q "touch ~/.ralph/.bootstrapped"

    # 3. set -e comes before marker write (line number ordering)
    local sete_line marker_line compose_line
    sete_line=$(echo "$log" | grep -n "set -e" | head -1 | cut -d: -f1)
    marker_line=$(echo "$log" | grep -n "touch ~/.ralph/.bootstrapped" | head -1 | cut -d: -f1)
    compose_line=$(echo "$log" | grep -n "compose -f" | head -1 | cut -d: -f1)

    # set -e must appear before compose up and marker write
    [ "$sete_line" -lt "$compose_line" ]
    # marker write must appear after compose up (last step)
    [ "$compose_line" -lt "$marker_line" ]
}

@test "bootstrap failure: no final exec when bootstrap fails" {
    # Track exec calls to distinguish bootstrap exec from final command exec
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "CALL: $*" >> "$TEST_WORK_DIR/docker_calls.log"

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
    # Marker check: not bootstrapped
    if echo "$*" | grep -q "test -f"; then
        exit 1
    fi
    # Bootstrap install script fails
    if echo "$*" | grep -q "bash -c"; then
        exit 1
    fi
    # Final exec (this should NOT be reached if bootstrap fails)
    echo "FINAL_EXEC_REACHED: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_failure
    # The final exec (ralph build) should never have been reached
    refute_output --partial "FINAL_EXEC_REACHED"
}

@test "bootstrap failure: create and run succeed but bootstrap exec failure exits ralph" {
    # Verify that even when create and run succeed, a bootstrap failure
    # causes ralph to exit without proceeding to the exec step
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "STEP: $1 $2 $(echo "$*" | head -c 80)" >> "$TEST_WORK_DIR/docker_calls.log"

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
    # Bootstrap fails
    if echo "$*" | grep -q "bash -c"; then
        echo "Bootstrap failed: apt-get install failed" >&2
        exit 1
    fi
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_failure

    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")

    # Create and run should have been called
    echo "$log" | grep -q "sandbox create"
    echo "$log" | grep -q "sandbox run"

    # Bootstrap exec was attempted
    echo "$log" | grep -q "sandbox exec"

    # But the ralph process exited with failure
    [ "$status" -ne 0 ]
}
