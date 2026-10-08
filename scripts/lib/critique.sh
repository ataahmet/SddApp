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
#   ledger    = <spec-dir>/critique/round-N.md         (reviewer report)
#               <spec-dir>/critique/round-N-verify.md  (in-loop verify gate, when it runs)
#               <spec-dir>/critique/round-N-refine.md  (executor report)
#               + one row per step in the spec's '## Critique Log'
#
# Stop conditions besides convergence and the round cap — all three end in
# 'critique: needs_user', because each means the loop can no longer make
# progress without the user:
#   - the reviewer reports NEEDS_USER>0;
#   - the executor reports REFINE: USER_OWNED>0 — an item whose fix can only
#     live in an '**Answer:**' line or the front matter, which the executor may
#     not touch (the reviewer sometimes tags these MAJOR/MINOR instead);
#   - a stall: a CRITICAL/MAJOR item at the same location comes back after the
#     executor's turn while the score does not improve, or survives three
#     consecutive rounds.
#
# The Critique Log records the SCRIPT's verdict, re-derived from the reviewer's
# counts, not the verdict line the reviewer printed; a mismatch is warned about.
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
# SDD_CRITIQUE_VERIFY     — 1 | 0                                  (default 1)
#     1 → once the reviewer is satisfied, the REAL 'sdd verify' gate runs as
#         the final arbiter of the round. Its FAIL report becomes the next
#         round's action items. The loop exits only on VERIFY: PASS.
#     0 → the reviewer's own rubric is the only exit condition (faster, but
#         'sdd verify' can then still FAIL on a converged spec: its bar is
#         zero-tolerance while the rubric's is a score).
# SDD_MODEL_CRITIQUE      — reviewer model. Set this to a model from a family
#                           OTHER than the executor's to get the cross-family
#                           review ARIS recommends; the loop warns when both
#                           halves resolve to the same family.
# SDD_MODEL_REFINE        — executor (refine) model.
# SDD_MODEL_VERIFY        — model for the in-loop verify gate (same variable
#                           'sdd verify' already uses).

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

# Moves an earlier run's reports out of the way before a new run starts.
# Every run numbers its rounds from 1, so without this a re-run overwrites
# round-N.md files that older Critique Log rows still point at, and leaves the
# higher-numbered files of a longer earlier run lying around (where the
# cross-round reviewer would read them as its own). The old rows are repointed
# at the archive and a separator row marks where the new run begins.
critique_archive_previous_run() { # <spec> <report-dir>
  local spec="$1" report_dir="$2" stamp archive rel f moved=0
  CRITIQUE_ARCHIVED=""
  for f in "$report_dir"/round-*.md; do
    [ -e "$f" ] && { moved=1; break; }
  done
  [ "$moved" -eq 1 ] || return 0

  stamp="$(date +%Y%m%d-%H%M%S)"
  archive="$report_dir/run-$stamp"
  rel="critique/run-$stamp"
  mkdir -p "$archive"
  mv "$report_dir"/round-*.md "$archive"/

  awk -v from='`critique/round-' -v to="\`$rel/round-" '
    /^#{1,6}[[:space:]].*[Cc]ritique [Ll]og/ { insec=1; print; next }
    insec && /^#{1,6}[[:space:]]/ { insec=0 }
    insec && /^\|/ {
      while ((i = index($0, from)) > 0) {
        $0 = substr($0, 1, i - 1) to substr($0, i + length(from))
      }
    }
    { print }
  ' "$spec" > "$spec.tmp" && mv "$spec.tmp" "$spec"

  critique_log_append "$spec" "new run" "-" "-" "-" "earlier reports archived" "$rel/"
  CRITIQUE_ARCHIVED="$rel/"
}

# Appends one row to the end of the Critique Log table (chronological order).
# <score> is an integer (rendered as N/10) or any other text, rendered as-is
# (e.g. "-" for an executor row that has no score).
critique_log_append() { # <spec> <round> <score> <critical> <major> <verdict> <report-rel>
  local spec="$1" row score_cell
  case "$3" in
    ''|*[!0-9]*) score_cell="$3" ;;
    *)           score_cell="$3/10" ;;
  esac
  row="| $2 | $score_cell | $4 | $5 | $6 | \`$7\` |"
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

# Verdict derived from the counts alone — the rule the loop actually applies.
# The reviewer prints its own VERDICT line too; this is what gets recorded.
critique_derive_verdict() { # <score> <critical> <major> <needs_user> <reviewer-verdict> <threshold>
  if [ "$4" -gt 0 ] || [ "$5" = "NEEDS_USER" ]; then
    echo "NEEDS_USER"
  elif [ "$1" -ge "$6" ] && [ "$2" -eq 0 ] && [ "$3" -eq 0 ]; then
    echo "CONVERGED"
  else
    echo "REVISE"
  fi
}

