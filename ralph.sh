#!/bin/bash
# Usage: ./ralph [options]
# Options:
#   --plan, -p              Plan mode (default: build)
#   --max-iterations N, -n N  Limit loop iterations (default: unlimited)
#   --model <alias>, -m <alias>  Select model by alias (see models.json)
#   --danger                Enable --dangerously-skip-permissions
#   --help, -h              Show this help
#
# Examples:
#   ./ralph                        # Build mode, safe, unlimited
#   ./ralph --plan                 # Plan mode, safe, unlimited
#   ./ralph -n 10                  # Build mode, safe, 10 iterations
#   ./ralph --plan -n 5 --danger   # Plan mode, skip permissions, 5 iterations
#   ./ralph -m opus-4.5             # Build with opus-4.5 model

# Resolve script directory for locating models.json and other assets
# Portable symlink resolution (macOS readlink lacks -f)
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
export SCRIPT_DIR

# Defaults
MODE="build"
COMMAND="/ralph-build"
MAX_ITERATIONS=0
DANGER=false
MODEL_ALIAS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --plan|-p)
            MODE="plan"
            COMMAND="/ralph-plan"
            shift
            ;;
        --max-iterations|-n)
            if [[ -z "$2" || "$2" = -* ]]; then
                echo "Error: --max-iterations requires a number"
                exit 1
            fi
            MAX_ITERATIONS="$2"
            shift 2
            ;;
        --model|-m)
            if [[ -z "$2" || "$2" = -* ]]; then
                echo "Error: --model requires an alias (e.g. opus-4.5, sonnet, haiku)"
                exit 1
            fi
            MODEL_ALIAS="$2"
            shift 2
            ;;
        --danger)
            DANGER=true
            shift
            ;;
        --help|-h)
            sed -n '2,/^$/s/^# //p' "$0"
            exit 0
            ;;
        *)
            echo "Error: Unknown option '$1'"
            echo "Run './ralph --help' for usage"
            exit 1
            ;;
    esac
done

# Detect active backend (priority order: env var → settings.local.json → settings.json → ~/.claude/settings.json)
ACTIVE_BACKEND="anthropic"  # Default to anthropic

# 1. Check environment variable (highest priority)
if [ -n "${CLAUDE_CODE_USE_BEDROCK}" ]; then
    if [ "${CLAUDE_CODE_USE_BEDROCK}" = "1" ]; then
        ACTIVE_BACKEND="bedrock"
    fi
else
    # 2. Check ./.claude/settings.local.json for VALUE (not just file existence)
    if [ "$ACTIVE_BACKEND" = "anthropic" ] && [ -f "./.claude/settings.local.json" ]; then
        BEDROCK_FLAG=$(jq -r '.env.CLAUDE_CODE_USE_BEDROCK // ""' ./.claude/settings.local.json 2>/dev/null)
        if [ "$BEDROCK_FLAG" = "1" ]; then
            ACTIVE_BACKEND="bedrock"
        fi
    fi

    # 3. Check ./.claude/settings.json for VALUE (if backend not yet set)
    if [ "$ACTIVE_BACKEND" = "anthropic" ] && [ -f "./.claude/settings.json" ]; then
        BEDROCK_FLAG=$(jq -r '.env.CLAUDE_CODE_USE_BEDROCK // ""' ./.claude/settings.json 2>/dev/null)
        if [ "$BEDROCK_FLAG" = "1" ]; then
            ACTIVE_BACKEND="bedrock"
        fi
    fi

    # 4. Check ~/.claude/settings.json for VALUE (lowest priority)
    if [ "$ACTIVE_BACKEND" = "anthropic" ] && [ -f "$HOME/.claude/settings.json" ]; then
        BEDROCK_FLAG=$(jq -r '.env.CLAUDE_CODE_USE_BEDROCK // ""' ~/.claude/settings.json 2>/dev/null)
        if [ "$BEDROCK_FLAG" = "1" ]; then
            ACTIVE_BACKEND="bedrock"
        fi
    fi
fi

# Resolve model alias via models.json
RESOLVED_MODEL=""
if [ -n "$MODEL_ALIAS" ]; then
    RESOLVED_MODEL=$(jq -r --arg alias "$MODEL_ALIAS" --arg backend "$ACTIVE_BACKEND" \
        '.[$alias][$backend] // empty' "$SCRIPT_DIR/models.json")

    # Pass-through: if alias not found in models.json, use raw value as model ID
    if [ -z "$RESOLVED_MODEL" ]; then
        RESOLVED_MODEL="$MODEL_ALIAS"
    fi
fi

# Preflight checks
if [ ! -d "./specs" ] || [ -z "$(ls -A ./specs 2>/dev/null)" ]; then
    echo "Error: No specs found. Run /ralph-spec first to generate specs in ./specs/"
    exit 1
fi

# Docker prerequisite checks
check_docker_installed() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Error: docker CLI not found. Install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    if ! docker compose version >/dev/null 2>&1; then
        echo "Error: docker compose V2 plugin not found. Install the Compose plugin: https://docs.docker.com/compose/install/"
        exit 1
    fi
}

is_container_running() {
    docker inspect --format '{{.State.Running}}' ralph-task-db 2>/dev/null | grep -q 'true'
}

# Ensure .env file exists for database configuration
ensure_env_file() {
    if [ -f "$SCRIPT_DIR/.env" ]; then
        return 0
    fi
    if [ -f "$SCRIPT_DIR/.env.example" ]; then
        cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
        echo "Created .env from .env.example — edit as needed."
        return 0
    fi
    echo "Warning: .env.example not found in $SCRIPT_DIR — set RALPH_DB_URL manually or run: cp .env.example .env"
}

