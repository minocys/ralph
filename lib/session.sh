#!/bin/bash
# lib/session.sh — shared session initialization for plan and build modes
#
# Provides:
#   setup_session_core()  — initialize session state common to both modes
#
# Sourced by lib/plan_loop.sh and lib/build_loop.sh, which each define their
# own setup_session() wrapper (build adds agent registration).
#
# Globals set:
#   ITERATION, CURRENT_BRANCH, TMPFILE, TASK_SCRIPT, AGENT_ID
# Exports set:
#   RALPH_SCOPE_REPO, RALPH_SCOPE_BRANCH (derived via task _get-scope)
#   RALPH_TASK_SCRIPT

# setup_session_core: shared session state initialization.
# Each mode's loop file wraps this in its own setup_session().
setup_session_core() {
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
