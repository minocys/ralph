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

    # Copy ralph.sh and lib/ into the test work directory so SCRIPT_DIR
    # resolves to TEST_WORK_DIR (avoids using the real task script/DB)
    cp "$SCRIPT_DIR/ralph.sh" "$TEST_WORK_DIR/ralph.sh"
    chmod +x "$TEST_WORK_DIR/ralph.sh"
    cp -r "$SCRIPT_DIR/lib" "$TEST_WORK_DIR/lib"

    # Minimal specs/ directory with a dummy spec so preflight passes
    mkdir -p "$TEST_WORK_DIR/specs"
    echo "# dummy spec" > "$TEST_WORK_DIR/specs/dummy.md"

    # Task stub so the build loop doesn't exit early on empty peek
    cat > "$TEST_WORK_DIR/task" <<'TASKSTUB'
#!/bin/bash
case "$1" in
    agent)
        case "$2" in
            register) echo "t001"; exit 0 ;;
            deregister) exit 0 ;;
            *) exit 0 ;;
        esac
        ;;
    peek)
        echo '{"id":"dummy-001","t":"Dummy task","s":"open","p":2}'
        exit 0
        ;;
    plan-status)
        echo "1 open, 0 active, 0 done, 0 blocked, 0 deleted"
        exit 0
        ;;
    list|fail)
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
TASKSTUB
    chmod +x "$TEST_WORK_DIR/task"

    # Stub directory for claude and other commands
    STUB_DIR="$(mktemp -d)"

    # Create a git stub so ralph.sh doesn't need a real git repo
    cat > "$STUB_DIR/git" <<'STUB'
#!/bin/bash
echo "main"
STUB
    chmod +x "$STUB_DIR/git"

    # Docker/pg_isready stubs so ensure_postgres passes quickly
    cat > "$STUB_DIR/docker" <<'DOCKERSTUB'
#!/bin/bash
case "$1" in
    compose)
        if [ "$2" = "version" ]; then echo "Docker Compose version v2.24.0"; fi
        exit 0 ;;
    inspect)
        if [ "$3" = "{{.State.Running}}" ]; then echo "true"
        elif [ "$3" = "{{.State.Health.Status}}" ]; then echo "healthy"; fi
        exit 0 ;;
esac
exit 0
DOCKERSTUB
    chmod +x "$STUB_DIR/docker"
    cat > "$STUB_DIR/pg_isready" <<'PGSTUB'
#!/bin/bash
exit 0
PGSTUB
    chmod +x "$STUB_DIR/pg_isready"

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

    # Tracker file: mktemp stub records created temp file paths here
    TMPFILE_TRACKER="$(mktemp)"
    export TMPFILE_TRACKER

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
    rm -f "$OUTPUT_FILE" "$PID_FILE" "$TMPFILE_TRACKER" 2>/dev/null
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
    ' -- "$TEST_WORK_DIR/ralph.sh" "${ralph_args[@]}" > "$OUTPUT_FILE" 2>&1 &
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

