#!/bin/bash
# lib/docker.sh — Docker lifecycle and PostgreSQL readiness for ralph.sh
#
# Provides:
#   check_docker_installed()  — verify docker CLI and compose V2 plugin
#   is_container_running()    — check if ralph-task-dev container is running
#   wait_for_healthy()        — poll until container healthy + pg_isready
#   ensure_env_file()         — create .env from .env.example if missing
#   load_env()                — ensure .env exists and source it
#   ensure_postgres()         — orchestrate full Docker lifecycle
#   derive_sandbox_name()     — deterministic sandbox name from repo+branch
#   lookup_sandbox()          — check sandbox existence and state
#   resolve_aws_credentials() — resolve AWS/Bedrock credentials for sandbox injection
#
# Globals used:
#   SCRIPT_DIR (must be set before sourcing)
#   DOCKER_HEALTH_TIMEOUT (optional, default 30s)
#   POSTGRES_PORT (optional, default 5464)

# check_docker_installed: verify docker CLI and compose V2 are available
check_docker_installed() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Error: docker CLI not found. Install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    if ! docker compose version >/dev/null 2>&1; then
        echo "Error: docker compose V2 plugin not found. Install the Compose plugin: https://docs.docker.com/compose/install/"
        exit 1
    fi
}

# is_container_running: check if ralph-task-dev container is running
is_container_running() {
    docker inspect --format '{{.State.Running}}' ralph-task-dev 2>/dev/null | grep -q 'true'
}

# wait_for_healthy: poll docker health + pg_isready until healthy or timeout
wait_for_healthy() {
    local timeout="${DOCKER_HEALTH_TIMEOUT:-30}"
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        local health_status
        health_status=$(docker inspect --format '{{.State.Health.Status}}' ralph-task-dev 2>/dev/null) || true
        if [ "$health_status" = "healthy" ] && pg_isready -h localhost -p "${POSTGRES_PORT:-5464}" -q 2>/dev/null; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "Error: ralph-task-dev failed to become healthy within ${timeout}s"
    exit 1
}

# ensure_env_file: create .env from .env.example if missing
ensure_env_file() {
    if [ -f "$SCRIPT_DIR/.env" ]; then
        return 0
    fi
    if [ -f "$SCRIPT_DIR/.env.example" ]; then
        cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
        echo "Created .env from .env.example — edit as needed."
        return 0
    fi
    echo "Warning: .env.example not found in $SCRIPT_DIR — set RALPH_DB_URL manually or run: cp .env.example .env"
}

# load_env: ensure .env exists and source it, preserving existing RALPH_DB_URL
load_env() {
    ensure_env_file
    if [ -f "$SCRIPT_DIR/.env" ]; then
        local _saved_db_url="${RALPH_DB_URL:-}"
        # shellcheck disable=SC1091
        . "$SCRIPT_DIR/.env"
        if [ -n "$_saved_db_url" ]; then RALPH_DB_URL="$_saved_db_url"; fi
    fi
}

# ensure_postgres: orchestrate Docker container startup and health check
ensure_postgres() {
    if [ "${RALPH_SKIP_DOCKER:-}" = "1" ]; then
        return 0
    fi
    check_docker_installed
    if is_container_running; then
        wait_for_healthy
        return 0
    fi
    docker compose --project-directory "$SCRIPT_DIR" up -d
    wait_for_healthy
}

# _sanitize_name_component: replace non-alphanumeric chars with dashes,
# collapse consecutive dashes, strip leading/trailing dashes.
# Usage: _sanitize_name_component "some/string"
# Outputs sanitized string on stdout.
_sanitize_name_component() {
    local input="$1"
    # Replace non-alphanumeric with dash
    local sanitized
    sanitized=$(printf '%s' "$input" | tr -c 'a-zA-Z0-9' '-')
    # Collapse consecutive dashes
    sanitized=$(printf '%s' "$sanitized" | sed 's/-\{2,\}/-/g')
    # Strip leading dashes
    sanitized="${sanitized#-}"
    # Strip trailing dashes
    sanitized="${sanitized%-}"
    printf '%s' "$sanitized"
}

