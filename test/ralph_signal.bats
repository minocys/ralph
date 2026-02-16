#!/usr/bin/env bats
# test/ralph_signal.bats — signal-handling tests for ralph.sh
#
# These tests verify the two-stage Ctrl+C graceful interrupt behavior:
# 1. First SIGINT prints a waiting message and lets claude clean up
# 2. Second SIGINT force-kills everything
# 3. SIGTERM force-kills immediately
#
# Each test creates its own specialized claude stub that responds to signals
# differently, since the default stub from test_helper.bash exits immediately.
#
# Testing signals in bash 3.2 (macOS):
# Background processes (&) inherit SIG_IGN for SIGINT, so `kill -INT $PID`
# cannot trigger trap handlers. To simulate terminal Ctrl+C, we run ralph.sh
# in its own session (via perl setsid) with SIGINT reset to SIG_DFL, then
# send SIGINT to the entire process group with `kill -INT -- -$PGID`.

load test_helper

# Override the default setup to use a no-op git stub and unset CLAUDE_CODE_USE_BEDROCK
# Signal tests need long-running claude stubs, so each test creates its own.
setup() {
    # Create a temp working directory so tests don't touch the real project
    TEST_WORK_DIR="$(mktemp -d)"

    # Minimal specs/ directory with a dummy spec so preflight passes
    mkdir -p "$TEST_WORK_DIR/specs"
    echo "# dummy spec" > "$TEST_WORK_DIR/specs/dummy.md"

    # Dummy IMPLEMENTATION_PLAN.json so build-mode preflight passes
    echo '[]' > "$TEST_WORK_DIR/IMPLEMENTATION_PLAN.json"

    # Stub directory for claude and other commands
    STUB_DIR="$(mktemp -d)"

    # Create a git stub so ralph.sh doesn't need a real git repo
    cat > "$STUB_DIR/git" <<'STUB'
#!/bin/bash
echo "main"
STUB
    chmod +x "$STUB_DIR/git"

    # Prepend stub directory so stubs are found instead of real commands
    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"

    # Ensure no bedrock env var leaks into tests
    unset CLAUDE_CODE_USE_BEDROCK

    # Save dirs for teardown
    export TEST_WORK_DIR
    export STUB_DIR

    # Output capture file for background ralph process
    OUTPUT_FILE="$(mktemp)"
    export OUTPUT_FILE

    # PID file: ralph writes its PID here so we can find its process group
    PID_FILE="$(mktemp)"
    export PID_FILE

    # Change to the temp working directory
    cd "$TEST_WORK_DIR"
}

teardown() {
    # Kill any leftover ralph process group
    if [[ -n "${RALPH_PGID:-}" ]] && kill -0 -- "-$RALPH_PGID" 2>/dev/null; then
        kill -9 -- "-$RALPH_PGID" 2>/dev/null || true
    fi
    # Also try individual PID
    if [[ -n "${RALPH_PID:-}" ]] && kill -0 "$RALPH_PID" 2>/dev/null; then
        kill -9 "$RALPH_PID" 2>/dev/null || true
        wait "$RALPH_PID" 2>/dev/null || true
    fi

    # Restore original PATH
    if [[ -n "$ORIGINAL_PATH" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi

    # Clean up temp directories and files
    rm -f "$OUTPUT_FILE" "$PID_FILE" 2>/dev/null
    if [[ -d "$TEST_WORK_DIR" ]]; then
        rm -rf "$TEST_WORK_DIR"
    fi
    if [[ -d "$STUB_DIR" ]]; then
        rm -rf "$STUB_DIR"
    fi
}

# launch_ralph_in_session: run ralph.sh in its own session so we can
# send process-group-wide SIGINT (simulating terminal Ctrl+C).
# Sets RALPH_PID and RALPH_PGID for the caller.
launch_ralph_in_session() {
    local ralph_args=("$@")

    # Use perl to create a new session (setsid) and reset SIGINT to default.
    # This undoes the SIG_IGN that bash sets for background processes (&),
    # which is critical for bash 3.2 where trap handlers won't fire if
    # SIGINT was SIG_IGN at exec time.
    perl -e '
        use POSIX qw(setsid);
        setsid() or die "setsid: $!";
        $SIG{INT} = "DEFAULT";
        $SIG{TERM} = "DEFAULT";
        exec @ARGV or die "exec: $!";
    ' -- "$SCRIPT_DIR/ralph.sh" "${ralph_args[@]}" > "$OUTPUT_FILE" 2>&1 &
    RALPH_PID=$!

    # The perl setsid makes the child its own session leader,
    # so its PGID equals its PID.
    RALPH_PGID=$RALPH_PID
}

# send_sigint: simulate Ctrl+C by sending SIGINT to the entire process group
send_sigint() {
    kill -INT -- "-$RALPH_PGID" 2>/dev/null || true
}

# send_sigterm: send SIGTERM to the entire process group
send_sigterm() {
    kill -TERM -- "-$RALPH_PGID" 2>/dev/null || true
}

# wait_for_ralph: wait for ralph to exit, returns its exit code
wait_for_ralph() {
    local timeout="${1:-10}"
    local i=0
    while kill -0 "$RALPH_PID" 2>/dev/null && [ "$i" -lt "$((timeout * 10))" ]; do
        sleep 0.1
        i=$((i + 1))
    done
    wait "$RALPH_PID" 2>/dev/null
    return $?
}

# --- Test 1: First Ctrl+C prints waiting message ---

@test "first Ctrl+C prints waiting message" {
    # Create a claude stub that traps SIGINT, sleeps briefly, then exits.
    # The stub must use `sleep & wait` so the sleep is interruptible.
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
trap 'sleep 1; exit 0' INT
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}'
sleep 30 &
wait $!
STUB
    chmod +x "$STUB_DIR/claude"

    # Launch ralph.sh in its own session
    launch_ralph_in_session -n 1

    # Wait for ralph to start and reach the pipeline
    sleep 2

    # Send SIGINT (simulating Ctrl+C) to the process group
    send_sigint

    # Wait for ralph to exit (it should exit 130 after claude cleans up)
    local exit_code=0
    wait_for_ralph 10 || exit_code=$?

    # Check that the waiting message was printed
    local output
    output="$(cat "$OUTPUT_FILE")"

    # The output should contain the waiting/grace message
    [[ "$output" == *"Waiting for claude to finish"* ]]
}

# --- Test 2: Single Ctrl+C exits 130 after claude cleanup ---

@test "single Ctrl+C exits 130 after claude cleanup" {
    # Create a claude stub that traps SIGINT, sleeps 1s for cleanup, then exits 0.
    # This simulates claude receiving INT, performing cleanup, and exiting normally.
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
trap 'sleep 1; exit 0' INT
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}'
sleep 30 &
wait $!
STUB
    chmod +x "$STUB_DIR/claude"

    # Launch ralph.sh in its own session
    launch_ralph_in_session -n 1

    # Wait for ralph to start and reach the pipeline
    sleep 2

    # Send a single SIGINT (simulating Ctrl+C) to the process group
    send_sigint

    # Wait for ralph to exit on its own (claude should finish cleanup in ~1s)
    local exit_code=0
    wait_for_ralph 10 || exit_code=$?

    # ralph should exit with code 130 (standard SIGINT exit code)
    [ "$exit_code" -eq 130 ]

    # Verify the ralph process is actually gone
    ! kill -0 "$RALPH_PID" 2>/dev/null
}
