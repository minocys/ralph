#!/bin/bash
# lib/build_loop.sh — build-mode iteration loop for ralph.sh
#
# Provides:
#   setup_session()    — initialize session state + register build agent
#   run_build_loop()   — execute the build-mode iteration loop
#
# Requires lib/session.sh (provides setup_session_core, sourced below).
#
# Globals set by setup_session:
#   ITERATION, CURRENT_BRANCH, TMPFILE, TASK_SCRIPT, AGENT_ID
# Exports set by setup_session:
#   RALPH_SCOPE_REPO, RALPH_SCOPE_BRANCH (derived via task _get-scope)
#   RALPH_TASK_SCRIPT, RALPH_AGENT_ID
# Globals used (must be set before calling run_build_loop):
#   MODE, COMMAND, MAX_ITERATIONS, ITERATION, DANGER, RESOLVED_MODEL,
#   TASK_SCRIPT, AGENT_ID, TMPFILE, JQ_FILTER, INTERRUPTED, PIPELINE_PID
#
# Note: INTERRUPTED and PIPELINE_PID are modified by signal handlers in
# lib/signals.sh and must remain global (not declared local here).

# shellcheck source=lib/session.sh
. "$SCRIPT_DIR/lib/session.sh"

# setup_session: extend the shared setup with build-mode agent registration.
# Overrides the function from session.sh — must be defined after sourcing.
setup_session() {
    # Shared initialisation (iteration, branch, tmpfile, scope)
    setup_session_core

    # Register agent in build mode if task script is available
    if [ -x "$TASK_SCRIPT" ]; then
        AGENT_ID=$("$TASK_SCRIPT" agent register 2>/dev/null) || true
        if [ -n "$AGENT_ID" ]; then
            export RALPH_AGENT_ID="$AGENT_ID"
        fi
    fi
}

# check_all_tasks_complete: returns 0 if open and active task counts are both 0,
# returns 1 otherwise (tasks remain, plan-status failed, or TASK_SCRIPT not executable).
check_all_tasks_complete() {
    if [ ! -x "$TASK_SCRIPT" ]; then
        return 1
    fi
    local PLAN_STATUS
    PLAN_STATUS=$("$TASK_SCRIPT" plan-status 2>/dev/null) || return 1
    if [ -z "$PLAN_STATUS" ]; then
        return 1
    fi
    local OPEN_COUNT ACTIVE_COUNT
    OPEN_COUNT=$(echo "$PLAN_STATUS" | grep -oE '^[0-9]+' | head -1)
    ACTIVE_COUNT=$(echo "$PLAN_STATUS" | grep -oE '[0-9]+ active' | grep -oE '^[0-9]+')
    if [ "${OPEN_COUNT:-1}" -eq 0 ] 2>/dev/null && [ "${ACTIVE_COUNT:-1}" -eq 0 ] 2>/dev/null; then
        return 0
    fi
    return 1
}

# run_build_loop: execute the build-mode iteration loop
# Pre-invocation completion check, Claude invocation, crash-safety fallback,
# and post-invocation completion check for loop termination.
run_build_loop() {
    while true; do
        if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -ge $MAX_ITERATIONS ]; then
            echo "Reached max iterations: $MAX_ITERATIONS"
            break
        fi

        # Pre-invocation completion check: exit if all tasks are done
        if check_all_tasks_complete; then
            echo "All tasks complete. Exiting loop."
            break
        fi

        # Build Claude argument list for this iteration
        local CLAUDE_ARGS=(-p "$COMMAND" --output-format=stream-json --verbose)
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

        # Crash-safety fallback: fail all active tasks assigned to this agent
        if [ -x "$TASK_SCRIPT" ] && [ -n "$AGENT_ID" ]; then
            local active_output
            active_output=$("$TASK_SCRIPT" list --status active --assignee "$AGENT_ID" --markdown 2>/dev/null || true)
            # Extract all task slugs from "id: <slug>" lines in the markdown-KV output.
            local active_id
            echo "$active_output" | awk '/^id: /{print substr($0,5)}' | while IFS= read -r active_id; do
                if [ -n "$active_id" ]; then
                    "$TASK_SCRIPT" fail "$active_id" --reason 'session exited without completing task' 2>/dev/null || true
                fi
            done
        fi

        # Post-invocation completion check: exit if all tasks are done
        if check_all_tasks_complete; then
            echo "All tasks complete. Exiting loop."
            exit 0
        fi

        ITERATION=$((ITERATION + 1))
        printf "\n\n======================== LOOP %d ========================\n" "$ITERATION"
    done
}
