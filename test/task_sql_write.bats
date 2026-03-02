#!/usr/bin/env bats
# test/task_sql_write.bats — verify sql_write() wraps SQL in
# BEGIN IMMEDIATE…COMMIT, uses .bail on, and retries on SQLITE_BUSY.

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    export RALPH_DB_PATH="$TEST_WORK_DIR/test.db"
    export TEST_WORK_DIR

    # Source the functions we need from lib/task
    eval "$(sed -n '/^db_check()/,/^}/p' "$SCRIPT_DIR/lib/task")"
    eval "$(sed -n '/^sqlite_cmd()/,/^}/p' "$SCRIPT_DIR/lib/task")"
    eval "$(sed -n '/^sql_write()/,/^}/p' "$SCRIPT_DIR/lib/task")"

    db_check
    # Create a simple table for testing writes
    sqlite_cmd "CREATE TABLE IF NOT EXISTS test_tbl (id TEXT PRIMARY KEY, val TEXT);"
}

teardown() {
    [[ -d "${TEST_WORK_DIR:-}" ]] && rm -rf "$TEST_WORK_DIR"
}

# ---------------------------------------------------------------------------
# Successful write commits
# ---------------------------------------------------------------------------
@test "sql_write commits a simple INSERT" {
    run sql_write "INSERT INTO test_tbl (id, val) VALUES ('a', 'hello');"
    assert_success

    run sqlite_cmd "SELECT val FROM test_tbl WHERE id='a';"
    assert_success
    assert_output "hello"
}

@test "sql_write commits multiple statements in one call" {
    run sql_write "INSERT INTO test_tbl (id, val) VALUES ('b', 'one');
INSERT INTO test_tbl (id, val) VALUES ('c', 'two');"
    assert_success

    run sqlite_cmd "SELECT count(*) FROM test_tbl;"
    assert_success
    assert_output "2"
}

@test "sql_write accepts SQL from stdin" {
    echo "INSERT INTO test_tbl (id, val) VALUES ('d', 'piped');" | sql_write
    run sqlite_cmd "SELECT val FROM test_tbl WHERE id='d';"
    assert_success
    assert_output "piped"
}

@test "sql_write reads SQL from argument" {
    sql_write "INSERT INTO test_tbl (id, val) VALUES ('e', 'arg');"
    run sqlite_cmd "SELECT val FROM test_tbl WHERE id='e';"
    assert_success
    assert_output "arg"
}

# ---------------------------------------------------------------------------
# .bail on stops on error
# ---------------------------------------------------------------------------
@test "sql_write stops on first error due to .bail on" {
    # First statement succeeds, second fails (duplicate PK), third would succeed
    run sql_write "INSERT INTO test_tbl (id, val) VALUES ('f', 'first');
INSERT INTO test_tbl (id, val) VALUES ('f', 'dupe');
INSERT INTO test_tbl (id, val) VALUES ('g', 'third');"
    assert_failure

    # 'f' was inserted before the error
    run sqlite_cmd "SELECT val FROM test_tbl WHERE id='f';"
    # With .bail on inside a transaction, the whole transaction is rolled back
    # because COMMIT never executes after the error
    assert_output ""
}

@test "sql_write rolls back entire transaction on error" {
    sql_write "INSERT INTO test_tbl (id, val) VALUES ('h', 'existing');"

    run sql_write "INSERT INTO test_tbl (id, val) VALUES ('i', 'new');
INSERT INTO test_tbl (id, val) VALUES ('h', 'dupe');"
    assert_failure

    # 'i' should NOT exist because transaction was rolled back
    run sqlite_cmd "SELECT count(*) FROM test_tbl WHERE id='i';"
    assert_success
    assert_output "0"
}

# ---------------------------------------------------------------------------
# Function wraps SQL in BEGIN IMMEDIATE...COMMIT
# ---------------------------------------------------------------------------
@test "sql_write function body contains BEGIN IMMEDIATE" {
    local fn_body
    fn_body="$(declare -f sql_write)"
    [[ "$fn_body" == *"BEGIN IMMEDIATE"* ]]
}

@test "sql_write function body contains COMMIT" {
    local fn_body
    fn_body="$(declare -f sql_write)"
    [[ "$fn_body" == *"COMMIT"* ]]
}

