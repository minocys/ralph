#!/usr/bin/env bats
# test/task_db_check.bats — tests for db_check(): RALPH_DB_PATH resolution,
# sqlite3 availability, and version checking.

load test_helper

# ---------------------------------------------------------------------------
# Helper: extract and call db_check from lib/task without running main.
# ---------------------------------------------------------------------------
_call_db_check() {
    eval "$(sed -n '/^db_check()/,/^}/p' "$SCRIPT_DIR/lib/task")"
    db_check
}

# ---------------------------------------------------------------------------
setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"
    export TEST_WORK_DIR STUB_DIR
}

teardown() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    [[ -d "${TEST_WORK_DIR:-}" ]] && rm -rf "$TEST_WORK_DIR"
    [[ -d "${STUB_DIR:-}" ]] && rm -rf "$STUB_DIR"
}

# ---------------------------------------------------------------------------
# RALPH_DB_PATH override
# ---------------------------------------------------------------------------
@test "db_check uses RALPH_DB_PATH when already set" {
    export RALPH_DB_PATH="$TEST_WORK_DIR/custom/tasks.db"
    run _call_db_check
    assert_success
    assert [ -d "$TEST_WORK_DIR/custom" ]
}

@test "db_check creates parent directory for RALPH_DB_PATH" {
    export RALPH_DB_PATH="$TEST_WORK_DIR/deep/nested/dir/tasks.db"
    run _call_db_check
    assert_success
    assert [ -d "$TEST_WORK_DIR/deep/nested/dir" ]
}

# ---------------------------------------------------------------------------
# Default path resolution — run the copied script; db_check runs as the first
# step of every subcommand, and mkdir -p creates the .ralph/ dir even if later
# steps fail.
# ---------------------------------------------------------------------------
@test "db_check defaults to REPO_ROOT/.ralph/tasks.db" {
    mkdir -p "$TEST_WORK_DIR/repo/lib"
    cp "$SCRIPT_DIR/lib/task" "$TEST_WORK_DIR/repo/lib/task"
    chmod +x "$TEST_WORK_DIR/repo/lib/task"

    unset RALPH_DB_PATH 2>/dev/null || true

    # Run the copied script — db_check will resolve default path and mkdir -p.
    # The command will fail later (ensure_schema calls psql_cmd), but db_check
    # will have already created .ralph/.
    run "$TEST_WORK_DIR/repo/lib/task" list
    assert [ -d "$TEST_WORK_DIR/repo/.ralph" ]
}

# ---------------------------------------------------------------------------
# sqlite3 missing from PATH
# ---------------------------------------------------------------------------
@test "db_check fails when sqlite3 is not on PATH" {
    export RALPH_DB_PATH="$TEST_WORK_DIR/test.db"
    # Create a wrapper script that strips sqlite3 from PATH before calling db_check
    cat > "$TEST_WORK_DIR/test_no_sqlite.sh" <<SCRIPT
#!/bin/bash
set -euo pipefail
# Build a clean PATH without sqlite3
NO_SQLITE_DIR="\$(mktemp -d)"
for dir in /usr/bin /bin /usr/sbin /sbin; do
    [ -d "\$dir" ] || continue
    for cmd in "\$dir"/*; do
        [ -x "\$cmd" ] || continue
        bn="\$(basename "\$cmd")"
        [[ "\$bn" == "sqlite3" ]] && continue
        ln -sf "\$cmd" "\$NO_SQLITE_DIR/\$bn" 2>/dev/null || true
    done
done
export PATH="\$NO_SQLITE_DIR"
export RALPH_DB_PATH="$TEST_WORK_DIR/test.db"
eval "\$(sed -n '/^db_check()/,/^}/p' "$SCRIPT_DIR/lib/task")"
db_check
SCRIPT
    chmod +x "$TEST_WORK_DIR/test_no_sqlite.sh"
    run "$TEST_WORK_DIR/test_no_sqlite.sh"
    assert_failure
    assert_output --partial "sqlite3 is required"
}

# ---------------------------------------------------------------------------
# sqlite3 version check
# ---------------------------------------------------------------------------
@test "db_check fails when sqlite3 version is below 3.35" {
    export RALPH_DB_PATH="$TEST_WORK_DIR/test.db"
    cat > "$STUB_DIR/sqlite3" <<'STUB'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "3.31.0 2020-01-01 00:00:00"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/sqlite3"
    run _call_db_check
    assert_failure
    assert_output --partial "3.35"
}

@test "db_check succeeds when sqlite3 version is 3.35" {
    export RALPH_DB_PATH="$TEST_WORK_DIR/test.db"
    cat > "$STUB_DIR/sqlite3" <<'STUB'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "3.35.0 2021-03-12 00:00:00"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/sqlite3"
    run _call_db_check
    assert_success
}

@test "db_check succeeds when sqlite3 version is above 3.35" {
    export RALPH_DB_PATH="$TEST_WORK_DIR/test.db"
    cat > "$STUB_DIR/sqlite3" <<'STUB'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "3.51.0 2025-06-12 00:00:00"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/sqlite3"
    run _call_db_check
    assert_success
}

# ---------------------------------------------------------------------------
# .env fallback sourcing for RALPH_DB_PATH
# ---------------------------------------------------------------------------
@test "db_check sources RALPH_DB_PATH from .env as fallback" {
    mkdir -p "$TEST_WORK_DIR/repo/lib"
    cp "$SCRIPT_DIR/lib/task" "$TEST_WORK_DIR/repo/lib/task"
    chmod +x "$TEST_WORK_DIR/repo/lib/task"
    # Write .env with a custom RALPH_DB_PATH — db_check will source it,
    # resolve the path, and mkdir -p the parent directory.
    echo "RALPH_DB_PATH=$TEST_WORK_DIR/from-env/tasks.db" > "$TEST_WORK_DIR/repo/.env"

    unset RALPH_DB_PATH 2>/dev/null || true

    # Run the script — db_check sources .env, sets RALPH_DB_PATH, creates dir.
    run "$TEST_WORK_DIR/repo/lib/task" list
    # Verify the directory from .env was created (confirms .env was sourced)
    assert [ -d "$TEST_WORK_DIR/from-env" ]
}

@test "db_check does not override RALPH_DB_PATH from .env when already set" {
    mkdir -p "$TEST_WORK_DIR/repo/lib"
    cp "$SCRIPT_DIR/lib/task" "$TEST_WORK_DIR/repo/lib/task"
    chmod +x "$TEST_WORK_DIR/repo/lib/task"
    echo "RALPH_DB_PATH=$TEST_WORK_DIR/from-env/tasks.db" > "$TEST_WORK_DIR/repo/.env"

    export RALPH_DB_PATH="$TEST_WORK_DIR/explicit/tasks.db"

    run _call_db_check
    assert_success
    # The explicitly set path's directory should be created
    assert [ -d "$TEST_WORK_DIR/explicit" ]
    # The .env path's directory should NOT be created
    assert [ ! -d "$TEST_WORK_DIR/from-env" ]
}
