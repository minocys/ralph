#!/bin/bash
# lib/config.sh — argument parsing, backend detection, and model resolution for ralph.sh
#
# Provides:
#   parse_flags()      — parse per-subcommand flags (--max-iterations, --model, --danger, --help)
#   parse_args()       — (backward compat) parse CLI flags including --plan/-p
#   detect_backend()   — determine active backend (anthropic or bedrock) from env/settings
#   resolve_model()    — resolve model alias via models.json
#   subcommand_usage() — print per-subcommand help text
#
# Globals set by parse_flags / parse_args:
#   MODE, COMMAND, MAX_ITERATIONS, DANGER, MODEL_ALIAS
# Globals set by detect_backend:
#   ACTIVE_BACKEND
# Globals set by resolve_model:
#   RESOLVED_MODEL
# Globals used:
#   SCRIPT_DIR (must be set before calling resolve_model)
#
# preflight():
#   Verifies that required files/directories exist before entering the main loop.

# subcommand_usage: print per-subcommand help and exit 0
# Usage: subcommand_usage (uses MODE global)
subcommand_usage() {
    echo "Usage: ralph $MODE [options]"
    echo ""
    echo "Options:"
    echo "  --max-iterations N, -n N   Limit loop iterations"
    if [ "$MODE" = "plan" ]; then
        echo "                             (default: 1)"
    else
        echo "                             (default: unlimited)"
    fi
    echo "  --model <alias>, -m <alias> Select model by alias (see models.json)"
    echo "  --danger                    Enable --dangerously-skip-permissions"
    echo "  --help, -h                  Show this help"
}

# parse_flags: parse per-subcommand flags (called after MODE is set by ralph.sh)
# Usage: parse_flags "$@"
# Sets: MAX_ITERATIONS, DANGER, MODEL_ALIAS
# Uses: MODE (must already be set)
parse_flags() {
    # -1 means "not explicitly set" — caller applies mode-specific default after
    MAX_ITERATIONS=-1
    DANGER=false
    MODEL_ALIAS=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-iterations|-n)
                if [[ -z "${2:-}" || "$2" = -* ]]; then
                    echo "Error: --max-iterations requires a number" >&2
                    exit 1
                fi
                MAX_ITERATIONS="$2"
                shift 2
                ;;
            --model|-m)
                if [[ -z "${2:-}" || "$2" = -* ]]; then
                    echo "Error: --model requires an alias (e.g. opus-4.5, sonnet, haiku)" >&2
                    exit 1
                fi
                MODEL_ALIAS="$2"
                shift 2
                ;;
            --danger)
                DANGER=true
                shift
                ;;
            --help|-h)
                subcommand_usage
                exit 0
                ;;
            *)
                echo "Error: Unknown option '$1'" >&2
                echo "Run 'ralph $MODE --help' for usage" >&2
                exit 1
                ;;
        esac
    done
}

# parse_args: (backward compat) parse CLI flags and set global mode/option variables
# Usage: parse_args "$@"
parse_args() {
    # Defaults
    MODE="build"
    COMMAND="/ralph-build"
    MAX_ITERATIONS=0
    DANGER=false
    MODEL_ALIAS=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --plan|-p)
                MODE="plan"
                COMMAND="/ralph-plan"
                shift
                ;;
            --max-iterations|-n)
                if [[ -z "$2" || "$2" = -* ]]; then
                    echo "Error: --max-iterations requires a number"
                    exit 1
                fi
                MAX_ITERATIONS="$2"
                shift 2
                ;;
            --model|-m)
                if [[ -z "$2" || "$2" = -* ]]; then
                    echo "Error: --model requires an alias (e.g. opus-4.5, sonnet, haiku)"
                    exit 1
                fi
                MODEL_ALIAS="$2"
                shift 2
                ;;
            --danger)
                DANGER=true
                shift
                ;;
            --help|-h)
                sed -n '2,/^$/s/^# //p' "$0"
                exit 0
                ;;
            *)
                echo "Error: Unknown option '$1'"
                echo "Run './ralph --help' for usage"
                exit 1
                ;;
        esac
    done
}

# detect_backend: determine active backend from env vars and settings files
# Priority: env var > settings.local.json > settings.json > ~/.claude/settings.json
detect_backend() {
    ACTIVE_BACKEND="anthropic"

    # 1. Check environment variable (highest priority)
    if [ -n "${CLAUDE_CODE_USE_BEDROCK}" ]; then
        if [ "${CLAUDE_CODE_USE_BEDROCK}" = "1" ]; then
            ACTIVE_BACKEND="bedrock"
        fi
    else
        # 2. Check ./.claude/settings.local.json for VALUE (not just file existence)
        if [ "$ACTIVE_BACKEND" = "anthropic" ] && [ -f "./.claude/settings.local.json" ]; then
            local BEDROCK_FLAG
            BEDROCK_FLAG=$(jq -r '.env.CLAUDE_CODE_USE_BEDROCK // ""' ./.claude/settings.local.json 2>/dev/null)
            if [ "$BEDROCK_FLAG" = "1" ]; then
                ACTIVE_BACKEND="bedrock"
            fi
        fi

        # 3. Check ./.claude/settings.json for VALUE (if backend not yet set)
        if [ "$ACTIVE_BACKEND" = "anthropic" ] && [ -f "./.claude/settings.json" ]; then
            local BEDROCK_FLAG
            BEDROCK_FLAG=$(jq -r '.env.CLAUDE_CODE_USE_BEDROCK // ""' ./.claude/settings.json 2>/dev/null)
            if [ "$BEDROCK_FLAG" = "1" ]; then
                ACTIVE_BACKEND="bedrock"
            fi
        fi

        # 4. Check ~/.claude/settings.json for VALUE (lowest priority)
        if [ "$ACTIVE_BACKEND" = "anthropic" ] && [ -f "$HOME/.claude/settings.json" ]; then
            local BEDROCK_FLAG
            BEDROCK_FLAG=$(jq -r '.env.CLAUDE_CODE_USE_BEDROCK // ""' ~/.claude/settings.json 2>/dev/null)
            if [ "$BEDROCK_FLAG" = "1" ]; then
                ACTIVE_BACKEND="bedrock"
            fi
        fi
    fi
}

# preflight: verify required directories and files exist
preflight() {
    if [ ! -d "./specs" ] || [ -z "$(ls -A ./specs 2>/dev/null)" ]; then
        echo "Error: No specs found. Run /ralph-spec first to generate specs in ./specs/"
        exit 1
    fi
}

# resolve_model: resolve model alias via models.json
# Uses MODEL_ALIAS and ACTIVE_BACKEND; sets RESOLVED_MODEL
resolve_model() {
    RESOLVED_MODEL=""
    if [ -n "$MODEL_ALIAS" ]; then
        RESOLVED_MODEL=$(jq -r --arg alias "$MODEL_ALIAS" --arg backend "$ACTIVE_BACKEND" \
            '.[$alias][$backend] // empty' "$SCRIPT_DIR/models.json")

        # Pass-through: if alias not found in models.json, use raw value as model ID
        if [ -z "$RESOLVED_MODEL" ]; then
            RESOLVED_MODEL="$MODEL_ALIAS"
        fi
    fi
}
