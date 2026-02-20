#!/bin/bash
# lib/signals.sh — cleanup and signal-handling functions for ralph.sh
#
# Provides:
#   setup_cleanup_trap()     — register EXIT trap to deregister agent and remove tmpfile
#   setup_signal_handlers()  — register INT/TERM traps for graceful/force interrupt
#   handle_int()             — two-stage Ctrl+C handler
#   handle_term()            — immediate force-kill on SIGTERM
#
# Globals used (must be set before calling setup functions):
#   AGENT_ID, TASK_SCRIPT, TMPFILE, INTERRUPTED, PIPELINE_PID

# cleanup: EXIT trap handler — deregister agent and remove tmpfile
cleanup() {
    # Deregister agent if one was registered
    if [ -n "$AGENT_ID" ] && [ -x "$TASK_SCRIPT" ]; then
        "$TASK_SCRIPT" agent deregister "$AGENT_ID" 2>/dev/null || true
    fi
    rm -f "$TMPFILE"
}

# setup_cleanup_trap: register cleanup() as the EXIT trap
setup_cleanup_trap() {
    trap cleanup EXIT
}

# handle_int: two-stage Ctrl+C handler
# First INT lets claude clean up; second INT force-kills.
handle_int() {
    INTERRUPTED=$((INTERRUPTED + 1))
    if [ "$INTERRUPTED" -ge 2 ]; then
        # Second Ctrl+C: force-kill pipeline and exit
        trap - INT TERM
        [ -n "$PIPELINE_PID" ] && kill -9 -- -$PIPELINE_PID 2>/dev/null
        exit 130
    fi
    # First Ctrl+C: print waiting message, let claude finish
    echo ""
    echo "Waiting for claude to finish cleanup... Press Ctrl+C again to force quit."
}

# handle_term: SIGTERM force-kill handler
# SIGTERM: force-kill pipeline immediately, no grace period.
handle_term() {
    trap - INT TERM
    if [ -n "$PIPELINE_PID" ]; then
        kill -9 -- -$PIPELINE_PID 2>/dev/null
    fi
    exit 130
}

# setup_signal_handlers: initialize interrupt state and register INT/TERM traps
setup_signal_handlers() {
    INTERRUPTED=0
    PIPELINE_PID=""
    trap handle_int INT
    trap handle_term TERM
}
