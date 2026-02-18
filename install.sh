#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
BIN_DIR="$HOME/.local/bin"

# Check for required dependencies
if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed."
    echo "  Install with: brew install jq (macOS) or apt install jq (Linux)"
    exit 1
fi

echo "Installing ralph from $REPO_DIR"

# Create target directories if they don't exist
mkdir -p "$SKILLS_DIR"
mkdir -p "$BIN_DIR"

# Symlink each skill into ~/.claude/skills
for skill_dir in "$REPO_DIR"/skills/*/; do
    skill_name="$(basename "$skill_dir")"
    target="$SKILLS_DIR/$skill_name"

    if [ -L "$target" ]; then
        echo "  Updating symlink: $target"
        rm "$target"
    elif [ -e "$target" ]; then
        echo "  Warning: $target already exists and is not a symlink, skipping"
        continue
    fi

    ln -s "$skill_dir" "$target"
    echo "  Linked skill: $skill_name -> $target"
done

# Symlink ralph.sh into ~/.local/bin
RALPH_LINK="$BIN_DIR/ralph"
if [ -L "$RALPH_LINK" ]; then
    echo "  Updating symlink: $RALPH_LINK"
    rm "$RALPH_LINK"
elif [ -e "$RALPH_LINK" ]; then
    echo "  Warning: $RALPH_LINK already exists and is not a symlink, skipping"
fi

if [ ! -e "$RALPH_LINK" ]; then
    ln -s "$REPO_DIR/ralph.sh" "$RALPH_LINK"
    echo "  Linked script: ralph.sh -> $RALPH_LINK"
fi

# Symlink task into ~/.local/bin
TASK_LINK="$BIN_DIR/task"
if [ -L "$TASK_LINK" ]; then
    echo "  Updating symlink: $TASK_LINK"
    rm "$TASK_LINK"
elif [ -e "$TASK_LINK" ]; then
    echo "  Warning: $TASK_LINK already exists and is not a symlink, skipping"
fi

if [ ! -e "$TASK_LINK" ]; then
    ln -s "$REPO_DIR/task" "$TASK_LINK"
    echo "  Linked script: task -> $TASK_LINK"
fi

echo ""
echo "Done. Make sure $BIN_DIR is in your PATH."
