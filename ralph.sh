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

# Source library modules
# shellcheck source=lib/config.sh
. "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=lib/docker.sh
. "$SCRIPT_DIR/lib/docker.sh"

parse_args "$@"
detect_backend
resolve_model

# Preflight checks
if [ ! -d "./specs" ] || [ -z "$(ls -A ./specs 2>/dev/null)" ]; then
    echo "Error: No specs found. Run /ralph-spec first to generate specs in ./specs/"
    exit 1
fi

ensure_env_file
# Source .env for POSTGRES_* and RALPH_DB_URL; preserve existing RALPH_DB_URL (backwards compat)
if [ -f "$SCRIPT_DIR/.env" ]; then
    _saved_db_url="${RALPH_DB_URL:-}"
    # shellcheck disable=SC1091
    . "$SCRIPT_DIR/.env"
    if [ -n "$_saved_db_url" ]; then RALPH_DB_URL="$_saved_db_url"; fi
fi

ensure_postgres

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

# Source library modules
# shellcheck source=lib/signals.sh
. "$SCRIPT_DIR/lib/signals.sh"
# shellcheck source=lib/output.sh
. "$SCRIPT_DIR/lib/output.sh"
# shellcheck source=lib/loop.sh
. "$SCRIPT_DIR/lib/loop.sh"

setup_cleanup_trap
setup_signal_handlers

print_banner

run_loop
