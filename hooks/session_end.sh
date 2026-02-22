#!/bin/bash
# hooks/session_end.sh — SessionEnd hook for Claude Code
# Releases any active task back to the pool when the session ends unexpectedly.
# Always exits 0.
set -euo pipefail

# If task script or agent ID aren't available, exit silently
if [[ -z "${RALPH_TASK_SCRIPT:-}" ]] || [[ -z "${RALPH_AGENT_ID:-}" ]]; then
    exit 0
fi

# Query active tasks for this agent; swallow errors from DB unavailability
active_output=$("$RALPH_TASK_SCRIPT" list --status active 2>/dev/null || true)

if [[ -n "$active_output" ]]; then
    # Table format: ID is $1, AGENT is $NF (last column).
    # Relies on agent IDs not appearing as last word of multi-word titles.
    task_id=$(echo "$active_output" | awk -v agent="$RALPH_AGENT_ID" '$NF == agent { print $1 }' | head -n1)
else
    task_id=""
fi

if [[ -n "$task_id" ]]; then
    echo "Warning: agent $RALPH_AGENT_ID session ended, failing task $task_id" >&2
    "$RALPH_TASK_SCRIPT" fail "$task_id" --reason "session ended unexpectedly" 2>/dev/null || true
fi

exit 0
