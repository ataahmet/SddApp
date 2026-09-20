#!/usr/bin/env bash
# critique.sh — ARIS-style critique-to-action loop for scripts/sdd
#
# Placement in the lifecycle (strictly AFTER align, strictly BEFORE verify):
#   new → ready → align → align-resolve → CRITIQUE (loop) → verify → start → implement → done
#
# The loop is the mechanism described in ARIS (arXiv:2605.03042, §2.2): an
# executor produces an artifact, a reviewer drawn from a DIFFERENT model family
# scores it under a fixed rubric and returns structured action items, the
# executor addresses them, and a convergence check decides whether to run
# another round. It terminates when the score clears a threshold (default 6/10)
# AND no critical items remain, or when the round cap (default 4) is hit.
#
# Mapping onto this repo:
#   artifact  = specs/**/spec.md (already aligned, answers filled by the user)
#   reviewer  = .claude/agents/sdd-critique.md   — read-only, independent
#   executor  = .claude/agents/sdd-refine.md     — edits the spec only
#   ledger    = <spec-dir>/critique/round-N.md + the spec's '## Critique Log'
#
# Cross-family separation is a MODEL-level concern here, not a backend-level
# one — exactly as in ARIS, where executor and reviewer both run under one CLI
# and the reviewer is routed to another family through a model bridge. So this
# file adds no backend machinery: both halves dispatch through the existing
# run_agent seam, and the families are decided by the critique/refine entries
# in model_default plus the SDD_MODEL_CRITIQUE / SDD_MODEL_REFINE overrides
# that scripts/sdd already resolves in model_for_role.
#
# This file is sourced by scripts/sdd. It relies on helpers defined there
# (fm_get/fm_set/fm_upsert, run_agent, resolve_agent_backend, model_for_role,
# require_alignment_resolved, today). Functions resolve at call time, so the
# source order at the top of scripts/sdd is fine.

###############################################################################
# Tunables (all optional; defaults mirror the ARIS paper)
###############################################################################
# SDD_CRITIQUE_ROUNDS     — max rounds before giving up            (default 4)
# SDD_CRITIQUE_THRESHOLD  — score needed to converge, out of 10    (default 6)
# SDD_CRITIQUE_CONTEXT    — fresh | cross-round                    (default fresh)
#     fresh       → every round opens a reviewer with no memory of earlier
#                   rounds (ARIS reviewer-bias guard).
#     cross-round → the reviewer is handed the previous round reports and is
#                   asked to confirm whether its earlier items were addressed.
# SDD_CRITIQUE_SCOPE      — spec-only | repo                       (default spec-only)
#     spec-only   → the reviewer reads the spec and CLAUDE.md.
#     repo        → the reviewer may also read the surrounding codebase to
#                   check the spec's contracts against what actually exists.
# SDD_MODEL_CRITIQUE      — reviewer model. Set this to a model from a family
#                           OTHER than the executor's to get the cross-family
#                           review ARIS recommends; the loop warns when both
#                           halves resolve to the same family.
# SDD_MODEL_REFINE        — executor (refine) model.

CRITIQUE_ROUNDS_DEFAULT=4
CRITIQUE_THRESHOLD_DEFAULT=6

###############################################################################
# Cross-family check (ARIS design principle 1: heterogeneous models)
###############################################################################

# Classifies a model string into a coarse provider family. Returns "unknown"
# for anything unrecognised — including copilot's "auto", where the CLI picks
# the model and this script has nothing to compare.
critique_model_family() { # <model>
  case "$1" in
    opus*|sonnet*|haiku*|claude*)     echo "claude" ;;
    gpt*|o1*|o3*|o4*|codex*|oracle*)  echo "gpt" ;;
    gemini*)                          echo "gemini" ;;
    *)                                echo "unknown" ;;
  esac
}

