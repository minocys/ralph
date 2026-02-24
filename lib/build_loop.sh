#!/bin/bash
# lib/build_loop.sh — build-mode session setup and iteration loop for ralph.sh
#
# Provides:
#   setup_session()    — initialize session state (iteration counter, branch, tmpfile, scope, agent)
#   run_build_loop()   — execute the build-mode iteration loop
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

    # Register agent in build mode if task script is available
    if [ -x "$TASK_SCRIPT" ]; then
        AGENT_ID=$("$TASK_SCRIPT" agent register 2>/dev/null) || true
        if [ -n "$AGENT_ID" ]; then
            export RALPH_AGENT_ID="$AGENT_ID"
        fi
    fi
}

# run_build_loop: execute the build-mode iteration loop
# Pre-invocation task peek, Claude invocation, crash-safety fallback,
# and plan-status check for loop termination.
run_build_loop() {
    while true; do
        if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -ge $MAX_ITERATIONS ]; then
            echo "Reached max iterations: $MAX_ITERATIONS"
            break
        fi

        # Pre-invocation task peek: get claimable + active tasks snapshot
        local PEEK_MD=""
        local PEEK_OK=false
        if [ -x "$TASK_SCRIPT" ]; then
            if PEEK_MD=$("$TASK_SCRIPT" peek -n 10 2>/dev/null); then
                PEEK_OK=true
            fi
        fi

        # Exit if peek succeeded but returned empty (no tasks)
        # If peek failed (non-zero exit), treat as transient and continue
        if [ -x "$TASK_SCRIPT" ] && $PEEK_OK && [ -z "$PEEK_MD" ]; then
            echo "No tasks available. Exiting loop."
            break
        fi

        # Build Claude argument list for this iteration
        local CLAUDE_ARGS
        if [ -n "$PEEK_MD" ]; then
            CLAUDE_ARGS=(-p "$COMMAND $PEEK_MD" --output-format=stream-json --verbose)
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

        # Crash-safety fallback: fail active tasks assigned to this agent
        if [ -x "$TASK_SCRIPT" ] && [ -n "$AGENT_ID" ]; then
            local active_output
            active_output=$("$TASK_SCRIPT" list --status active --assignee "$AGENT_ID" --markdown 2>/dev/null || true)
            # Extract task slug from the first "id: <slug>" line in the markdown-KV output.
            local ACTIVE_ID
            ACTIVE_ID=$(echo "$active_output" | awk '/^id: /{print substr($0,5); exit}')
            if [ -n "$ACTIVE_ID" ]; then
                "$TASK_SCRIPT" fail "$ACTIVE_ID" --reason 'session exited without completing task' 2>/dev/null || true
            fi
        fi

        # Check plan-status: exit if all tasks complete
        if [ -x "$TASK_SCRIPT" ]; then
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
