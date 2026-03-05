#!/usr/bin/env bats
load test_helper

# ---------------------------------------------------------------------------
# sqlite_cmd – runs sqlite3 with standard flags against DB_PATH
# ---------------------------------------------------------------------------

setup() {
    # Create a temp directory and git repo so db_check() can derive DB_PATH
    TEST_WORK_DIR="$(mktemp -d)"
    git -C "$TEST_WORK_DIR" init --quiet
    git -C "$TEST_WORK_DIR" config user.email "test@test.com"
    git -C "$TEST_WORK_DIR" config user.name "Test"
    export TEST_WORK_DIR
    cd "$TEST_WORK_DIR"
}

teardown() {
    if [[ -d "$TEST_WORK_DIR" ]]; then
        rm -rf "$TEST_WORK_DIR"
    fi
}

# Extract sqlite_cmd and db_check from lib/task without running main.
_call_sqlite_cmd() {
    # Source db_check and sqlite_cmd functions
    eval "$(sed -n '/^db_check()/,/^}/p' "$SCRIPT_DIR/lib/task")"
    eval "$(sed -n '/^sqlite_cmd()/,/^}/p' "$SCRIPT_DIR/lib/task")"
    db_check
    sqlite_cmd "$@"
}

@test "sqlite_cmd runs SELECT 1 and returns '1'" {
    run _call_sqlite_cmd "SELECT 1;"
    assert_success
    assert_output "1"
}

@test "sqlite_cmd uses pipe separator for multi-column output" {
    run _call_sqlite_cmd "SELECT 1, 2, 3;"
    assert_success
    assert_output "1|2|3"
}

@test "sqlite_cmd fails on invalid SQL" {
    run _call_sqlite_cmd "INVALID SQL;"
    assert_failure
}
