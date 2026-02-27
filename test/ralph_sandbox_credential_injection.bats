#!/usr/bin/env bats
# test/ralph_sandbox_credential_injection.bats — Tests for credential injection into sandbox exec calls

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

    # pg_isready stub
    cat > "$STUB_DIR/pg_isready" <<'PGSTUB'
#!/bin/bash
exit 0
PGSTUB
    chmod +x "$STUB_DIR/pg_isready"

    export ORIGINAL_PATH="$PATH"
    export PATH="$STUB_DIR:$PATH"
    export TEST_WORK_DIR
    export STUB_DIR

    # Default scope overrides (no git needed)
    export RALPH_SCOPE_REPO="test/repo"
    export RALPH_SCOPE_BRANCH="main"

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

# Helper: create a docker stub with sandbox running + logging
_setup_running_sandbox_docker_stub() {
    cat > "$STUB_DIR/docker" <<'STUB'
#!/bin/bash
echo "DOCKER_CMD: $*" >> "$TEST_WORK_DIR/docker_calls.log"
if [ "$1" = "sandbox" ] && [ "$2" = "ls" ]; then
    echo '[{"name":"ralph-test-repo-main","status":"running"}]'
    exit 0
fi
if [ "$1" = "sandbox" ] && [ "$2" = "exec" ]; then
    echo "EXEC_ARGS: $*"
    exit 0
fi
if [ "$1" = "compose" ] && [ "$2" = "version" ]; then
    echo "Docker Compose version v2.24.0"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/docker"
}

# Helper: create aws stub that returns valid credentials
_setup_aws_stub() {
    cat > "$STUB_DIR/aws" <<'STUB'
#!/bin/bash
if [ "$1" = "configure" ] && [ "$2" = "export-credentials" ]; then
    cat <<'JSON'
{
  "Version": 1,
  "AccessKeyId": "AKIAIOSFODNN7EXAMPLE",
  "SecretAccessKey": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
  "SessionToken": "FwoGZXIvYXdzEBYaDH7example-session-token"
}
JSON
    exit 0
fi
if [ "$1" = "configure" ] && [ "$2" = "get" ] && [ "$3" = "region" ]; then
    echo "us-west-2"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/aws"
}

# --- exec includes -e AWS_ACCESS_KEY_ID=... flags when backend is bedrock ---

@test "exec includes -e AWS_ACCESS_KEY_ID when backend is bedrock" {
    _setup_running_sandbox_docker_stub
    _setup_aws_stub
    export CLAUDE_CODE_USE_BEDROCK=1
    unset AWS_DEFAULT_REGION

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    assert_output --partial "-e AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"
}

@test "exec includes -e AWS_SECRET_ACCESS_KEY when backend is bedrock" {
    _setup_running_sandbox_docker_stub
    _setup_aws_stub
    export CLAUDE_CODE_USE_BEDROCK=1
    unset AWS_DEFAULT_REGION

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    assert_output --partial "-e AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
}

@test "exec includes -e AWS_SESSION_TOKEN when backend is bedrock" {
    _setup_running_sandbox_docker_stub
    _setup_aws_stub
    export CLAUDE_CODE_USE_BEDROCK=1
    unset AWS_DEFAULT_REGION

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    assert_output --partial "-e AWS_SESSION_TOKEN=FwoGZXIvYXdzEBYaDH7example-session-token"
}

@test "exec includes -e AWS_DEFAULT_REGION when backend is bedrock" {
    _setup_running_sandbox_docker_stub
    _setup_aws_stub
    export CLAUDE_CODE_USE_BEDROCK=1
    unset AWS_DEFAULT_REGION

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    assert_output --partial "-e AWS_DEFAULT_REGION=us-west-2"
}

# --- exec includes -e CLAUDE_CODE_USE_BEDROCK=1 when set ---

@test "exec includes -e CLAUDE_CODE_USE_BEDROCK=1 when backend is bedrock" {
    _setup_running_sandbox_docker_stub
    _setup_aws_stub
    export CLAUDE_CODE_USE_BEDROCK=1
    unset AWS_DEFAULT_REGION

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    assert_output --partial "-e CLAUDE_CODE_USE_BEDROCK=1"
}

# --- exec omits AWS flags when backend is anthropic ---

@test "exec omits AWS flags when backend is anthropic" {
    _setup_running_sandbox_docker_stub
    unset CLAUDE_CODE_USE_BEDROCK
    # Override HOME so detect_backend() doesn't read host ~/.claude/settings.json
    export HOME="$TEST_WORK_DIR"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    refute_output --partial "AWS_ACCESS_KEY_ID"
    refute_output --partial "AWS_SECRET_ACCESS_KEY"
    refute_output --partial "AWS_SESSION_TOKEN"
    refute_output --partial "AWS_DEFAULT_REGION"
}

@test "exec omits CLAUDE_CODE_USE_BEDROCK when backend is anthropic" {
    _setup_running_sandbox_docker_stub
    unset CLAUDE_CODE_USE_BEDROCK
    # Override HOME so detect_backend() doesn't read host ~/.claude/settings.json
    export HOME="$TEST_WORK_DIR"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    refute_output --partial "CLAUDE_CODE_USE_BEDROCK"
}

