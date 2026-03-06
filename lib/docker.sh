#!/bin/bash
# lib/docker.sh — Docker sandbox helpers
#
# Functions:
#   derive_sandbox_name       - Derive deterministic sandbox name from repo+branch
#   check_sandbox_state       - Check sandbox state (running, stopped, or not found)
#   sandbox_create            - Create a new Docker sandbox with claude-code template
#   sandbox_bootstrap         - One-time bootstrap of ralph inside a sandbox
#   resolve_aws_credentials   - Resolve AWS/Bedrock credentials for sandbox injection
#   build_credential_flags    - Assemble -e flags for docker sandbox exec

# derive_sandbox_name: produce a deterministic sandbox name from repo+branch
# Pattern: ralph-{owner}-{repo}-{branch}, sanitized and truncated to 63 chars
derive_sandbox_name() {
    local repo branch owner_repo name

    # Repo: env var override or git remote
    if [ -n "${RALPH_SCOPE_REPO:-}" ]; then
        owner_repo="$RALPH_SCOPE_REPO"
    else
        local remote_url
        remote_url="$(git remote get-url origin 2>/dev/null)" || {
            echo "Error: no git remote \"origin\" found" >&2
            return 1
        }
        # Strip .git suffix
        remote_url="${remote_url%.git}"
        # Extract owner/repo from URL
        if [[ "$remote_url" =~ ^[a-zA-Z]+:// ]]; then
            # URL scheme format: https://host/owner/repo or ssh://git@host/owner/repo
            local path="${remote_url#*://}"  # remove scheme
            owner_repo="${path#*/}"          # remove host
        else
            # SCP-like SSH format: git@github.com:owner/repo
            owner_repo="${remote_url##*:}"
        fi
    fi

    # Branch: env var override or git branch
    if [ -n "${RALPH_SCOPE_BRANCH:-}" ]; then
        branch="$RALPH_SCOPE_BRANCH"
    else
        branch="$(git branch --show-current 2>/dev/null)" || {
            echo "Error: detached HEAD state. Checkout a branch first" >&2
            return 1
        }
        if [ -z "$branch" ]; then
            echo "Error: detached HEAD state. Checkout a branch first" >&2
            return 1
        fi
    fi

    # Replace slash between owner/repo with dash
    owner_repo="${owner_repo//\//-}"

    # Build raw name
    name="ralph-${owner_repo}-${branch}"

    # Sanitize: replace non-alphanumeric chars with dashes
    name="$(echo "$name" | tr -c 'a-zA-Z0-9' '-')"

    # Collapse consecutive dashes
    name="$(echo "$name" | sed 's/--*/-/g')"

    # Strip leading and trailing dashes
    name="$(echo "$name" | sed 's/^-//;s/-$//')"

    # Truncate to 63 chars
    name="${name:0:63}"

    # Ensure no trailing dash after truncation
    name="${name%-}"

    echo "$name"
}

# check_sandbox_state: check if a sandbox exists and its state
# Returns: "running", "stopped", or "" (not found)
check_sandbox_state() {
    local name="$1"
    local state

    # Query docker sandbox ls for the named sandbox
    state="$(docker sandbox ls --json 2>/dev/null | \
        jq -r --arg name "$name" '.[] | select(.Name == $name) | .Status' 2>/dev/null)" || true

    case "$state" in
        running|Running)
            echo "running"
            ;;
        stopped|Stopped|exited|Exited)
            echo "stopped"
            ;;
        *)
            echo ""
            ;;
    esac
}

# sandbox_create: create a new Docker sandbox with the claude-code template
# Arguments:
#   $1 — sandbox name (from derive_sandbox_name)
#   $2 — absolute path to target repo directory (mounted read-write)
#   $3 — absolute path to ralph repo directory (mounted read-only)
sandbox_create() {
    local name="$1"
    local target_repo_dir="$2"
    local ralph_dir="$3"

    if [ -z "$name" ]; then
        echo "Error: sandbox name is required" >&2
        return 1
    fi
    if [ -z "$target_repo_dir" ]; then
        echo "Error: target repo directory is required" >&2
        return 1
    fi
    if [ -z "$ralph_dir" ]; then
        echo "Error: ralph directory is required" >&2
        return 1
    fi

    docker sandbox create \
        -t docker/sandbox-templates:claude-code \
        --name "$name" \
        shell \
        "$target_repo_dir" \
        "${ralph_dir}:ro"
}