# Warns — never fails — when reviewer and executor land in the same family.
# ARIS treats cross-family pairing as the recommended configuration, not a hard
# system constraint, and so does this.
critique_warn_same_family() { # <reviewer-model> <executor-model>
  local rf ef
  rf="$(critique_model_family "$1")"
  ef="$(critique_model_family "$2")"
  [ "$rf" = "unknown" ] && return 0
  [ "$ef" = "unknown" ] && return 0
  [ "$rf" != "$ef" ] && return 0
  echo "  ⚠ reviewer and executor are both '$rf' models — correlated blind spots are more likely." >&2
  echo "    ARIS's recommended configuration pairs different families. Set e.g.:" >&2
  echo "      SDD_MODEL_CRITIQUE=<a model from another family> ./scripts/sdd critique <spec>" >&2
}

###############################################################################
# Critique Log section / ledger helpers
###############################################################################

# Appends the '## Critique Log' section + table header when either is missing.
# Mirrors cmd_align's treatment of '## Open Decisions (Alignment)': specs
# written before this feature existed keep working without being migrated.
critique_log_ensure() { # <spec>
  local spec="$1"
  if ! grep -qiE "^#{1,6}[[:space:]].*Critique Log" "$spec"; then
    printf '\n## Critique Log\n<!-- `./scripts/sdd critique` appends one row per round. Reports: ./critique/round-N.md -->\n\n| Round | Score | Critical | Major | Verdict | Report |\n|-------|-------|----------|-------|---------|--------|\n' >> "$spec"
    return 0
  fi
  # Section exists but the table was removed by hand → put the header back.
  if ! awk '
      /^#{1,6}[[:space:]].*[Cc]ritique [Ll]og/ { insec=1; next }
      insec && /^#{1,6}[[:space:]]/ { insec=0 }
      insec && /^\|[[:space:]]*:?-+/ { found=1 }
      END { exit(found?0:1) }
    ' "$spec"; then
    printf '\n| Round | Score | Critical | Major | Verdict | Report |\n|-------|-------|----------|-------|---------|--------|\n' >> "$spec"
  fi
}

# Appends one row to the end of the Critique Log table (chronological order).
critique_log_append() { # <spec> <round> <score> <critical> <major> <verdict> <report-rel>
  local spec="$1" row
  row="| $2 | $3/10 | $4 | $5 | $6 | \`$7\` |"
  awk -v row="$row" '
    BEGIN { insec=0; sep=0; done=0 }
    {
      if ($0 ~ /^#{1,6}[[:space:]].*[Cc]ritique [Ll]og/) { insec=1; sep=0; print; next }
      if (insec && !done) {
        if ($0 ~ /^\|[[:space:]]*:?-+/) { sep=1; print; next }
        if (sep && $0 ~ /^\|/) { print; next }
        if (sep) { print row; done=1; insec=0; print; next }
        print; next
      }
      print
    }
    END { if (insec && !done && sep) print row }
  ' "$spec" > "$spec.tmp" && mv "$spec.tmp" "$spec"
}

###############################################################################
# Reviewer verdict parsing
###############################################################################
# The reviewer's first lines are machine-readable (see .claude/agents/
# sdd-critique.md). Same contract style as cmd_verify's 'VERIFY: PASS' line:
#   CRITIQUE: SCORE=7/10
#   CRITIQUE: CRITICAL=0
#   CRITIQUE: MAJOR=2
#   CRITIQUE: NEEDS_USER=0
#   CRITIQUE: VERDICT=CONVERGED|REVISE|NEEDS_USER

critique_field() { # <output-file> <field>
  local v
  v="$(grep -oE "CRITIQUE:[[:space:]]*$2=[A-Za-z0-9_/]+" "$1" | head -1 | sed -E "s|.*$2=||")"
  printf '%s' "$v"
}

critique_score() { # <output-file>  → integer 0-10, empty when unparseable
  local v
  v="$(critique_field "$1" SCORE)"
  printf '%s' "${v%%/*}"
}

###############################################################################
# The loop
###############################################################################

# Mandatory gate helper, mirroring require_alignment_resolved /
# require_verify_passed. Backwards compatible on purpose: a spec with no
# 'critique:' field (or '~') predates this feature and is NOT blocked.
require_critique_converged() { # <spec>
  local spec="$1" flag
  flag="$(fm_get "$spec" critique)"
  [ -z "$flag" ] && return 0
  [ "$flag" = "~" ] && return 0
  [ "$flag" = "skipped" ] && return 0
  case "$flag" in
    converged) return 0 ;;
    needs_user)
      echo "✗ critique is 'needs_user' — the reviewer raised items only you can decide."
      echo "  Read the last report under $(dirname "$spec")/critique/, update the spec, then re-run:"
      echo "    ./scripts/sdd critique $spec"
      return 1
      ;;
    max_rounds)
      echo "✗ critique hit the round cap without converging (critique_score: $(fm_get "$spec" critique_score)/10)."
      echo "  Either address the remaining items by hand and re-run 'sdd critique',"
      echo "  or record the reason under '## Deviations from CLAUDE.md' and set 'critique: skipped'."
      return 1
      ;;
    *)
      echo "✗ critique is '$flag' — the critique-to-action loop has not converged."
      echo "  Run: ./scripts/sdd critique $spec"
      return 1
      ;;
  esac
}