# --- all 4 AWS vars are present in a single exec call ---

@test "exec passes all 4 AWS credential flags in a single exec call" {
    _setup_running_sandbox_docker_stub
    _setup_aws_stub
    export CLAUDE_CODE_USE_BEDROCK=1
    unset AWS_DEFAULT_REGION

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    # All flags should be present in the exec output
    assert_output --partial "-e AWS_ACCESS_KEY_ID="
    assert_output --partial "-e AWS_SECRET_ACCESS_KEY="
    assert_output --partial "-e AWS_SESSION_TOKEN="
    assert_output --partial "-e AWS_DEFAULT_REGION="
    assert_output --partial "-e CLAUDE_CODE_USE_BEDROCK=1"
}

# --- credential injection happens on exec, not just bootstrap ---

@test "credential injection on exec for running sandbox (no create/bootstrap)" {
    _setup_running_sandbox_docker_stub
    _setup_aws_stub
    export CLAUDE_CODE_USE_BEDROCK=1
    unset AWS_DEFAULT_REGION

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    # Verify no create was needed (sandbox was already running)
    run cat "$TEST_WORK_DIR/docker_calls.log"
    refute_output --partial "sandbox create"
    # But credentials are still injected
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "-e AWS_ACCESS_KEY_ID="
}

# --- exec preserves existing AWS_DEFAULT_REGION from host env ---

@test "exec uses host AWS_DEFAULT_REGION when set" {
    _setup_running_sandbox_docker_stub
    _setup_aws_stub
    export CLAUDE_CODE_USE_BEDROCK=1
    export AWS_DEFAULT_REGION="eu-west-1"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    assert_output --partial "-e AWS_DEFAULT_REGION=eu-west-1"
}

# --- exec exits 1 when bedrock credentials fail ---

@test "exec exits 1 when bedrock credential resolution fails" {
    _setup_running_sandbox_docker_stub
    cat > "$STUB_DIR/aws" <<'STUB'
#!/bin/bash
if [ "$1" = "configure" ] && [ "$2" = "export-credentials" ]; then
    echo "The SSO session associated with this profile has expired" >&2
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/aws"
    export CLAUDE_CODE_USE_BEDROCK=1

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_failure
    assert_output --partial "aws sso login"
}

# --- subcommand and flags are preserved after credential injection ---

@test "exec preserves subcommand and flags after credential -e flags" {
    _setup_running_sandbox_docker_stub
    _setup_aws_stub
    export CLAUDE_CODE_USE_BEDROCK=1
    unset AWS_DEFAULT_REGION

    run "$SCRIPT_DIR/ralph.sh" --docker build -n 3 --model opus-4.5
    assert_success
    assert_output --partial "ralph build -n 3 --model opus-4.5"
}

# --- RALPH_DOCKER_ENV custom variable passthrough ---

@test "RALPH_DOCKER_ENV=FOO,BAR adds -e FOO=val -e BAR=val to exec" {
    _setup_running_sandbox_docker_stub
    unset CLAUDE_CODE_USE_BEDROCK
    export HOME="$TEST_WORK_DIR"
    export RALPH_DOCKER_ENV="FOO,BAR"
    export FOO="hello"
    export BAR="world"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    assert_output --partial "-e FOO=hello"
    assert_output --partial "-e BAR=world"
}

@test "RALPH_DOCKER_ENV skips unset variables silently" {
    _setup_running_sandbox_docker_stub
    unset CLAUDE_CODE_USE_BEDROCK
    export HOME="$TEST_WORK_DIR"
    export RALPH_DOCKER_ENV="SET_VAR,UNSET_VAR"
    export SET_VAR="present"
    unset UNSET_VAR

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    assert_output --partial "-e SET_VAR=present"
    refute_output --partial "UNSET_VAR"
}

@test "empty RALPH_DOCKER_ENV adds no extra -e flags" {
    _setup_running_sandbox_docker_stub
    unset CLAUDE_CODE_USE_BEDROCK
    export HOME="$TEST_WORK_DIR"
    export RALPH_DOCKER_ENV=""

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    # With anthropic backend and empty RALPH_DOCKER_ENV, no -e flags at all
    refute_output --partial " -e "
}

@test "unset RALPH_DOCKER_ENV adds no extra -e flags" {
    _setup_running_sandbox_docker_stub
    unset CLAUDE_CODE_USE_BEDROCK
    export HOME="$TEST_WORK_DIR"
    unset RALPH_DOCKER_ENV

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    refute_output --partial " -e "
}

@test "RALPH_DOCKER_ENV works alongside bedrock credential flags" {
    _setup_running_sandbox_docker_stub
    _setup_aws_stub
    export CLAUDE_CODE_USE_BEDROCK=1
    unset AWS_DEFAULT_REGION
    export RALPH_DOCKER_ENV="MY_CUSTOM"
    export MY_CUSTOM="customval"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success
    # Both bedrock and custom env flags should be present
    assert_output --partial "-e AWS_ACCESS_KEY_ID="
    assert_output --partial "-e MY_CUSTOM=customval"
}
