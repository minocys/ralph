# test/test_helper.bash — shared setup for all ralph bats tests

# Resolve paths relative to this helper file
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/.." && pwd)"
export TEST_DIR SCRIPT_DIR

# Load bats helper libraries using absolute paths
load "$TEST_DIR/libs/bats-support/load"
load "$TEST_DIR/libs/bats-assert/load"
load "$TEST_DIR/libs/bats-file/load"

# Default scope for tests — set unconditionally at load time so that env vars
# from the caller's shell (e.g. RALPH_SCOPE_REPO derived from git) are always
# overridden. Individual tests can re-export per-test if needed.
export RALPH_SCOPE_REPO="test/repo"
export RALPH_SCOPE_BRANCH="main"

# Reusable setup/teardown — test files that need custom setup() should call
# common_setup first, then add their own logic.
common_setup() {
    # Create a temp working directory so tests don't touch the real project
    TEST_WORK_DIR="$(mktemp -d)"

    # Initialize a git repo so db_check() can derive the database path
    git -C "$TEST_WORK_DIR" init --quiet
    git -C "$TEST_WORK_DIR" config user.email "test@test.com"
    git -C "$TEST_WORK_DIR" config user.name "Test"

    # db_check() derives: <git-root>/.ralph/tasks.db
    # Set RALPH_DB_PATH here for test assertions (e.g., direct sqlite3 queries).
    # lib/task ignores this env var — it always uses git rev-parse.
    export RALPH_DB_PATH="$TEST_WORK_DIR/.ralph/tasks.db"

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

    # Default scope for tests (overridable per-test)
    export RALPH_SCOPE_REPO="test/repo"
    export RALPH_SCOPE_BRANCH="main"

    # Change to the temp working directory
    cd "$TEST_WORK_DIR"
}

common_teardown() {
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

setup() {
    common_setup
}

teardown() {
    common_teardown
}
