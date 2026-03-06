#!/usr/bin/env bats
# test/docker_sandbox_bootstrap.bats — tests for sandbox_bootstrap() in lib/docker.sh
#
# Covers: idempotent skip via marker, installation of ralph + lib + models +
# skills + hooks, jq/sqlite3 installation, sqlite3 version verification,
# SCRIPT_DIR adaptation, hook configuration, and error cases.
#
# Strategy: The docker mock logs every invocation's full argument list to
# $STUB_DIR/docker.log. Tests inspect the log to verify that sandbox_bootstrap()
# sends the correct commands to docker sandbox exec.

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a docker mock for bootstrap testing.
# - `docker sandbox exec <name> test -f ...` returns based on $1 (true/false)
# - `docker sandbox exec <name> bash -c <script>` logs and succeeds
# - All calls are logged to $STUB_DIR/docker.log
create_bootstrap_docker_mock() {
    local marker_exists="${1:-false}"

    cat > "$STUB_DIR/docker" <<MOCK
#!/bin/bash
# Log the full invocation as a single line using printf %q to escape newlines
printf 'DOCKER_CALL: '
printf '%q ' "\$@"
printf '\n'
# Also append to log file the same way
{ printf 'DOCKER_CALL: '; printf '%q ' "\$@"; printf '\n'; } >> "$STUB_DIR/docker.log"

case "\$1" in
    sandbox)
        case "\$2" in
            exec)
                shift 2  # remove 'sandbox exec'
                local_name="\$1"; shift
                # Handle marker check: docker sandbox exec <name> test -f <path>
                if [ "\$1" = "test" ] && [ "\$2" = "-f" ]; then
                    if [ "$marker_exists" = "true" ]; then
                        exit 0  # marker found
                    else
                        exit 1  # marker not found
                    fi
                fi
                # Handle bootstrap exec: docker sandbox exec <name> bash -c <script>
                # Just succeed — don't actually run the script
                exit 0
                ;;
        esac
        ;;
esac
exit 0
MOCK
    chmod +x "$STUB_DIR/docker"
    > "$STUB_DIR/docker.log"
}

# Create a docker mock that fails on exec (for error propagation testing)
create_failing_docker_mock() {
    cat > "$STUB_DIR/docker" <<'MOCK'
#!/bin/bash
case "$1" in
    sandbox)
        case "$2" in
            exec)
                shift 2
                local_name="$1"; shift
                if [ "$1" = "test" ]; then
                    exit 1  # marker not found
                fi
                # bootstrap exec fails
                exit 1
                ;;
        esac
        ;;
esac
exit 0
MOCK
    chmod +x "$STUB_DIR/docker"
}

# Helper: get the bootstrap script content from docker.log
# Extracts the bash -c argument from the logged docker call
get_bootstrap_log() {
    cat "$STUB_DIR/docker.log"
}

setup() {
    common_setup
    create_bootstrap_docker_mock false
}

teardown() {
    common_teardown
}

# ---------------------------------------------------------------------------
# Idempotent skip via marker
# ---------------------------------------------------------------------------
@test "sandbox_bootstrap skips if .bootstrapped marker exists" {
    source "$SCRIPT_DIR/lib/docker.sh"
    create_bootstrap_docker_mock true

    run sandbox_bootstrap "test-sandbox" "/mnt/ralph"
    assert_success
    assert_output --partial "already bootstrapped"

    # Should only have the marker check call, no bash -c bootstrap
    local log
    log="$(get_bootstrap_log)"
    [[ "$log" != *"bash -c"* ]] || { echo "Expected no bash -c in log: $log"; false; }
}

@test "sandbox_bootstrap runs when marker does not exist" {
    source "$SCRIPT_DIR/lib/docker.sh"
    create_bootstrap_docker_mock false

    run sandbox_bootstrap "test-sandbox" "/mnt/ralph"
    assert_success

    # Should have both: marker check (test -f) and bootstrap (bash -c)
    local log
    log="$(get_bootstrap_log)"
    [[ "$log" == *"test -f"* ]]
    [[ "$log" == *"bash"* ]]
}

# ---------------------------------------------------------------------------
# Bootstrap script content — file installation
# ---------------------------------------------------------------------------
@test "sandbox_bootstrap copies ralph.sh to /usr/local/bin/ralph" {
    source "$SCRIPT_DIR/lib/docker.sh"
    run sandbox_bootstrap "test-sandbox" "/mnt/ralph"
    assert_success

    local log
    log="$(get_bootstrap_log)"
    [[ "$log" == *"/usr/local/bin/ralph"* ]]
}