# sandbox_bootstrap: one-time setup of ralph, sqlite3, and dependencies inside sandbox
# Checks for ~/.ralph/.bootstrapped marker and skips if present.
# Arguments:
#   $1 — sandbox name
#   $2 — absolute path to ralph source directory (read-only mount inside sandbox)
sandbox_bootstrap() {
    local name="$1"
    local ralph_source="$2"

    if [ -z "$name" ]; then
        echo "Error: sandbox name is required" >&2
        return 1
    fi
    if [ -z "$ralph_source" ]; then
        echo "Error: ralph source directory is required" >&2
        return 1
    fi

    # Check for bootstrap marker — skip if already done
    if docker sandbox exec "$name" test -f ~/.ralph/.bootstrapped 2>/dev/null; then
        echo "Sandbox $name already bootstrapped, skipping"
        return 0
    fi

    echo "Bootstrapping sandbox $name..."

    # Build the bootstrap script that runs inside the sandbox.
    # The ralph source dir is mounted read-only; we copy to writable locations.
    local bootstrap_script
    bootstrap_script="$(cat <<'BOOTSTRAP_EOF'
set -euo pipefail

RALPH_SRC="__RALPH_SOURCE__"
INSTALL_DIR="/opt/ralph"

# --- Install jq and sqlite3 if missing ---
NEED_INSTALL=""
command -v jq >/dev/null 2>&1 || NEED_INSTALL="jq"
command -v sqlite3 >/dev/null 2>&1 || NEED_INSTALL="$NEED_INSTALL sqlite3"
if [ -n "$NEED_INSTALL" ]; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq $NEED_INSTALL
fi

# --- Verify sqlite3 >= 3.35 ---
_sqlite_ver="$(sqlite3 --version | awk '{print $1}')"
_sqlite_major="${_sqlite_ver%%.*}"
_sqlite_minor="${_sqlite_ver#*.}"; _sqlite_minor="${_sqlite_minor%%.*}"
if [ "$_sqlite_major" -lt 3 ] 2>/dev/null || { [ "$_sqlite_major" -eq 3 ] && [ "$_sqlite_minor" -lt 35 ]; }; then
    echo "Error: sqlite3 >= 3.35 is required (found $_sqlite_ver)" >&2
    echo "  RETURNING clause support requires version 3.35+" >&2
    exit 1
fi
echo "  sqlite3 $_sqlite_ver OK"

# --- Copy ralph to writable locations ---
sudo mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/hooks"
mkdir -p ~/.claude/skills ~/.ralph

# Copy ralph.sh to /usr/local/bin/ralph with SCRIPT_DIR adapted
sudo cp "$RALPH_SRC/ralph.sh" /usr/local/bin/ralph
sudo chmod +x /usr/local/bin/ralph
# Replace the dynamic SCRIPT_DIR resolution with a fixed path
sudo sed -i '/^SOURCE="\${BASH_SOURCE\[0\]}"/,/^export SCRIPT_DIR$/c\SCRIPT_DIR="/opt/ralph"\nexport SCRIPT_DIR' /usr/local/bin/ralph

# Copy lib/ to /opt/ralph/lib/
sudo cp -r "$RALPH_SRC"/lib/* "$INSTALL_DIR/lib/"
sudo chmod +x "$INSTALL_DIR/lib/task" 2>/dev/null || true

# Copy models.json to /opt/ralph/
sudo cp "$RALPH_SRC/models.json" "$INSTALL_DIR/models.json"

# Copy skills/ to ~/.claude/skills/
cp -r "$RALPH_SRC"/skills/* ~/.claude/skills/

# Copy hooks/ to /opt/ralph/hooks/
sudo cp "$RALPH_SRC"/hooks/* "$INSTALL_DIR/hooks/"
sudo chmod +x "$INSTALL_DIR/hooks/"*.sh 2>/dev/null || true

# --- Configure Claude Code hooks ---
SETTINGS_FILE="$HOME/.claude/settings.json"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi
jq '.hooks = ((.hooks // {}) * {"PreCompact":[{"matcher":"*","hooks":[{"type":"command","command":"bash /opt/ralph/hooks/precompact.sh"}]}],"SessionEnd":[{"matcher":"*","hooks":[{"type":"command","command":"bash /opt/ralph/hooks/session_end.sh"}]}]})' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"

# --- Write bootstrap marker ---
mkdir -p ~/.ralph
touch ~/.ralph/.bootstrapped
echo "Bootstrap complete"
BOOTSTRAP_EOF
)"

    # Replace placeholder with actual ralph source path
    bootstrap_script="${bootstrap_script//__RALPH_SOURCE__/$ralph_source}"

    # Execute bootstrap inside the sandbox
    docker sandbox exec "$name" bash -c "$bootstrap_script"
}

# resolve_aws_credentials: resolve AWS credentials for Bedrock access
# If AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are already set, validates via
# aws sts get-caller-identity. Otherwise, attempts credential resolution.
# Resolves AWS_DEFAULT_REGION from env or aws configure get region.
# Exits 1 with actionable error on failure.
resolve_aws_credentials() {
    # Verify aws CLI is available
    if ! command -v aws >/dev/null 2>&1; then
        echo "Error: aws CLI is required for Bedrock credential resolution but not found in PATH" >&2
        echo "Install the AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" >&2
        return 1
    fi

    # If credentials are not already in environment, try to resolve them
    if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
        # Verify credentials are available (triggers SSO refresh if configured)
        if ! aws sts get-caller-identity >/dev/null 2>&1; then
            echo "Error: AWS credentials could not be resolved" >&2
            echo "Try running: aws sso login" >&2
            echo "Or configure credentials: aws configure" >&2
            return 1
        fi

        # Export credentials from the resolved profile
        local cred_output
        cred_output="$(aws configure export-credentials --format env 2>/dev/null)" || {
            echo "Error: failed to export AWS credentials" >&2
            echo "Try running: aws sso login" >&2
            return 1
        }
        eval "$cred_output"
    fi

    # Resolve region if not set
    if [ -z "${AWS_DEFAULT_REGION:-}" ]; then
        AWS_DEFAULT_REGION="$(aws configure get region 2>/dev/null)" || true
        if [ -z "$AWS_DEFAULT_REGION" ]; then
            echo "Error: AWS_DEFAULT_REGION is not set and could not be resolved from aws configure" >&2
            echo "Set AWS_DEFAULT_REGION or run: aws configure set region <region>" >&2
            return 1
        fi
        echo "$AWS_DEFAULT_REGION"
        export AWS_DEFAULT_REGION
    fi
}

# build_credential_flags: assemble -e flags for docker sandbox exec
# Prints flags to stdout, one per line: -e KEY=VALUE
# Handles: AWS credentials, CLAUDE_CODE_USE_BEDROCK, RALPH_SCOPE_*, RALPH_DOCKER_ENV
build_credential_flags() {
    # AWS credentials
    [ -n "${AWS_ACCESS_KEY_ID:-}" ] && echo "-e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID"
    [ -n "${AWS_SECRET_ACCESS_KEY:-}" ] && echo "-e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY"
    [ -n "${AWS_SESSION_TOKEN:-}" ] && echo "-e AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN"
    [ -n "${AWS_DEFAULT_REGION:-}" ] && echo "-e AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION"

    # Bedrock flag
    [ "${CLAUDE_CODE_USE_BEDROCK:-}" = "1" ] && echo "-e CLAUDE_CODE_USE_BEDROCK=1"

    # Scope passthrough
    [ -n "${RALPH_SCOPE_REPO:-}" ] && echo "-e RALPH_SCOPE_REPO=$RALPH_SCOPE_REPO"
    [ -n "${RALPH_SCOPE_BRANCH:-}" ] && echo "-e RALPH_SCOPE_BRANCH=$RALPH_SCOPE_BRANCH"

    # Custom environment variables from RALPH_DOCKER_ENV (comma-separated)
    if [ -n "${RALPH_DOCKER_ENV:-}" ]; then
        local IFS=','
        local var_name
        for var_name in $RALPH_DOCKER_ENV; do
            # Trim whitespace
            var_name="$(echo "$var_name" | tr -d ' ')"
            # Only include if the variable is set in the environment
            if [ -n "${!var_name+x}" ]; then
                echo "-e ${var_name}=${!var_name}"
            fi
        done
    fi
}
