#!/bin/bash
# lib/loop.sh — main iteration loop for ralph.sh
#
# Provides:
#   setup_session() — initialize session state (iteration counter, branch, tmpfile, agent)
#   run_loop()      — execute the main ralph build/plan iteration loop
#
# Globals set by setup_session:
#   ITERATION, CURRENT_BRANCH, TMPFILE, TASK_SCRIPT, AGENT_ID
# Globals used (must be set before calling run_loop):
#   MODE, COMMAND, MAX_ITERATIONS, ITERATION, DANGER, RESOLVED_MODEL,
#   TASK_SCRIPT, AGENT_ID, TMPFILE, JQ_FILTER, INTERRUPTED, PIPELINE_PID,
#   RALPH_EXEC_MODE, RALPH_WORK_DIR
#
# Note: INTERRUPTED and PIPELINE_PID are modified by signal handlers in
# lib/signals.sh and must remain global (not declared local here).

# setup_session: initialize session state for the main loop
setup_session() {
    ITERATION=0
    CURRENT_BRANCH=$(git branch --show-current)
    TMPFILE=$(mktemp)
    AGENT_ID=""

    TASK_SCRIPT="$SCRIPT_DIR/task"
    export RALPH_TASK_SCRIPT="$TASK_SCRIPT"

    # Register agent in build mode if task script is available
    if [ "$MODE" = "build" ] && [ -x "$TASK_SCRIPT" ]; then
        AGENT_ID=$("$TASK_SCRIPT" agent register 2>/dev/null) || true
        if [ -n "$AGENT_ID" ]; then
            export RALPH_AGENT_ID="$AGENT_ID"
        fi
    fi
}

# run_loop: execute the main ralph build/plan iteration loop
run_loop() {
    while true; do
        if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -ge $MAX_ITERATIONS ]; then
            echo "Reached max iterations: $MAX_ITERATIONS"
            break
        fi

        # Pre-invocation task peek: get claimable + active tasks snapshot
        local PEEK_MD=""
        local PEEK_OK=false
        if [ "$MODE" = "build" ] && [ -x "$TASK_SCRIPT" ]; then
            if PEEK_MD=$("$TASK_SCRIPT" peek -n 10 2>/dev/null); then
                PEEK_OK=true
            fi
        fi

        # Plan-mode pre-fetch: get current task DAG for planner
        local PLAN_EXPORT_MD=""
        if [ "$MODE" = "plan" ] && [ -x "$TASK_SCRIPT" ]; then
            PLAN_EXPORT_MD=$("$TASK_SCRIPT" plan-export --markdown 2>/dev/null) || true
        fi

        # In build mode, exit if peek succeeded but returned empty (no tasks)
        # If peek failed (non-zero exit), treat as transient and continue
        if [ "$MODE" = "build" ] && [ -x "$TASK_SCRIPT" ] && $PEEK_OK && [ -z "$PEEK_MD" ]; then
            echo "No tasks available. Exiting loop."
            break
        fi

        # Build Claude argument list for this iteration
        local CLAUDE_ARGS
        if [ -n "$PEEK_MD" ]; then
            CLAUDE_ARGS=(-p "$COMMAND $PEEK_MD" --output-format=stream-json --verbose)
        elif [ "$MODE" = "plan" ] && [ -n "$PLAN_EXPORT_MD" ]; then
            CLAUDE_ARGS=(-p "$COMMAND $PLAN_EXPORT_MD" --output-format=stream-json --verbose)
        else
            CLAUDE_ARGS=(-p "$COMMAND" --output-format=stream-json --verbose)
        fi
        $DANGER && CLAUDE_ARGS+=(--dangerously-skip-permissions)
        [ -n "$RESOLVED_MODEL" ] && CLAUDE_ARGS+=(--model "$RESOLVED_MODEL")
        [[ "${RALPH_WORK_DIR:-}" == */.ralph/worktrees/* ]] && CLAUDE_ARGS+=(--project-directory "$RALPH_WORK_DIR")

        # Reset interrupt counter for this iteration
        INTERRUPTED=0

        # Build the claude command based on execution mode
        local CLAUDE_CMD
        if [ "${RALPH_EXEC_MODE:-local}" = "docker" ]; then
            CLAUDE_CMD=(docker exec ralph-worker claude)
        else
            CLAUDE_CMD=(claude)
        fi

        # Run pipeline in background subshell so wait is interruptible by signals
        ( "${CLAUDE_CMD[@]}" "${CLAUDE_ARGS[@]}" | tee "$TMPFILE" | jq --unbuffered -rj "$JQ_FILTER" ) &
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

        # Crash-safety fallback: fail active tasks assigned to this agent
        if [ "$MODE" = "build" ] && [ -x "$TASK_SCRIPT" ] && [ -n "$AGENT_ID" ]; then
            local ACTIVE_TASKS
            # Table format: ID is $1, AGENT is $NF (last column).
            # Relies on agent IDs not appearing as last word of multi-word titles.
            ACTIVE_TASKS=$("$TASK_SCRIPT" list --status active 2>/dev/null | awk -v agent="$AGENT_ID" '$NF == agent { print $1 }') || true
            local ACTIVE_ID
            while IFS= read -r ACTIVE_ID; do
                [ -z "$ACTIVE_ID" ] && continue
                "$TASK_SCRIPT" fail "$ACTIVE_ID" --reason 'session exited without completing task' 2>/dev/null || true
            done <<< "$ACTIVE_TASKS"
        fi

        if [ "$MODE" = "plan" ]; then
            if jq -s '[.[] | select(.type == "assistant")] | last | .message.content[]? | select(.type == "text") | .text' "$TMPFILE" 2>/dev/null \
              | grep -q '<promise>Tastes Like Burning.</promise>'; then
                echo "Ralph completed successfully. Exiting loop."
                echo "Completed at iteration $ITERATION of $MAX_ITERATIONS"
                exit 0
            fi
        elif [ "$MODE" = "build" ] && [ -x "$TASK_SCRIPT" ]; then
            local PLAN_STATUS
            PLAN_STATUS=$("$TASK_SCRIPT" plan-status 2>/dev/null) || true
            if [ -n "$PLAN_STATUS" ]; then
                local OPEN_COUNT ACTIVE_COUNT
                OPEN_COUNT=$(echo "$PLAN_STATUS" | grep -oE '^[0-9]+' | head -1)
                ACTIVE_COUNT=$(echo "$PLAN_STATUS" | grep -oE '[0-9]+ active' | grep -oE '^[0-9]+')
                if [ "${OPEN_COUNT:-1}" -eq 0 ] 2>/dev/null && [ "${ACTIVE_COUNT:-1}" -eq 0 ] 2>/dev/null; then
                    echo "All tasks complete. Exiting loop."
                    exit 0
                fi
            fi
        fi

        ITERATION=$((ITERATION + 1))
        printf "\n\n======================== LOOP %d ========================\n" "$ITERATION"
    done
}
