# Specs

| Spec | Topic of Concern |
| ---- | ---------------- |
| [spec-template.md](spec-template.md) | Add output format guidance to ralph-spec |
| [shared-vocabulary.md](shared-vocabulary.md) | Distribute the concepts table to ralph-plan and ralph-build |
| [shell-portability.md](shell-portability.md) | Align ralph.sh from zsh to bash |
| [model-alias-registry.md](model-alias-registry.md) | Extensible JSON registry mapping model aliases to backend-specific IDs |
| [cli-model-selection.md](cli-model-selection.md) | Multi-source backend detection and model selection via CLI flags |
| [cli-subcommand-dispatch.md](cli-subcommand-dispatch.md) | Restructure ralph.sh into a thin subcommand dispatcher with plan, build, and task as peer subcommands |
| [task-data-store.md](task-data-store.md) | PostgreSQL-backed persistent storage for multi-agent task orchestration |
| [task-cli.md](task-cli.md) | Phase-specific bash CLI for planner and builders to interact with the task backlog via `ralph task` |
| [task-cli-relocation.md](task-cli-relocation.md) | Move task script to lib/task and route user access through `ralph task` |
| [agent-lifecycle.md](agent-lifecycle.md) | Agent registration and identification for ephemeral Docker containers |
| [task-scheduling.md](task-scheduling.md) | Task peek, untargeted and targeted claiming, lease-based recovery, DAG scheduling, and idempotent plan synchronization |
| [plan-skill-integration.md](plan-skill-integration.md) | Plan loop pre-fetches task DAG and passes it to the plan skill as an argument |
| [plan-loop-control.md](plan-loop-control.md) | Deterministic for-loop for plan mode, replacing the sentinel-based while-true loop |
| [build-skill-integration.md](build-skill-integration.md) | ralph-build receives task landscape, selects the best task via LLM reasoning, and implements via targeted claiming |
| [build-loop-control.md](build-loop-control.md) | Pre-invocation task peek, context passing to the build skill, post-iteration status checks, and crash-safety fallback |
| [session-safety-hooks.md](session-safety-hooks.md) | PreCompact and SessionEnd hooks to release active tasks on unexpected exits |
| [plan-sync-validation.md](plan-sync-validation.md) | Validate JSONL input in plan-sync before processing, fail fast on malformed data |
| [graceful-interrupt.md](graceful-interrupt.md) | Two-stage Ctrl+C: graceful cleanup then force-kill |
| [docker-auto-start.md](docker-auto-start.md) | Automatic PostgreSQL Docker container lifecycle management |
| [shared-env-config.md](shared-env-config.md) | Single .env file as shared source of truth for database configuration |
| [ralph-modular-refactor.md](ralph-modular-refactor.md) | Split ralph.sh into sourced lib/ modules and subcommand dispatcher |
| [task-output-format.md](task-output-format.md) | Replace JSONL output with markdown-KV format for `list --all` and peek |
| [task-steps-simplification.md](task-steps-simplification.md) | Flatten task steps from a separate table into a TEXT[] column and remove step tracking |
| [deprecate-plan-export.md](deprecate-plan-export.md) | Complete removal of `plan-export` command (replaced by `ralph task list --all`) |
| [scoped-task-lists.md](scoped-task-lists.md) | Scope task and agent data by git repository and branch for multi-agent isolation |
| [docker-sandbox-dispatch.md](docker-sandbox-dispatch.md) | CLI routing that intercepts `--docker` and delegates subcommand execution to a Docker sandbox |
| [sandbox-identity.md](sandbox-identity.md) | Deterministic sandbox naming from repo and branch, with existence lookup and reuse |
| [sandbox-bootstrap.md](sandbox-bootstrap.md) | One-time setup of ralph, PostgreSQL, and dependencies inside a newly created sandbox |
| [sandbox-credentials.md](sandbox-credentials.md) | AWS/Bedrock credential resolution and injection into the sandbox environment |
| [sandbox-signal-handling.md](sandbox-signal-handling.md) | Ctrl+C detach behavior when attached to a Docker sandbox exec session |
