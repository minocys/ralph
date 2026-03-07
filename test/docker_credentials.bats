#!/usr/bin/env bats
# test/docker_credentials.bats — tests for resolve_aws_credentials() in lib/docker.sh
#
# Covers: credential resolution from environment, aws CLI fallback,
#         region resolution, error handling, and credential flag assembly.

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Source docker.sh and config.sh for detect_backend + resolve_aws_credentials
source_libs() {
    source "$SCRIPT_DIR/lib/config.sh"
    source "$SCRIPT_DIR/lib/docker.sh"
}

# Create an aws CLI stub that returns credentials
# $1: access key
# $2: secret key
# $3: session token
# $4: region (for aws configure get region)
create_aws_stub() {
    local access_key="${1:-AKIAIOSFODNN7EXAMPLE}"
    local secret_key="${2:-wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY}"
    local session_token="${3:-FwoGZXIvYXdzEBYaDH}"
    local region="${4:-us-east-1}"
    cat > "$STUB_DIR/aws" <<AWSSTUB
#!/bin/bash
case "\$*" in
    "sts get-caller-identity")
        echo '{"Account":"123456789012","Arn":"arn:aws:iam::123456789012:user/test"}'
        exit 0
        ;;
    "configure get region")
        echo "$region"
        exit 0
        ;;
    "configure export-credentials --format env")
        cat <<'CREDS'
export AWS_ACCESS_KEY_ID=$access_key
export AWS_SECRET_ACCESS_KEY=$secret_key
export AWS_SESSION_TOKEN=$session_token
CREDS
        exit 0
        ;;
esac
exit 1
AWSSTUB
    chmod +x "$STUB_DIR/aws"
}

# Create an aws stub that fails (simulating expired SSO or no config)
create_aws_stub_fail() {
    cat > "$STUB_DIR/aws" <<'AWSSTUB'
#!/bin/bash
echo "Unable to locate credentials. You can configure credentials by running \"aws configure\"." >&2
exit 255
AWSSTUB
    chmod +x "$STUB_DIR/aws"
}

# Create an aws stub where sts succeeds but configure get region fails
create_aws_stub_no_region() {
    cat > "$STUB_DIR/aws" <<'AWSSTUB'
#!/bin/bash
case "$*" in
    "sts get-caller-identity")
        echo '{"Account":"123456789012"}'
        exit 0
        ;;
    "configure get region")
        exit 1
        ;;
esac
exit 1
AWSSTUB
    chmod +x "$STUB_DIR/aws"
}

setup() {
    common_setup
    # Ensure bedrock-related vars are unset
    unset CLAUDE_CODE_USE_BEDROCK
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    unset AWS_DEFAULT_REGION
}

# ---------------------------------------------------------------------------
# resolve_aws_credentials: success cases with env vars already set
# ---------------------------------------------------------------------------

@test "resolve_aws_credentials: uses existing AWS env vars when all are set" {
    export AWS_ACCESS_KEY_ID="AKIAEXISTING"
    export AWS_SECRET_ACCESS_KEY="existingsecret"
    export AWS_SESSION_TOKEN="existingtoken"
    export AWS_DEFAULT_REGION="us-west-2"
    source_libs
    run resolve_aws_credentials
    assert_success
    # Env vars should remain unchanged
}

@test "resolve_aws_credentials: resolves region from aws configure when AWS_DEFAULT_REGION unset" {
    export AWS_ACCESS_KEY_ID="AKIAEXISTING"
    export AWS_SECRET_ACCESS_KEY="existingsecret"
    export AWS_SESSION_TOKEN="existingtoken"
    create_aws_stub "ignored" "ignored" "ignored" "eu-west-1"
    source_libs
    run resolve_aws_credentials
    assert_success
    assert_output --partial "eu-west-1"
}

# ---------------------------------------------------------------------------
# resolve_aws_credentials: fallback to aws CLI
# ---------------------------------------------------------------------------

@test "resolve_aws_credentials: calls aws sts get-caller-identity to verify credentials" {
    create_aws_stub
    source_libs
    run resolve_aws_credentials
    assert_success
}

@test "resolve_aws_credentials: exports region from aws configure get region" {
    create_aws_stub "AKIATEST" "secret" "token" "ap-southeast-1"
    source_libs
    run resolve_aws_credentials
    assert_success
    assert_output --partial "ap-southeast-1"
}

# ---------------------------------------------------------------------------
# resolve_aws_credentials: error cases
# ---------------------------------------------------------------------------

@test "resolve_aws_credentials: exits 1 when aws CLI is not installed" {
    # Remove aws from PATH
    rm -f "$STUB_DIR/aws"
    # Ensure no real aws binary is picked up by restricting to stub dir only
    local save_path="$PATH"
    # Keep only essentials
    export PATH="$STUB_DIR:/usr/bin:/bin"
    source_libs
    run resolve_aws_credentials
    assert_failure
    assert_output --partial "aws CLI is required"
    export PATH="$save_path"
}

@test "resolve_aws_credentials: exits 1 with sso login suggestion on credential failure" {
    create_aws_stub_fail
    source_libs
    run resolve_aws_credentials
    assert_failure
    assert_output --partial "aws sso login"
}

@test "resolve_aws_credentials: exits 1 when aws sts get-caller-identity fails" {
    create_aws_stub_fail
    source_libs
    run resolve_aws_credentials
    assert_failure
}

@test "resolve_aws_credentials: error message is actionable" {
    create_aws_stub_fail
    source_libs
    run resolve_aws_credentials
    assert_failure
    # Must suggest a concrete action
    assert_output --partial "aws sso login"
}

