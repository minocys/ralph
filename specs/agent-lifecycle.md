# Agent Lifecycle

Agent identification and registration for multi-agent task orchestration across ephemeral Docker containers.

## Requirements

- When a ralph build loop starts, it must register an agent via `task agent register` before entering the build loop
- Registration must:
  - Generate a unique 4-character hex ID (e.g. `a7f2`)
  - Record the shell process PID (`$$`)
  - Record the hostname (`$HOSTNAME` or `$(hostname)`) for multi-host identification
  - Set `started_at` to current timestamp
  - Print the agent ID to stdout for capture by the calling script
- The agent ID must be passed to Claude Code so agents can identify themselves when claiming tasks
- `task agent list` must show all active agents with their ID, PID, hostname, and started_at
- `task agent deregister <id>` must set agent status to `stopped`
- On ralph loop exit (normal completion or signal), deregister the agent
- Crash recovery is handled by the lease mechanism (see Task Scheduling spec) — no agent-level recovery command is needed

## Constraints

- Agent IDs must be unique within the database — retry generation on collision
- Agent registration and deregistration must be atomic transactions
- Agents are ephemeral — a stopped agent's record is retained for debugging but has no operational effect

## Out of Scope

- Heartbeat updates during long-running tasks (leases on tasks handle this)
- Agent-to-agent communication or coordination beyond task claiming
- Authentication or authorization of agents
- Agent health monitoring or dashboards
- PID-based liveness detection (unreliable across containers; leases replace this)
