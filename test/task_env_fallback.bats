#!/usr/bin/env bats
# test/task_env_fallback.bats — tests for .env fallback sourcing in task db_check()
# db_check() now resolves RALPH_DB_PATH (not RALPH_DB_URL) and falls back to
# $REPO_ROOT/.ralph/tasks.db when neither .env nor the environment provides it.

load test_helper

# ---------------------------------------------------------------------------
# Helper: copy task script to temp dir/lib so .env can be placed in parent
# ---------------------------------------------------------------------------
setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"
    export TEST_WORK_DIR STUB_DIR

    # Copy the real task script to temp dir/lib (mirrors lib/task layout)
    mkdir -p "$TEST_WORK_DIR/lib"
    cp "$SCRIPT_DIR/lib/task" "$TEST_WORK_DIR/lib/task"
    chmod +x "$TEST_WORK_DIR/lib/task"

    cd "$TEST_WORK_DIR"
}

teardown() {
    if [[ -n "$ORIGINAL_PATH" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    [[ -d "$TEST_WORK_DIR" ]] && rm -rf "$TEST_WORK_DIR"
    [[ -d "$STUB_DIR" ]] && rm -rf "$STUB_DIR"
}

# ---------------------------------------------------------------------------
# .env fallback sourcing — RALPH_DB_PATH
# ---------------------------------------------------------------------------
@test "task sources RALPH_DB_PATH from .env as fallback" {
    echo "RALPH_DB_PATH=$TEST_WORK_DIR/env-db/tasks.db" > "$TEST_WORK_DIR/.env"
    unset RALPH_DB_PATH 2>/dev/null || true

    run "$TEST_WORK_DIR/lib/task" list
    # db_check should source .env and create the specified directory
    assert [ -d "$TEST_WORK_DIR/env-db" ]
}

@test "task does not source .env when RALPH_DB_PATH already set" {
    echo "RALPH_DB_PATH=$TEST_WORK_DIR/env-db/tasks.db" > "$TEST_WORK_DIR/.env"
    export RALPH_DB_PATH="$TEST_WORK_DIR/explicit-db/tasks.db"

    run "$TEST_WORK_DIR/lib/task" list
    # Should use the pre-set RALPH_DB_PATH, not the one from .env
    assert [ -d "$TEST_WORK_DIR/explicit-db" ]
    assert [ ! -d "$TEST_WORK_DIR/env-db" ]
}

@test "task defaults to .ralph/tasks.db when RALPH_DB_PATH not set and no .env" {
    # No .env in TEST_WORK_DIR (parent of lib/)
    unset RALPH_DB_PATH 2>/dev/null || true

    run "$TEST_WORK_DIR/lib/task" list
    # db_check falls back to $REPO_ROOT/.ralph/tasks.db and creates the dir
    assert [ -d "$TEST_WORK_DIR/.ralph" ]
}

# ---------------------------------------------------------------------------
# Symlink resolution — .env resolved from actual script location, not symlink
# ---------------------------------------------------------------------------
@test "task resolves .env through symlink" {
    mkdir -p "$TEST_WORK_DIR/repo/lib"
    cp "$SCRIPT_DIR/lib/task" "$TEST_WORK_DIR/repo/lib/task"
    chmod +x "$TEST_WORK_DIR/repo/lib/task"
    echo "RALPH_DB_PATH=$TEST_WORK_DIR/symlink-env/tasks.db" > "$TEST_WORK_DIR/repo/.env"

    mkdir -p "$TEST_WORK_DIR/bin"
    ln -s "$TEST_WORK_DIR/repo/lib/task" "$TEST_WORK_DIR/bin/task"

    unset RALPH_DB_PATH 2>/dev/null || true

    # Run via symlink — should resolve .env from repo/ (parent of lib/), not bin/
    run "$TEST_WORK_DIR/bin/task" list
    assert [ -d "$TEST_WORK_DIR/symlink-env" ]
}

@test "task symlink does not find .env next to symlink" {
    mkdir -p "$TEST_WORK_DIR/repo/lib"
    mkdir -p "$TEST_WORK_DIR/bin"
    cp "$SCRIPT_DIR/lib/task" "$TEST_WORK_DIR/repo/lib/task"
    chmod +x "$TEST_WORK_DIR/repo/lib/task"
    # .env is next to the symlink, NOT next to the actual script's parent
    echo "RALPH_DB_PATH=$TEST_WORK_DIR/wrong-env/tasks.db" > "$TEST_WORK_DIR/bin/.env"
    ln -s "$TEST_WORK_DIR/repo/lib/task" "$TEST_WORK_DIR/bin/task"

    unset RALPH_DB_PATH 2>/dev/null || true

    # Should NOT find .env (it's in bin/, not repo/) — falls back to default
    run "$TEST_WORK_DIR/bin/task" list
    assert [ ! -d "$TEST_WORK_DIR/wrong-env" ]
    # Instead, .ralph/ should be created under the repo root
    assert [ -d "$TEST_WORK_DIR/repo/.ralph" ]
}
