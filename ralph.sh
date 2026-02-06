#!/bin/zsh
# Usage: ./ralph [options]
# Options:
#   --plan, -p              Plan mode (default: build)
#   --max-iterations N, -n N  Limit loop iterations (default: unlimited)
#   --danger                Enable --dangerously-skip-permissions
#   --help, -h              Show this help
#
# Examples:
#   ./ralph                        # Build mode, safe, unlimited
#   ./ralph --plan                 # Plan mode, safe, unlimited
#   ./ralph -n 10                  # Build mode, safe, 10 iterations
#   ./ralph --plan -n 5 --danger   # Plan mode, skip permissions, 5 iterations

# Defaults
MODE="build"
COMMAND="/ralph-build"
MAX_ITERATIONS=0
DANGER=false

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

# Preflight checks
if [ ! -d "./specs" ] || [ -z "$(ls -A ./specs 2>/dev/null)" ]; then
    echo "Error: No specs found. Run /ralph-spec first to generate specs in ./specs/"
    exit 1
fi

if [ "$MODE" != "plan" ] && [ ! -f "./IMPLEMENTATION_PLAN.json" ]; then
    echo "Error: IMPLEMENTATION_PLAN.json not found. Run './ralph --plan' or /ralph-plan first."
    exit 1
fi

ITERATION=0
CURRENT_BRANCH=$(git branch --show-current)
TMPFILE=$(mktemp)
trap "rm -f $TMPFILE" EXIT
trap "exit 130" INT TERM

# jq filter: extract human-readable text from stream-json events
JQ_FILTER='
if .type == "assistant" then
    (.message.content[]? |
        if .type == "text" then .text
        elif .type == "tool_use" then
            "\n🔧 \(.name)" +
            (if .name == "Read" then " \(.input.file_path // "")"
            elif .name == "Write" then " \(.input.file_path // "")"
            elif .name == "Edit" then " \(.input.file_path // "")"
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
[ $MAX_ITERATIONS -gt 0 ] && echo "Max:    $MAX_ITERATIONS iterations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

while true; do
    if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -ge $MAX_ITERATIONS ]; then
        echo "Reached max iterations: $MAX_ITERATIONS"
        break
    fi

    # Run Ralph iteration: save raw JSON to tmpfile, display readable text
    CLAUDE_ARGS=(-p $COMMAND --output-format=stream-json --verbose)
    $DANGER && CLAUDE_ARGS+=(--dangerously-skip-permissions)

    claude "${CLAUDE_ARGS[@]}" | tee "$TMPFILE" | jq --unbuffered -rj "$JQ_FILTER"

    if grep -q "<promise>COMPLETE</promise>" "$TMPFILE"; then
        echo "Ralph completed successfully. Exiting loop."
        echo "Completed at iteration $ITERATION of $MAX_ITERATIONS"
        exit 0
    fi

    ITERATION=$((ITERATION + 1))
    print "\n\n======================== LOOP $ITERATION ========================\n"
done