###############################################################################
# Executor report parsing
###############################################################################
# sdd-refine's first lines are machine-readable (see .claude/agents/
# sdd-refine.md):
#   REFINE: APPLIED=3
#   REFINE: USER_OWNED=1
#   REFINE: UNRESOLVED=0

refine_field() { # <output-file> <field>  → integer, empty when missing
  local v
  v="$(grep -oE "REFINE:[[:space:]]*$2=[0-9]+" "$1" | head -1 | sed -E "s|.*$2=||")"
  printf '%s' "$v"
}

###############################################################################
# Stall detection
###############################################################################
# The bold location of every CRITICAL/MAJOR action item, one per line, sorted.
#   - [MAJOR] **§9 Q3** → ...   →   §9 Q3
critique_blocking_keys() { # <report-file>
  sed -nE 's/^[[:space:]]*[-*][[:space:]]*\[(CRITICAL|MAJOR)\][[:space:]]*\*\*([^*]+)\*\*.*/\2/p' "$1" \
    | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' \
    | LC_ALL=C sort -u
}

# Lines present in both sorted key lists.
critique_keys_common() { # <keys-a> <keys-b>
  [ -n "$1" ] && [ -n "$2" ] || return 0
  LC_ALL=C comm -12 <(printf '%s\n' "$1") <(printf '%s\n' "$2")
}

###############################################################################
# In-loop verify gate
###############################################################################
# The reviewer's rubric and 'sdd verify' do not measure the same thing: the
# rubric is a score with a tolerance, verify is zero-tolerance. A spec can
# therefore satisfy the reviewer and still FAIL verify — on findings no round
# ever reported, because the reviewer was never asked about them.
#
# So once the reviewer is satisfied, the real verify agent runs as the round's
# final arbiter. ARIS does the same thing with experiments: the reviewer does
# not predict results, the actual run happens inside the loop and its output
# feeds the next revision.
#
# Writes the agent's raw output to <out-path>. Returns:
#   0 → VERIFY: PASS
#   1 → VERIFY: FAIL
#   2 → infrastructure failure: the CLI never produced usable output
#   3 → the run completed twice without any 'VERIFY:' line. Unlike standalone
#       'sdd verify', this is NOT folded into FAIL: a report with no verdict
#       has no findings either, so feeding it to the executor would only burn
#       a round. `claude -p` returns the wrapper session's reply, which can
#       summarise the verdict line away — one re-run usually recovers it.
critique_run_verify_gate() { # <spec> <out-path>
  local spec="$1" out="$2" attempt
  for attempt in 1 2; do
    RUN_AGENT_OUTPUT=""
    if ! run_agent "sdd-verify" "readonly" "verify" "$(verify_prompt "$spec" loop)"; then
      rm -f "${RUN_AGENT_OUTPUT:-}"
      return 2
    fi
    mv "$RUN_AGENT_OUTPUT" "$out"
    if grep -qE 'VERIFY:[[:space:]]*PASS' "$out"; then
      return 0
    fi
    if grep -qE 'VERIFY:[[:space:]]*FAIL' "$out"; then
      return 1
    fi
    if [ "$attempt" -eq 1 ]; then
      echo "  ⚠ verify completed without a 'VERIFY:' line — re-running it once ..." >&2
    fi
  done
  return 3
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
      echo "✗ critique is 'needs_user' — the loop stopped on items only you can change or decide."
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
  critique_archive_previous_run "$spec" "$report_dir"
  fm_upsert "$spec" critique "pending"
  fm_upsert "$spec" critique_score "~"
  fm_upsert "$spec" critique_rounds "0"
  # The loop rewrites the spec → any earlier verify pass is stale by definition.
  fm_upsert "$spec" verify "pending"
  fm_set "$spec" updated "$(today)"

  echo "→ Critique-to-action loop  ($backend)"
  echo "    reviewer : $review_model   ($(critique_model_family "$review_model"))"
  echo "    executor : $exec_model   ($(critique_model_family "$exec_model"))"
  echo "    rounds   : max $rounds        threshold: >= $threshold/10, 0 critical, 0 major"
  echo "    context  : $context           scope: $scope"
  echo "    exit gate: reviewer rubric$([ "${SDD_CRITIQUE_VERIFY:-1}" = "1" ] && echo " + sdd-verify PASS" || echo " only (SDD_CRITIQUE_VERIFY=0)")"
  [ -n "${CRITIQUE_ARCHIVED:-}" ] && echo "    archive  : earlier run's reports → $CRITIQUE_ARCHIVED"
  critique_warn_same_family "$review_model" "$exec_model"
  echo

  local round=1 score="" critical="" major="" needs_user="" verdict="" outcome="max_rounds" last_score=0
  local verify_passed=0 base_verdict="" script_verdict="" stop_reason="" stop_report=""
  local keys="" prev_keys="" prev2_keys="" prev_score="" stall_items="" repeated=""
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
This is a CROSS-ROUND review. Earlier reports for this spec (yours as round-N.md, the
executor's as round-N-refine.md, the verify gate's as round-N-verify.md) are at:
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

Convergence bar for this run: SCORE >= $threshold/10 with CRITICAL=0 and MAJOR=0.
The executor cannot edit '**Answer:**' lines or the front matter: any item whose fix lives
there is NEEDS_USER, never CRITICAL, MAJOR or MINOR.
Review the spec's CONTENT only: the script-owned front-matter fields (status, alignment,
verify, critique*, updated, ...) and the '## Critique Log' are mid-update while you run and
are never an action item or a reason to lower the score.

