#!/usr/bin/env bats
# test/ralph_sandbox_credentials_integration.bats — Integration tests for sandbox credential flow
#
# These tests exercise the full ralph.sh --docker pipeline end-to-end,
# verifying that credentials are resolved, injected via -e flags on the
# docker sandbox exec call, and that errors propagate correctly.
#
# Each test verifies the docker_calls.log to confirm the exact exec
# command structure rather than relying solely on stdout.

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

# ============================================================
# Section: Bedrock backend resolves and injects AWS credentials
# ============================================================

@test "integration: bedrock backend resolves credentials and injects all 4 AWS vars into exec" {
    _setup_running_sandbox_docker_stub
    _setup_aws_stub
    export CLAUDE_CODE_USE_BEDROCK=1
    unset AWS_DEFAULT_REGION

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    # Verify docker_calls.log contains a sandbox exec with all credential flags
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "-e AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"
    assert_output --partial "-e AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    assert_output --partial "-e AWS_SESSION_TOKEN=FwoGZXIvYXdzEBYaDH7example-session-token"
    assert_output --partial "-e AWS_DEFAULT_REGION=us-west-2"
    assert_output --partial "-e CLAUDE_CODE_USE_BEDROCK=1"
}

@test "integration: bedrock exec log shows credentials injected on same exec call as ralph command" {
    _setup_running_sandbox_docker_stub
    _setup_aws_stub
    export CLAUDE_CODE_USE_BEDROCK=1
    unset AWS_DEFAULT_REGION

    run "$SCRIPT_DIR/ralph.sh" --docker build -n 2

    # The exec line in the log should contain both credentials and the forwarded args
    run cat "$TEST_WORK_DIR/docker_calls.log"
    # Find the sandbox exec line and verify it has all pieces
    run grep "sandbox exec" "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "-e AWS_ACCESS_KEY_ID="
    assert_output --partial "ralph build -n 2"
}

@test "integration: bedrock uses host AWS_DEFAULT_REGION when set instead of aws configure" {
    _setup_running_sandbox_docker_stub
    _setup_aws_stub
    export CLAUDE_CODE_USE_BEDROCK=1
    export AWS_DEFAULT_REGION="eu-central-1"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "-e AWS_DEFAULT_REGION=eu-central-1"
    # Should NOT contain the aws configure fallback region
    refute_output --partial "us-west-2"
}

@test "integration: bedrock credentials injected for running sandbox without create/bootstrap" {
    _setup_running_sandbox_docker_stub
    _setup_aws_stub
    export CLAUDE_CODE_USE_BEDROCK=1
    unset AWS_DEFAULT_REGION

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    # Verify no sandbox create occurred (sandbox was already running)
    run cat "$TEST_WORK_DIR/docker_calls.log"
    refute_output --partial "sandbox create"
    # But credentials are still present
    assert_output --partial "-e AWS_ACCESS_KEY_ID="
}

# ============================================================
# Section: Anthropic backend skips AWS credential resolution
# ============================================================

@test "integration: anthropic backend exec has no AWS credential flags" {
    _setup_running_sandbox_docker_stub
    unset CLAUDE_CODE_USE_BEDROCK
    # Override HOME so detect_backend() doesn't read host settings
    export HOME="$TEST_WORK_DIR"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    # Verify docker_calls.log has exec but NO credential flags
    run cat "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "sandbox exec"
    refute_output --partial "AWS_ACCESS_KEY_ID"
    refute_output --partial "AWS_SECRET_ACCESS_KEY"
    refute_output --partial "AWS_SESSION_TOKEN"
    refute_output --partial "AWS_DEFAULT_REGION"
    refute_output --partial "CLAUDE_CODE_USE_BEDROCK"
}

@test "integration: anthropic backend does not invoke aws CLI at all" {
    _setup_running_sandbox_docker_stub
    unset CLAUDE_CODE_USE_BEDROCK
    export HOME="$TEST_WORK_DIR"

    # Create an aws stub that records invocations
    cat > "$STUB_DIR/aws" <<'STUB'
#!/bin/bash
echo "AWS_CLI_CALLED: $*" >> "$TEST_WORK_DIR/aws_calls.log"
exit 0
STUB
    chmod +x "$STUB_DIR/aws"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    # aws should never have been called
    if [ -f "$TEST_WORK_DIR/aws_calls.log" ]; then
        run cat "$TEST_WORK_DIR/aws_calls.log"
        assert_output ""
    fi
}

@test "integration: anthropic exec has no -e flags at all without RALPH_DOCKER_ENV" {
    _setup_running_sandbox_docker_stub
    unset CLAUDE_CODE_USE_BEDROCK
    unset RALPH_DOCKER_ENV
    export HOME="$TEST_WORK_DIR"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    # The exec line should not contain any -e flags
    run grep "sandbox exec" "$TEST_WORK_DIR/docker_calls.log"
    refute_output --partial " -e "
}

# ============================================================
# Section: Expired credentials produce actionable error
# ============================================================

