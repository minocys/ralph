#!/usr/bin/env bats
# test/task_env_fallback.bats — tests for db_check() git-root derivation.
# db_check() now derives the database path from git rev-parse --show-toplevel.
# RALPH_DB_PATH env var and .env sourcing are no longer used.

load test_helper

# ---------------------------------------------------------------------------
setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"
    export TEST_WORK_DIR STUB_DIR
}

teardown() {
    if [[ -n "$ORIGINAL_PATH" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    [[ -d "$TEST_WORK_DIR" ]] && rm -rf "$TEST_WORK_DIR"
    [[ -d "$STUB_DIR" ]] && rm -rf "$STUB_DIR"
}

# ---------------------------------------------------------------------------
# Git-root derivation — DB path derived from working directory's git root
# ---------------------------------------------------------------------------
@test "task resolves DB to git-root/.ralph/tasks.db" {
    mkdir -p "$TEST_WORK_DIR/repo"
    git -C "$TEST_WORK_DIR/repo" init --quiet
    git -C "$TEST_WORK_DIR/repo" config user.email "test@test.com"
    git -C "$TEST_WORK_DIR/repo" config user.name "Test"

    cd "$TEST_WORK_DIR/repo"
    # Run the real task script — db_check will derive path from git root
    run "$SCRIPT_DIR/lib/task" list
    # db_check should create .ralph/ at the git root
    assert [ -d "$TEST_WORK_DIR/repo/.ralph" ]
}

@test "task ignores RALPH_DB_PATH env var" {
    mkdir -p "$TEST_WORK_DIR/repo"
    git -C "$TEST_WORK_DIR/repo" init --quiet
    git -C "$TEST_WORK_DIR/repo" config user.email "test@test.com"
    git -C "$TEST_WORK_DIR/repo" config user.name "Test"

    export RALPH_DB_PATH="$TEST_WORK_DIR/custom/tasks.db"
    cd "$TEST_WORK_DIR/repo"
    run "$SCRIPT_DIR/lib/task" list
    # Should use git root, not the env var
    assert [ -d "$TEST_WORK_DIR/repo/.ralph" ]
    assert [ ! -d "$TEST_WORK_DIR/custom" ]
}

@test "task ignores .env file for DB path" {
    mkdir -p "$TEST_WORK_DIR/repo"
    git -C "$TEST_WORK_DIR/repo" init --quiet
    git -C "$TEST_WORK_DIR/repo" config user.email "test@test.com"
    git -C "$TEST_WORK_DIR/repo" config user.name "Test"
    echo "RALPH_DB_PATH=$TEST_WORK_DIR/env-db/tasks.db" > "$TEST_WORK_DIR/repo/.env"

    unset RALPH_DB_PATH 2>/dev/null || true
    cd "$TEST_WORK_DIR/repo"
    run "$SCRIPT_DIR/lib/task" list
    # Should use git root, not the .env value
    assert [ -d "$TEST_WORK_DIR/repo/.ralph" ]
    assert [ ! -d "$TEST_WORK_DIR/env-db" ]
}

@test "task fails outside git repo" {
    cd "$TEST_WORK_DIR"
    run "$SCRIPT_DIR/lib/task" list
    assert_failure
    assert_output --partial "not inside a git repository"
}