Then relay the subagent's machine-readable header verbatim as YOUR first lines of output —
the five 'CRITIQUE:' lines, nothing before them, no preamble and no heading. Put the rest of
the report after them. These lines are parsed by a script; omitting them fails the run."

    local review_out
    RUN_AGENT_OUTPUT=""
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

    ###########################################################################
    # Verdict — re-derived from the counts; the reviewer's own line is advisory.
    ###########################################################################
    base_verdict="$(critique_derive_verdict "$score" "$critical" "$major" "$needs_user" "$verdict" "$threshold")"
    if [ "$verdict" != "$base_verdict" ]; then
      echo "  ⚠ reviewer printed VERDICT=$verdict, but its own counts give $base_verdict — recording $base_verdict." >&2
    fi

    ###########################################################################
    # Stall check — a blocking item the executor already had a turn at.
    ###########################################################################
    keys="$(critique_blocking_keys "$report")"
    stall_items=""
    if [ "$base_verdict" = "REVISE" ] && [ "$round" -gt 1 ]; then
      repeated="$(critique_keys_common "$keys" "$prev_keys")"
      if [ -n "$repeated" ] && [ -n "$prev_score" ] && [ "$score" -le "$prev_score" ]; then
        stall_items="$repeated"
      elif [ -n "$repeated" ] && [ "$round" -gt 2 ]; then
        stall_items="$(critique_keys_common "$repeated" "$prev2_keys")"
      fi
    fi
    script_verdict="$base_verdict"
    [ -n "$stall_items" ] && script_verdict="STALLED"

    critique_log_append "$spec" "$round" "$score" "$critical" "$major" "$script_verdict" \
      "critique/round-$round.md"
    fm_upsert "$spec" critique_rounds "$round"
    fm_upsert "$spec" critique_score "$score"
    fm_set "$spec" updated "$(today)"

    echo
    echo "  score=$score/10  critical=$critical  major=$major  verdict=$script_verdict"
    echo "  report → ${report#$ROOT/}"

    ###########################################################################
    # Step 5 — convergence check (runs BEFORE any revision, as in ARIS).
    ###########################################################################
    if [ "$script_verdict" = "NEEDS_USER" ]; then
      # Hard stop. The refine agent must never invent an answer to a decision
      # the user owns — that is the whole point of the align/align-resolve
      # split this repo already enforces.
      outcome="needs_user"; stop_reason="reviewer"; stop_report="$report"
      echo
      echo "⏸  The reviewer raised $needs_user item(s) that require YOUR decision."
      break
    fi

    if [ "$script_verdict" = "STALLED" ]; then
      # Another round would only re-raise the same items: whatever the executor
      # did last turn did not move them, usually because their fix lives in an
      # answer line or the front matter and the reviewer tagged them MAJOR.
      outcome="needs_user"; stop_reason="stalled"; stop_report="$report"
      echo
      echo "⏸  Stalled — these blocking item(s) came back after the executor's turn:"
      printf '%s\n' "$stall_items" | sed 's/^/     · /'
      echo "   Another round would re-raise them; they need your edit or your decision."
      break
    fi

    # MAJOR=0 is part of the bar on purpose. Converging with MAJOR items open
    # used to leave them unapplied: the loop breaks on convergence, so refine
    # never ran on the satisfied round and those items stayed in the report
    # instead of the spec — where 'sdd verify' then found them.
    local gate_report="$report" gate_kind="critique"
    if [ "$script_verdict" = "CONVERGED" ]; then
      if [ "${SDD_CRITIQUE_VERIFY:-1}" != "1" ]; then
        outcome="converged"
        echo
        echo "✓ Converged: score $score/10 >= $threshold, no critical or major items left."
        echo "  (in-loop verify disabled via SDD_CRITIQUE_VERIFY=0 — run 'sdd verify' yourself)"
        break
      fi

      #########################################################################
      # Final arbiter: the real verify gate, on the real spec.
      #########################################################################
      echo
      echo "→ Reviewer satisfied — running the verify gate as final arbiter ..."
      local vout="$report_dir/round-$round-verify.md"
      local vrc=0
      critique_run_verify_gate "$spec" "$vout" || vrc=$?

      if [ "$vrc" -eq 2 ]; then
        echo
        echo "✗ The verify gate could not run (CLI failed before producing output)." \
             "Wrote 'critique: failed'; fix the CLI and re-run 'sdd critique'." >&2
        fm_upsert "$spec" critique "failed"
        exit 1
      fi

      if [ "$vrc" -eq 3 ]; then
        critique_log_append "$spec" "$round v" "-" "-" "-" "VERIFY:NONE" \
          "critique/round-$round-verify.md"
        echo
        echo "✗ The verify gate ran twice without printing a 'VERIFY:' line — its verdict is" \
             "unknown, which is not the same as FAIL. Read ${vout#$ROOT/} and re-run" \
             "'sdd critique'." >&2
        fm_upsert "$spec" critique "failed"
        exit 1
      fi

      if [ "$vrc" -eq 0 ]; then
        critique_log_append "$spec" "$round v" "-" "-" "-" "VERIFY:PASS" \
          "critique/round-$round-verify.md"
        outcome="converged"
        verify_passed=1
        echo "  ✓ VERIFY: PASS"
        echo
        echo "✓ Converged: score $score/10, no critical/major items, and verify passed."
        break
      fi

      # Verify FAILed on a spec the reviewer was happy with — exactly the case
      # that used to slip through. Its findings become this round's action
      # items, so the next round fixes them instead of the user discovering
      # them after the loop has already declared success.
      critique_log_append "$spec" "$round v" "-" "-" "-" "VERIFY:FAIL" \
        "critique/round-$round-verify.md"
      gate_report="$vout"
      gate_kind="verify"
      echo "  ✗ VERIFY: FAIL — feeding its findings back into the loop."
    fi

    if [ "$round" -eq "$rounds" ]; then
      outcome="max_rounds"
      echo
      if [ "$gate_kind" = "verify" ]; then
        echo "✗ Round cap reached: the reviewer was satisfied but verify still FAILs."
      else
        echo "✗ Round cap reached without convergence (last score $score/10, $critical critical, $major major)."
      fi
      break
    fi

    # Remembered for the next round's stall check. Only reviewer rounds carry
    # blocking keys; after a verify FAIL they are empty, so no stall is claimed.
    prev2_keys="$prev_keys"; prev_keys="$keys"; prev_score="$score"

    ###########################################################################
    # Step 3-4 — executor addresses the action items.
    ###########################################################################
    local refine_contract="
