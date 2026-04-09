# Sandbox Credentials

## Overview

Ralph inside a Docker sandbox needs API credentials to invoke Claude Code. The Docker sandbox proxy automatically injects standard API keys (ANTHROPIC_API_KEY) into outbound requests. However, AWS/Bedrock credentials require explicit handling because they use a multi-variable authentication model (access key, secret, session token, region) that the sandbox proxy does not manage.

## Requirements

### Standard API keys

- ANTHROPIC_API_KEY and other standard API keys are handled by the Docker sandbox proxy's automatic credential injection. No action is required from ralph.
- The sandbox proxy intercepts outbound HTTPS requests and injects credentials stored on the host. Credentials are never stored inside the sandbox VM.

### AWS credential resolution

- When `--docker` is active, ralph must check if the active backend is Bedrock (using the same detection logic as `lib/config.sh:detect_backend()`).
- If the backend is Bedrock, ralph resolves the current AWS credentials before exec-ing into the sandbox.
- Resolution uses `aws sts get-session-credentials` (or `aws sts get-caller-identity` followed by extracting credentials from the resolved profile) to obtain temporary session credentials.
- The resolved credentials are: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_DEFAULT_REGION`.
- If `AWS_DEFAULT_REGION` is not set in the host environment, it is read from `aws configure get region`.
- If credential resolution fails (e.g., `aws` CLI not installed, SSO session expired, no valid profile), ralph exits 1 with an actionable error message suggesting the user run `aws sso login` or configure AWS credentials.

### Credential injection

- Resolved AWS credentials are passed to the sandbox via `-e` flags on the `docker sandbox exec` call: `-e AWS_ACCESS_KEY_ID=... -e AWS_SECRET_ACCESS_KEY=... -e AWS_SESSION_TOKEN=... -e AWS_DEFAULT_REGION=...`.
- Credentials are injected on every `docker sandbox exec` call, not just during bootstrap. This ensures fresh credentials are available even if previous ones have expired.

### Bedrock environment flag

- If `CLAUDE_CODE_USE_BEDROCK=1` is set on the host, it must be forwarded to the sandbox exec via `-e CLAUDE_CODE_USE_BEDROCK=1`.
- The dispatch code reads this from the same sources as `detect_backend()`: environment variable, then Claude settings files.

### Custom environment variable passthrough

- Users can pass additional environment variables into the sandbox by setting `RALPH_DOCKER_ENV` as a comma-separated list of variable names.
- Example: `RALPH_DOCKER_ENV=MY_CUSTOM_VAR,ANOTHER_VAR ralph --docker build` passes `-e MY_CUSTOM_VAR=... -e ANOTHER_VAR=...` to the exec call.
- Variables listed in `RALPH_DOCKER_ENV` that are not set in the host environment are silently skipped.

### AWS SSO limitations

- AWS SSO tokens have a limited lifetime (typically 1-8 hours). If a long-running ralph loop outlives the session token, API calls will fail inside the sandbox.
- Ralph does not attempt to refresh credentials during a running sandbox session. The user must re-run `aws sso login` on the host and restart the ralph command.
- This limitation must be documented in ralph's help output for `--docker`.

## Constraints

- The `aws` CLI must be available on the host for Bedrock credential resolution. If `aws` is not installed and backend is Bedrock, exit 1 with an error.
- Credentials are passed as environment variables to `docker sandbox exec`, which means they are visible in the process table on the host. This is acceptable for local development use.
- The sandbox proxy's credential injection is transparent and cannot be disabled or configured by ralph.

## Out of Scope

- Mounting `~/.aws` config files into the sandbox.
- Credential refresh or rotation during a running session.
- IAM role assumption or cross-account access.
- Non-AWS cloud provider credentials (GCP, Azure).
- Encrypting credentials in transit between host and sandbox.
