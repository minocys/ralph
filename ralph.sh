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
    echo "Usage: ralph [options] <command> [command-options]"
    echo ""
    echo "Options:"
    echo "  --docker  Run the command inside a Docker sandbox"
    echo ""
    echo "Commands:"
    echo "  plan   Run the planner (study specs, create tasks)"
    echo "  build  Run the builder (claim and implement tasks)"
    echo "  task   Interact with the task backlog"
    echo ""
    echo "Run 'ralph <command> --help' for command-specific options."
}

# docker_usage: print --docker-specific help and exit
docker_usage() {
    echo "Usage: ralph --docker <command> [command-options]"
    echo ""
    echo "Run a ralph command inside a Docker sandbox."
    echo ""
    echo "The sandbox is automatically created and managed per repo+branch."
    echo "All arguments after --docker are forwarded to the sandboxed ralph."
    echo ""
    echo "Commands:"
    echo "  plan   Run the planner inside the sandbox"
    echo "  build  Run the builder inside the sandbox"
    echo "  task   Interact with the task backlog inside the sandbox"
    echo ""
    echo "Examples:"
    echo "  ralph --docker build -n 3          # Run 3 build iterations in sandbox"
    echo "  ralph --docker plan --model opus    # Plan with specific model in sandbox"
    echo "  ralph --docker task list            # List tasks from sandbox"
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
        # shellcheck source=lib/signals.sh
        . "$SCRIPT_DIR/lib/signals.sh"
        # shellcheck source=lib/output.sh
        . "$SCRIPT_DIR/lib/output.sh"
        # shellcheck source=lib/plan_loop.sh
        . "$SCRIPT_DIR/lib/plan_loop.sh"

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
        setup_session
        setup_cleanup_trap
        setup_signal_handlers
        print_banner
        run_plan_loop
        ;;

    # Build subcommand: source shared libs + loop, parse flags, run
    build)
        shift
        # shellcheck source=lib/config.sh
        . "$SCRIPT_DIR/lib/config.sh"
        # shellcheck source=lib/signals.sh
        . "$SCRIPT_DIR/lib/signals.sh"
        # shellcheck source=lib/output.sh
        . "$SCRIPT_DIR/lib/output.sh"
        # shellcheck source=lib/build_loop.sh
        . "$SCRIPT_DIR/lib/build_loop.sh"

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
        setup_session
        setup_cleanup_trap
        setup_signal_handlers
        print_banner
        run_build_loop
        ;;

    # Docker sandbox dispatch
    --docker)
        shift
        # --docker --help: print docker-specific usage
        if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
            docker_usage
            exit 0
        fi
        # --docker with no subcommand: error
        if [ -z "${1:-}" ]; then
            echo "Error: --docker requires a subcommand (e.g. ralph --docker plan)" >&2
            echo "Run 'ralph --docker --help' for usage" >&2
            exit 1
        fi
        # Preflight: verify docker CLI is available
        if ! command -v docker >/dev/null 2>&1; then
            echo "Error: docker CLI is required but not found in PATH" >&2
            echo "Install Docker Desktop (v4.58+) from https://www.docker.com/products/docker-desktop/" >&2
            exit 1
        fi
        # Source docker helpers
        # shellcheck source=lib/docker.sh
        . "$SCRIPT_DIR/lib/docker.sh"
        # Derive sandbox name from repo+branch
        SANDBOX_NAME="$(derive_sandbox_name)"
        # Check sandbox state
        SANDBOX_STATE="$(check_sandbox_state "$SANDBOX_NAME")"
        case "$SANDBOX_STATE" in
            running)
                # Sandbox exists and is running — exec directly
                ;;
            stopped)
                # Sandbox exists but stopped — start it
                docker sandbox run "$SANDBOX_NAME"
                ;;
            "")
                # No sandbox — create and bootstrap
                docker sandbox create --name "$SANDBOX_NAME"
                # TODO: bootstrap sandbox (see sandbox-bootstrap spec)
                ;;
        esac
        # Resolve credentials and build -e flags
        CRED_FLAGS=()
        if type resolve_aws_credentials >/dev/null 2>&1; then
            resolve_aws_credentials
            CRED_FLAGS+=(-e "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID")
            CRED_FLAGS+=(-e "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY")
            [ -n "${AWS_SESSION_TOKEN:-}" ] && CRED_FLAGS+=(-e "AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN")
            [ -n "${AWS_REGION:-}" ] && CRED_FLAGS+=(-e "AWS_REGION=$AWS_REGION")
        fi
        # Exec ralph inside the sandbox, forwarding all remaining args
        exec docker sandbox exec -it "${CRED_FLAGS[@]}" "$SANDBOX_NAME" ralph "$@"
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