@test "integration: expired SSO credentials exit 1 with 'aws sso login' suggestion" {
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

@test "integration: expired credentials do not exec into sandbox" {
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

    # Verify no sandbox exec was attempted
    if [ -f "$TEST_WORK_DIR/docker_calls.log" ]; then
        run grep "sandbox exec" "$TEST_WORK_DIR/docker_calls.log"
        assert_output ""
    fi
}

@test "integration: missing aws CLI with bedrock backend exits 1 with install URL" {
    _setup_running_sandbox_docker_stub
    # Remove any aws from PATH
    rm -f "$STUB_DIR/aws"
    local new_path=""
    IFS=: read -ra dirs <<< "$PATH"
    for d in "${dirs[@]}"; do
        [ -x "$d/aws" ] && continue
        if [ -z "$new_path" ]; then
            new_path="$d"
        else
            new_path="$new_path:$d"
        fi
    done
    export PATH="$new_path"

    export CLAUDE_CODE_USE_BEDROCK=1

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_failure
    assert_output --partial "aws CLI not found"
    assert_output --partial "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
}

@test "integration: missing aws CLI does not exec into sandbox" {
    _setup_running_sandbox_docker_stub
    rm -f "$STUB_DIR/aws"
    local new_path=""
    IFS=: read -ra dirs <<< "$PATH"
    for d in "${dirs[@]}"; do
        [ -x "$d/aws" ] && continue
        if [ -z "$new_path" ]; then
            new_path="$d"
        else
            new_path="$new_path:$d"
        fi
    done
    export PATH="$new_path"

    export CLAUDE_CODE_USE_BEDROCK=1

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_failure

    # No sandbox exec should have occurred
    if [ -f "$TEST_WORK_DIR/docker_calls.log" ]; then
        run grep "sandbox exec" "$TEST_WORK_DIR/docker_calls.log"
        assert_output ""
    fi
}

@test "integration: credential failure error includes 'Failed to resolve AWS credentials'" {
    _setup_running_sandbox_docker_stub
    cat > "$STUB_DIR/aws" <<'STUB'
#!/bin/bash
if [ "$1" = "configure" ] && [ "$2" = "export-credentials" ]; then
    echo "Unable to locate credentials" >&2
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/aws"
    export CLAUDE_CODE_USE_BEDROCK=1

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_failure
    assert_output --partial "Failed to resolve AWS credentials"
}

@test "integration: region resolution failure exits 1 with actionable error" {
    _setup_running_sandbox_docker_stub
    cat > "$STUB_DIR/aws" <<'STUB'
#!/bin/bash
if [ "$1" = "configure" ] && [ "$2" = "export-credentials" ]; then
    cat <<'JSON'
{
  "Version": 1,
  "AccessKeyId": "AKIAEXAMPLE",
  "SecretAccessKey": "SECRETEXAMPLE",
  "SessionToken": "TOKENEXAMPLE"
}
JSON
    exit 0
fi
if [ "$1" = "configure" ] && [ "$2" = "get" ] && [ "$3" = "region" ]; then
    echo ""
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/aws"
    export CLAUDE_CODE_USE_BEDROCK=1
    unset AWS_DEFAULT_REGION

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_failure
    assert_output --partial "AWS region could not be determined"
}

# ============================================================
# Section: RALPH_DOCKER_ENV passthrough works end-to-end
# ============================================================

@test "integration: RALPH_DOCKER_ENV passes custom vars into exec via docker_calls.log" {
    _setup_running_sandbox_docker_stub
    unset CLAUDE_CODE_USE_BEDROCK
    export HOME="$TEST_WORK_DIR"
    export RALPH_DOCKER_ENV="MY_API_KEY,MY_SECRET"
    export MY_API_KEY="key123"
    export MY_SECRET="secret456"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    # Verify docker_calls.log has the custom env flags on the exec line
    run grep "sandbox exec" "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "-e MY_API_KEY=key123"
    assert_output --partial "-e MY_SECRET=secret456"
}

@test "integration: RALPH_DOCKER_ENV with unset vars skips them in docker_calls.log" {
    _setup_running_sandbox_docker_stub
    unset CLAUDE_CODE_USE_BEDROCK
    export HOME="$TEST_WORK_DIR"
    export RALPH_DOCKER_ENV="PRESENT_VAR,ABSENT_VAR"
    export PRESENT_VAR="here"
    unset ABSENT_VAR

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    run grep "sandbox exec" "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "-e PRESENT_VAR=here"
    refute_output --partial "ABSENT_VAR"
}

@test "integration: RALPH_DOCKER_ENV combined with bedrock credentials in docker_calls.log" {
    _setup_running_sandbox_docker_stub
    _setup_aws_stub
    export CLAUDE_CODE_USE_BEDROCK=1
    unset AWS_DEFAULT_REGION
    export RALPH_DOCKER_ENV="CUSTOM_FLAG"
    export CUSTOM_FLAG="enabled"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    # Both bedrock credentials and custom env should appear on the exec line
    run grep "sandbox exec" "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "-e AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"
    assert_output --partial "-e CLAUDE_CODE_USE_BEDROCK=1"
    assert_output --partial "-e CUSTOM_FLAG=enabled"
}

@test "integration: empty RALPH_DOCKER_ENV adds no flags to exec in docker_calls.log" {
    _setup_running_sandbox_docker_stub
    unset CLAUDE_CODE_USE_BEDROCK
    export HOME="$TEST_WORK_DIR"
    export RALPH_DOCKER_ENV=""

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    run grep "sandbox exec" "$TEST_WORK_DIR/docker_calls.log"
    refute_output --partial " -e "
}

@test "integration: RALPH_DOCKER_ENV preserves values with special characters" {
    _setup_running_sandbox_docker_stub
    unset CLAUDE_CODE_USE_BEDROCK
    export HOME="$TEST_WORK_DIR"
    export RALPH_DOCKER_ENV="DB_URL"
    export DB_URL="postgres://user:pass@host:5432/db"

    run "$SCRIPT_DIR/ralph.sh" --docker build
    assert_success

    run grep "sandbox exec" "$TEST_WORK_DIR/docker_calls.log"
    assert_output --partial "-e DB_URL=postgres://user:pass@host:5432/db"
}
