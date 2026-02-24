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

# Resolve script directory (portable symlink resolution — macOS readlink lacks -f)
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
# shellcheck source=lib/signals.sh
. "$SCRIPT_DIR/lib/signals.sh"
# shellcheck source=lib/output.sh
. "$SCRIPT_DIR/lib/output.sh"
# shellcheck source=lib/loop.sh
. "$SCRIPT_DIR/lib/loop.sh"

# Route subcommands that bypass the main orchestration loop
if [ "${1:-}" = "task" ]; then
    shift
    exec "$SCRIPT_DIR/lib/task" "$@"
fi

# Orchestrate: parse → configure → preflight → postgres → session → traps → run
parse_args "$@"
detect_backend
resolve_model
preflight
load_env
ensure_postgres
setup_session
setup_cleanup_trap
setup_signal_handlers
print_banner
run_loop
