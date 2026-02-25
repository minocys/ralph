#!/usr/bin/env bats
# test/compose_worker.bats — ralph-worker service tests for docker-compose.yml
#
# Validates the docker-compose.yml structure using grep-based checks.
# Does NOT start containers.

_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
_SCRIPT_DIR="$(cd "$_TEST_DIR/.." && pwd)"

load "$_TEST_DIR/libs/bats-support/load"
load "$_TEST_DIR/libs/bats-assert/load"

COMPOSE_FILE="$_SCRIPT_DIR/docker-compose.yml"

# --- ralph-worker service exists ---

@test "docker-compose.yml defines ralph-worker service" {
    run grep -E '^\s+ralph-worker:' "$COMPOSE_FILE"
    assert_success
}

# --- image ---

@test "ralph-worker uses image ralph-worker:latest" {
    run sed -n '/^  ralph-worker:/,/^  [a-z]/p' "$COMPOSE_FILE"
    assert_success
    assert_output --partial "image: ralph-worker:latest"
}

# --- container_name ---

@test "ralph-worker has container_name ralph-worker" {
    run sed -n '/^  ralph-worker:/,/^  [a-z]/p' "$COMPOSE_FILE"
    assert_success
    assert_output --partial "container_name: ralph-worker"
}

# --- env_file ---

@test "ralph-worker uses env_file .env" {
    run sed -n '/^  ralph-worker:/,/^  [a-z]/p' "$COMPOSE_FILE"
    assert_success
    assert_output --partial "env_file: .env"
}

# --- depends_on ---

@test "ralph-worker depends_on ralph-task-db" {
    run sed -n '/^  ralph-worker:/,/^  [a-z]/p' "$COMPOSE_FILE"
    assert_success
    assert_output --partial "depends_on:"
    assert_output --partial "ralph-task-db:"
}

@test "ralph-worker depends_on ralph-task-db with service_healthy condition" {
    run sed -n '/^  ralph-worker:/,/^  [a-z]/p' "$COMPOSE_FILE"
    assert_success
    assert_output --partial "condition: service_healthy"
}

# --- networks ---

@test "ralph-worker is attached to ralph-net network" {
    run sed -n '/^  ralph-worker:/,/^  [a-z]/p' "$COMPOSE_FILE"
    assert_success
    assert_output --partial "ralph-net"
}

# --- environment: RALPH_DB_URL ---

@test "ralph-worker sets RALPH_DB_URL to internal network address" {
    run sed -n '/^  ralph-worker:/,/^  [a-z]/p' "$COMPOSE_FILE"
    assert_success
    assert_output --partial "RALPH_DB_URL: postgres://ralph:ralph@ralph-task-db:5432/ralph"
}

@test "ralph-worker environment section exists" {
    run sed -n '/^  ralph-worker:/,/^  [a-z]/p' "$COMPOSE_FILE"
    assert_success
    assert_output --partial "environment:"
}

# --- volumes ---

@test "ralph-worker has volumes section" {
    run sed -n '/^  ralph-worker:/,/^  [a-z]/p' "$COMPOSE_FILE"
    assert_success
    assert_output --partial "volumes:"
}

@test "ralph-worker mounts project directory to /workspace/project" {
    run sed -n '/^  ralph-worker:/,/^  [a-z]/p' "$COMPOSE_FILE"
    assert_success
    assert_output --partial '/workspace/project'
}

@test "ralph-worker project mount uses RALPH_PROJECT_DIR variable interpolation" {
    run sed -n '/^  ralph-worker:/,/^  [a-z]/p' "$COMPOSE_FILE"
    assert_success
    assert_output --partial 'RALPH_PROJECT_DIR'
}

@test "ralph-worker project mount defaults to current directory" {
    run grep 'RALPH_PROJECT_DIR:-\.' "$COMPOSE_FILE"
    assert_success
}

# --- ~/.claude bind mount ---

@test "ralph-worker mounts ~/.claude to /mnt/claude-host read-only" {
    run sed -n '/^  ralph-worker:/,/^  [a-z]/p' "$COMPOSE_FILE"
    assert_success
    assert_output --partial '/mnt/claude-host:ro'
}

@test "ralph-worker ~/.claude mount uses home directory tilde" {
    run grep '~/.claude:/mnt/claude-host:ro' "$COMPOSE_FILE"
    assert_success
}

# --- ~/.gitconfig bind mount ---

@test "ralph-worker mounts ~/.gitconfig to /home/ralph/.gitconfig read-only" {
    run sed -n '/^  ralph-worker:/,/^  [a-z]/p' "$COMPOSE_FILE"
    assert_success
    assert_output --partial '/home/ralph/.gitconfig:ro'
}

@test "ralph-worker ~/.gitconfig mount uses home directory tilde" {
    run grep '~/.gitconfig:/home/ralph/.gitconfig:ro' "$COMPOSE_FILE"
    assert_success
}

# --- environment: API credential passthrough ---

@test "ralph-worker passes ANTHROPIC_API_KEY with empty default" {
    run grep 'ANTHROPIC_API_KEY:.*{ANTHROPIC_API_KEY:-}' "$COMPOSE_FILE"
    assert_success
}

@test "ralph-worker passes AWS_ACCESS_KEY_ID with empty default" {
    run grep 'AWS_ACCESS_KEY_ID:.*{AWS_ACCESS_KEY_ID:-}' "$COMPOSE_FILE"
    assert_success
}

@test "ralph-worker passes AWS_SECRET_ACCESS_KEY with empty default" {
    run grep 'AWS_SECRET_ACCESS_KEY:.*{AWS_SECRET_ACCESS_KEY:-}' "$COMPOSE_FILE"
    assert_success
}

@test "ralph-worker passes AWS_SESSION_TOKEN with empty default" {
    run grep 'AWS_SESSION_TOKEN:.*{AWS_SESSION_TOKEN:-}' "$COMPOSE_FILE"
    assert_success
}

@test "ralph-worker passes CLAUDE_CODE_USE_BEDROCK with empty default" {
    run grep 'CLAUDE_CODE_USE_BEDROCK:.*{CLAUDE_CODE_USE_BEDROCK:-}' "$COMPOSE_FILE"
    assert_success
}

@test "API credential env vars use empty defaults only" {
    # Each credential var should have :- immediately followed by } (no default value)
    for var in ANTHROPIC_API_KEY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN CLAUDE_CODE_USE_BEDROCK; do
        run grep "${var}:.*\${${var}:-}" "$COMPOSE_FILE"
        assert_success
    done
}

# --- existing service unchanged ---

@test "ralph-task-db service still exists" {
    run grep -E '^\s+ralph-task-db:' "$COMPOSE_FILE"
    assert_success
}

@test "ralph-net network still defined" {
    run grep -E '^networks:' "$COMPOSE_FILE"
    assert_success
    run grep -E '^\s+ralph-net:' "$COMPOSE_FILE"
    assert_success
}
