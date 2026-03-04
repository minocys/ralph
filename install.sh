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

if ! command -v sqlite3 &>/dev/null; then
    echo "Error: sqlite3 is required but not installed."
    echo "  macOS:  sqlite3 ships with Xcode Command Line Tools"
    echo "  Linux:  sudo apt install sqlite3  (Debian/Ubuntu)"
    echo "          sudo dnf install sqlite   (Fedora/RHEL)"
    exit 1
fi

# Verify sqlite3 version >= 3.35 (required for RETURNING clause)
_sqlite_ver="$(sqlite3 --version | awk '{print $1}')"
_sqlite_major="${_sqlite_ver%%.*}"
_sqlite_minor="${_sqlite_ver#*.}"; _sqlite_minor="${_sqlite_minor%%.*}"
if [ "$_sqlite_major" -lt 3 ] 2>/dev/null || { [ "$_sqlite_major" -eq 3 ] && [ "$_sqlite_minor" -lt 35 ]; }; then
    echo "Error: sqlite3 >= 3.35 is required (found $_sqlite_ver)."
    echo "  RETURNING clause support requires version 3.35+."
    exit 1
fi
echo "  sqlite3 $_sqlite_ver OK"

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

# Clean up legacy task symlink from previous installs
TASK_LINK="$BIN_DIR/task"
if [ -L "$TASK_LINK" ]; then
    echo "  Removing legacy symlink: $TASK_LINK (use 'ralph task' instead)"
    rm "$TASK_LINK"
fi

# Add hooks to ~/.claude/settings.json
SETTINGS_FILE="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi
jq --arg repo "$REPO_DIR" '.hooks = ((.hooks // {}) * {"PreCompact":[{"matcher":"*","hooks":[{"type":"command","command":("bash " + $repo + "/hooks/precompact.sh")}]}],"SessionEnd":[{"matcher":"*","hooks":[{"type":"command","command":("bash " + $repo + "/hooks/session_end.sh")}]}]})' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
echo "  Configured hooks in $SETTINGS_FILE"

echo ""
echo "Done. Make sure $BIN_DIR is in your PATH."
