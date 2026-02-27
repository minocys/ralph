#!/usr/bin/env bats
# test/ralph_sandbox_credentials.bats — Tests for resolve_aws_credentials()

load test_helper

# Helper: source lib/docker.sh to get all functions
_load_docker_functions() {
    . "$SCRIPT_DIR/lib/docker.sh"
}

# --- resolve_aws_credentials sets all 4 AWS vars ---

@test "resolve_aws_credentials sets all 4 AWS vars from aws configure export-credentials" {
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

    _load_docker_functions
    unset AWS_DEFAULT_REGION
    run resolve_aws_credentials
    assert_success
    assert_output --partial "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"
    assert_output --partial "AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    assert_output --partial "AWS_SESSION_TOKEN=FwoGZXIvYXdzEBYaDH7example-session-token"
    assert_output --partial "AWS_DEFAULT_REGION=us-west-2"
}

@test "resolve_aws_credentials preserves existing AWS_DEFAULT_REGION" {
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
exit 0
STUB
    chmod +x "$STUB_DIR/aws"

    _load_docker_functions
    export AWS_DEFAULT_REGION="eu-west-1"
    run resolve_aws_credentials
    assert_success
    assert_output --partial "AWS_DEFAULT_REGION=eu-west-1"
}

# --- missing aws CLI exits 1 with actionable error ---

@test "resolve_aws_credentials exits 1 when aws CLI is missing" {
    # Build a PATH that excludes any directory containing aws
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

    _load_docker_functions
    run resolve_aws_credentials
    assert_failure
    assert_output --partial "aws CLI not found"
}

@test "resolve_aws_credentials error message suggests installing aws CLI" {
    # Build a PATH that excludes any directory containing aws
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

    _load_docker_functions
    run resolve_aws_credentials
    assert_failure
    assert_output --partial "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
}

# --- credential resolution failure ---

@test "resolve_aws_credentials exits 1 when credentials are expired" {
    cat > "$STUB_DIR/aws" <<'STUB'
#!/bin/bash
if [ "$1" = "configure" ] && [ "$2" = "export-credentials" ]; then
    echo "The SSO session associated with this profile has expired" >&2
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/aws"

    _load_docker_functions
    run resolve_aws_credentials
    assert_failure
    assert_output --partial "aws sso login"
}

@test "resolve_aws_credentials exits 1 with actionable error on credential failure" {
    cat > "$STUB_DIR/aws" <<'STUB'
#!/bin/bash
if [ "$1" = "configure" ] && [ "$2" = "export-credentials" ]; then
    echo "Unable to locate credentials" >&2
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/aws"

    _load_docker_functions
    run resolve_aws_credentials
    assert_failure
    assert_output --partial "Failed to resolve AWS credentials"
}

# --- region fallback to aws configure get region ---

@test "resolve_aws_credentials falls back to aws configure get region when AWS_DEFAULT_REGION unset" {
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
    echo "ap-southeast-1"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/aws"

    _load_docker_functions
    unset AWS_DEFAULT_REGION
    run resolve_aws_credentials
    assert_success
    assert_output --partial "AWS_DEFAULT_REGION=ap-southeast-1"
}

@test "resolve_aws_credentials exits 1 when region cannot be determined" {
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
    echo ""
    exit 1
fi
exit 0
STUB
    chmod +x "$STUB_DIR/aws"

    _load_docker_functions
    unset AWS_DEFAULT_REGION
    run resolve_aws_credentials
    assert_failure
    assert_output --partial "AWS region could not be determined"
}

# --- output format for env injection ---

@test "resolve_aws_credentials outputs KEY=VALUE format for all 4 vars" {
    cat > "$STUB_DIR/aws" <<'STUB'
#!/bin/bash
if [ "$1" = "configure" ] && [ "$2" = "export-credentials" ]; then
    cat <<'JSON'
{
  "Version": 1,
  "AccessKeyId": "AKIA1234",
  "SecretAccessKey": "SECRET1234",
  "SessionToken": "TOKEN1234"
}
JSON
    exit 0
fi
if [ "$1" = "configure" ] && [ "$2" = "get" ] && [ "$3" = "region" ]; then
    echo "us-east-1"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/aws"

    _load_docker_functions
    unset AWS_DEFAULT_REGION
    run resolve_aws_credentials
    assert_success
    # Verify each line is present
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    [ "$line_count" -eq 4 ]
    assert_output --partial "AWS_ACCESS_KEY_ID=AKIA1234"
    assert_output --partial "AWS_SECRET_ACCESS_KEY=SECRET1234"
    assert_output --partial "AWS_SESSION_TOKEN=TOKEN1234"
    assert_output --partial "AWS_DEFAULT_REGION=us-east-1"
}

# --- handles credentials without session token (long-term keys) ---

@test "resolve_aws_credentials handles missing SessionToken gracefully" {
    cat > "$STUB_DIR/aws" <<'STUB'
#!/bin/bash
if [ "$1" = "configure" ] && [ "$2" = "export-credentials" ]; then
    cat <<'JSON'
{
  "Version": 1,
  "AccessKeyId": "AKIALONG",
  "SecretAccessKey": "SECRETLONG"
}
JSON
    exit 0
fi
if [ "$1" = "configure" ] && [ "$2" = "get" ] && [ "$3" = "region" ]; then
    echo "us-east-1"
    exit 0
fi
exit 0
STUB
    chmod +x "$STUB_DIR/aws"

    _load_docker_functions
    unset AWS_DEFAULT_REGION
    run resolve_aws_credentials
    assert_success
    assert_output --partial "AWS_ACCESS_KEY_ID=AKIALONG"
    assert_output --partial "AWS_SECRET_ACCESS_KEY=SECRETLONG"
    assert_output --partial "AWS_SESSION_TOKEN="
    assert_output --partial "AWS_DEFAULT_REGION=us-east-1"
}
