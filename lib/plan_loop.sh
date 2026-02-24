#!/bin/bash
# lib/plan_loop.sh — plan-mode session setup and iteration loop for ralph.sh
#
# Provides:
#   setup_session()   — initialize session state (iteration counter, branch, tmpfile, scope)
#   run_plan_loop()   — execute the plan-mode iteration loop
#
# Globals set by setup_session:
#   ITERATION, CURRENT_BRANCH, TMPFILE, TASK_SCRIPT
# Exports set by setup_session:
#   RALPH_SCOPE_REPO, RALPH_SCOPE_BRANCH (derived via task _get-scope)
#   RALPH_TASK_SCRIPT
# Globals used (must be set before calling run_plan_loop):
#   MODE, COMMAND, MAX_ITERATIONS, ITERATION, DANGER, RESOLVED_MODEL,
#   TASK_SCRIPT, TMPFILE, JQ_FILTER, INTERRUPTED, PIPELINE_PID
#
# Note: INTERRUPTED and PIPELINE_PID are modified by signal handlers in
# lib/signals.sh and must remain global (not declared local here).

# setup_session: initialize session state for the main loop
# Shared between plan and build modes — both files include this function.
setup_session() {
    ITERATION=0
    CURRENT_BRANCH=$(git branch --show-current)
    TMPFILE=$(mktemp)
    AGENT_ID=""

    TASK_SCRIPT="$SCRIPT_DIR/lib/task"
    export RALPH_TASK_SCRIPT="$TASK_SCRIPT"

    # Derive and export scope so all subprocesses (task, claude) inherit it.
    # Uses `task _get-scope` to avoid duplicating URL-parsing logic.
    if [ -x "$TASK_SCRIPT" ]; then
        local scope_output
        if scope_output=$("$TASK_SCRIPT" _get-scope 2>/dev/null); then
            export RALPH_SCOPE_REPO
            RALPH_SCOPE_REPO=$(echo "$scope_output" | grep '^repo:' | cut -d: -f2-)
            export RALPH_SCOPE_BRANCH
            RALPH_SCOPE_BRANCH=$(echo "$scope_output" | grep '^branch:' | cut -d: -f2-)
        fi
    fi
}

# run_plan_loop: execute the plan-mode iteration loop
# Runs exactly MAX_ITERATIONS times (default 1). No crash-safety fallback
# needed — the planner does not claim tasks.
run_plan_loop() {
    while true; do
        if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -ge $MAX_ITERATIONS ]; then
            echo "Reached max iterations: $MAX_ITERATIONS"
            break
        fi

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

        # Plan-mode completion check: sentinel in last assistant message
        if jq -s '[.[] | select(.type == "assistant")] | last | .message.content[]? | select(.type == "text") | .text' "$TMPFILE" 2>/dev/null \
          | grep -q '<promise>Tastes Like Burning.</promise>'; then
            echo "Ralph completed successfully. Exiting loop."
            echo "Completed at iteration $ITERATION of $MAX_ITERATIONS"
            exit 0
        fi

        ITERATION=$((ITERATION + 1))
        printf "\n\n======================== LOOP %d ========================\n" "$ITERATION"
    done
}
