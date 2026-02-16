# Graceful Interrupt Handling

## Overview

`ralph.sh` does not reliably exit when the user presses Ctrl+C. The root cause is that bash defers trap handlers until a foreground pipeline completes, and the `claude` CLI catches SIGINT for its own cleanup, creating a deadlock where the shell waits for `claude` and the trap never fires.

This spec replaces the current signal handling with a background-pipeline + `wait` pattern that supports two-stage interrupt: first Ctrl+C lets `claude` clean up gracefully, second Ctrl+C force-kills everything.

## Requirements

### Two-stage interrupt

- **First Ctrl+C**: the shell prints a message indicating it is waiting for `claude` to clean up and that the user can press Ctrl+C again to force quit. The `claude` process receives SIGINT (from the terminal's process group signal) and is allowed to finish its cleanup. The shell re-waits for the pipeline to exit naturally. Once the pipeline exits, ralph itself exits with code 130 — it does **not** continue to the next loop iteration.
- **Second Ctrl+C** (optional): if `claude` is taking too long to clean up, the shell force-terminates all child processes and exits with code 130.

### Background pipeline with `wait`

- The `claude | tee | jq` pipeline must run in the background (appended `&`) wrapped in a subshell `(...)` so that `$!` captures the subshell PID, which remains alive until all pipeline components exit.
- The shell waits on the subshell PID using the `wait` builtin, which is interruptible by trapped signals.
- After `wait` is interrupted, the shell re-enters a `wait` loop (guarded by `kill -0`) to give `claude` time to finish.

### Interrupt state tracking

- A shell variable (e.g., `INTERRUPTED`) tracks how many times SIGINT has been received during the current pipeline execution.
- The variable resets to `0` before each iteration of the main loop.

### Force-kill mechanism

- On second interrupt, the handler resets traps (`trap - INT TERM`) to prevent recursive signals, then sends `kill -9 -- -$PIPELINE_PID` (SIGKILL to the pipeline's process group) to ensure `claude`, `tee`, `jq`, and any grandchildren are terminated.
  - The `-- -$PID` syntax kills the entire process group of the subshell, not just the subshell itself.
  - This is more robust than `kill -9 $PIPELINE_PID` because it guarantees all pipeline components are killed even if they've spawned their own children.
- The handler then calls `exit 130`.

### Temp file cleanup

- The existing `trap 'rm -f "$TMPFILE"' EXIT` must be preserved. Force-kill triggers `exit 130`, which fires the EXIT trap and cleans up the temp file.

### TERM signal

- SIGTERM should force-kill immediately (no two-stage grace period). This matches expected behavior for non-interactive termination (e.g., `kill <pid>`, system shutdown).
- The TERM handler uses `kill -9 -- -$PIPELINE_PID` to kill the pipeline's process group, identical to the second Ctrl+C force-kill mechanism.
  - `$PIPELINE_PID` is the PID of the pipeline subshell captured with `$!`.
  - `-$PIPELINE_PID` (negative) means "the process group of the pipeline subshell".
  - This kills all pipeline components (`claude`, `tee`, `jq`) and their descendants while allowing ralph to exit cleanly with code 130.
  - Using the same process group kill as handle_int's second Ctrl+C ensures consistent cleanup behavior.

## Implementation Best Practices

### Process group kill syntax

The spec uses **process group kill** syntax (`kill -- -$PID`) rather than simple `kill $PID`. This is a common idiom in production bash scripts for robust cleanup.

**Why `kill -- -$PID`?**
- `--` prevents argument parsing issues if PID is negative or looks like a flag
- `-$PID` (negative) targets the **process group** of PID, not just the single process
- For a subshell `( pipeline ) &`, this kills all pipeline components (`claude | tee | jq`) and their descendants
- Without the negative sign, only the subshell itself dies; child processes may continue running

**Example:**
```bash
( sleep 30 | tee output.log ) &
SUBSHELL_PID=$!

# ❌ Only kills the subshell; sleep and tee keep running
kill -9 $SUBSHELL_PID

# ✅ Kills subshell AND all its children (sleep, tee)
kill -9 -- -$SUBSHELL_PID
```

**Why `kill -9 -- -$PIPELINE_PID` in TERM handler?**
- `$PIPELINE_PID` is the PID of the pipeline subshell (captured with `$!`)
- `-$PIPELINE_PID` targets the pipeline's process group (all pipeline components and descendants)
- Using `-$$` (ralph's own process group) would send SIGKILL to ralph itself, which is unblockable and prevents `exit 130` from executing
- By targeting only the pipeline's process group, ralph can kill the children and then exit cleanly with code 130, ensuring EXIT trap runs for temp file cleanup

### Research sources

These patterns were validated against production codebases:
- **dygraphs/scripts/watch.sh**: `trap "kill -- -$$" SIGINT`
- **PeerTube/scripts/nightly.sh**: `kill -- -$PGID` for process group cleanup
- **JetBrains/teamcity-docker-minimal-agent**: Force-stop with process group management

The two-stage interrupt approach is more sophisticated than most patterns found in the wild, which typically use either immediate kill or timeout-based polling. Ralph's signal-driven design provides better user experience for interactive CLI use.

## Constraints

- `ralph.sh` must remain a pure bash script with no dependencies beyond `jq`.
- No use of `set -m` (job control). Without `set -m`, the pipeline shares the shell's process group. Ctrl+C from the terminal delivers SIGINT to the entire group, which is the desired behavior: `claude` receives SIGINT directly and begins its own cleanup. The shell gains responsiveness by using `wait` (interruptible) instead of a foreground pipeline (not interruptible).
- Must work on macOS bash 3.2 (shipped with macOS) and bash 5.x (Homebrew).
- After the first Ctrl+C, `tee` and `jq` die from SIGINT, so streaming output to the terminal stops. This is acceptable — the user initiated the interrupt.
- `claude` may receive SIGPIPE after `tee` dies. Well-behaved CLIs ignore SIGPIPE and continue cleanup. This is outside the scope of `ralph.sh`.

## Testing

### Test file

Add `test/ralph_signal.bats` for signal-handling tests.

### Test helper changes

The existing `claude` stub in `test_helper.bash` exits immediately. Signal tests need a stub that stays alive long enough to receive and respond to signals. Each test that needs signal behavior should create its own specialized stub (e.g., one that traps SIGINT and sleeps).

### Test cases

| # | Test | How |
|---|------|-----|
| 1 | First Ctrl+C prints waiting message | Launch `ralph.sh` in background, send SIGINT, wait briefly, check output for the "waiting" message |
| 2 | Single Ctrl+C exits 130 after `claude` finishes cleanup (no second Ctrl+C needed) | Use a stub that traps INT, sleeps 1s, then exits. Send one SIGINT, wait for ralph to exit on its own. Assert exit code 130 and that the process is gone |
| 3 | Second Ctrl+C force-kills and exits 130 | Use a stub that traps INT and ignores it (stays alive). Send SIGINT, wait briefly, send second SIGINT. Assert ralph exits 130 |
| 4 | Temp file is cleaned up after force-kill | After double Ctrl+C exit, assert the temp file created by `mktemp` no longer exists |
| 5 | SIGTERM force-kills immediately | Send SIGTERM instead of SIGINT. Assert ralph exits without waiting for the "graceful" phase |

### Testing technique

Signal tests are inherently timing-sensitive. Use `sleep` with conservative timeouts and `wait` with `$!` to avoid flakiness. Run the script in the background (`&`), capture PID, use `kill -INT $PID` / `kill -TERM $PID`, and verify exit status.

## Out of Scope

- Modifying the `claude` CLI's own SIGINT handling.
- Guaranteeing cleanup output is visible after first Ctrl+C (tee/jq die, output stream breaks).
- Adding `set -m` job control or `setsid` for process group isolation.
- Windows/WSL-specific signal behavior.