# ---------------------------------------------------------------------------
# resolve_aws_credentials: region fallback
# ---------------------------------------------------------------------------

@test "resolve_aws_credentials: uses AWS_DEFAULT_REGION from env when set" {
    export AWS_ACCESS_KEY_ID="AKIAEXISTING"
    export AWS_SECRET_ACCESS_KEY="existingsecret"
    export AWS_SESSION_TOKEN="existingtoken"
    export AWS_DEFAULT_REGION="ca-central-1"
    create_aws_stub "ignored" "ignored" "ignored" "should-not-use"
    source_libs
    run resolve_aws_credentials
    assert_success
    # Should NOT call aws configure get region since AWS_DEFAULT_REGION is set
    refute_output --partial "should-not-use"
}

@test "resolve_aws_credentials: exits 1 when region cannot be resolved" {
    export AWS_ACCESS_KEY_ID="AKIAEXISTING"
    export AWS_SECRET_ACCESS_KEY="existingsecret"
    export AWS_SESSION_TOKEN="existingtoken"
    create_aws_stub_no_region
    source_libs
    run resolve_aws_credentials
    assert_failure
    assert_output --partial "region"
}

# ---------------------------------------------------------------------------
# build_credential_flags: assembles -e flags for docker sandbox exec
# ---------------------------------------------------------------------------

@test "build_credential_flags: includes all four AWS vars" {
    export AWS_ACCESS_KEY_ID="AKIATEST"
    export AWS_SECRET_ACCESS_KEY="secrettest"
    export AWS_SESSION_TOKEN="tokentest"
    export AWS_DEFAULT_REGION="us-east-1"
    source_libs
    run build_credential_flags
    assert_success
    assert_output --partial "-e AWS_ACCESS_KEY_ID=AKIATEST"
    assert_output --partial "-e AWS_SECRET_ACCESS_KEY=secrettest"
    assert_output --partial "-e AWS_SESSION_TOKEN=tokentest"
    assert_output --partial "-e AWS_DEFAULT_REGION=us-east-1"
}

@test "build_credential_flags: includes CLAUDE_CODE_USE_BEDROCK when set" {
    export CLAUDE_CODE_USE_BEDROCK=1
    export AWS_ACCESS_KEY_ID="AKIATEST"
    export AWS_SECRET_ACCESS_KEY="secrettest"
    export AWS_DEFAULT_REGION="us-east-1"
    source_libs
    run build_credential_flags
    assert_success
    assert_output --partial "-e CLAUDE_CODE_USE_BEDROCK=1"
}

@test "build_credential_flags: omits AWS_SESSION_TOKEN when not set" {
    export AWS_ACCESS_KEY_ID="AKIATEST"
    export AWS_SECRET_ACCESS_KEY="secrettest"
    export AWS_DEFAULT_REGION="us-east-1"
    unset AWS_SESSION_TOKEN
    source_libs
    run build_credential_flags
    assert_success
    assert_output --partial "-e AWS_ACCESS_KEY_ID=AKIATEST"
    refute_output --partial "AWS_SESSION_TOKEN"
}

@test "build_credential_flags: includes RALPH_DOCKER_ENV custom vars" {
    export AWS_ACCESS_KEY_ID="AKIATEST"
    export AWS_SECRET_ACCESS_KEY="secrettest"
    export AWS_DEFAULT_REGION="us-east-1"
    export MY_CUSTOM_VAR="custom_value"
    export RALPH_DOCKER_ENV="MY_CUSTOM_VAR"
    source_libs
    run build_credential_flags
    assert_success
    assert_output --partial "-e MY_CUSTOM_VAR=custom_value"
}

@test "build_credential_flags: skips unset RALPH_DOCKER_ENV vars silently" {
    export AWS_ACCESS_KEY_ID="AKIATEST"
    export AWS_SECRET_ACCESS_KEY="secrettest"
    export AWS_DEFAULT_REGION="us-east-1"
    unset NONEXISTENT_VAR 2>/dev/null || true
    export RALPH_DOCKER_ENV="NONEXISTENT_VAR"
    source_libs
    run build_credential_flags
    assert_success
    refute_output --partial "NONEXISTENT_VAR"
}

@test "build_credential_flags: handles multiple RALPH_DOCKER_ENV vars" {
    export AWS_ACCESS_KEY_ID="AKIATEST"
    export AWS_SECRET_ACCESS_KEY="secrettest"
    export AWS_DEFAULT_REGION="us-east-1"
    export VAR_ONE="value1"
    export VAR_TWO="value2"
    export RALPH_DOCKER_ENV="VAR_ONE,VAR_TWO"
    source_libs
    run build_credential_flags
    assert_success
    assert_output --partial "-e VAR_ONE=value1"
    assert_output --partial "-e VAR_TWO=value2"
}

# ---------------------------------------------------------------------------
# Scope passthrough: RALPH_SCOPE_REPO and RALPH_SCOPE_BRANCH
# ---------------------------------------------------------------------------

@test "build_credential_flags: passes RALPH_SCOPE_REPO and RALPH_SCOPE_BRANCH" {
    export AWS_ACCESS_KEY_ID="AKIATEST"
    export AWS_SECRET_ACCESS_KEY="secrettest"
    export AWS_DEFAULT_REGION="us-east-1"
    export RALPH_SCOPE_REPO="myorg/myrepo"
    export RALPH_SCOPE_BRANCH="feature/test"
    source_libs
    run build_credential_flags
    assert_success
    assert_output --partial "-e RALPH_SCOPE_REPO=myorg/myrepo"
    assert_output --partial "-e RALPH_SCOPE_BRANCH=feature/test"
}
