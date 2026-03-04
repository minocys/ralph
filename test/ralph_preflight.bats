#!/usr/bin/env bats
# test/ralph_preflight.bats — preflight check tests for ralph.sh

load test_helper

@test "missing specs/ directory exits 1" {
    rm -rf "$TEST_WORK_DIR/specs"
    run "$SCRIPT_DIR/ralph.sh" build -n 1
    assert_failure
    assert_output --partial "No specs found"
}

@test "empty specs/ directory exits 1" {
    rm -rf "$TEST_WORK_DIR/specs"
    mkdir -p "$TEST_WORK_DIR/specs"
    run "$SCRIPT_DIR/ralph.sh" build -n 1
    assert_failure
    assert_output --partial "No specs found"
}

@test "missing sqlite3 exits 1 with actionable error" {
    # Build a PATH with symlinks to everything except sqlite3
    local NO_SQLITE_DIR
    NO_SQLITE_DIR=$(mktemp -d)
    for dir in /usr/bin /bin /usr/sbin /sbin /opt/homebrew/bin; do
        [ -d "$dir" ] || continue
        for cmd in "$dir"/*; do
            [ -x "$cmd" ] || continue
            local bn
            bn=$(basename "$cmd")
            [[ "$bn" == "sqlite3" ]] && continue
            ln -sf "$cmd" "$NO_SQLITE_DIR/$bn" 2>/dev/null || true
        done
    done
    PATH="$NO_SQLITE_DIR" run "$SCRIPT_DIR/ralph.sh" build -n 1
    assert_failure
    assert_output --partial "sqlite3 is required but not installed"
}

