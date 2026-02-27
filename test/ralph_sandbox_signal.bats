#!/usr/bin/env bats
# test/ralph_sandbox_signal.bats — Tests for signal handling in --docker dispatch path

load test_helper

setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    mkdir -p "$TEST_WORK_DIR/specs"
    echo "# dummy spec" > "$TEST_WORK_DIR/specs/dummy.md"

    STUB_DIR="$(mktemp -d)"

    # claude stub
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo "CLAUDE_STUB_CALLED"
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    # Default docker stub: running sandbox
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_ARGS: $*"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"
    export TEST_WORK_DIR
    export STUB_DIR

    cd "$TEST_WORK_DIR"
}

# --- Signal handler verification ---

@test "--docker path does not source lib/signals.sh" {
    # Verify by checking that the --docker case in ralph.sh does not
    # contain any reference to signals.sh sourcing
    run grep -A 50 '^\s*--docker)' "$SCRIPT_DIR/ralph.sh"
    assert_success
    # Extract just the --docker case block (up to the next ;; )
    local docker_block
    docker_block=$(sed -n '/^[[:space:]]*--docker)/,/;;/p' "$SCRIPT_DIR/ralph.sh")
    # Verify signals.sh is NOT sourced in the --docker block
    if echo "$docker_block" | grep -q 'signals\.sh'; then
        fail "--docker case sources lib/signals.sh but should not"
    fi
}

@test "--docker path does not call setup_signal_handlers" {
    local docker_block
    docker_block=$(sed -n '/^[[:space:]]*--docker)/,/;;/p' "$SCRIPT_DIR/ralph.sh")
    if echo "$docker_block" | grep -q 'setup_signal_handlers'; then
        fail "--docker case calls setup_signal_handlers but should not"
    fi
}

@test "--docker path does not call setup_cleanup_trap" {
    local docker_block
    docker_block=$(sed -n '/^[[:space:]]*--docker)/,/;;/p' "$SCRIPT_DIR/ralph.sh")
    if echo "$docker_block" | grep -q 'setup_cleanup_trap'; then
        fail "--docker case calls setup_cleanup_trap but should not"
    fi
}

@test "plan path sources lib/signals.sh (confirming signal setup exists elsewhere)" {
    # Sanity check: verify that the plan subcommand DOES source signals.sh
    local plan_block
    plan_block=$(sed -n '/^[[:space:]]*plan)/,/;;/p' "$SCRIPT_DIR/ralph.sh")
    echo "$plan_block" | grep -q 'signals\.sh'
}

@test "build path sources lib/signals.sh (confirming signal setup exists elsewhere)" {
    # Sanity check: verify that the build subcommand DOES source signals.sh
    local build_block
    build_block=$(sed -n '/^[[:space:]]*build)/,/;;/p' "$SCRIPT_DIR/ralph.sh")
    echo "$build_block" | grep -q 'signals\.sh'
}

# --- Exit code forwarding ---

@test "--docker forwards exit code 0 from sandbox exec" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
}

@test "--docker forwards non-zero exit code from sandbox exec" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    exit 42
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    [ "$status" -eq 42 ]
}

@test "--docker forwards exit code 130 (SIGINT) from sandbox exec" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    exit 130
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    [ "$status" -eq 130 ]
}

@test "--docker forwards exit code 1 from sandbox exec" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    [ "$status" -eq 1 ]
}