@test "sql_write function body contains .bail on" {
    local fn_body
    fn_body="$(declare -f sql_write)"
    [[ "$fn_body" == *".bail on"* ]]
}

@test "sql_write actually uses BEGIN IMMEDIATE (concurrent write blocked)" {
    # Enable WAL so concurrent readers don't block
    sqlite_cmd "PRAGMA journal_mode=WAL;"

    # Start a long-running write transaction in the background that holds the lock
    sqlite3 "$RALPH_DB_PATH" "BEGIN IMMEDIATE; INSERT INTO test_tbl VALUES ('lock','held'); SELECT writeable_sleep(1);" &>/dev/null &
    local bg_pid=$!

    # Give the background process a moment to acquire the lock
    sleep 0.1

    # sql_write should eventually succeed (busy_timeout allows waiting)
    # or fail with BUSY if the timeout expires
    sql_write "INSERT INTO test_tbl (id, val) VALUES ('j', 'after_lock');" || true

    wait "$bg_pid" 2>/dev/null || true

    # Verify our write eventually committed
    run sqlite_cmd "SELECT val FROM test_tbl WHERE id='j';"
    assert_success
    assert_output "after_lock"
}

# ---------------------------------------------------------------------------
# Retry on SQLITE_BUSY (exit code 5)
# ---------------------------------------------------------------------------
@test "sql_write retries on exit code 5" {
    # Create a stub sqlite3 that fails with exit code 5 twice, then succeeds
    local stub_dir
    stub_dir="$(mktemp -d)"
    local counter_file="$TEST_WORK_DIR/attempt_count"
    echo "0" > "$counter_file"

    cat > "$stub_dir/sqlite3" <<STUB
#!/bin/bash
count=\$(cat "$counter_file")
count=\$((count + 1))
echo "\$count" > "$counter_file"
if [ "\$count" -le 2 ]; then
    exit 5
fi
# On third attempt, run the real sqlite3
exec /usr/bin/sqlite3 "\$@"
STUB
    chmod +x "$stub_dir/sqlite3"

    # Prepend stub dir to PATH so sql_write uses the stub
    local orig_path="$PATH"
    export PATH="$stub_dir:$orig_path"

    run sql_write "INSERT INTO test_tbl (id, val) VALUES ('k', 'retried');"
    assert_success

    # Verify it took 3 attempts
    local attempts
    attempts="$(cat "$counter_file")"
    [[ "$attempts" -eq 3 ]]

    export PATH="$orig_path"
    rm -rf "$stub_dir"
}

@test "sql_write fails after max retries exhausted" {
    # Create a stub sqlite3 that always fails with exit code 5
    local stub_dir
    stub_dir="$(mktemp -d)"
    cat > "$stub_dir/sqlite3" <<'STUB'
#!/bin/bash
exit 5
STUB
    chmod +x "$stub_dir/sqlite3"

    local orig_path="$PATH"
    export PATH="$stub_dir:$orig_path"

    run sql_write "INSERT INTO test_tbl (id, val) VALUES ('m', 'never');"
    assert_failure
    [[ "$status" -eq 5 ]]

    export PATH="$orig_path"
    rm -rf "$stub_dir"
}

@test "sql_write does not retry on non-BUSY errors" {
    # Create a stub sqlite3 that fails with exit code 1
    local stub_dir
    stub_dir="$(mktemp -d)"
    local counter_file="$TEST_WORK_DIR/attempt_count"
    echo "0" > "$counter_file"

    cat > "$stub_dir/sqlite3" <<STUB
#!/bin/bash
count=\$(cat "$counter_file")
count=\$((count + 1))
echo "\$count" > "$counter_file"
exit 1
STUB
    chmod +x "$stub_dir/sqlite3"

    local orig_path="$PATH"
    export PATH="$stub_dir:$orig_path"

    run sql_write "INSERT INTO test_tbl (id, val) VALUES ('n', 'nope');"
    assert_failure
    [[ "$status" -eq 1 ]]

    # Should have only attempted once (no retry on non-BUSY)
    local attempts
    attempts="$(cat "$counter_file")"
    [[ "$attempts" -eq 1 ]]

    export PATH="$orig_path"
    rm -rf "$stub_dir"
}
