#!/usr/bin/env bats
# test/ralph_docker_dispatch.bats — tests for --docker flag dispatch in ralph.sh
#
# Covers: --docker flag parsing, preflight checks, sandbox lifecycle
# (running/stopped/new), exec invocation with -it, subcommand and flag
# forwarding, exit code forwarding, and --help output.

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a docker mock that simulates sandbox lifecycle.
# $1: sandbox state — "running", "stopped", or "none" (no sandbox)
# The mock logs every invocation to $STUB_DIR/docker.log for assertion.
create_docker_mock() {
    local state="${1:-running}"
    cat > "$STUB_DIR/docker" <<STUB
#!/bin/bash
# Log every docker call for verification
echo "\$*" >> "$STUB_DIR/docker.log"
case "\$1" in
    sandbox)
        case "\$2" in
            ls)
                case "$state" in
                    running)
                        echo '[{"Name":"ralph-test-repo-main","Status":"running"}]'
                        ;;
                    stopped)
                        echo '[{"Name":"ralph-test-repo-main","Status":"stopped"}]'
                        ;;
                    none)
                        echo '[]'
                        ;;
                esac
                ;;
            run|create|start)
                # lifecycle commands — just succeed
                exit 0
                ;;
            exec)
                # Print the full exec command for verification
                echo "EXEC_CALLED"
                echo "EXEC_ARGS: \$*"
                exit 0
                ;;
        esac
        ;;
esac
exit 0
STUB
    chmod +x "$STUB_DIR/docker"
    # Clear log
    > "$STUB_DIR/docker.log"
}

# Create a docker mock that exits with a specific code on exec
create_docker_mock_exit() {
    local exit_code="${1:-0}"
    cat > "$STUB_DIR/docker" <<STUB
#!/bin/bash
echo "\$*" >> "$STUB_DIR/docker.log"
case "\$1" in
    sandbox)
        case "\$2" in
            ls)
                echo '[{"Name":"ralph-test-repo-main","Status":"running"}]'
                ;;
            exec)
                exit $exit_code
                ;;
        esac
        ;;
esac
exit 0
STUB
    chmod +x "$STUB_DIR/docker"
    > "$STUB_DIR/docker.log"
}

# ---------------------------------------------------------------------------
# --docker flag dispatch — error cases
# ---------------------------------------------------------------------------
@test "ralph --docker with no subcommand prints error and exits 1" {
    run "$SCRIPT_DIR/ralph.sh" --docker
    assert_failure
    assert_output --partial "Error: --docker requires a subcommand"
}

@test "ralph --docker --help prints docker usage and exits 0" {
    run "$SCRIPT_DIR/ralph.sh" --docker --help
    assert_success
    assert_output --partial "--docker"
    assert_output --partial "sandbox"
}

@test "ralph --docker -h prints docker usage and exits 0" {
    run "$SCRIPT_DIR/ralph.sh" --docker -h
    assert_success
    assert_output --partial "--docker"
}

@test "ralph --docker exits 1 when docker CLI is not available" {
    # Build a PATH without docker
    local NO_DOCKER_DIR
    NO_DOCKER_DIR=$(mktemp -d)
    cp "$STUB_DIR/claude" "$NO_DOCKER_DIR/claude"
    for cmd in bash git sed tr cut sqlite3; do
        local cmd_path
        cmd_path=$(which "$cmd" 2>/dev/null) || continue
        ln -sf "$cmd_path" "$NO_DOCKER_DIR/$cmd"
    done

    PATH="$NO_DOCKER_DIR" run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_failure
    assert_output --partial "docker CLI is required but not found"
    assert_output --partial "Docker Desktop"
}

# ---------------------------------------------------------------------------
# --docker dispatch — subcommand forwarding
# ---------------------------------------------------------------------------
@test "ralph --docker plan forwards to sandbox exec with plan subcommand" {
    create_docker_mock running
    run "$SCRIPT_DIR/ralph.sh" --docker plan -n 1
    assert_success
    assert_output --partial "EXEC_CALLED"
    # Verify exec args include: sandbox exec -it <name> ralph plan -n 1
    assert_output --partial "ralph plan -n 1"
}

@test "ralph --docker build forwards subcommand and all flags" {
    create_docker_mock running
    run "$SCRIPT_DIR/ralph.sh" --docker build -n 3 --danger
    assert_success
    assert_output --partial "EXEC_CALLED"
    assert_output --partial "ralph build -n 3 --danger"
}

@test "ralph --docker task forwards to sandbox exec" {
    create_docker_mock running
    run "$SCRIPT_DIR/ralph.sh" --docker task list
    assert_success
    assert_output --partial "EXEC_CALLED"
    assert_output --partial "ralph task list"
}

@test "ralph --docker exec uses -it flags" {
    create_docker_mock running
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    # Check docker.log for the exec call with -it
    run grep "sandbox exec" "$STUB_DIR/docker.log"
    assert_success
    assert_output --partial "exec -it"
}

