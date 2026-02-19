#!/bin/bash
# hooks/precompact.sh — PreCompact hook for Claude Code
# Releases any active task back to the pool when context limit is reached.
# Always outputs JSON to stdout and exits 0.
set -euo pipefail

# If task script or agent ID aren't available, output minimal JSON and exit
if [[ -z "${RALPH_TASK_SCRIPT:-}" ]] || [[ -z "${RALPH_AGENT_ID:-}" ]]; then
    echo '{"continue":true}'
    exit 0
fi

# Query active tasks for this agent; swallow errors from DB unavailability
active_json=$("$RALPH_TASK_SCRIPT" list --status active --json 2>/dev/null || true)

if [[ -n "$active_json" ]]; then
    # Filter for tasks assigned to this agent
    task_id=$(echo "$active_json" | jq -r "select(.assignee == \"$RALPH_AGENT_ID\") | .id" 2>/dev/null | head -n1)
else
    task_id=""
fi

if [[ -n "$task_id" ]]; then
    "$RALPH_TASK_SCRIPT" fail "$task_id" --reason "context limit reached" >/dev/null 2>&1 || true
    echo '{"continue":false,"stopReason":"Context Limit Reached"}'
else
    echo '{"continue":true}'
fi

exit 0
