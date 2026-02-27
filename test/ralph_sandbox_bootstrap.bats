#!/usr/bin/env bats
# test/ralph_sandbox_bootstrap.bats — Tests for create_sandbox() and bootstrap marker

load test_helper

# Helper: source lib/docker.sh to get all functions
_load_docker_functions() {
    . "$SCRIPT_DIR/lib/docker.sh"
}

# Override setup to provide a docker stub that logs all calls
setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    mkdir -p "$TEST_WORK_DIR/specs"
    echo "# dummy spec" > "$TEST_WORK_DIR/specs/dummy.md"

    STUB_DIR="$(mktemp -d)"

    # docker stub that logs all calls to a file
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "$*" >> "$TEST_WORK_DIR/docker_calls.log"
# Handle compose version for check_docker_installed
if [ "$1" = "compose" ] && [ "$2" = "version" ]; then
    echo "Docker Compose version v2.24.0"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    # jq must be available for lookup_sandbox etc
    cat > "$STUB_DIR/pg_isready" <<'PGSTUB'
#!/bin/bash
exit 0
PGSTUB
    chmod +x "$STUB_DIR/pg_isready"

    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"
    export TEST_WORK_DIR
    export STUB_DIR

    # Prevent detect_backend() from reading host ~/.claude/settings.json
    export HOME="$TEST_WORK_DIR"
    unset CLAUDE_CODE_USE_BEDROCK

    cd "$TEST_WORK_DIR"
}

teardown() {
    if [[ -n "$ORIGINAL_PATH" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    if [[ -d "$TEST_WORK_DIR" ]]; then
        rm -rf "$TEST_WORK_DIR"
    fi
    if [[ -d "$STUB_DIR" ]]; then
        rm -rf "$STUB_DIR"
    fi
}

# --- create_sandbox() calls docker sandbox create with correct args ---

@test "create_sandbox calls docker sandbox create" {
    _load_docker_functions
    create_sandbox "ralph-test-main" "/home/user/project" "/opt/ralph-docker"
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "sandbox create"
}

@test "create_sandbox passes --name flag with sandbox name" {
    _load_docker_functions
    create_sandbox "ralph-myorg-myrepo-feature" "/home/user/project" "/opt/ralph-docker"
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "--name ralph-myorg-myrepo-feature"
}

@test "create_sandbox uses claude-code template" {
    _load_docker_functions
    create_sandbox "ralph-test-main" "/home/user/project" "/opt/ralph-docker"
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "-t docker/sandbox-templates:claude-code"
}

@test "create_sandbox uses shell agent type" {
    _load_docker_functions
    create_sandbox "ralph-test-main" "/home/user/project" "/opt/ralph-docker"
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "shell"
}

# --- target repo dir is passed as first shell arg ---

@test "create_sandbox passes target repo dir after shell keyword" {
    _load_docker_functions
    create_sandbox "ralph-test-main" "/home/user/my-project" "/opt/ralph-docker"
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "shell /home/user/my-project"
}

@test "create_sandbox passes target repo dir with spaces correctly" {
    _load_docker_functions
    create_sandbox "ralph-test-main" "/home/user/my project" "/opt/ralph-docker"
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "my project"
}

# --- ralph-docker dir is passed with :ro suffix ---

@test "create_sandbox passes ralph-docker dir with :ro suffix" {
    _load_docker_functions
    create_sandbox "ralph-test-main" "/home/user/project" "/opt/ralph-docker"
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "/opt/ralph-docker:ro"
}

@test "create_sandbox ralph-docker :ro mount appears after target repo dir" {
    _load_docker_functions
    create_sandbox "ralph-test-main" "/home/user/project" "/opt/ralph-docker"
    run cat "$TEST_WORK_DIR/docker_calls.log"
    # The full argument order: sandbox create -t <template> --name <name> shell <target> <ralph-docker>:ro
    assert_output --partial "shell /home/user/project /opt/ralph-docker:ro"
}

# --- docker sandbox create argument order matches spec ---

@test "create_sandbox full command matches spec format" {
    _load_docker_functions
    create_sandbox "ralph-test-main" "/home/user/project" "/opt/ralph-docker"
    run cat "$TEST_WORK_DIR/docker_calls.log"
    # Spec: docker sandbox create -t docker/sandbox-templates:claude-code --name <name> shell <target-repo-dir> <ralph-docker-dir>:ro
    assert_output --partial "sandbox create -t docker/sandbox-templates:claude-code --name ralph-test-main shell /home/user/project /opt/ralph-docker:ro"
}

# --- sandbox run is called after creation in dispatch ---

@test "dispatch calls docker sandbox run after create_sandbox" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "$*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    # Bootstrap marker check fails (not yet bootstrapped)
    if echo "$*" | grep -q "test -f"; then
        exit 1
    fi
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    # Verify sandbox run appears in the log after sandbox create
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "sandbox create"
    assert_output --partial "sandbox run"

    # Verify run comes after create (line ordering)
    local create_line run_line
    create_line=$(grep -n "sandbox create" "$TEST_WORK_DIR/docker_calls.log" | head -1 | cut -d: -f1)
    run_line=$(grep -n "sandbox run" "$TEST_WORK_DIR/docker_calls.log" | head -1 | cut -d: -f1)
    [ "$create_line" -lt "$run_line" ]
}

@test "dispatch passes sandbox name to docker sandbox run" {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "$*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    if echo "$*" | grep -q "test -f"; then
        exit 1
    fi
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "sandbox run ralph-test-repo-main"
}