# ---------------------------------------------------------------------------
# --docker dispatch — sandbox lifecycle: running
# ---------------------------------------------------------------------------
@test "ralph --docker with running sandbox skips create and run" {
    create_docker_mock running
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    # Should NOT call sandbox create or sandbox run
    run grep "sandbox create" "$STUB_DIR/docker.log"
    assert_failure
    run grep "sandbox run" "$STUB_DIR/docker.log"
    assert_failure
}

# ---------------------------------------------------------------------------
# --docker dispatch — sandbox lifecycle: stopped
# ---------------------------------------------------------------------------
@test "ralph --docker with stopped sandbox calls docker sandbox run" {
    create_docker_mock stopped
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    # Should call sandbox run to start the stopped sandbox
    run grep "sandbox run" "$STUB_DIR/docker.log"
    assert_success
}

@test "ralph --docker with stopped sandbox does not call create" {
    create_docker_mock stopped
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    run grep "sandbox create" "$STUB_DIR/docker.log"
    assert_failure
}

# ---------------------------------------------------------------------------
# --docker dispatch — sandbox lifecycle: not found
# ---------------------------------------------------------------------------
@test "ralph --docker with no sandbox calls sandbox_create with template and mounts" {
    create_docker_mock none
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    run grep "sandbox create" "$STUB_DIR/docker.log"
    assert_success
    # Verify template flag
    assert_output --partial "docker/sandbox-templates:claude-code"
    # Verify sandbox name
    assert_output --partial "--name ralph-test-repo-main"
    # Verify shell agent type
    assert_output --partial "shell"
    # Verify ralph dir mounted read-only (SCRIPT_DIR with :ro suffix)
    assert_output --partial ":ro"
}

# ---------------------------------------------------------------------------
# --docker does not source lib/signals.sh
# ---------------------------------------------------------------------------
@test "ralph --docker does not source lib/signals.sh" {
    create_docker_mock running
    # If signals.sh were sourced, setup_signal_handlers would be defined.
    # We verify by checking that ralph.sh --docker does not call signal setup.
    # Simpler: grep the --docker case block in ralph.sh for signals.sh
    run grep -A 50 "^    --docker)" "$SCRIPT_DIR/ralph.sh"
    refute_output --partial "signals.sh"
}

# ---------------------------------------------------------------------------
# --docker exit code forwarding
# ---------------------------------------------------------------------------
@test "ralph --docker forwards non-zero exit code from sandboxed ralph" {
    create_docker_mock_exit 42
    # Note: exec replaces the process, so `run` captures the exec'd process exit code
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_failure
    [ "$status" -eq 42 ]
}

@test "ralph --docker forwards exit code 0 on success" {
    create_docker_mock_exit 0
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
}

# ---------------------------------------------------------------------------
# --help includes --docker
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# --docker dispatch — credential injection: Bedrock backend
# ---------------------------------------------------------------------------

@test "ralph --docker passes AWS credential -e flags to exec when backend is bedrock" {
    create_docker_mock running
    export CLAUDE_CODE_USE_BEDROCK=1
    export AWS_ACCESS_KEY_ID="AKIATESTKEY"
    export AWS_SECRET_ACCESS_KEY="secretvalue"
    export AWS_SESSION_TOKEN="tokenvalue"
    export AWS_DEFAULT_REGION="us-west-2"
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    assert_output --partial "EXEC_CALLED"
    # Verify -e flags for all four AWS vars in exec args
    assert_output --partial "-e AWS_ACCESS_KEY_ID=AKIATESTKEY"
    assert_output --partial "-e AWS_SECRET_ACCESS_KEY=secretvalue"
    assert_output --partial "-e AWS_SESSION_TOKEN=tokenvalue"
    assert_output --partial "-e AWS_DEFAULT_REGION=us-west-2"
}

@test "ralph --docker passes CLAUDE_CODE_USE_BEDROCK=1 to exec" {
    create_docker_mock running
    export CLAUDE_CODE_USE_BEDROCK=1
    export AWS_ACCESS_KEY_ID="AKIATESTKEY"
    export AWS_SECRET_ACCESS_KEY="secretvalue"
    export AWS_DEFAULT_REGION="us-west-2"
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    assert_output --partial "-e CLAUDE_CODE_USE_BEDROCK=1"
}

@test "ralph --docker with bedrock resolves credentials via aws CLI when not in env" {
    create_docker_mock running
    # Create aws stub that provides credentials
    cat > "$STUB_DIR/aws" <<'AWSSTUB'
#!/bin/bash
case "$*" in
    "sts get-caller-identity")
        echo '{"Account":"123456789012"}'
        exit 0
        ;;
    "configure export-credentials --format env")
        echo 'export AWS_ACCESS_KEY_ID=AKIARESOLVED'
        echo 'export AWS_SECRET_ACCESS_KEY=resolvedsecret'
        echo 'export AWS_SESSION_TOKEN=resolvedtoken'
        exit 0
        ;;
    "configure get region")
        echo "eu-west-1"
        exit 0
        ;;