cmd_critique() {
  local spec="" rounds="" threshold=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --rounds)    rounds="$2"; shift 2 ;;
      --threshold) threshold="$2"; shift 2 ;;
      --rounds=*)    rounds="${1#*=}"; shift ;;
      --threshold=*) threshold="${1#*=}"; shift ;;
      -*) echo "Unknown option: $1"; exit 1 ;;
      *)  spec="$1"; shift ;;
    esac
  done

  [ -n "$spec" ] || { echo "Usage: sdd critique <spec.md> [--rounds N] [--threshold N]"; exit 1; }
  [ -f "$spec" ] || { echo "Spec not found: $spec"; exit 1; }

  rounds="${rounds:-${SDD_CRITIQUE_ROUNDS:-$CRITIQUE_ROUNDS_DEFAULT}}"
  threshold="${threshold:-${SDD_CRITIQUE_THRESHOLD:-$CRITIQUE_THRESHOLD_DEFAULT}}"
  case "$rounds" in ''|*[!0-9]*) echo "✗ --rounds must be a positive integer (got '$rounds')."; exit 1 ;; esac
  case "$threshold" in ''|*[!0-9]*) echo "✗ --threshold must be an integer 0-10 (got '$threshold')."; exit 1 ;; esac
  [ "$rounds" -ge 1 ] || { echo "✗ --rounds must be >= 1."; exit 1; }
  [ "$threshold" -le 10 ] || { echo "✗ --threshold must be <= 10."; exit 1; }

  local context="${SDD_CRITIQUE_CONTEXT:-fresh}"
  case "$context" in fresh|cross-round) ;; *) echo "✗ SDD_CRITIQUE_CONTEXT must be fresh|cross-round (got '$context')."; exit 1 ;; esac
  local scope="${SDD_CRITIQUE_SCOPE:-spec-only}"
  case "$scope" in spec-only|repo) ;; *) echo "✗ SDD_CRITIQUE_SCOPE must be spec-only|repo (got '$scope')."; exit 1 ;; esac

  # Ordering gate: critique reviews an ALIGNED artifact. Running it before the
  # user has answered the open decisions would make the reviewer grade
  # placeholders, and would tempt the refine agent into inventing answers.
  require_alignment_resolved "$spec" || {
    echo "  'sdd critique' runs after alignment is resolved."
    exit 1
  }

  # Resolve the backend BEFORE touching the spec (same no-op contract as
  # cmd_align, D6): if no CLI is available the file must stay byte-identical.
  # The value is used only to report which models the two roles resolve to —
  # dispatch itself goes through run_agent, which resolves the backend again.
  local backend review_model exec_model
  backend="$(resolve_agent_backend)" || exit 1
  review_model="$(model_for_role critique "$backend")" || exit 1
  exec_model="$(model_for_role refine "$backend")" || exit 1

  local spec_dir report_dir
  spec_dir="$(cd "$(dirname "$spec")" && pwd)"
  report_dir="$spec_dir/critique"
  mkdir -p "$report_dir"

  critique_log_ensure "$spec"
  fm_upsert "$spec" critique "pending"
  fm_upsert "$spec" critique_score "~"
  fm_upsert "$spec" critique_rounds "0"
  # The loop rewrites the spec → any earlier verify pass is stale by definition.
  fm_upsert "$spec" verify "pending"
  fm_set "$spec" updated "$(today)"

  echo "→ Critique-to-action loop  ($backend)"
  echo "    reviewer : $review_model   ($(critique_model_family "$review_model"))"
  echo "    executor : $exec_model   ($(critique_model_family "$exec_model"))"
  echo "    rounds   : max $rounds        threshold: >= $threshold/10 and 0 critical"
  echo "    context  : $context           scope: $scope"
  critique_warn_same_family "$review_model" "$exec_model"
  echo

  local round=1 score="" critical="" major="" needs_user="" verdict="" outcome="max_rounds" last_score=0
  while [ "$round" -le "$rounds" ]; do
    echo "════════════════ round $round / $rounds ════════════════"

    ###########################################################################
    # Step 1-2 — reviewer critiques the artifact, independently.
    ###########################################################################
    # ARIS reviewer independence: the executor hands over a PATH and a review
    # objective, never a summary. Summarising first would have the reviewer
    # grade the executor's framing instead of the artifact itself.
    local prior_block=""
    if [ "$context" = "cross-round" ] && [ "$round" -gt 1 ]; then
      prior_block="
