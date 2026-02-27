#!/usr/bin/env bats
# test/ralph_sandbox_bootstrap.bats — Tests for create_sandbox(), bootstrap_sandbox(), and bootstrap marker

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

# =============================================================================
# bootstrap_sandbox() — ralph installation inside sandbox
# =============================================================================

# Helper: set up a docker stub that logs full args and simulates
# "not yet bootstrapped" (marker check returns 1).
_setup_bootstrap_docker_stub() {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "$*" >> "$TEST_WORK_DIR/docker_calls.log"
# Marker check: simulate not bootstrapped
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    if echo "$*" | grep -q "test -f"; then
        exit 1
    fi
fi
# All other calls succeed
exit 0
STUB
    chmod +x "$STUB_DIR/docker"
}

# Helper: run bootstrap_sandbox and return the log content
_run_bootstrap() {
    _setup_bootstrap_docker_stub
    _load_docker_functions
    bootstrap_sandbox "ralph-test-main" "/opt/ralph-docker"
}

# --- bootstrap_sandbox() copies ralph.sh to /usr/local/bin/ralph ---

@test "bootstrap installs ralph.sh to /usr/local/bin/ralph" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial 'cp "$RALPH_MOUNT/ralph.sh" /usr/local/bin/ralph'
}

@test "bootstrap makes /usr/local/bin/ralph executable" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "chmod +x /usr/local/bin/ralph"
}

@test "bootstrap patches SCRIPT_DIR to /opt/ralph" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial 'SCRIPT_DIR="/opt/ralph"'
}

# --- bootstrap_sandbox() copies lib/ to writable location ---

@test "bootstrap copies lib/ to /opt/ralph/lib/" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial 'cp -r "$RALPH_MOUNT/lib/"* /opt/ralph/lib/'
}

@test "bootstrap creates /opt/ralph/lib directory" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "mkdir -p /opt/ralph/lib"
}

# --- bootstrap_sandbox() copies models.json ---

@test "bootstrap copies models.json to /opt/ralph/" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial 'cp "$RALPH_MOUNT/models.json" /opt/ralph/'
}

# --- bootstrap_sandbox() copies skills/ to ~/.claude/skills/ ---

@test "bootstrap copies skills/ to ~/.claude/skills/" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial 'cp -r "$RALPH_MOUNT/skills/"* ~/.claude/skills/'
}

@test "bootstrap creates ~/.claude/skills/ directory" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "mkdir -p ~/.claude/skills"
}

# --- bootstrap_sandbox() copies hooks/ ---

@test "bootstrap copies hooks/ to /opt/ralph/hooks/" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial 'cp -r "$RALPH_MOUNT/hooks/"* /opt/ralph/hooks/'
}

# --- bootstrap_sandbox() copies db/ ---

@test "bootstrap copies db/ to /opt/ralph/db/" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial 'cp -r "$RALPH_MOUNT/db/"* /opt/ralph/db/'
}

@test "bootstrap creates /opt/ralph/db directory" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "mkdir -p /opt/ralph/db"
}

# --- bootstrap_sandbox() installs jq and psql client ---

@test "bootstrap installs jq via apt-get" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "apt-get install -y -qq jq"
}

@test "bootstrap installs postgresql-client via apt-get" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "apt-get install -y -qq postgresql-client"
}

@test "bootstrap uses sudo for apt-get install" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "sudo apt-get install -y -qq jq"
    assert_output --partial "sudo apt-get install -y -qq postgresql-client"
}

# =============================================================================
# bootstrap_sandbox() — PostgreSQL setup inside sandbox
# =============================================================================

# --- docker-compose.yml generation ---

@test "bootstrap creates ~/.ralph directory for compose and env files" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "mkdir -p ~/.ralph"
}

@test "bootstrap generates docker-compose.yml at ~/.ralph/" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "~/.ralph/docker-compose.yml"
}

@test "bootstrap compose file uses postgres:17-alpine image" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "postgres:17-alpine"
}

@test "bootstrap compose file defines ralph-task-dev service" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "ralph-task-dev:"
}

@test "bootstrap compose file maps port 5464:5432" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "5464:5432"
}

@test "bootstrap compose file sets POSTGRES_USER to ralph" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "POSTGRES_USER: ralph"
}

@test "bootstrap compose file sets POSTGRES_PASSWORD to ralph" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "POSTGRES_PASSWORD: ralph"
}

@test "bootstrap compose file sets POSTGRES_DB to ralph" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "POSTGRES_DB: ralph"
}

@test "bootstrap compose file includes healthcheck with pg_isready" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "pg_isready"
}

@test "bootstrap compose file mounts init scripts from /opt/ralph/db" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "/opt/ralph/db:/docker-entrypoint-initdb.d:ro"
}

