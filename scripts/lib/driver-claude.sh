#!/usr/bin/env bash
# driver-claude.sh — Claude Code CLI driver for scripts/sdd
# See specs/refactors/002-copilot-cli-agent-support/spec.md
#
# Exposes two entry points that scripts/sdd's run_agent seam dispatches to:
#   driver_claude_available          → 0 if the `claude` binary is on PATH
#   driver_claude_run_agent <agent> <mode> <model> <prompt>
#                                     → invokes `claude -p ...` for the given mode
#
# This file is sourced by scripts/sdd; it relies on $ROOT being set by the caller.

# Binary-presence check only (D6) — no auth/quota probing, no runtime fallback.
driver_claude_available() {
  command -v claude >/dev/null 2>&1
}

# Usage: driver_claude_run_agent <agent> <mode> <model> <prompt>
#   <agent> is unused by this driver (Claude dispatch happens by naming the
#   subagent inside <prompt>) but is threaded through so a future driver
#   (e.g. Copilot CLI's `--agent`) can use it without changing call sites.
#   <mode>: edit      → --permission-mode acceptEdits
#           full      → --permission-mode bypassPermissions
#           readonly  → --permission-mode dontAsk --allowedTools "Task,Read,Grep,Glob"
#             (also tees combined stdout/stderr into $RUN_AGENT_OUTPUT for
#              verdict parsing by the caller, e.g. cmd_verify)
driver_claude_run_agent() {
  local agent="$1" mode="$2" model="$3" prompt="$4"
  case "$mode" in
    edit)
      ( cd "$ROOT" && claude -p "$prompt" \
        --model "$model" \
        --permission-mode acceptEdits ) || true
      ;;
    full)
      ( cd "$ROOT" && claude -p "$prompt" \
        --model "$model" \
        --permission-mode bypassPermissions ) || true
      ;;
    readonly)
      RUN_AGENT_OUTPUT="$(mktemp)"
      ( cd "$ROOT" && claude -p "$prompt" \
        --model "$model" \
        --permission-mode dontAsk \
        --allowedTools "Task,Read,Grep,Glob" ) 2>&1 | tee "$RUN_AGENT_OUTPUT" || true
      ;;
    *)
      echo "driver-claude: unknown mode '$mode'" >&2
      return 1
      ;;
  esac
}
