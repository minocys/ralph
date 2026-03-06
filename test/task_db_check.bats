#!/usr/bin/env bats
# test/task_db_check.bats — tests for db_check(): git-root DB path derivation,
# sqlite3 availability, version checking, and auto-gitignore.

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
# db_check fails outside a git repository
# ---------------------------------------------------------------------------
@test "db_check fails outside git repo with expected error" {
    cd "$TEST_WORK_DIR"
    run _call_db_check
    assert_failure
    assert_output --partial "not inside a git repository"
}

# ---------------------------------------------------------------------------
# db_check resolves DB to git-root/.ralph/tasks.db inside a temp git repo
# ---------------------------------------------------------------------------
@test "db_check resolves DB to git-root/.ralph/tasks.db inside a temp git repo" {
    # Create a temporary git repo
    mkdir -p "$TEST_WORK_DIR/myrepo"
    git -C "$TEST_WORK_DIR/myrepo" init --quiet
    git -C "$TEST_WORK_DIR/myrepo" config user.email "test@test.com"
    git -C "$TEST_WORK_DIR/myrepo" config user.name "Test"

    cd "$TEST_WORK_DIR/myrepo"
    run _call_db_check
    assert_success
    assert [ -d "$TEST_WORK_DIR/myrepo/.ralph" ]
}

# ---------------------------------------------------------------------------
# db_check resolves from a subdirectory within the git repo
# ---------------------------------------------------------------------------
@test "db_check resolves DB from subdirectory to git root" {
    mkdir -p "$TEST_WORK_DIR/myrepo/src/deep/nested"
    git -C "$TEST_WORK_DIR/myrepo" init --quiet
    git -C "$TEST_WORK_DIR/myrepo" config user.email "test@test.com"
    git -C "$TEST_WORK_DIR/myrepo" config user.name "Test"

    cd "$TEST_WORK_DIR/myrepo/src/deep/nested"
    run _call_db_check
    assert_success
    assert [ -d "$TEST_WORK_DIR/myrepo/.ralph" ]
}

# ---------------------------------------------------------------------------
# db_check creates .ralph/.gitignore with * content
# ---------------------------------------------------------------------------
@test "db_check creates .ralph/.gitignore with wildcard content" {
    mkdir -p "$TEST_WORK_DIR/myrepo"
    git -C "$TEST_WORK_DIR/myrepo" init --quiet
    git -C "$TEST_WORK_DIR/myrepo" config user.email "test@test.com"
    git -C "$TEST_WORK_DIR/myrepo" config user.name "Test"

    cd "$TEST_WORK_DIR/myrepo"
    run _call_db_check
    assert_success
    assert [ -f "$TEST_WORK_DIR/myrepo/.ralph/.gitignore" ]
    run cat "$TEST_WORK_DIR/myrepo/.ralph/.gitignore"
    assert_output "*"
}

# ---------------------------------------------------------------------------
# db_check does not overwrite existing .ralph/.gitignore
# ---------------------------------------------------------------------------
@test "db_check does not overwrite existing .ralph/.gitignore" {
    mkdir -p "$TEST_WORK_DIR/myrepo/.ralph"
    echo "custom" > "$TEST_WORK_DIR/myrepo/.ralph/.gitignore"
    git -C "$TEST_WORK_DIR/myrepo" init --quiet
    git -C "$TEST_WORK_DIR/myrepo" config user.email "test@test.com"
    git -C "$TEST_WORK_DIR/myrepo" config user.name "Test"

    cd "$TEST_WORK_DIR/myrepo"
    run _call_db_check
    assert_success
    run cat "$TEST_WORK_DIR/myrepo/.ralph/.gitignore"
    assert_output "custom"
}

# ---------------------------------------------------------------------------
# db_check ignores RALPH_DB_PATH env var
# ---------------------------------------------------------------------------
@test "db_check ignores RALPH_DB_PATH env var" {
    mkdir -p "$TEST_WORK_DIR/myrepo"
    git -C "$TEST_WORK_DIR/myrepo" init --quiet
    git -C "$TEST_WORK_DIR/myrepo" config user.email "test@test.com"
    git -C "$TEST_WORK_DIR/myrepo" config user.name "Test"

    export RALPH_DB_PATH="$TEST_WORK_DIR/custom/tasks.db"
    cd "$TEST_WORK_DIR/myrepo"
    run _call_db_check
    assert_success
    # .ralph/ should be at git root, not at custom path
    assert [ -d "$TEST_WORK_DIR/myrepo/.ralph" ]
    assert [ ! -d "$TEST_WORK_DIR/custom" ]
}

# ---------------------------------------------------------------------------
# sqlite3 missing from PATH
# ---------------------------------------------------------------------------
@test "db_check fails when sqlite3 is not on PATH" {
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
    mkdir -p "$TEST_WORK_DIR/myrepo"
    git -C "$TEST_WORK_DIR/myrepo" init --quiet
    git -C "$TEST_WORK_DIR/myrepo" config user.email "test@test.com"
    git -C "$TEST_WORK_DIR/myrepo" config user.name "Test"

    cat > "$STUB_DIR/sqlite3" <<'STUB'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "3.31.0 2020-01-01 00:00:00"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/sqlite3"
    cd "$TEST_WORK_DIR/myrepo"
    run _call_db_check
    assert_failure
    assert_output --partial "3.35"
}

@test "db_check succeeds when sqlite3 version is 3.35" {
    mkdir -p "$TEST_WORK_DIR/myrepo"
    git -C "$TEST_WORK_DIR/myrepo" init --quiet
    git -C "$TEST_WORK_DIR/myrepo" config user.email "test@test.com"
    git -C "$TEST_WORK_DIR/myrepo" config user.name "Test"

    cat > "$STUB_DIR/sqlite3" <<'STUB'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "3.35.0 2021-03-12 00:00:00"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/sqlite3"
    cd "$TEST_WORK_DIR/myrepo"
    run _call_db_check
    assert_success
}

@test "db_check succeeds when sqlite3 version is above 3.35" {
    mkdir -p "$TEST_WORK_DIR/myrepo"
    git -C "$TEST_WORK_DIR/myrepo" init --quiet
    git -C "$TEST_WORK_DIR/myrepo" config user.email "test@test.com"
    git -C "$TEST_WORK_DIR/myrepo" config user.name "Test"

    cat > "$STUB_DIR/sqlite3" <<'STUB'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "3.51.0 2025-06-12 00:00:00"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/sqlite3"
    cd "$TEST_WORK_DIR/myrepo"
    run _call_db_check
    assert_success
}