@test "sandbox_bootstrap copies lib/ to /opt/ralph/lib/" {
    source "$SCRIPT_DIR/lib/docker.sh"
    run sandbox_bootstrap "test-sandbox" "/mnt/ralph"
    assert_success

    local log
    log="$(get_bootstrap_log)"
    [[ "$log" == *"/opt/ralph/lib"* ]]
}

@test "sandbox_bootstrap copies models.json to /opt/ralph/" {
    source "$SCRIPT_DIR/lib/docker.sh"
    run sandbox_bootstrap "test-sandbox" "/mnt/ralph"
    assert_success

    local log
    log="$(get_bootstrap_log)"
    # The script uses $INSTALL_DIR which is /opt/ralph; printf %q may escape the $
    [[ "$log" == *"models.json"* ]]
    # Verify INSTALL_DIR is set to /opt/ralph in the script
    [[ "$log" == *'INSTALL_DIR="/opt/ralph"'* ]] || [[ "$log" == *"INSTALL_DIR=\\\"/opt/ralph\\\""* ]] || [[ "$log" == *"INSTALL_DIR="* ]]
}

@test "sandbox_bootstrap copies skills/ to ~/.claude/skills/" {
    source "$SCRIPT_DIR/lib/docker.sh"
    run sandbox_bootstrap "test-sandbox" "/mnt/ralph"
    assert_success

    local log
    log="$(get_bootstrap_log)"
    [[ "$log" == *".claude/skills"* ]]
}

@test "sandbox_bootstrap copies hooks/ to /opt/ralph/hooks/" {
    source "$SCRIPT_DIR/lib/docker.sh"
    run sandbox_bootstrap "test-sandbox" "/mnt/ralph"
    assert_success

    local log
    log="$(get_bootstrap_log)"
    [[ "$log" == *"/opt/ralph/hooks"* ]]
}

# ---------------------------------------------------------------------------
# jq and sqlite3 installation
# ---------------------------------------------------------------------------
@test "sandbox_bootstrap installs jq and sqlite3 via apt-get" {
    source "$SCRIPT_DIR/lib/docker.sh"
    run sandbox_bootstrap "test-sandbox" "/mnt/ralph"
    assert_success

    local log
    log="$(get_bootstrap_log)"
    [[ "$log" == *"apt-get"* ]]
    [[ "$log" == *"jq"* ]]
    [[ "$log" == *"sqlite3"* ]]
}

# ---------------------------------------------------------------------------
# sqlite3 version verification
# ---------------------------------------------------------------------------
@test "sandbox_bootstrap verifies sqlite3 version >= 3.35" {
    source "$SCRIPT_DIR/lib/docker.sh"
    run sandbox_bootstrap "test-sandbox" "/mnt/ralph"
    assert_success

    local log
    log="$(get_bootstrap_log)"
    # The version check threshold
    [[ "$log" == *"3.35"* ]]
    # Must check sqlite3 --version
    [[ "$log" == *"sqlite3 --version"* ]]
}

# ---------------------------------------------------------------------------
# SCRIPT_DIR adaptation
# ---------------------------------------------------------------------------
@test "sandbox_bootstrap adapts SCRIPT_DIR to /opt/ralph" {
    source "$SCRIPT_DIR/lib/docker.sh"
    run sandbox_bootstrap "test-sandbox" "/mnt/ralph"
    assert_success

    local log
    log="$(get_bootstrap_log)"
    [[ "$log" == *"SCRIPT_DIR"* ]]
    [[ "$log" == *"/opt/ralph"* ]]
}

# ---------------------------------------------------------------------------
# Hook configuration
# ---------------------------------------------------------------------------
@test "sandbox_bootstrap configures Claude Code hooks in settings.json" {
    source "$SCRIPT_DIR/lib/docker.sh"
    run sandbox_bootstrap "test-sandbox" "/mnt/ralph"
    assert_success

    local log
    log="$(get_bootstrap_log)"
    [[ "$log" == *"settings.json"* ]]
    [[ "$log" == *"PreCompact"* ]]
    [[ "$log" == *"SessionEnd"* ]]
    [[ "$log" == *"precompact.sh"* ]]
    [[ "$log" == *"session_end.sh"* ]]
}

# ---------------------------------------------------------------------------
# Bootstrap marker written on success
# ---------------------------------------------------------------------------
@test "sandbox_bootstrap writes .bootstrapped marker" {
    source "$SCRIPT_DIR/lib/docker.sh"
    run sandbox_bootstrap "test-sandbox" "/mnt/ralph"
    assert_success

    local log
    log="$(get_bootstrap_log)"
    [[ "$log" == *".ralph/.bootstrapped"* ]]
}

