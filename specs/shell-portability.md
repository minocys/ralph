# Shell Portability

Align `ralph.sh` from zsh to bash so both scripts in the project use the same shell.

## Requirements

- Change the shebang in `ralph.sh` from `#!/bin/zsh` to `#!/bin/bash`
- Replace the `print` call (line 109) with `printf` or `echo`
- Verify that all other syntax used in `ralph.sh` is bash-compatible:
  - Array append (`CLAUDE_ARGS+=()`) — supported in bash 3.1+
  - `[[ ]]` conditionals — supported in bash
  - `$(( ))` arithmetic — supported in bash
- `install.sh` remains unchanged (already bash)

## Constraints

- Do not change any behavior — only the shell compatibility layer
- Do not refactor or restructure ralph.sh beyond what is needed for bash compatibility

## Out of Scope

- Adding new features to ralph.sh
- Changing the jq filter or output format
- Modifying install.sh