if [ "${RALPH_SKIP_DOCKER:-}" != "1" ]; then
    check_docker_installed
fi

ensure_env_file
# Source .env as fallback — don't override existing RALPH_DB_URL (backwards compat)
if [ -z "${RALPH_DB_URL:-}" ] && [ -f "$SCRIPT_DIR/.env" ]; then
    # shellcheck disable=SC1091
    . "$SCRIPT_DIR/.env"
fi

ITERATION=0
CURRENT_BRANCH=$(git branch --show-current)
TMPFILE=$(mktemp)
AGENT_ID=""

# Register agent in build mode if task script is available
TASK_SCRIPT="$SCRIPT_DIR/task"
export RALPH_TASK_SCRIPT="$TASK_SCRIPT"

if [ "$MODE" = "build" ] && [ -x "$TASK_SCRIPT" ]; then
    AGENT_ID=$("$TASK_SCRIPT" agent register 2>/dev/null) || true
    if [ -n "$AGENT_ID" ]; then
        export RALPH_AGENT_ID="$AGENT_ID"
    fi
fi

cleanup() {
    # Deregister agent if one was registered
    if [ -n "$AGENT_ID" ] && [ -x "$TASK_SCRIPT" ]; then
        "$TASK_SCRIPT" agent deregister "$AGENT_ID" 2>/dev/null || true
    fi
    rm -f "$TMPFILE"
}

trap cleanup EXIT

# --- Graceful interrupt handling ---
# Two-stage Ctrl+C: first INT lets claude clean up, second INT force-kills.
# SIGTERM always force-kills immediately.
INTERRUPTED=0
PIPELINE_PID=""

handle_int() {
    INTERRUPTED=$((INTERRUPTED + 1))
    if [ "$INTERRUPTED" -ge 2 ]; then
        # Second Ctrl+C: force-kill pipeline and exit
        trap - INT TERM
        [ -n "$PIPELINE_PID" ] && kill -9 -- -$PIPELINE_PID 2>/dev/null
        exit 130
    fi
    # First Ctrl+C: print waiting message, let claude finish
    echo ""
    echo "Waiting for claude to finish cleanup... Press Ctrl+C again to force quit."
}

handle_term() {
    # SIGTERM: force-kill pipeline immediately, no grace period
    trap - INT TERM
    if [ -n "$PIPELINE_PID" ]; then
        kill -9 -- -$PIPELINE_PID 2>/dev/null
    fi
    exit 130
}

trap handle_int INT
trap handle_term TERM

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

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Mode:   $MODE"
echo "Prompt: $COMMAND"
echo "Branch: $CURRENT_BRANCH"
echo "Safe:   $( $DANGER && echo 'NO (--dangerously-skip-permissions)' || echo 'yes' )"
echo "Backend: $ACTIVE_BACKEND"
[ -n "$AGENT_ID" ] && echo "Agent:  $AGENT_ID"
[ -n "$MODEL_ALIAS" ] && echo "Model:  $MODEL_ALIAS ($RESOLVED_MODEL)"
[ $MAX_ITERATIONS -gt 0 ] && echo "Max:    $MAX_ITERATIONS iterations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

while true; do
    if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -ge $MAX_ITERATIONS ]; then
        echo "Reached max iterations: $MAX_ITERATIONS"
        break
    fi

    # Pre-invocation task peek: get claimable + active tasks snapshot
    PEEK_JSONL=""
    PEEK_OK=false
    if [ "$MODE" = "build" ] && [ -x "$TASK_SCRIPT" ]; then
        if PEEK_JSONL=$("$TASK_SCRIPT" peek -n 5 2>/dev/null); then
            PEEK_OK=true
        fi
    fi

    # Plan-mode pre-fetch: get current task DAG for planner
    PLAN_EXPORT_JSONL=""
    if [ "$MODE" = "plan" ] && [ -x "$TASK_SCRIPT" ]; then
        PLAN_EXPORT_JSONL=$("$TASK_SCRIPT" plan-export --json 2>/dev/null) || true
    fi

    # In build mode, exit if peek succeeded but returned empty (no tasks)
    # If peek failed (non-zero exit), treat as transient and continue
    if [ "$MODE" = "build" ] && [ -x "$TASK_SCRIPT" ] && $PEEK_OK && [ -z "$PEEK_JSONL" ]; then
        echo "No tasks available. Exiting loop."
        break
    fi

    # Run Ralph iteration: save raw JSON to tmpfile, display readable text
    if [ -n "$PEEK_JSONL" ]; then
        CLAUDE_ARGS=(-p "$COMMAND $PEEK_JSONL" --output-format=stream-json --verbose)
    elif [ "$MODE" = "plan" ] && [ -n "$PLAN_EXPORT_JSONL" ]; then
        CLAUDE_ARGS=(-p "$COMMAND $PLAN_EXPORT_JSONL" --output-format=stream-json --verbose)
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
    PIPELINE_STATUS=$?
    PIPELINE_PID=""

    # If interrupted, exit 130 — do not continue to next iteration
    if [ "$INTERRUPTED" -gt 0 ]; then
        exit 130
    fi

    # Crash-safety fallback: fail active tasks assigned to this agent
    if [ "$MODE" = "build" ] && [ -x "$TASK_SCRIPT" ] && [ -n "$AGENT_ID" ]; then
        ACTIVE_TASKS=$("$TASK_SCRIPT" list --status active --json 2>/dev/null | jq -r "select(.assignee == \"$AGENT_ID\") | .id" 2>/dev/null) || true
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
        PLAN_STATUS=$("$TASK_SCRIPT" plan-status 2>/dev/null) || true
        if [ -n "$PLAN_STATUS" ]; then
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