This is a CROSS-ROUND review. Your own earlier reports for this spec are at:
$(ls -1 "$report_dir"/round-*.md 2>/dev/null | sed 's|^|  |')
Read them and state explicitly, per earlier item, whether it is now resolved."
    fi

    local scope_block="Read the spec and judge it against CLAUDE.md only."
    if [ "$scope" = "repo" ]; then
      scope_block="Read the spec, CLAUDE.md, AND the surrounding codebase. Check the spec's
contracts (class names, Hilt scopes, existing UseCase/Repository shapes) against what the
repository actually contains, and report drift as an action item."
    fi

    local review_prompt="Use the sdd-critique subagent to review spec: $spec
$scope_block$prior_block

Then relay the subagent's machine-readable header verbatim as YOUR first lines of output —
the five 'CRITIQUE:' lines, nothing before them, no preamble and no heading. Put the rest of
the report after them. These lines are parsed by a script; omitting them fails the run."

    local review_out
    if ! run_agent "sdd-critique" "readonly" "critique" "$review_prompt"; then
      rm -f "${RUN_AGENT_OUTPUT:-}"
      echo
      echo "✗ Critique could not run — the reviewer CLI failed before producing output" \
           "(rejected flag, unavailable model, crashed, missing auth, ...). Front matter left" \
           "at 'pending'; fix the CLI or SDD_MODEL_CRITIQUE and re-run 'sdd critique'." >&2
      fm_upsert "$spec" critique "failed"
      exit 1
    fi
    review_out="$RUN_AGENT_OUTPUT"

    score="$(critique_score "$review_out")"
    critical="$(critique_field "$review_out" CRITICAL)"
    major="$(critique_field "$review_out" MAJOR)"
    needs_user="$(critique_field "$review_out" NEEDS_USER)"
    verdict="$(critique_field "$review_out" VERDICT)"

    # An unparseable verdict is treated as a failed round, never as a pass —
    # same stance cmd_verify takes on a missing VERIFY line.
    if [ -z "$score" ] || [ -z "$verdict" ]; then
      echo
      echo "✗ Round $round produced no parseable 'CRITIQUE:' header — treated as non-convergent."
      score="${score:-0}"; critical="${critical:-1}"; major="${major:-0}"
      needs_user="${needs_user:-0}"; verdict="${verdict:-REVISE}"
    fi
    critical="${critical:-0}"; major="${major:-0}"; needs_user="${needs_user:-0}"
    last_score="$score"

    local report="$report_dir/round-$round.md"
    {
      echo "<!-- generated by ./scripts/sdd critique — round $round — $(today) -->"
      echo "<!-- reviewer model: $review_model | context: $context | scope: $scope -->"
      echo
      cat "$review_out"
    } > "$report"
    rm -f "$review_out"

    critique_log_append "$spec" "$round" "$score" "$critical" "$major" "$verdict" \
      "critique/round-$round.md"
    fm_upsert "$spec" critique_rounds "$round"
    fm_upsert "$spec" critique_score "$score"
    fm_set "$spec" updated "$(today)"

    echo
    echo "  score=$score/10  critical=$critical  major=$major  verdict=$verdict"
    echo "  report → ${report#$ROOT/}"

    ###########################################################################
    # Step 5 — convergence check (runs BEFORE any revision, as in ARIS).
    ###########################################################################
    if [ "$needs_user" -gt 0 ] || [ "$verdict" = "NEEDS_USER" ]; then
      # Hard stop. The refine agent must never invent an answer to a decision
      # the user owns — that is the whole point of the align/align-resolve
      # split this repo already enforces.
      outcome="needs_user"
      echo
      echo "⏸  The reviewer raised $needs_user item(s) that require YOUR decision."
      break
    fi

    if [ "$score" -ge "$threshold" ] && [ "$critical" -eq 0 ]; then
      outcome="converged"
      echo
      echo "✓ Converged: score $score/10 >= $threshold and no critical items left."
      break
    fi

    if [ "$round" -eq "$rounds" ]; then
      outcome="max_rounds"
      echo
      echo "✗ Round cap reached without convergence (last score $score/10, $critical critical)."
      break
    fi

    ###########################################################################
    # Step 3-4 — executor addresses the action items.
    ###########################################################################
    echo
    echo "→ Applying action items with sdd-refine ($exec_model) ..."
    run_agent "sdd-refine" "edit" "refine" \
      "Use the sdd-refine subagent to apply the reviewer's action items.

