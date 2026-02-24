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
    # Copy ralph.sh + lib/ into TEST_WORK_DIR with a task stub so the build
    # loop doesn't exit early on empty peek (avoids needing a real DB here)
    # Resolve to physical path (ralph.sh uses cd -P which resolves symlinks)
    TEST_WORK_DIR="$(cd -P "$TEST_WORK_DIR" && pwd)"
    cp "$SCRIPT_DIR/ralph.sh" "$TEST_WORK_DIR/ralph.sh"
    chmod +x "$TEST_WORK_DIR/ralph.sh"
    mkdir -p "$TEST_WORK_DIR/lib"
    for f in "$SCRIPT_DIR"/lib/*.sh; do
        cp "$f" "$TEST_WORK_DIR/lib/"
    done

    cat > "$TEST_WORK_DIR/lib/task" <<'TASKSTUB'
#!/bin/bash
case "$1" in
    agent) case "$2" in register) echo "t001" ;; esac; exit 0 ;;
    peek) echo '{"id":"d","t":"Dummy","s":"open","p":2}'; exit 0 ;;
    *) exit 0 ;;
esac
TASKSTUB
    chmod +x "$TEST_WORK_DIR/lib/task"

    # Replace the claude stub with one that writes SCRIPT_DIR to a file
    local marker="$TEST_WORK_DIR/script_dir_marker"
    cat > "$STUB_DIR/claude" <<STUB
#!/bin/bash
echo "\$SCRIPT_DIR" > "$marker"
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$TEST_WORK_DIR/ralph.sh" -n 1
    assert_success
    assert_file_exists "$marker"
    run cat "$marker"
    assert_output "$TEST_WORK_DIR"
}
