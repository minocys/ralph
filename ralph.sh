#!/bin/bash
# ralph — autonomous build loop powered by Claude Code
#
# Usage: ralph [--docker] <command> [options]
#
# Global Options:
#   --docker  Run the command inside a Docker sandbox
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
    echo "Usage: ralph [--docker] <command> [options]"
    echo ""
    echo "Global Options:"
    echo "  --docker  Run the command inside a Docker sandbox"
    echo ""
    echo "Commands:"
    echo "  plan   Run the planner (study specs, create tasks)"
    echo "  build  Run the builder (claim and implement tasks)"
    echo "  task   Interact with the task backlog"
    echo ""
    echo "Run 'ralph <command> --help' for command-specific options."
}

# docker_usage: print docker-specific help and exit
docker_usage() {
    echo "Usage: ralph --docker <command> [options]"
    echo ""
    echo "Run a ralph command inside a Docker sandbox for the current repo+branch."
    echo ""
    echo "Commands:"
    echo "  plan   Run the planner inside a sandbox"
    echo "  build  Run the builder inside a sandbox"
    echo "  task   Interact with the task backlog inside a sandbox"
    echo ""
    echo "The sandbox is derived from the current git repo and branch."
    echo "If no sandbox exists, one is created and bootstrapped automatically."
    echo ""
    echo "Note: AWS SSO tokens have a limited lifetime. If using Bedrock,"
    echo "re-run 'aws sso login' if credentials expire during a long session."
}

# Detect subcommand from first positional argument
SUBCMD="${1:-}"

case "$SUBCMD" in
    # Docker sandbox dispatch: delegate to sandbox, no local setup
    --docker)
        shift
        # Check for --help before anything else
        if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
            docker_usage
            exit 0
        fi
        # Require a subcommand after --docker
        if [ $# -eq 0 ]; then
            echo "Error: --docker requires a subcommand (e.g., ralph --docker build)" >&2
            echo "Run 'ralph --docker --help' for usage" >&2
            exit 1
        fi
        # Verify docker CLI is available
        if ! command -v docker >/dev/null 2>&1; then
            echo "Error: docker CLI not found. Install Docker: https://docs.docker.com/get-docker/" >&2
            exit 1
        fi
        # Capture forwarded args (subcommand + all flags)
        DOCKER_FORWARD_ARGS=("$@")
        # Source docker.sh for sandbox functions
        # shellcheck source=lib/docker.sh
        . "$SCRIPT_DIR/lib/docker.sh"
        # Derive sandbox name from repo+branch
        derive_sandbox_name
        # Check sandbox state
        SANDBOX_STATUS=$(lookup_sandbox "$SANDBOX_NAME")
        if [ -z "$SANDBOX_STATUS" ]; then
            # No sandbox: create, start, bootstrap, exec
            TARGET_REPO_DIR="$(pwd)"
            echo "Creating sandbox '$SANDBOX_NAME'..."
            create_sandbox "$SANDBOX_NAME" "$TARGET_REPO_DIR" "$SCRIPT_DIR"
            docker sandbox run "$SANDBOX_NAME"
            bootstrap_sandbox "$SANDBOX_NAME" "$SCRIPT_DIR"
        elif [ "$SANDBOX_STATUS" = "stopped" ]; then
            # Stopped: restart then exec
            docker sandbox run "$SANDBOX_NAME"
        fi
        # Exec ralph inside the sandbox
        exec docker sandbox exec -it "$SANDBOX_NAME" ralph "${DOCKER_FORWARD_ARGS[@]}"
        ;;

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
        load_env
        ensure_postgres
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
        # shellcheck source=lib/docker.sh
        . "$SCRIPT_DIR/lib/docker.sh"
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
        load_env
        ensure_postgres
        setup_session
        setup_cleanup_trap
        setup_signal_handlers
        print_banner
        run_build_loop
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