## Spec
$spec

## Reviewer report (round $round)
$report

Apply every CRITICAL and MAJOR item to the spec. Do NOT answer any '**Answer:**' line in
'## Open Decisions (Alignment)' yourself — if an item needs a decision the user owns, leave it
and say so in your report. Touch the spec only; write no production code."

    fm_set "$spec" updated "$(today)"
    round=$((round + 1))
  done

  echo "════════════════════════════════════════"
  fm_upsert "$spec" critique "$outcome"
  fm_upsert "$spec" critique_score "$last_score"
  fm_set "$spec" updated "$(today)"

  case "$outcome" in
    converged)
      echo "✓ critique: converged  (score $last_score/10 after $round round(s))"
      echo "  The spec changed during the loop → verify was reset to 'pending'."
      echo "  Next: ./scripts/sdd verify $spec"
      return 0
      ;;
    needs_user)
      echo "✗ critique: needs_user  (score $last_score/10)"
      echo "  Read: ${report_dir#$ROOT/}/round-$round.md"
      echo "  Answer the flagged decisions in the spec, then re-run:"
      echo "    ./scripts/sdd critique $spec"
      exit 1
      ;;
    *)
      echo "✗ critique: max_rounds  (best score $last_score/10, threshold $threshold)"
      echo "  Read: ${report_dir#$ROOT/}/round-$rounds.md"
      echo "  Fix the remaining items by hand and re-run 'sdd critique', or — if the"
      echo "  reviewer is wrong — justify it under '## Deviations from CLAUDE.md' and set"
      echo "  'critique: skipped' in the front matter to release the gate deliberately."
      exit 1
      ;;
  esac
}