# wait_for_pipeline: poll OUTPUT_FILE until the claude stub's output appears,
# proving the background pipeline (claude | tee | jq) is running and signal
# handlers are installed. Replaces the fixed `sleep 2` that caused
# intermittent failures on loaded macOS systems.
wait_for_pipeline() {
    local timeout="${1:-10}"
    local i=0
    while ! grep -q "working" "$OUTPUT_FILE" 2>/dev/null && [ "$i" -lt "$((timeout * 10))" ]; do
        sleep 0.1
        i=$((i + 1))
    done
    grep -q "working" "$OUTPUT_FILE" 2>/dev/null
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

    # Wait for ralph's pipeline to start (claude stub produces "working")
    wait_for_pipeline

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

    # Wait for ralph's pipeline to start (claude stub produces "working")
    wait_for_pipeline

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

# --- Test 3: Second Ctrl+C force-kills and exits 130 ---

@test "second Ctrl+C force-kills and exits 130" {
    # Create a claude stub that traps INT and IGNORES it (stays alive forever).
    # This simulates a claude process that won't exit on its own after SIGINT.
    # The only way to stop it is ralph's second-INT force-kill mechanism.
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
trap '' INT
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}'
while true; do sleep 1; done
STUB
    chmod +x "$STUB_DIR/claude"

    # Launch ralph.sh in its own session
    launch_ralph_in_session -n 1

    # Wait for ralph's pipeline to start (claude stub produces "working")
    wait_for_pipeline

    # First SIGINT: ralph should print waiting message but NOT exit
    # (because the claude stub ignores INT and stays alive)
    send_sigint

    # Brief pause to let the first INT handler fire and print the message
    sleep 1

    # Second SIGINT: ralph should force-kill everything and exit 130
    send_sigint

    # Wait for ralph to exit
    local exit_code=0
    wait_for_ralph 10 || exit_code=$?

    # ralph should exit with code 130
    [ "$exit_code" -eq 130 ]

    # Verify the ralph process is actually gone
    ! kill -0 "$RALPH_PID" 2>/dev/null
}

# --- Test 4: Temp file is cleaned up after force-kill ---

@test "temp file cleaned up after double Ctrl+C" {
    # Create a mktemp stub that delegates to real mktemp but records paths.
    # ralph.sh calls mktemp once to create TMPFILE; the EXIT trap removes it.
    # This test verifies that the EXIT trap fires even after force-kill (exit 130).
    cat > "$STUB_DIR/mktemp" <<STUB
#!/bin/bash
result=\$(/usr/bin/mktemp "\$@")
echo "\$result" >> "$TMPFILE_TRACKER"
echo "\$result"
STUB
    chmod +x "$STUB_DIR/mktemp"

    # Create a claude stub that traps INT and ignores it (stays alive forever).
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
trap '' INT
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}'
while true; do sleep 1; done
STUB
    chmod +x "$STUB_DIR/claude"

    # Launch ralph.sh in its own session
    launch_ralph_in_session -n 1

    # Wait for ralph's pipeline to start (claude stub produces "working")
    wait_for_pipeline

    # Verify at least one temp file was recorded by the mktemp stub
    [ -s "$TMPFILE_TRACKER" ]

    # Remember the temp file paths before kill
    local tracked_files
    tracked_files="$(cat "$TMPFILE_TRACKER")"

    # Double Ctrl+C: force-kill
    send_sigint
    sleep 1
    send_sigint

    # Wait for ralph to exit
    wait_for_ralph 10 || true

    # Assert every temp file recorded by mktemp stub has been cleaned up
    local f
    while IFS= read -r f; do
        [ -n "$f" ] && ! [ -e "$f" ]
    done <<< "$tracked_files"
}

# --- Test 5: SIGTERM force-kills immediately ---

@test "SIGTERM force-kills immediately and exits 130" {
    # Create a claude stub that stays alive (traps nothing, just sleeps).
    # SIGTERM to the group should kill everything immediately.
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}'
sleep 30 &
wait $!
STUB
    chmod +x "$STUB_DIR/claude"

    # Launch ralph.sh in its own session
    launch_ralph_in_session -n 1

    # Wait for ralph's pipeline to start (claude stub produces "working")
    wait_for_pipeline

    # Send SIGTERM (no grace period expected)
    send_sigterm

    # Wait for ralph to exit — should be fast (no waiting for claude cleanup)
    local exit_code=0
    wait_for_ralph 5 || exit_code=$?

    # ralph should exit with code 130
    [ "$exit_code" -eq 130 ]

    # Verify the ralph process is actually gone
    ! kill -0 "$RALPH_PID" 2>/dev/null

    # Check output does NOT contain the "Waiting for claude" message
    # (SIGTERM should force-kill, not enter graceful mode)
    local output
    output="$(cat "$OUTPUT_FILE")"
    [[ "$output" != *"Waiting for claude to finish"* ]]
}
