# Agent Lifecycle

Agent identification, registration, and crash recovery for multi-agent task orchestration.

## Requirements

- When a ralph loop starts, it must register an agent via `task agent register` before entering the build loop
- Registration must:
  - Generate a unique 4-character hex ID (e.g. `a7f2`)
  - Record the shell process PID (`$$`)
  - Set `started_at` and `heartbeat` to current timestamp
  - Print the agent ID to stdout for capture by the calling script
- The agent ID must be passed to Claude Code so agents can identify themselves when claiming tasks
- `task agent list` must show all active agents with their ID, PID, started_at, and heartbeat
- `task agent deregister <id>` must:
  - Set agent status to `stopped`
  - NOT release claimed tasks (explicit recovery is separate)
- `task agent recover <id>` must:
  - Set all `active` tasks assigned to that agent back to `open` with assignee cleared
  - Set agent status to `stopped`
  - Print the number of tasks released
- On ralph loop exit (normal completion or signal), deregister the agent
- On ralph loop startup, detect and offer recovery for agents whose PID is no longer running (stale agents)

## Constraints

- Agent IDs must be unique within the database — retry generation on collision
- PID-based liveness detection is best-effort (PIDs can be recycled by the OS)
- Agent registration and deregistration must be atomic transactions

## Out of Scope

- Heartbeat update during long-running tasks
- Agent-to-agent communication or coordination beyond task claiming
- Authentication or authorization of agents
- Distributed agents across multiple machines