Start your output with the three 'REFINE:' header lines defined in your agent file. An item
whose fix is an '**Answer:**' line or a front-matter field is USER_OWNED whatever its severity:
skip it, count it, and list it with the recommended replacement under '## User-owned'."
    local refine_prompt
    echo
    if [ "$gate_kind" = "verify" ]; then
      echo "→ Applying verify findings with sdd-refine ($exec_model) ..."
      refine_prompt="Use the sdd-refine subagent to resolve a FAILED verify gate.

## Spec
$spec

## Verify report (round $round)
$gate_report

The spec satisfied the review rubric but 'sdd verify' still FAILED. Treat every contradiction,
ambiguity and open question the report names as a CRITICAL item and resolve it in the spec. Do
NOT answer or rewrite any '**Answer:**' line in '## Open Decisions (Alignment)' yourself — if
the report names a decision the user owns, count it as USER_OWNED. Touch the spec only; write
no production code.
$refine_contract"
    else
      echo "→ Applying action items with sdd-refine ($exec_model) ..."
      refine_prompt="Use the sdd-refine subagent to apply the reviewer's action items.

## Spec
$spec

## Reviewer report (round $round)
$gate_report

Apply every CRITICAL and MAJOR item to the spec. Do NOT answer or rewrite any '**Answer:**'
line in '## Open Decisions (Alignment)' yourself — if an item needs a decision the user owns,
count it as USER_OWNED. Touch the spec only; write no production code.
$refine_contract"
    fi

    # Capture the executor's report (drivers tee edit-mode output into
    # $RUN_AGENT_OUTPUT when RUN_AGENT_CAPTURE=1) so it lands in the ledger
    # instead of scrolling away in the terminal.
    RUN_AGENT_OUTPUT=""
    RUN_AGENT_CAPTURE=1
    run_agent "sdd-refine" "edit" "refine" "$refine_prompt"
    RUN_AGENT_CAPTURE=0

    local refine_report="$report_dir/round-$round-refine.md"
    {
      echo "<!-- generated by ./scripts/sdd critique — round $round refine — $(today) -->"
      echo "<!-- executor model: $exec_model | input: ${gate_report#$ROOT/} -->"
      echo
      if [ -n "${RUN_AGENT_OUTPUT:-}" ] && [ -f "$RUN_AGENT_OUTPUT" ]; then
        cat "$RUN_AGENT_OUTPUT"
      else
        echo "(no executor output was captured)"
      fi
    } > "$refine_report"
    rm -f "${RUN_AGENT_OUTPUT:-}"

    local applied user_owned unresolved
    applied="$(refine_field "$refine_report" APPLIED)"
    user_owned="$(refine_field "$refine_report" USER_OWNED)"
    unresolved="$(refine_field "$refine_report" UNRESOLVED)"
    if [ -z "$user_owned" ]; then
      echo "  ⚠ sdd-refine printed no 'REFINE:' header — treating it as USER_OWNED=0;" \
           "the stall check still applies next round." >&2
    fi
    critique_log_append "$spec" "$round r" "-" "-" "-" \
      "APPLIED=${applied:-?} USER_OWNED=${user_owned:-?} UNRESOLVED=${unresolved:-?}" \
      "critique/round-$round-refine.md"
    echo "  applied=${applied:-?}  user_owned=${user_owned:-?}  unresolved=${unresolved:-?}"
    echo "  report → ${refine_report#$ROOT/}"

    if [ "${user_owned:-0}" -gt 0 ]; then
      outcome="needs_user"; stop_reason="refine"; stop_report="$refine_report"
      echo
      echo "⏸  The executor skipped $user_owned item(s) that only you can change" \
           "(an alignment answer or a front-matter field)."
      break
    fi

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
      if [ "$verify_passed" -eq 1 ]; then
        # The gate ran on this exact content and passed, and nothing has edited
        # the spec since (the loop breaks immediately on PASS), so recording the
        # result here is honest rather than a shortcut.
        fm_upsert "$spec" verify "passed"
        fm_set "$spec" updated "$(today)"
        echo "  The verify gate ran inside the loop and PASSED → verify: passed."
        echo "  Next: ./scripts/sdd start $spec"
      else
        echo "  The spec changed during the loop → verify was reset to 'pending'."
        echo "  Next: ./scripts/sdd verify $spec"
      fi
      return 0
      ;;
    needs_user)
      echo "✗ critique: needs_user  (score $last_score/10)"
      echo "  Read: ${stop_report#$ROOT/}"
      case "$stop_reason" in
        refine)
          echo "  Apply the items under '## User-owned' yourself — each is an alignment answer or a"
          echo "  front-matter field the executor may not touch — then re-run:"
          ;;
        stalled)
          echo "  The listed item(s) did not move after the executor's turn. Fix them by hand (an"
          echo "  alignment answer or a front-matter field is the usual culprit), or — if the reviewer"
          echo "  is wrong — justify them under '## Deviations from CLAUDE.md' and set"
          echo "  'critique: skipped'. Otherwise re-run:"
          ;;
        *)
          echo "  Answer the flagged decisions in the spec, then re-run:"
          ;;
      esac
      echo "    ./scripts/sdd critique $spec"
      echo "  Edit the answer lines by hand — re-running 'sdd align' would clear every answer."
      exit 1
      ;;
    *)
      echo "✗ critique: max_rounds  (best score $last_score/10, threshold $threshold)"
      echo "  Read: ${report_dir#$ROOT/}/round-$rounds.md"
      [ -f "$report_dir/round-$rounds-verify.md" ] && \
        echo "       ${report_dir#$ROOT/}/round-$rounds-verify.md  (verify gate findings)"
      echo "  Fix the remaining items by hand and re-run 'sdd critique', or — if the"
      echo "  reviewer is wrong — justify it under '## Deviations from CLAUDE.md' and set"
      echo "  'critique: skipped' in the front matter to release the gate deliberately."
      exit 1
      ;;
  esac
}
