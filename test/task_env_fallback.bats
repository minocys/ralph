#!/usr/bin/env bats
# test/task_env_fallback.bats — tests for .env fallback sourcing in task db_check()

load test_helper

# ---------------------------------------------------------------------------
# Helper: copy task script to temp dir so .env can be placed alongside it
# ---------------------------------------------------------------------------
setup() {
    # Run default setup from test_helper
    TEST_WORK_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"
    export TEST_WORK_DIR STUB_DIR

    # Copy the real task script to temp dir
    cp "$SCRIPT_DIR/task" "$TEST_WORK_DIR/task"
    chmod +x "$TEST_WORK_DIR/task"

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
# .env fallback sourcing
# ---------------------------------------------------------------------------
@test "task sources .env as fallback when RALPH_DB_URL not set" {
    echo 'RALPH_DB_URL=postgres://ralph:ralph@localhost:9999/ralph' > "$TEST_WORK_DIR/.env"
    unset RALPH_DB_URL 2>/dev/null || true

    run "$TEST_WORK_DIR/task" list
    # db_check should succeed (RALPH_DB_URL sourced from .env)
    # The command will fail at psql connection, NOT at "RALPH_DB_URL is not set"
    refute_output --partial "RALPH_DB_URL"
}

@test "task does not source .env when RALPH_DB_URL already set" {
    echo 'RALPH_DB_URL=postgres://overridden:test@localhost:9999/overridden' > "$TEST_WORK_DIR/.env"
    export RALPH_DB_URL="postgres://original:test@localhost:9999/original"

    run "$TEST_WORK_DIR/task" list
    # Should use the pre-set RALPH_DB_URL, not the one from .env
    refute_output --partial "RALPH_DB_URL"
    refute_output --partial "overridden"
}

@test "task error suggests cp .env.example .env when RALPH_DB_URL not set and no .env" {
    # No .env in TEST_WORK_DIR
    unset RALPH_DB_URL 2>/dev/null || true

    run "$TEST_WORK_DIR/task" list
    assert_failure
    assert_output --partial "cp .env.example .env"
}

# ---------------------------------------------------------------------------
# Symlink resolution — .env resolved from actual script location, not symlink
# ---------------------------------------------------------------------------
@test "task resolves .env through symlink" {
    mkdir -p "$TEST_WORK_DIR/repo"
    cp "$SCRIPT_DIR/task" "$TEST_WORK_DIR/repo/task"
    chmod +x "$TEST_WORK_DIR/repo/task"
    echo 'RALPH_DB_URL=postgres://ralph:ralph@localhost:9999/ralph' > "$TEST_WORK_DIR/repo/.env"

    mkdir -p "$TEST_WORK_DIR/bin"
    ln -s "$TEST_WORK_DIR/repo/task" "$TEST_WORK_DIR/bin/task"

    unset RALPH_DB_URL 2>/dev/null || true

    # Run via symlink — should resolve .env from repo/, not bin/
    run "$TEST_WORK_DIR/bin/task" list
    refute_output --partial "RALPH_DB_URL"
}

@test "task symlink does not find .env next to symlink" {
    mkdir -p "$TEST_WORK_DIR/repo"
    mkdir -p "$TEST_WORK_DIR/bin"
    cp "$SCRIPT_DIR/task" "$TEST_WORK_DIR/repo/task"
    chmod +x "$TEST_WORK_DIR/repo/task"
    # .env is next to the symlink, NOT next to the actual script
    echo 'RALPH_DB_URL=postgres://ralph:ralph@localhost:9999/ralph' > "$TEST_WORK_DIR/bin/.env"
    ln -s "$TEST_WORK_DIR/repo/task" "$TEST_WORK_DIR/bin/task"

    unset RALPH_DB_URL 2>/dev/null || true

    # Should NOT find .env (it's in bin/, not repo/)
    run "$TEST_WORK_DIR/bin/task" list
    assert_failure
    assert_output --partial "cp .env.example .env"
}