esac
exit 1
AWSSTUB
    chmod +x "$STUB_DIR/aws"
    export CLAUDE_CODE_USE_BEDROCK=1
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    unset AWS_DEFAULT_REGION
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    assert_output --partial "-e AWS_ACCESS_KEY_ID=AKIARESOLVED"
    assert_output --partial "-e AWS_SECRET_ACCESS_KEY=resolvedsecret"
    assert_output --partial "-e AWS_SESSION_TOKEN=resolvedtoken"
    assert_output --partial "-e AWS_DEFAULT_REGION=eu-west-1"
}

@test "ralph --docker exits 1 when bedrock credentials cannot be resolved" {
    create_docker_mock running
    cat > "$STUB_DIR/aws" <<'AWSSTUB'
#!/bin/bash
echo "Unable to locate credentials" >&2
exit 255
AWSSTUB
    chmod +x "$STUB_DIR/aws"
    export CLAUDE_CODE_USE_BEDROCK=1
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    unset AWS_DEFAULT_REGION
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_failure
    assert_output --partial "aws sso login"
}

# ---------------------------------------------------------------------------
# --docker dispatch — credential injection: Anthropic backend (default)
# ---------------------------------------------------------------------------

@test "ralph --docker with anthropic backend does not pass AWS -e flags" {
    create_docker_mock running
    # Force anthropic backend: override HOME so detect_backend() can't find
    # user-wide ~/.claude/settings.json with CLAUDE_CODE_USE_BEDROCK=1
    local FAKE_HOME
    FAKE_HOME="$(mktemp -d)"
    export HOME="$FAKE_HOME"
    unset CLAUDE_CODE_USE_BEDROCK
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    unset AWS_DEFAULT_REGION
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    assert_output --partial "EXEC_CALLED"
    refute_output --partial "AWS_ACCESS_KEY_ID"
    refute_output --partial "AWS_SECRET_ACCESS_KEY"
    refute_output --partial "CLAUDE_CODE_USE_BEDROCK"
    rm -rf "$FAKE_HOME"
}

# ---------------------------------------------------------------------------
# --docker dispatch — scope variable passthrough
# ---------------------------------------------------------------------------

@test "ralph --docker passes RALPH_SCOPE_REPO and RALPH_SCOPE_BRANCH to exec" {
    create_docker_mock running
    export RALPH_SCOPE_REPO="myorg/myrepo"
    export RALPH_SCOPE_BRANCH="feature/test"
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    assert_output --partial "-e RALPH_SCOPE_REPO=myorg/myrepo"
    assert_output --partial "-e RALPH_SCOPE_BRANCH=feature/test"
}

# ---------------------------------------------------------------------------
# --docker dispatch — RALPH_DOCKER_ENV custom variable passthrough
# ---------------------------------------------------------------------------

@test "ralph --docker passes RALPH_DOCKER_ENV custom vars to exec" {
    create_docker_mock running
    export MY_CUSTOM_VAR="custom_value"
    export RALPH_DOCKER_ENV="MY_CUSTOM_VAR"
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    assert_output --partial "-e MY_CUSTOM_VAR=custom_value"
}

@test "ralph --docker handles multiple RALPH_DOCKER_ENV vars" {
    create_docker_mock running
    export VAR_ONE="value1"
    export VAR_TWO="value2"
    export RALPH_DOCKER_ENV="VAR_ONE,VAR_TWO"
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    assert_output --partial "-e VAR_ONE=value1"
    assert_output --partial "-e VAR_TWO=value2"
}

@test "ralph --docker silently skips unset RALPH_DOCKER_ENV vars" {
    create_docker_mock running
    export EXISTING_VAR="present"
    unset NONEXISTENT_VAR 2>/dev/null || true
    export RALPH_DOCKER_ENV="EXISTING_VAR,NONEXISTENT_VAR"
    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    assert_output --partial "-e EXISTING_VAR=present"
    refute_output --partial "NONEXISTENT_VAR"
}

# ---------------------------------------------------------------------------
# --help includes --docker
# ---------------------------------------------------------------------------

@test "ralph --help includes --docker in output" {
    run "$SCRIPT_DIR/ralph.sh" --help
    assert_success
    assert_output --partial "--docker"
}

@test "ralph -h includes --docker in output" {
    run "$SCRIPT_DIR/ralph.sh" -h
    assert_success
    assert_output --partial "--docker"
}

@test "ralph --help shows --docker in options section" {
    run "$SCRIPT_DIR/ralph.sh" --help
    assert_success
    assert_output --partial "Run the command inside a Docker sandbox"
}
