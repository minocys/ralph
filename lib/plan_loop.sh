#!/bin/bash
# lib/plan_loop.sh — plan-mode iteration loop for ralph.sh
#
# Provides:
#   run_plan_loop()   — execute the plan-mode iteration loop
#
# Requires lib/session.sh to be sourced first (provides setup_session).
#
# Globals used (must be set before calling run_plan_loop):
#   MODE, COMMAND, MAX_ITERATIONS, ITERATION, DANGER, RESOLVED_MODEL,
#   TASK_SCRIPT, TMPFILE, JQ_FILTER, INTERRUPTED, PIPELINE_PID
#
# Note: INTERRUPTED and PIPELINE_PID are modified by signal handlers in
# lib/signals.sh and must remain global (not declared local here).

# shellcheck source=lib/session.sh
. "$SCRIPT_DIR/lib/session.sh"

# setup_session: plan mode needs only the shared core (no agent registration).
setup_session() {
    setup_session_core
}

# run_plan_loop: execute the plan-mode iteration loop
# Runs exactly MAX_ITERATIONS times (default 1). No crash-safety fallback
# needed — the planner does not claim tasks.
run_plan_loop() {
    for (( i=1; i<=MAX_ITERATIONS; i++ )); do
        # Pre-fetch: get current task DAG for planner
        local LIST_ALL_MD=""
        if [ -x "$TASK_SCRIPT" ]; then
            LIST_ALL_MD=$("$TASK_SCRIPT" list --all --markdown 2>/dev/null) || true
        fi

        # Build Claude argument list for this iteration
        local CLAUDE_ARGS
        if [ -n "$LIST_ALL_MD" ]; then
            CLAUDE_ARGS=(-p "$COMMAND $LIST_ALL_MD" --output-format=stream-json --verbose)
        else
            CLAUDE_ARGS=(-p "$COMMAND" --output-format=stream-json --verbose)
        fi
        $DANGER && CLAUDE_ARGS+=(--dangerously-skip-permissions)
        [ -n "$RESOLVED_MODEL" ] && CLAUDE_ARGS+=(--model "$RESOLVED_MODEL")

        # Reset interrupt counter for this iteration
        INTERRUPTED=0

        # Run pipeline in background subshell so wait is interruptible by signals
        ( claude "${CLAUDE_ARGS[@]}" | tee "$TMPFILE" | jq --unbuffered -rj "$JQ_FILTER" ) &
        PIPELINE_PID=$!

        # Wait for pipeline; re-wait after first interrupt to let claude finish
        while kill -0 "$PIPELINE_PID" 2>/dev/null; do
            wait "$PIPELINE_PID" 2>/dev/null || true
        done
        wait "$PIPELINE_PID" 2>/dev/null
        PIPELINE_PID=""

        # If interrupted, exit 130 — do not continue to next iteration
        if [ "$INTERRUPTED" -gt 0 ]; then
            exit 130
        fi

        ITERATION=$((ITERATION + 1))
        printf "\n\n======================== LOOP %d ========================\n" "$ITERATION"
    done
    echo "Reached max iterations: $MAX_ITERATIONS"
}
