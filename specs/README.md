# Specs

| Spec | Topic of Concern |
| ---- | ---------------- |
| [spec-template.md](spec-template.md) | Add output format guidance to ralph-spec |
| [shared-vocabulary.md](shared-vocabulary.md) | Distribute the concepts table to ralph-plan and ralph-build |
| [shell-portability.md](shell-portability.md) | Align ralph.sh from zsh to bash |
| [model-alias-registry.md](model-alias-registry.md) | Extensible JSON registry mapping model aliases to backend-specific IDs |
| [cli-model-selection.md](cli-model-selection.md) | Multi-source backend detection and model selection via CLI flags |
| [task-data-store.md](task-data-store.md) | PostgreSQL-backed persistent storage for multi-agent task orchestration |
| [task-cli.md](task-cli.md) | Phase-specific bash CLI for planner and builders to interact with the task backlog |
| [agent-lifecycle.md](agent-lifecycle.md) | Agent registration and identification for ephemeral Docker containers |
| [task-scheduling.md](task-scheduling.md) | Task peek, untargeted and targeted claiming, lease-based recovery, DAG scheduling, and idempotent plan synchronization |
| [plan-skill-integration.md](plan-skill-integration.md) | Outer loop pre-fetches task DAG and passes it to the plan skill as an argument |
| [build-skill-integration.md](build-skill-integration.md) | ralph-build receives task landscape, selects the best task via LLM reasoning, and implements via targeted claiming |
| [build-loop-control.md](build-loop-control.md) | Pre-invocation task peek, context passing to the build skill, post-iteration status checks, and crash-safety fallback in ralph.sh |
| [session-safety-hooks.md](session-safety-hooks.md) | PreCompact and SessionEnd hooks to release active tasks on unexpected exits |
| [plan-sync-validation.md](plan-sync-validation.md) | Validate JSONL input in plan-sync before processing, fail fast on malformed data |
| [graceful-interrupt.md](graceful-interrupt.md) | Two-stage Ctrl+C: graceful cleanup then force-kill |
| [docker-auto-start.md](docker-auto-start.md) | Automatic PostgreSQL Docker container lifecycle management |
| [shared-env-config.md](shared-env-config.md) | Single .env file as shared source of truth for database configuration |
| [ralph-modular-refactor.md](ralph-modular-refactor.md) | Split ralph.sh monolith into sourced lib/ modules by concern |
| [task-output-format.md](task-output-format.md) | Replace JSONL output with markdown-KV format for plan-export and peek |
| [task-steps-simplification.md](task-steps-simplification.md) | Flatten task steps from a separate table into a TEXT[] column and remove step tracking |
| [docker-executor-toggle.md](docker-executor-toggle.md) | `DOCKER_EXECUTOR` env var switches ralph between local and containerized Claude Code execution |
| [worker-container-image.md](worker-container-image.md) | Alpine-based Dockerfile with Claude Code, git, jq, and psql for running ralph loops in Docker |
| [container-networking.md](container-networking.md) | Shared Docker network and compose service connecting ralph-worker to ralph-task-db |
| [project-auth-mounting.md](project-auth-mounting.md) | Bind-mount strategy for project directories, ~/.claude auth, and credential passthrough |
| [container-entrypoint.md](container-entrypoint.md) | Entrypoint script that installs skills, hooks, and bootstraps the ralph environment inside the container |
| [git-worktree-isolation.md](git-worktree-isolation.md) | Git worktrees for concurrent loop isolation within the same project directory |
