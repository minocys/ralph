#!/bin/zsh
# Usage: ./ralph [plan] [max_iterations]
# Examples:
#   ./ralph              # Build mode, unlimited iterations
#   ./ralph 20           # Build mode, max 20 iterations
#   ./ralph plan         # Plan mode, unlimited iterations
#   ./ralph plan 5       # Plan mode, max 5 iterations

# Parse arguments
if [ "$1" = "plan" ]; then
    # Plan mode
    MODE="plan"
    COMMAND="/ralph-plan"
    MAX_ITERATIONS=${2:-0}
elif [[ "$1" = <-> ]]; then
    # Build mode with max iterations
    MODE="build"
    COMMAND="/ralph-build"
    MAX_ITERATIONS=$1
else
    # Build mode, unlimited (no arguments or invalid input)
    MODE="build"
    COMMAND="/ralph-build"
    MAX_ITERATIONS=0
fi

# Preflight checks
if [ ! -d "./specs" ] || [ -z "$(ls -A ./specs 2>/dev/null)" ]; then
    echo "Error: No specs found. Run /ralph-spec first to generate specs in ./specs/"
    exit 1
fi

if [ "$MODE" != "plan" ] && [ ! -f "./IMPLEMENTATION_PLAN.md" ]; then
    echo "Error: IMPLEMENTATION_PLAN.md not found. Run \"ralph plan\" or /ralph-plan first."
    exit 1
fi

ITERATION=0
CURRENT_BRANCH=$(git branch --show-current)
TMPFILE=$(mktemp)
trap "rm -f $TMPFILE" EXIT

# jq filter: extract human-readable text from stream-json events
JQ_FILTER='
if .type == "assistant" then
    (.message.content[]? |
        if .type == "text" then .text
        elif .type == "tool_use" then "\n🔧 \(.name)\n"
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
[ $MAX_ITERATIONS -gt 0 ] && echo "Max:    $MAX_ITERATIONS iterations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

while true; do
    if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -ge $MAX_ITERATIONS ]; then
        echo "Reached max iterations: $MAX_ITERATIONS"
        break
    fi

    # Run Ralph iteration: save raw JSON to tmpfile, display readable text
    claude -p $COMMAND \
        --dangerously-skip-permissions \
        --output-format=stream-json \
        --verbose | tee "$TMPFILE" | jq --unbuffered -rj "$JQ_FILTER"

    if grep -q "<promise>COMPLETE</promise>" "$TMPFILE"; then
        echo "Ralph completed successfully. Exiting loop."
        echo "Completed at iteration $ITERATION of $MAX_ITERATIONS"
        exit 0
    fi

    ITERATION=$((ITERATION + 1))
    print "\n\n======================== LOOP $ITERATION ========================\n"
done
