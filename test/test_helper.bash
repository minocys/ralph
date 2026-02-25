# test/test_helper.bash — shared setup for all ralph bats tests

# Resolve paths relative to this helper file
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/.." && pwd)"
export TEST_DIR SCRIPT_DIR

# Load bats helper libraries using absolute paths
load "$TEST_DIR/libs/bats-support/load"
load "$TEST_DIR/libs/bats-assert/load"
load "$TEST_DIR/libs/bats-file/load"

# Source .env from project root for database URL (matches runtime behavior)
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    # shellcheck disable=SC1091
    . "$SCRIPT_DIR/.env"
fi
export RALPH_DB_URL="${RALPH_DB_URL:-postgres://ralph:ralph@localhost:5499/ralph}"

# Default scope for tests — set unconditionally at load time so that env vars
# from the caller's shell (e.g. RALPH_SCOPE_REPO derived from git) are always
# overridden. Individual tests can re-export per-test if needed.
export RALPH_SCOPE_REPO="test/repo"
export RALPH_SCOPE_BRANCH="main"

setup() {
    # Create a temp working directory so tests don't touch the real project
    TEST_WORK_DIR="$(mktemp -d)"

    # Minimal specs/ directory with a dummy spec so preflight passes
    mkdir -p "$TEST_WORK_DIR/specs"
    echo "# dummy spec" > "$TEST_WORK_DIR/specs/dummy.md"

    # Create a fake claude stub that prints its arguments and exits 0
    STUB_DIR="$(mktemp -d)"
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo "CLAUDE_STUB_CALLED"
echo "ARGS: $*"
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    # Prepend stub directory so the stub is found instead of real claude
    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"

    # Save dirs for teardown
    export TEST_WORK_DIR
    export STUB_DIR

    # RALPH_DB_URL is set at load time (above) from .env

    # Default scope for tests (overridable per-test)
    export RALPH_SCOPE_REPO="test/repo"
    export RALPH_SCOPE_BRANCH="main"

    # Docker/pg_isready stubs so ensure_postgres() passes without real Docker
    cat > "$STUB_DIR/docker" <<'DOCKERSTUB'
#!/bin/bash
case "$1" in
    compose)
        if [ "$2" = "version" ]; then
            echo "Docker Compose version v2.24.0"
        fi
        exit 0
        ;;
    inspect)
        if [ "$3" = "{{.State.Running}}" ]; then
            echo "true"
        elif [ "$3" = "{{.State.Health.Status}}" ]; then
            echo "healthy"
        fi
        exit 0
        ;;
esac
exit 0
DOCKERSTUB
    chmod +x "$STUB_DIR/docker"

    cat > "$STUB_DIR/pg_isready" <<'PGSTUB'
#!/bin/bash
exit 0
PGSTUB
    chmod +x "$STUB_DIR/pg_isready"

    # Change to the temp working directory
    cd "$TEST_WORK_DIR"
}

teardown() {
    # Restore original PATH
    if [[ -n "$ORIGINAL_PATH" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi

    # Clean up temp directories
    if [[ -d "$TEST_WORK_DIR" ]]; then
        rm -rf "$TEST_WORK_DIR"
    fi
    if [[ -d "$STUB_DIR" ]]; then
        rm -rf "$STUB_DIR"
    fi
}
