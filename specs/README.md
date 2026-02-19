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
| [task-scheduling.md](task-scheduling.md) | Lease-based claiming, DAG scheduling, and idempotent plan synchronization |
| [plan-skill-integration.md](plan-skill-integration.md) | Migrate ralph-plan from IMPLEMENTATION_PLAN.json to the task CLI |
| [build-skill-integration.md](build-skill-integration.md) | Migrate ralph-build to atomic task claim/done/fail operations |
| [build-loop-control.md](build-loop-control.md) | Replace text-based completion signal with task status checks in ralph.sh |
| [session-safety-hooks.md](session-safety-hooks.md) | PreCompact and SessionEnd hooks to release active tasks on unexpected exits |
| [graceful-interrupt.md](graceful-interrupt.md) | Two-stage Ctrl+C: graceful cleanup then force-kill |