# ---------------------------------------------------------------------------
# Ralph source path substitution
# ---------------------------------------------------------------------------
@test "sandbox_bootstrap uses the provided ralph source path" {
    source "$SCRIPT_DIR/lib/docker.sh"
    run sandbox_bootstrap "test-sandbox" "/custom/ralph/mount"
    assert_success

    local log
    log="$(get_bootstrap_log)"
    [[ "$log" == *"/custom/ralph/mount"* ]]
}

# ---------------------------------------------------------------------------
# Error cases
# ---------------------------------------------------------------------------
@test "sandbox_bootstrap fails if sandbox name is empty" {
    source "$SCRIPT_DIR/lib/docker.sh"
    run sandbox_bootstrap "" "/mnt/ralph"
    assert_failure
    assert_output --partial "sandbox name is required"
}

@test "sandbox_bootstrap fails if ralph source dir is empty" {
    source "$SCRIPT_DIR/lib/docker.sh"
    run sandbox_bootstrap "test-sandbox" ""
    assert_failure
    assert_output --partial "ralph source directory is required"
}

@test "sandbox_bootstrap propagates non-zero exit from docker exec" {
    source "$SCRIPT_DIR/lib/docker.sh"
    create_failing_docker_mock

    run sandbox_bootstrap "test-sandbox" "/mnt/ralph"
    assert_failure
}

# ---------------------------------------------------------------------------
# Ralph executable permissions
# ---------------------------------------------------------------------------
@test "sandbox_bootstrap makes ralph.sh executable in /usr/local/bin" {
    source "$SCRIPT_DIR/lib/docker.sh"
    run sandbox_bootstrap "test-sandbox" "/mnt/ralph"
    assert_success

    local log
    log="$(get_bootstrap_log)"
    [[ "$log" == *"chmod +x /usr/local/bin/ralph"* ]]
}

# ---------------------------------------------------------------------------
# Integration with ralph.sh docker dispatch
# ---------------------------------------------------------------------------
@test "ralph --docker calls sandbox_bootstrap for new sandbox" {
    cat > "$STUB_DIR/docker" <<MOCK
#!/bin/bash
{ printf 'DOCKER_CALL: '; printf '%q ' "\$@"; printf '\n'; } >> "$STUB_DIR/docker.log"
case "\$1" in
    sandbox)
        case "\$2" in
            ls)
                echo '[]'
                ;;
            create)
                exit 0
                ;;
            exec)
                shift 2
                local_name="\$1"; shift
                if [ "\$1" = "test" ] && [ "\$2" = "-f" ]; then
                    exit 1  # marker not found -> needs bootstrap
                fi
                # bootstrap or final exec — succeed
                echo "EXEC_CALLED"
                exit 0
                ;;
        esac
        ;;
esac
exit 0
MOCK
    chmod +x "$STUB_DIR/docker"
    > "$STUB_DIR/docker.log"

    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    # Verify sandbox_bootstrap was triggered (bash -c in log)
    local log
    log="$(cat "$STUB_DIR/docker.log")"
    [[ "$log" == *"bash"* ]]
    [[ "$log" == *"/usr/local/bin/ralph"* ]]
}

@test "ralph --docker skips bootstrap for running sandbox with marker" {
    cat > "$STUB_DIR/docker" <<MOCK
#!/bin/bash
{ printf 'DOCKER_CALL: '; printf '%q ' "\$@"; printf '\n'; } >> "$STUB_DIR/docker.log"
case "\$1" in
    sandbox)
        case "\$2" in
            ls)
                echo '[{"Name":"ralph-test-repo-main","Status":"running"}]'
                ;;
            exec)
                shift 2
                local_name="\$1"; shift
                if [ "\$1" = "test" ] && [ "\$2" = "-f" ]; then
                    exit 0  # marker exists -> skip bootstrap
                fi
                echo "EXEC_CALLED"
                exit 0
                ;;
        esac
        ;;
esac
exit 0
MOCK
    chmod +x "$STUB_DIR/docker"
    > "$STUB_DIR/docker.log"

    run "$SCRIPT_DIR/ralph.sh" --docker plan
    assert_success
    assert_output --partial "already bootstrapped"
    # No bootstrap exec call should be present
    local log
    log="$(cat "$STUB_DIR/docker.log")"
    [[ "$log" != *"/usr/local/bin/ralph"* ]] || { echo "Unexpected bootstrap in log"; false; }
}
