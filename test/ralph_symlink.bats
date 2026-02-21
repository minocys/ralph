#!/usr/bin/env bats
# test/ralph_symlink.bats — SCRIPT_DIR symlink resolution tests for ralph.sh

load test_helper

@test "SCRIPT_DIR resolves through symlink to repo directory" {
    # Create a symlink in a different directory pointing to ralph.sh
    local link_dir="$TEST_WORK_DIR/fake-bin"
    mkdir -p "$link_dir"
    ln -s "$SCRIPT_DIR/ralph.sh" "$link_dir/ralph"

    # Invoke via symlink — SCRIPT_DIR should resolve to the repo, not fake-bin
    run "$link_dir/ralph" --help
    assert_success
    assert_output --partial "Usage"
}

@test "SCRIPT_DIR resolves through chained symlinks" {
    # Create a chain: link_a -> link_b -> ralph.sh
    local link_dir_a="$TEST_WORK_DIR/chain-a"
    local link_dir_b="$TEST_WORK_DIR/chain-b"
    mkdir -p "$link_dir_a" "$link_dir_b"

    ln -s "$SCRIPT_DIR/ralph.sh" "$link_dir_b/ralph"
    ln -s "$link_dir_b/ralph" "$link_dir_a/ralph"

    run "$link_dir_a/ralph" --help
    assert_success
    assert_output --partial "Usage"
}

@test "SCRIPT_DIR finds models.json when invoked via symlink" {
    # Symlink ralph into a temp directory
    local link_dir="$TEST_WORK_DIR/fake-bin"
    mkdir -p "$link_dir"
    ln -s "$SCRIPT_DIR/ralph.sh" "$link_dir/ralph"

    # If SCRIPT_DIR resolves correctly, model lookup should work
    run "$link_dir/ralph" --model opus-4.5 -n 1
    assert_success
    assert_output --partial "Model:  opus-4.5"
}

@test "SCRIPT_DIR is exported for child processes" {
    # Use isolated test schema so task-peek returns data (prevents early loop exit)
    local test_schema="test_symlink_$(date +%s)_$$"
    local orig_url="$RALPH_DB_URL"
    psql "$orig_url" -tAX -c "CREATE SCHEMA $test_schema" >/dev/null 2>&1
    export RALPH_DB_URL="${orig_url}?options=-csearch_path%3D${test_schema}"
    "$SCRIPT_DIR/task" create dummy-001 "Dummy task" >/dev/null 2>&1

    # Replace the claude stub with one that writes SCRIPT_DIR to a file
    local marker="$TEST_WORK_DIR/script_dir_marker"
    cat > "$STUB_DIR/claude" <<STUB
#!/bin/bash
echo "\$SCRIPT_DIR" > "$marker"
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_success
    assert_file_exists "$marker"
    run cat "$marker"
    assert_output "$SCRIPT_DIR"

    # Cleanup test schema
    psql "$orig_url" -tAX -c "DROP SCHEMA $test_schema CASCADE" >/dev/null 2>&1
    export RALPH_DB_URL="$orig_url"
}