# derive_sandbox_name: build deterministic sandbox name from repo+branch.
# Pattern: ralph-{sanitized_repo}-{sanitized_branch}
# Truncated to 63 characters (no trailing dash).
# Repo/branch derived from env vars or git (same logic as lib/task get_scope).
# Sets global: SANDBOX_NAME
derive_sandbox_name() {
    local scope_repo scope_branch

    # Repo: env var takes precedence over git
    if [ -n "${RALPH_SCOPE_REPO:-}" ]; then
        scope_repo="$RALPH_SCOPE_REPO"
    else
        if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            echo 'Error: not inside a git repository' >&2
            exit 1
        fi

        local remote_url
        if ! remote_url=$(git remote get-url origin 2>/dev/null); then
            echo 'Error: no git remote "origin" found' >&2
            exit 1
        fi

        # Strip trailing .git suffix
        local clean_url="${remote_url%.git}"

        if [[ "$clean_url" =~ ^[a-zA-Z]+:// ]]; then
            # URL format: https://github.com/owner/repo
            local path="${clean_url#*://}"  # remove scheme
            path="${path#*/}"               # remove host
            scope_repo="$path"
        else
            # SCP-like SSH format: git@github.com:owner/repo
            scope_repo="${clean_url##*:}"
        fi
    fi

    # Branch: env var takes precedence over git
    if [ -n "${RALPH_SCOPE_BRANCH:-}" ]; then
        scope_branch="$RALPH_SCOPE_BRANCH"
    else
        if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            echo 'Error: not inside a git repository' >&2
            exit 1
        fi

        local branch
        branch=$(git branch --show-current)
        if [ -z "$branch" ]; then
            echo 'Error: detached HEAD state. Checkout a branch first' >&2
            exit 1
        fi
        scope_branch="$branch"
    fi

    # Sanitize components: replace slash between owner/repo with dash
    local sanitized_repo sanitized_branch
    sanitized_repo=$(_sanitize_name_component "$scope_repo")
    sanitized_branch=$(_sanitize_name_component "$scope_branch")

    # Assemble name
    local name="ralph-${sanitized_repo}-${sanitized_branch}"

    # Truncate to 63 characters
    if [ "${#name}" -gt 63 ]; then
        name="${name:0:63}"
        # Ensure no trailing dash after truncation
        name="${name%-}"
    fi

    SANDBOX_NAME="$name"
}

# lookup_sandbox: check if a sandbox exists and return its status.
# Usage: lookup_sandbox <name>
# Outputs: "running", "stopped", or "" (not found).
lookup_sandbox() {
    local name="$1"
    local json
    json=$(docker sandbox ls --json 2>/dev/null) || { echo ""; return 0; }

    local status
    status=$(printf '%s' "$json" | jq -r --arg name "$name" \
        '.[] | select(.name == $name) | .status // empty' 2>/dev/null)

    case "$status" in
        running) echo "running" ;;
        stopped|exited) echo "stopped" ;;
        *) echo "" ;;
    esac
}

# create_sandbox: create a new Docker sandbox for the given name.
# Usage: create_sandbox <name> <target_repo_dir> <ralph_docker_dir>
# Creates sandbox with claude-code template, shell agent, and mounts.
create_sandbox() {
    local name="$1"
    local target_repo_dir="$2"
    local ralph_docker_dir="$3"

    docker sandbox create \
        -t docker/sandbox-templates:claude-code \
        --name "$name" \
        shell \
        "$target_repo_dir" \
        "${ralph_docker_dir}:ro"
}

