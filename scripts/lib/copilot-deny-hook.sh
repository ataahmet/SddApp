#!/usr/bin/env bash
# copilot-deny-hook.sh — Copilot CLI preToolUse hook for the SDD deny list.
#
# `./scripts/sdd setup-user` registers this file as the preToolUse hook of the
# project's sddapp/copilot-plugin/ plugin, which every Copilot run scripts/sdd
# starts loads with --plugin-dir.
#
# Why a hook: Copilot CLI's --deny-tool knows shell(), write(), url() and MCP
# rules, but no read(path) kind (`copilot help permissions`). A deny-list file
# is therefore guarded here: before each tool call Copilot sends the call to
# this script as JSON on stdin; when the call's arguments name a file on the
# list, the script prints
#   {"permissionDecision":"deny","permissionDecisionReason":"..."}
# and Copilot refuses the call. Otherwise it prints nothing and Copilot's
# normal permission flow decides.
#
# Matching: every path-like token in the call's arguments is cut down to its
# last path component and compared, as a shell glob, with each one-word list
# entry (".env", "*.jks"). Multi-word entries are shell commands; scripts/sdd
# passes those to each run as --deny-tool 'shell(<command>:*)' flags instead.
# With jq, file contents being written (file_text, new_str, …) and the
# command's free-text description are skipped, so an edit that merely mentions
# ".env" is not refused; without jq the whole call is scanned, which can
# refuse more than needed but never less.
#
# Limits: a command that reaches a file without naming it (`grep -r x .`, a
# script that opens files itself) is not seen.
#
# The list is read on every call (sddapp/deny-list.txt; $SDD_DENY_LIST, set in
# the hook's env by setup-user), so edits apply immediately.
set -f   # entries and tokens contain '*': never expand them against the disk

list="${SDD_DENY_LIST:-$PWD/sddapp/deny-list.txt}"
if [ ! -f "$list" ]; then
  echo "sdd-deny hook: $list not found, nothing is denied; run ./scripts/sdd setup-user" >&2
  exit 0
fi

entries=()
while IFS= read -r line || [ -n "$line" ]; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  case "$line" in ""|"#"*|*" "*) continue ;; esac
  entries+=("$line")
done < "$list"
[ "${#entries[@]}" -gt 0 ] || exit 0

payload="$(cat)"
args=""
if command -v jq >/dev/null 2>&1; then
  args="$(printf '%s' "$payload" | jq -r --argjson skip \
    '["file_text","new_str","old_str","content","new_content","insert_text","description"]' '
      (.toolArgs // .tool_input // empty)
      | (if type == "string" then (try fromjson catch .) else . end) as $a
      | if ($a | type) == "string" then $a
        else [ $a | paths(type == "string") ]
             | map(select((.[-1] | tostring) as $k | ($skip | index($k)) == null))
             | .[] as $p | $a | getpath($p)
        end' 2>/dev/null)" || args="$payload"
fi
# No jq, or no arguments where they were expected: scan the whole call.
[ -n "$args" ] || args="$payload"

for tok in $(printf '%s' "$args" | tr -c 'A-Za-z0-9._/*~-' ' '); do
  name="${tok##*/}"
  [ -n "$name" ] || continue
  for entry in "${entries[@]}"; do
    # shellcheck disable=SC2254 # the entry is a glob on purpose
    case "$name" in
      $entry)
        # shellcheck disable=SC1003 # deletes '"' and '\' so the reason stays valid JSON
        reason="$(printf '%s' "$entry" | tr -d '"\\')"
        printf '{"permissionDecision":"deny","permissionDecisionReason":"Blocked by the SDD deny list (%s)"}\n' "$reason"
        exit 0
        ;;
    esac
  done
done
exit 0
