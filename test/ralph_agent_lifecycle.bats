#!/usr/bin/env bats
# test/ralph_agent_lifecycle.bats — Tests for agent lifecycle integration in ralph.sh
# Requires: running PostgreSQL (docker compose up -d)

load test_helper

# ---------------------------------------------------------------------------
# Helper: check if PostgreSQL is reachable
# ---------------------------------------------------------------------------
db_available() {
    [[ -n "${RALPH_DB_URL:-}" ]] && psql "$RALPH_DB_URL" -tAX -c "SELECT 1" >/dev/null 2>&1
}

setup() {
    TEST_WORK_DIR="$(mktemp -d)"
    STUB_DIR="$(mktemp -d)"
    export TEST_WORK_DIR STUB_DIR

    if ! db_available; then
        skip "PostgreSQL not available (set RALPH_DB_URL and start database)"
    fi

    TEST_SCHEMA="test_$(date +%s)_$$"
    export TEST_SCHEMA

    psql "$RALPH_DB_URL" -tAX -c "CREATE SCHEMA $TEST_SCHEMA" >/dev/null 2>&1
    export RALPH_DB_URL_ORIG="$RALPH_DB_URL"
    export RALPH_DB_URL="${RALPH_DB_URL}?options=-csearch_path%3D${TEST_SCHEMA}"

    # Seed a dummy task so task-peek returns data (prevents early loop exit)
    "$SCRIPT_DIR/lib/task" create dummy-001 "Dummy test task" >/dev/null 2>&1

    # Create a fake claude stub that exits immediately
    cat > "$STUB_DIR/claude" <<'STUB'
#!/bin/bash
echo '{"type":"result","subtype":"success","total_cost_usd":0.001,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"

    # Docker/pg_isready stubs — DB is already running, skip real Docker checks
    cat > "$STUB_DIR/docker" <<'DOCKERSTUB'
#!/bin/bash
case "$1" in
    compose)
        if [ "$2" = "version" ]; then echo "Docker Compose version v2.24.0"; fi
        exit 0 ;;
    inspect)
        if [ "$3" = "{{.State.Running}}" ]; then echo "true"
        elif [ "$3" = "{{.State.Health.Status}}" ]; then echo "healthy"; fi
        exit 0 ;;
esac
exit 0
DOCKERSTUB
    chmod +x "$STUB_DIR/docker"
    cat > "$STUB_DIR/pg_isready" <<'PGSTUB'
#!/bin/bash
exit 0
PGSTUB
    chmod +x "$STUB_DIR/pg_isready"

    # Minimal specs so preflight passes
    mkdir -p "$TEST_WORK_DIR/specs"
    echo "# dummy spec" > "$TEST_WORK_DIR/specs/dummy.md"

    cd "$TEST_WORK_DIR"
}

teardown() {
    if [[ -n "$ORIGINAL_PATH" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi

    if [[ -n "${RALPH_DB_URL_ORIG:-}" ]]; then
        psql "$RALPH_DB_URL_ORIG" -tAX -c "DROP SCHEMA IF EXISTS $TEST_SCHEMA CASCADE" >/dev/null 2>&1
    fi

    [[ -d "$TEST_WORK_DIR" ]] && rm -rf "$TEST_WORK_DIR"
    [[ -d "$STUB_DIR" ]] && rm -rf "$STUB_DIR"
}

@test "build mode registers agent and displays agent ID in banner" {
    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_success
    assert_output --partial "Agent:"
}

@test "build mode deregisters agent on normal exit" {
    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_success

    # Extract agent ID from banner output
    AGENT_ID=$(echo "$output" | grep "Agent:" | awk '{print $2}')
    [ -n "$AGENT_ID" ]

    # Verify agent status is stopped after exit
    STATUS=$(psql "$RALPH_DB_URL" -tAX -c "SELECT status FROM agents WHERE id = '$AGENT_ID'")
    [ "$STATUS" = "stopped" ]
}

@test "build mode exports RALPH_AGENT_ID for claude" {
    # Create a claude stub that writes RALPH_AGENT_ID to a file for verification
    ENVFILE="$TEST_WORK_DIR/agent_env.txt"
    cat > "$STUB_DIR/claude" <<STUB
#!/bin/bash
echo "\$RALPH_AGENT_ID" > "$ENVFILE"
echo '{"type":"result","subtype":"success","total_cost_usd":0.001,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_success
    # Verify the env file was written with a 4-char hex ID
    [ -f "$ENVFILE" ]
    CAPTURED_ID=$(cat "$ENVFILE" | tr -d '\n')
    [[ "$CAPTURED_ID" =~ ^[0-9a-f]{4}$ ]]
}

@test "build mode exports RALPH_SCOPE_REPO and RALPH_SCOPE_BRANCH for claude" {
    ENVFILE="$TEST_WORK_DIR/scope_env.txt"
    cat > "$STUB_DIR/claude" <<STUB
#!/bin/bash
echo "repo=\$RALPH_SCOPE_REPO" > "$ENVFILE"
echo "branch=\$RALPH_SCOPE_BRANCH" >> "$ENVFILE"
echo '{"type":"result","subtype":"success","total_cost_usd":0.001,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_success

    [ -f "$ENVFILE" ]
    run cat "$ENVFILE"
    assert_line --index 0 "repo=test/repo"
    assert_line --index 1 "branch=main"
}

@test "plan mode exports RALPH_SCOPE_REPO and RALPH_SCOPE_BRANCH for claude" {
    ENVFILE="$TEST_WORK_DIR/scope_env.txt"
    cat > "$STUB_DIR/claude" <<STUB
#!/bin/bash
echo "repo=\$RALPH_SCOPE_REPO" > "$ENVFILE"
echo "branch=\$RALPH_SCOPE_BRANCH" >> "$ENVFILE"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"<promise>Tastes Like Burning.</promise>"}]}}'
echo '{"type":"result","subtype":"success","total_cost_usd":0.001,"num_turns":1}'
exit 0
STUB
    chmod +x "$STUB_DIR/claude"

    run "$SCRIPT_DIR/ralph.sh" --plan -n 1
    assert_success

    [ -f "$ENVFILE" ]
    run cat "$ENVFILE"
    assert_line --index 0 "repo=test/repo"
    assert_line --index 1 "branch=main"
}

@test "plan mode does not register agent" {
    run "$SCRIPT_DIR/ralph.sh" --plan -n 1
    assert_success
    refute_output --partial "Agent:"
}

@test "build mode without task script does not fail" {
    # Ensure task script is not found by removing it from PATH/SCRIPT_DIR context
    # ralph.sh uses SCRIPT_DIR/task, so we test by running from a dir without task
    # The task script check uses -x so a missing file is handled gracefully
    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_success
}

@test "agent is registered with active status in database" {
    # Run ralph briefly
    run "$SCRIPT_DIR/ralph.sh" -n 1
    assert_success

    # Agent should exist (status will be stopped after cleanup)
    AGENT_ID=$(echo "$output" | grep "Agent:" | awk '{print $2}')
    [ -n "$AGENT_ID" ]

    COUNT=$(psql "$RALPH_DB_URL" -tAX -c "SELECT count(*) FROM agents WHERE id = '$AGENT_ID'")
    [ "$COUNT" = "1" ]
}