# bootstrap_sandbox: one-time setup of ralph and dependencies inside a sandbox.
# Usage: bootstrap_sandbox <name> <ralph_docker_dir>
# Checks for marker file; if missing, installs ralph, postgres, and writes marker.
bootstrap_sandbox() {
    local name="$1"
    local ralph_docker_dir="$2"

    # Check if already bootstrapped
    if docker sandbox exec "$name" test -f ~/.ralph/.bootstrapped 2>/dev/null; then
        return 0
    fi

    echo "Bootstrapping sandbox '$name'..."

    # Find the ralph-docker mount path inside the sandbox.
    # The second mount argument becomes available at a path based on its basename.
    local mount_basename
    mount_basename=$(basename "$ralph_docker_dir")

    # Install ralph and dependencies inside the sandbox
    docker sandbox exec "$name" bash -c "
        set -e

        # Determine the ralph-docker mount path (search common mount locations)
        RALPH_MOUNT=''
        for candidate in \"/root/$mount_basename\" \"/home/agent/$mount_basename\" \"/$mount_basename\"; do
            if [ -f \"\$candidate/ralph.sh\" ]; then
                RALPH_MOUNT=\"\$candidate\"
                break
            fi
        done
        if [ -z \"\$RALPH_MOUNT\" ]; then
            echo 'Error: could not locate ralph-docker mount inside sandbox' >&2
            exit 1
        fi

        # Create ralph install directory
        sudo mkdir -p /opt/ralph/lib
        sudo mkdir -p /opt/ralph/db

        # Copy ralph.sh to /usr/local/bin/ralph
        sudo cp \"\$RALPH_MOUNT/ralph.sh\" /usr/local/bin/ralph
        sudo chmod +x /usr/local/bin/ralph
        # Patch SCRIPT_DIR to point to /opt/ralph
        sudo sed -i 's|^SCRIPT_DIR=.*|SCRIPT_DIR=\"/opt/ralph\"|' /usr/local/bin/ralph

        # Copy lib/, models.json, db/ to /opt/ralph/
        sudo cp -r \"\$RALPH_MOUNT/lib/\"* /opt/ralph/lib/
        sudo cp \"\$RALPH_MOUNT/models.json\" /opt/ralph/
        if [ -d \"\$RALPH_MOUNT/db\" ]; then
            sudo cp -r \"\$RALPH_MOUNT/db/\"* /opt/ralph/db/
        fi

        # Copy skills to ~/.claude/skills/
        mkdir -p ~/.claude/skills
        if [ -d \"\$RALPH_MOUNT/skills\" ]; then
            cp -r \"\$RALPH_MOUNT/skills/\"* ~/.claude/skills/
        fi

        # Copy hooks
        if [ -d \"\$RALPH_MOUNT/hooks\" ]; then
            sudo mkdir -p /opt/ralph/hooks
            sudo cp -r \"\$RALPH_MOUNT/hooks/\"* /opt/ralph/hooks/
        fi

        # Install jq if not present
        if ! command -v jq >/dev/null 2>&1; then
            sudo apt-get update -qq && sudo apt-get install -y -qq jq
        fi

        # Install psql client if not present
        if ! command -v psql >/dev/null 2>&1; then
            sudo apt-get update -qq && sudo apt-get install -y -qq postgresql-client
        fi

        # Set up PostgreSQL via Docker Compose inside sandbox
        mkdir -p ~/.ralph
        cat > ~/.ralph/docker-compose.yml <<'COMPOSE'
services:
  ralph-task-dev:
    image: postgres:17-alpine
    ports:
      - \"5464:5432\"
    environment:
      POSTGRES_USER: ralph
      POSTGRES_PASSWORD: ralph
      POSTGRES_DB: ralph
    healthcheck:
      test: [\"CMD-SHELL\", \"pg_isready -U ralph\"]
      interval: 2s
      timeout: 5s
      retries: 10
    volumes:
      - ralph-data:/var/lib/postgresql/data
      - /opt/ralph/db:/docker-entrypoint-initdb.d:ro
volumes:
  ralph-data:
COMPOSE

        # Generate .env
        cat > ~/.ralph/.env <<'ENVFILE'
RALPH_DB_URL=postgres://ralph:ralph@localhost:5464/ralph
POSTGRES_PORT=5464
ENVFILE

        # Start PostgreSQL
        docker compose -f ~/.ralph/docker-compose.yml up -d

        # Wait for healthy
        timeout=30
        elapsed=0
        while [ \"\$elapsed\" -lt \"\$timeout\" ]; do
            if docker inspect --format '{{.State.Health.Status}}' ralph-task-dev 2>/dev/null | grep -q healthy; then
                break
            fi
            sleep 1
            elapsed=\$((elapsed + 1))
        done

        # Write bootstrap marker
        touch ~/.ralph/.bootstrapped
        echo 'Bootstrap complete.'
    "
}

# resolve_aws_credentials: resolve current AWS credentials for sandbox injection.
# Outputs KEY=VALUE lines for: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
# AWS_SESSION_TOKEN, AWS_DEFAULT_REGION.
# Exits 1 with actionable error if aws CLI is missing or credentials fail.
resolve_aws_credentials() {
    # Verify aws CLI is available
    if ! command -v aws >/dev/null 2>&1; then
        echo "Error: aws CLI not found. Install it: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" >&2
        return 1
    fi

    # Resolve credentials via aws configure export-credentials
    local cred_json
    if ! cred_json=$(aws configure export-credentials --format json 2>&1); then
        echo "Error: Failed to resolve AWS credentials. Run 'aws sso login' or configure AWS credentials." >&2
        echo "$cred_json" >&2
        return 1
    fi

    # Extract credential fields from JSON
    local access_key secret_key session_token
    access_key=$(printf '%s' "$cred_json" | jq -r '.AccessKeyId // empty')
    secret_key=$(printf '%s' "$cred_json" | jq -r '.SecretAccessKey // empty')
    session_token=$(printf '%s' "$cred_json" | jq -r '.SessionToken // empty')

    if [ -z "$access_key" ] || [ -z "$secret_key" ]; then
        echo "Error: Failed to resolve AWS credentials. Run 'aws sso login' or configure AWS credentials." >&2
        return 1
    fi

    # Resolve region: env var takes precedence, then aws configure
    local region="${AWS_DEFAULT_REGION:-}"
    if [ -z "$region" ]; then
        region=$(aws configure get region 2>/dev/null) || true
    fi
    if [ -z "$region" ]; then
        echo "Error: AWS region could not be determined. Set AWS_DEFAULT_REGION or run 'aws configure set region <region>'." >&2
        return 1
    fi

    # Output KEY=VALUE lines for consumption by caller
    echo "AWS_ACCESS_KEY_ID=${access_key}"
    echo "AWS_SECRET_ACCESS_KEY=${secret_key}"
    echo "AWS_SESSION_TOKEN=${session_token}"
    echo "AWS_DEFAULT_REGION=${region}"
}
