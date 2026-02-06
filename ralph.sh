#!/bin/zsh
# Usage: ./loop.sh [plan] [max_iterations]
# Examples:
#   ./loop.sh              # Build mode, unlimited iterations
#   ./loop.sh 20           # Build mode, max 20 iterations
#   ./loop.sh plan         # Plan mode, unlimited iterations
#   ./loop.sh plan 5       # Plan mode, max 5 iterations

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

if [ ! -f "./IMPLEMENTATION_PLAN.md" ]; then
    echo "Error: IMPLEMENTATION_PLAN.md not found. Run /ralph-plan first."
    exit 1
fi

ITERATION=0
CURRENT_BRANCH=$(git branch --show-current)

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

    # Run Ralph iteration with selected prompt
    OUTPUT=$(claude -p $COMMAND \
        --dangerously-skip-permissions \
        --output-format=stream-json \
        --verbose | tee /dev/stderr)

    if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
        echo "Ralph completed successfully. Exiting loop."
        echo "Completed at iteration $ITERATION of $MAX_ITERATIONS"
        exit 0
    fi

    ITERATION=$((ITERATION + 1))
    print "\n\n======================== LOOP $ITERATION ========================\n"
done
