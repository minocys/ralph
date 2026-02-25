#!/bin/bash
# hooks/precompact.sh — PreCompact hook for Claude Code
# Releases any active task back to the pool when context limit is reached.
# Always outputs JSON to stdout and exits 0.
set -euo pipefail

# If task script or agent ID aren't available, output minimal JSON and exit
if [[ -z "${RALPH_TASK_SCRIPT:-}" ]] || [[ -z "${RALPH_AGENT_ID:-}" ]] || [[ -z "${RALPH_SCOPE_REPO:-}" ]] || [[ -z "${RALPH_SCOPE_BRANCH:-}" ]]; then
    echo '{"continue":true}'
    exit 0
fi

# Query active tasks for this agent in markdown-KV format; swallow errors from DB unavailability
active_output=$("$RALPH_TASK_SCRIPT" list --status active --assignee "$RALPH_AGENT_ID" --markdown 2>/dev/null || true)

# Extract task slug from the first "id: <slug>" line in the markdown-KV output.
task_id=$(echo "$active_output" | awk '/^id: /{print substr($0,5); exit}')

if [[ -n "$task_id" ]]; then
    echo "Warning: agent $RALPH_AGENT_ID context limit reached, failing task $task_id" >&2
    "$RALPH_TASK_SCRIPT" fail "$task_id" --reason "context limit reached" >/dev/null 2>&1 || true
    echo '{"continue":false,"stopReason":"Context Limit Reached"}'
else
    echo '{"continue":true}'
fi

exit 0
