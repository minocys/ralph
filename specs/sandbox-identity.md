# Sandbox Identity

## Overview

Each Docker sandbox must be uniquely and deterministically identified by the git repository and branch it operates on. This allows ralph to reuse existing sandboxes across invocations and subcommands (plan, build, task) for the same repo+branch, while maintaining isolation between different repos and branches.

## Requirements

### Name derivation

- The sandbox name follows the pattern: `ralph-{sanitized_repo}-{sanitized_branch}`.
- The repo component is derived from the git remote origin URL, extracting the `owner/repo` slug (same logic as scoped-task-lists spec's scope derivation). The slash between owner and repo is replaced with a dash, yielding `owner-repo`.
- The branch component is the current git branch name.
- Sanitization replaces all characters that are not alphanumeric (`[a-zA-Z0-9]`) with a single dash (`-`).
- Leading and trailing dashes are stripped from each component after sanitization.
- Consecutive dashes are collapsed to a single dash.
- Example: repo `minocys/ralph-docker`, branch `feature/auth/v2` → sandbox name `ralph-minocys-ralph-docker-feature-auth-v2`.
- Example: repo `acme/web-app`, branch `main` → sandbox name `ralph-acme-web-app-main`.

### Git detection

- Repo is determined in order: `RALPH_SCOPE_REPO` environment variable, then `git remote get-url origin` (stripping `.git` suffix, handling SSH and HTTPS formats).
- Branch is determined in order: `RALPH_SCOPE_BRANCH` environment variable, then `git branch --show-current`.
- If not inside a git repository, exit 1 with error: `Error: not inside a git repository`.
- If no remote named `origin` exists, exit 1 with error: `Error: no git remote "origin" found`.
- If in detached HEAD state, exit 1 with error: `Error: detached HEAD state. Checkout a branch first`.

### Lookup

- Sandbox existence is checked via `docker sandbox ls --json`, filtering by name.
- The lookup must distinguish three states: **not found**, **running**, **stopped**.
- The lookup function returns the sandbox status or empty string if not found.

### Name length

- Docker sandbox names have a practical limit. If the derived name exceeds 63 characters, it must be truncated to 63 characters (dropping from the end), ensuring the result does not end with a dash.

## Constraints

- The sanitization function must be implementable in bash 3.2+ without external dependencies beyond standard coreutils (`tr`, `sed`).
- The name must be valid for Docker sandbox `--name`: letters, numbers, hyphens, underscores, periods, and plus/minus signs.
- The name must be deterministic — the same repo+branch must always produce the same name.

## Out of Scope

- Namespace collision handling beyond truncation (two different long repo+branch combos producing the same truncated name is accepted as unlikely).
- Sandbox naming for non-git workspaces.
- Custom name overrides via CLI flags.
