#!/bin/bash
# ralph — autonomous build loop powered by Claude Code
#
# Usage: ralph <command> [options]
#
# Commands:
#   plan   Run the planner (study specs, create tasks)
#   build  Run the builder (claim and implement tasks)
#   task   Interact with the task backlog
#
# Run 'ralph <command> --help' for command-specific options.

# Resolve script directory (portable symlink resolution — macOS readlink lacks -f)
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
export SCRIPT_DIR

# usage: print top-level help and exit
usage() {
    echo "Usage: ralph <command> [options]"
    echo ""
    echo "Commands:"
    echo "  plan   Run the planner (study specs, create tasks)"
    echo "  build  Run the builder (claim and implement tasks)"
    echo "  task   Interact with the task backlog"
    echo ""
    echo "Run 'ralph <command> --help' for command-specific options."
}

# Detect subcommand from first positional argument
SUBCMD="${1:-}"

case "$SUBCMD" in
    # Task subcommand: exec directly to lib/task, no other setup
    task)
        shift
        exec "$SCRIPT_DIR/lib/task" "$@"
        ;;

    # Plan subcommand: source shared libs + loop, parse flags, run
    plan)
        shift
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

        MODE="plan"
        COMMAND="/ralph-plan"
        parse_flags "$@"

        # Plan mode default: 1 iteration (if not explicitly set)
        if [ "$MAX_ITERATIONS" -eq -1 ]; then
            MAX_ITERATIONS=1
        fi

        # Plan mode rejects -n 0
        if [ "$MAX_ITERATIONS" -eq 0 ]; then
            echo "Error: plan mode requires at least 1 iteration (-n 0 is not allowed)" >&2
            exit 1
        fi

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
        ;;

    # Build subcommand: source shared libs + loop, parse flags, run
    build)
        shift
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

        MODE="build"
        COMMAND="/ralph-build"
        parse_flags "$@"

        # Build mode default: 0 (unlimited) if not explicitly set
        if [ "$MAX_ITERATIONS" -eq -1 ]; then
            MAX_ITERATIONS=0
        fi

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
        ;;

    # Help
    --help|-h)
        usage
        exit 0
        ;;

    # No arguments: print help
    "")
        usage
        exit 0
        ;;

    # Unknown subcommand
    *)
        echo "Error: unknown command '$SUBCMD'" >&2
        echo "Run 'ralph --help' for usage" >&2
        exit 1
        ;;
esac