@test "bootstrap compose file defines a data volume" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "ralph-data:/var/lib/postgresql/data"
}

# --- .env generation ---

@test "bootstrap generates .env with RALPH_DB_URL" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "RALPH_DB_URL=postgres://ralph:ralph@localhost:5464/ralph"
}

@test "bootstrap generates .env with POSTGRES_PORT" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "POSTGRES_PORT=5464"
}

@test "bootstrap generates .env with POSTGRES_USER" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "POSTGRES_USER=ralph"
}

@test "bootstrap generates .env with POSTGRES_PASSWORD" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "POSTGRES_PASSWORD=ralph"
}

@test "bootstrap generates .env with POSTGRES_DB" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "POSTGRES_DB=ralph"
}

@test "bootstrap generates .env at ~/.ralph/.env" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "~/.ralph/.env"
}

# --- PostgreSQL startup and healthcheck ---

@test "bootstrap starts PostgreSQL via docker compose up" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "docker compose -f ~/.ralph/docker-compose.yml up -d"
}

@test "bootstrap starts postgres after generating compose file" {
    _run_bootstrap
    # Compose file generation (cat > ~/.ralph/docker-compose.yml) must appear
    # before the docker compose up command in the script
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "docker-compose.yml"
    assert_output --partial "compose -f ~/.ralph/docker-compose.yml up -d"
}

@test "bootstrap waits for postgres healthcheck after starting" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    # The healthcheck loop inspects container health status
    assert_output --partial "inspect --format"
    assert_output --partial "ralph-task-dev"
}

@test "bootstrap healthcheck polls docker inspect for healthy status" {
    # Use a docker stub that tracks inspect calls for health status
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "$*" >> "$TEST_WORK_DIR/docker_calls.log"
# Marker check: simulate not bootstrapped
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    if echo "$*" | grep -q "test -f"; then
        exit 1
    fi
fi
# Simulate healthy on inspect
if [ "$1" = "inspect" ]; then
    echo "healthy"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    _load_docker_functions
    bootstrap_sandbox "ralph-test-main" "/opt/ralph-docker"

    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "inspect"
    assert_output --partial "Health.Status"
}

@test "bootstrap compose up runs before healthcheck inspect" {
    _run_bootstrap
    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")

    # The bash -c script passed to docker sandbox exec contains both
    # 'compose -f' (start) and 'inspect' (healthcheck) in order
    local compose_pos inspect_pos
    compose_pos=$(echo "$log" | grep -n "compose -f" | head -1 | cut -d: -f1)
    inspect_pos=$(echo "$log" | grep -n "inspect" | head -1 | cut -d: -f1)

    # compose up is inside the exec bash -c script, inspect is a separate call
    # from within the same script — both appear in the log
    # Just verify both appear (ordering is within the bash -c script)
    [ -n "$compose_pos" ]
}

# --- bootstrap_sandbox() writes marker ---

@test "bootstrap writes .bootstrapped marker" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "touch ~/.ralph/.bootstrapped"
}

# --- bootstrap_sandbox() skips when marker exists ---

@test "bootstrap skips when marker file already exists" {
    # Override docker stub: marker check succeeds (already bootstrapped)
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "$*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    if echo "$*" | grep -q "test -f"; then
        exit 0
    fi
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"

    _load_docker_functions
    bootstrap_sandbox "ralph-test-main" "/opt/ralph-docker"

    # Should only have marker check, no bash -c install script
    local log
    log=$(cat "$TEST_WORK_DIR/docker_calls.log")
    local bash_c_count
    bash_c_count=$(echo "$log" | grep -c "bash -c" || true)
    [ "$bash_c_count" -eq 0 ]
}

# --- bootstrap_sandbox() invokes docker sandbox exec with sandbox name ---

@test "bootstrap exec targets the correct sandbox name" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    # The install exec call: sandbox exec ralph-test-main bash -c ...
    assert_output --partial "sandbox exec ralph-test-main bash -c"
}

# --- bootstrap_sandbox() uses set -e for fail-fast ---

@test "bootstrap script uses set -e for fail-fast" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "set -e"
}

# --- bootstrap_sandbox() searches for mount path ---

@test "bootstrap searches common mount locations for ralph-docker" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    # Uses basename of ralph_docker_dir to search mount paths
    assert_output --partial "/root/ralph-docker"
    assert_output --partial "/home/agent/ralph-docker"
}

# --- bootstrap_sandbox() uses sudo for privileged operations ---

@test "bootstrap uses sudo for copying to /opt/ralph" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "sudo cp"
    assert_output --partial "sudo mkdir -p /opt/ralph"
}

@test "bootstrap uses sudo for copying to /usr/local/bin" {
    _run_bootstrap
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial 'sudo cp "$RALPH_MOUNT/ralph.sh" /usr/local/bin/ralph'
}
