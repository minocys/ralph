#!/bin/bash
# lib/output.sh — output formatting for ralph.sh
#
# Provides:
#   JQ_FILTER     — jq expression to extract human-readable text from stream-json events
#   print_banner() — display session configuration before the main loop
#
# Globals used (must be set before calling print_banner):
#   MODE, COMMAND, CURRENT_BRANCH, DANGER, ACTIVE_BACKEND,
#   AGENT_ID, MODEL_ALIAS, RESOLVED_MODEL, MAX_ITERATIONS,
#   RALPH_EXEC_MODE, RALPH_WORK_DIR, RALPH_WORK_BRANCH

# jq filter: extract human-readable text from stream-json events
JQ_FILTER='
if .type == "assistant" then
    (.message.content[]? |
        if .type == "text" then .text
        elif .type == "tool_use" then
            "\n🔧 \(.name)" +
            (if .name == "Read" then " \(.input.file_path // "")"
            elif .name == "Write" then " \(.input.file_path // "")\n\(.input.content // "" | .[0:500])\n"
            elif .name == "Edit" then " \(.input.file_path // "")\n   - \(.input.old_string // "" | .[0:200] | gsub("\n"; "\n   - "))\n   + \(.input.new_string // "" | .[0:200] | gsub("\n"; "\n   + "))\n"
            elif .name == "Bash" then "\n   $ \(.input.command // "" | .[0:120])"
            elif .name == "Grep" then " \(.input.pattern // "") \(.input.path // "")"
            elif .name == "Glob" then " \(.input.pattern // "") \(.input.path // "")"
            elif .name == "Task" then " [\(.input.subagent_type // "")] \(.input.description // "")"
            elif .name == "TaskCreate" then " \(.input.subject // "")"
            elif .name == "TaskUpdate" then " #\(.input.taskId // "") → \(.input.status // "")"
            elif .name == "TodoWrite" then ""
            elif .name == "Skill" then " /\(.input.skill // "")"
            else " \(.input | tostring | .[0:200])"
            end) + "\n"
        else empty end
    ) // empty
elif .type == "result" then
    "\n━━ Done (\(.subtype)) | cost: $\(.total_cost_usd | tostring | .[0:6]) | turns: \(.num_turns) ━━\n"
else empty end
'

# print_banner: display session configuration before the main loop
print_banner() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Mode:   $MODE"
    echo "Prompt: $COMMAND"
    echo "Branch: $CURRENT_BRANCH"
    echo "Safe:   $( $DANGER && echo 'NO (--dangerously-skip-permissions)' || echo 'yes' )"
    echo "Backend: $ACTIVE_BACKEND"
    [ -n "$AGENT_ID" ] && echo "Agent:  $AGENT_ID"
    echo "Exec:   ${RALPH_EXEC_MODE:-local}"
    if [[ "${RALPH_WORK_DIR:-}" == */.ralph/worktrees/* ]]; then
        echo "Work:   $RALPH_WORK_DIR"
        [ -n "${RALPH_WORK_BRANCH:-}" ] && echo "WBranch: $RALPH_WORK_BRANCH"
    fi
    [ -n "$MODEL_ALIAS" ] && echo "Model:  $MODEL_ALIAS ($RESOLVED_MODEL)"
    [ $MAX_ITERATIONS -gt 0 ] && echo "Max:    $MAX_ITERATIONS iterations"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
