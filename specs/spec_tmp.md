---
task_id: 003
task_name: locked-spec-checkverify
type: refactor
status: draft            # draft → ready → active → done | blocked | dropped
branch: ~                # `scripts/sdd start` fills in: main/003-locked-spec-checkverify
alignment: resolved      # pre-filled in §8; do NOT run `sdd align` (it clears the section)
verify: pending          # `scripts/sdd verify` → passed | failed (gate for start/implement)
created: 2026-09-17
updated: 2026-09-17
target_version: X.Y.Z    # ← fill in before `sdd ready`
blocked_reason: ~
dropped_reason: ~
---

# [REF-003] Locked main spec, agent-owned draft spec, and the CheckVerify scoring agent

> Don't repeat CLAUDE.md; reference it only. Write any deviations in §9.

> A test safety net is required for refactors; if coverage is insufficient, open a test spec first.
> This refactor touches shell tooling and agent definitions only — no Kotlin. See §9.

> **Bootstrap note.** This spec introduces the `lock:` front-matter field and the two-phase
> verify pipeline. It is itself processed by the *current* (single-phase) flow, so its own front
> matter deliberately carries no `lock:` field. The first spec to run through the new pipeline is
> the next one created after T1 lands.

## 1. Motivation

`sdd verify` today is a dead end. The `sdd-verify` agent inspects the spec read-only, and any
open question — however small, however mechanically answerable — produces `VERIFY: FAIL`, writes
`verify: failed` into the front matter, and blocks `start` and `implement` until a human edits the
spec by hand. The agent is explicitly told to "never pass in doubt", so in practice it fails on
questions it could have answered itself from CLAUDE.md.

Three problems follow from that:

1. **No auto-resolution.** A question like "which Hilt scope does this Repository bind in?" is
   fully determined by CLAUDE.md's DI rules. Failing the spec and waiting for a human is wasted
   round-trip.
2. **No triage.** A missing Response contract and a naming preference are treated identically —
   both produce FAIL. There is no notion of which questions actually matter.
3. **The main spec is mutable by agents.** `sdd-align` edits `spec.md` directly, and
   `sdd-implement` ticks its checkboxes and appends to its Changelog. The human-authored intent
   and the agent-generated commentary live in the same file, so there is no stable record of what
   was originally asked for, and a misbehaving agent can silently rewrite the contract it is
   supposed to be implementing.

## 2. Current State

```
sdd verify <spec>
  └─ run_agent "sdd-verify" "readonly" "verify"      # tools: Read, Grep, Glob
       └─ compares spec.md ↔ CLAUDE.md
       └─ emits "VERIFY: PASS" | "VERIFY: FAIL" as first output line
  └─ script parses the verdict → fm_upsert spec.md verify: passed | failed
  └─ FAIL (or no parseable verdict) → exit 1, implement stays blocked
```

- One agent, one phase, one binary verdict.
- `spec.md` is the only spec artefact; every agent that has `Edit`/`Write` can modify it.
- Agent-writability is governed only by each agent's frontmatter `tools:` list, which cannot be
  scoped to a path — `sdd-align` and `sdd-implement` hold repo-wide `Edit`/`Write`.
- `scripts/lib/deny-list.txt` can express only path reads (`Read(...)`) and shell commands
  (`Bash(...)`); see `deny_entry_to_claude` in `scripts/sdd`. There is no way to deny a *write*
  to a path.

## 3. Target State

```
sdd verify <spec>
  ├─ 0. guards: spec exists, status ∈ {draft, ready}
  ├─ 1. snapshot  = sha256(spec.md)
  ├─ 2. create    specs/**/spec.draft.md  from specs/templates/draft.md   (script, not agent)
  ├─ 3. lock      fm_upsert spec.md  lock: locked
  ├─ 4. PHASE 1   run_agent "sdd-verify" "draft" "verify"
  │                 reads spec.md (read-only) + CLAUDE.md
  │                 writes its questions into spec.draft.md § Verify Questions
  │                 emits "VERIFY: PASS" | "VERIFY: FAIL"
  ├─ 5. integrity sha256(spec.md) == snapshot, else hard fail
  ├─ 6. PHASE 2   run_agent "sdd-checkverify" "draft" "checkverify"
  │                 scores every Phase-1 question (rubric §3.4)
  │                 resolves the ones that qualify → writes fixes into spec.draft.md
  │                 emits "CHECKVERIFY: PASS" | "CHECKVERIFY: FAIL"
  ├─ 7. integrity sha256(spec.md) == snapshot, else hard fail
  └─ 8. verdict   fm_upsert spec.md  verify: passed | failed      (script writes, never the agent)
```

Phase 1's verdict no longer decides the gate. It only signals whether questions exist: zero
questions written → Phase 2 is skipped and `verify: passed` is set directly. This is the
behavioural inversion at the heart of the refactor — `VERIFY: FAIL` used to mean "blocked", and
now means "there is work for CheckVerify".

### 3.1 Spec lock

`lock:` is a new front-matter field on every spec, with two values:

| Value    | Meaning                                                              | Set by          |
| -------- | -------------------------------------------------------------------- | --------------- |
| `open`   | Human- and agent-editable. The state a spec is created in.           | template, `sdd unlock` |
| `locked` | No agent may write to or delete `spec.md`. Only `scripts/sdd` writes. | `sdd verify` step 3 |

The lock applies to **agents**, not to the CLI. `scripts/sdd` remains the sole writer of a locked
spec's front matter (`verify:`, `status:`, `branch:`, `updated:`), which is what makes step 8
possible at all. This mirrors the existing contract stated in `.claude/agents/sdd-verify.md`:
"`./scripts/sdd verify` records your verdict in the front matter for you."

Enforcement is layered, because no single layer is sufficient:

| Layer | Mechanism | Covers |
| ----- | --------- | ------ |
| L1 | `lock: locked` in front matter; every agent's definition carries a "locked spec" clause | Agent intent |
| L2 | `draft` driver mode passes path-scoped write denies for `specs/**/spec.md` on the invocation | Tool capability, per run |
| L3 | `sha256` snapshot compared before and after every agent dispatch (steps 1, 5, 7) | Actual mutation, backend-neutral |
| L4 | `sdd implement` refuses to run if the spec is `locked` and its hash differs from the recorded `lock_hash` | Tamper detection across sessions |

L2 is invocation-scoped on purpose. A global deny in `.claude/settings.json` would also block
`sdd align`, which legitimately writes into `spec.md`'s Alignment section *before* the lock is
taken. L3 is the layer that actually guarantees the property: it holds even if a backend ignores
or mistranslates the deny flags.

`sdd unlock <spec>` sets `lock: open`, clears `lock_hash`, and resets `verify: pending` — editing
a verified spec invalidates the verification, exactly as `sdd align` already resets `verify:` when
it re-opens alignment.

### 3.2 Draft spec

Path: `specs/{type}s/{task_id}-{task_name}/spec.draft.md`, a sibling of `spec.md`.

The glob `specs/**/spec.md` does not match `spec.draft.md`, so the L2 denies leave the draft
writable while the main spec is closed. Both live under `specs/{features,bugs,refactors,tests}/`,
which the SDD artifact's `.gitignore` rules already exclude, so no `.gitignore` change is needed.

Created by `scripts/sdd` (step 2) from a new `specs/templates/draft.md`, with this front matter:

```yaml
---
draft_of: specs/refactors/003-locked-spec-checkverify/spec.md
source_sha: <sha256 of spec.md at creation>
verify_round: 1          # increments on each `sdd verify` re-run
created: YYYY-MM-DD
updated: YYYY-MM-DD
checkverify: pending     # pending | passed | failed
---
```

and these sections:

| Section | Written by | Contents |
| ------- | ---------- | -------- |
| `## Verify Questions` | `sdd-verify` (Phase 1) | Numbered questions, same `**Question:**` shape the Alignment parser already uses |
| `## Scoring` | `sdd-checkverify` | One row per question: the four dimension scores, total, band, veto flag |
| `## Resolutions` | `sdd-checkverify` | Per resolved question: target section in `spec.md`, the corrected content, any stated assumption |
| `## Blockers` | `sdd-checkverify` | Unresolvable questions that force `CHECKVERIFY: FAIL`, with what the human must decide |
| `## Notes` | `sdd-checkverify` | Scored-but-not-resolved questions, one line each, informational |

`## Resolutions` is the deliverable. It does not mutate `spec.md`; it is an overlay that
`sdd implement` reads alongside the locked spec (§3.5). The main spec stays the record of what the
human asked for; the draft is the record of what the agents worked out.

A re-run of `sdd verify` does not delete the previous draft. It increments `verify_round` and
appends a new round block, so the scoring history of a spec is preserved.

### 3.3 The CheckVerify agent

New agent `sdd-checkverify`, at `.claude/agents/sdd-checkverify.md`:

```yaml
---
name: sdd-checkverify
description: Scores the sdd-verify agent's open questions against a weighted rubric, resolves the ones that qualify by deriving answers from CLAUDE.md and the codebase, and writes the resolutions into the draft spec. Never writes to the locked main spec.
tools: Read, Grep, Glob, Edit, Write
model: opus
color: coral
---
```

- `Read, Grep, Glob` to inspect `spec.md`, `CLAUDE.md`, and the codebase.
- `Edit, Write` scoped by L2 to everything *except* `specs/**/spec.md` — the draft is its only
  writable spec surface.
- **No `Bash`.** It must not run gradle, git, or `scripts/sdd`. It reasons and writes; the script
  owns all state transitions.
- `model: opus`, matching `sdd-align` — scoring and answer derivation are the reasoning-heavy
  steps, where `sdd-implement` and `sdd-verify` sit on `sonnet`.

### 3.4 Scoring rubric

Every question from Phase 1 is scored on four weighted dimensions summing to 100. The dimensions
are chosen so that the two independent things that matter — *how much damage the question does if
ignored*, and *whether a machine can legitimately answer it* — are scored separately and can veto
each other.

**D1 — Blocking impact (0–35).** If this stays unanswered, what happens to the implementation?

| Score | Condition |
| ----- | --------- |
| 35 | Implementation cannot begin. A required contract, type, or state is absent — no Response class named, no error branch in the ViewEntity, no defined DTO field. |
| 25 | Implementation can begin but bakes in an assumption that is more likely wrong than right, and getting it wrong means rework rather than a tweak. |
| 15 | Affects one edge case or error branch only; the happy path is fully specified. |
| 5 | Naming, ordering, or wording preference. Zero functional consequence. |
| 0 | Already answered elsewhere in `spec.md`. The question is redundant. |

**D2 — CLAUDE.md rule coupling (0–25).** How directly does the question touch codified rules?

| Score | Condition |
| ----- | --------- |
| 25 | Touches a rule CLAUDE.md marks non-negotiable or FORBIDDEN — the DI scope table, RxJava2 vs coroutines, Hilt vs Koin, Timber vs `Log.*`, Gson `@SerializedName`. |
| 15 | Touches the layer-dependency rule (`presentation → domain ← data`) or a layer's stated responsibility. |
| 8 | Touches a convention: branch naming, commit format, test class naming. |
| 0 | No rule in CLAUDE.md speaks to it. |

**D3 — Gap locality (0–20).** Can the fix be written into an identifiable place?

| Score | Condition |
| ----- | --------- |
| 20 | Maps to exactly one section of `spec.md` and one concrete edit. |
| 12 | Maps to two or three sections. |
| 5 | Cross-cutting; no clean insertion point. |
| 0 | Cannot be localised at all. **Veto.** |

**D4 — Answer derivability (0–20).** Can CheckVerify answer it without a human?

| Score | Condition |
| ----- | --------- |
| 20 | A CLAUDE.md rule or an existing codebase pattern dictates exactly one answer. |
| 12 | Derivable with a single assumption, which must be written down verbatim in `## Resolutions`. |
| 5 | Requires a product, business, or UX decision. |
| 0 | Requires information that does not exist yet — an unbuilt API, an undecided design. **Veto.** |

**Total = D1 + D2 + D3 + D4.**

#### Bands and preconditions

A question is **resolved** only if all three hold:

```
total ≥ 70   AND   D4 ≥ 12   AND   D3 ≥ 12
```

| Band | Condition | Action |
| ---- | --------- | ------ |
| `RESOLVE` | total ≥ 70 and D4 ≥ 12 and D3 ≥ 12 | Derive the answer, write the fix into `## Resolutions` with its target section |
| `NOTED` | 40 ≤ total < 70, or total ≥ 70 but D3/D4 precondition unmet | One line in `## Notes` with score and reason. No edit. Does not block. |
| `DISCARDED` | total < 40 and not vetoed | One line in `## Notes`. Redundant or trivia. |
| `BLOCKER` | vetoed (D3 = 0 or D4 = 0) **and** D1 ≥ 25 | Entry in `## Blockers`. Forces `CHECKVERIFY: FAIL`. |

Vetoed questions have their total capped at 40 regardless of the other dimensions.

#### Why the threshold is 70, and why the preconditions exist

The numbers are set so the threshold cannot be reached by the wrong combination:

- **A redundant question can never be resolved.** With D1 = 0 the ceiling is 25 + 20 + 20 = 65,
  below 70. Resolution therefore always requires genuine blocking impact.
- **Rule coupling alone can never carry a question.** D2's maximum of 25 is less than the 46 that
  D1 + D2 must contribute once D3 and D4 sit at their minimum passing values.
- **The `D4 ≥ 12` precondition is load-bearing.** Without it, a question scoring D1 = 35,
  D2 = 25, D3 = 12, D4 = 5 totals 77 and would be auto-resolved — but D4 = 5 means it needs a
  product decision, so the agent would be inventing business logic. The precondition is what
  stops a high total from overriding "a human has to decide this".
- **The `D3 ≥ 12` precondition** stops the agent from writing a fix it cannot place, which would
  land as vague prose appended somewhere unhelpful.
- **Veto plus D1 ≥ 25 is the safety valve.** A question that genuinely cannot be answered and
  genuinely blocks implementation must keep the spec failed. Without this rule the pipeline could
  set `verify: passed` on a spec with a real hole in it — a strictly worse failure mode than the
  current over-eager FAIL.

#### Worked examples

| Question | D1 | D2 | D3 | D4 | Total | Band |
| -------- | -- | -- | -- | -- | ----- | ---- |
| "Which Hilt scope does `TokenRepository` bind in?" | 35 | 25 | 20 | 20 | 100 | `RESOLVE` — CLAUDE.md's DI rules give exactly one answer: `@ActivityRetainedScoped` |
| "The spec's `Response` has no error field; what is the error ViewEntity?" | 35 | 15 | 20 | 12 | 82 | `RESOLVE` — one stated assumption: mirror the existing error-state pattern |
| "Should the retry backoff be 2s or 5s?" | 25 | 0 | 20 | 5 | 50 | `NOTED` — product decision, D4 precondition unmet |
| "Should the ViewModel be named `LoginViewModel` or `SignInViewModel`?" | 5 | 8 | 20 | 20 | 53 | `NOTED` — no functional consequence |
| "Which endpoint does this call? The API is not built yet." | 35 | 0 | 12 | 0 | 40 (capped) | `BLOCKER` — vetoed, D1 ≥ 25 |
| "Is `minSdk` 23?" | 0 | 15 | 20 | 20 | 55 → 55 | `NOTED` — D1 = 0, already in CLAUDE.md |

### 3.5 Downstream consumption

`sdd implement` passes both paths to `sdd-implement`, and the agent's precedence order becomes:

```
CLAUDE.md  >  spec.draft.md § Resolutions  >  spec.md
```

CLAUDE.md still wins over everything, as it does today. The draft's resolutions outrank the main
spec because a resolution exists precisely where the main spec was wrong or silent. `sdd-implement`
loses the ability to tick checkboxes or append to the Changelog in a locked `spec.md`; it records
task completion in the draft instead, and `sdd done` / the script handles the main spec.

## 4. Affected Files

- [ ] `scripts/sdd` — draft/lock/hash helpers, `model_default`, `model_for_role`, `cmd_verify`,
      `cmd_checkverify`, `cmd_unlock`, `cmd_implement`, `deny_entry_to_claude`, `usage`, `main`
- [ ] `scripts/lib/driver-claude.sh` — new `draft` mode
- [ ] `scripts/lib/driver-copilot.sh` — new `draft` mode
- [ ] `scripts/lib/deny-list.txt` — tool-prefixed entry syntax + header docs
- [ ] `.claude/agents/sdd-verify.md` — writes to draft, never to `spec.md`
- [ ] `.claude/agents/sdd-checkverify.md` — **new**
- [ ] `.claude/agents/sdd-implement.md` — draft-aware precedence, lock clause
- [ ] `.claude/agents/sdd-align.md` — lock clause (refuse if `lock: locked`)
- [ ] `.github/agents/*.agent.md` — regenerated by `sdd sync-agents`, never hand-edited
- [ ] `specs/templates/feature.md`, `bug.md`, `refactor.md`, `test.md` — add `lock: open`
- [ ] `specs/templates/draft.md` — **new**
- [ ] `artifact/manifest.txt` — list the new agent and template files
- [ ] `CLAUDE.md` — §9.1 lifecycle table, gate descriptions, lock rule
- [ ] `sdd-artifact-usage.md` — document `spec.draft.md` and the new commands

## 5. Breaking Changes

- [ ] None
- [x] Yes:
  1. **`sdd verify` semantics change.** `VERIFY: FAIL` no longer implies `verify: failed`. Any
     tooling or habit that reads Phase 1's verdict as the gate result breaks. The gate result is
     now Phase 2's verdict.
  2. **Agents can no longer write to a verified `spec.md`.** `sdd-align` run after `sdd verify`
     fails until `sdd unlock`. `sdd-implement` no longer ticks main-spec checkboxes.
  3. **`deny-list.txt` gains a new entry shape.** Existing entries are unaffected — the parser
     must stay backwards-compatible with the three current shapes (literal, glob, multi-word).
  4. **Specs created before T1 have no `lock:` field.** `require_lock_state` must treat an absent
     or `~` value as `open`, matching how `require_alignment_resolved` already tolerates specs
     that predate the `alignment:` field.

## 6. Task List

- [ ] T1 – Add `lock: open` to the four spec templates; add `specs/templates/draft.md` with the
      front matter and five sections from §3.2.
- [ ] T2 – `scripts/sdd`: add `draft_path`, `create_draft_spec`, `spec_sha`, and
      `require_spec_unmodified`. `spec_sha` must work with both `shasum -a 256` (macOS) and
      `sha256sum` (Linux).
- [ ] T3 – `scripts/sdd`: add `lock_spec`, `unlock_spec`, `require_lock_state` (absent/`~` → open),
      and `cmd_unlock`.
- [ ] T4 – `scripts/sdd`: add the `checkverify` role to `model_default` (`opus` on claude, `auto`
      on copilot) and `model_for_role` (`SDD_MODEL_CHECKVERIFY` override); document it in the
      header comment block alongside the other four.
- [ ] T5 – `scripts/lib/driver-claude.sh`: add `draft` mode — `--permission-mode acceptEdits`,
      path-scoped write denies for `specs/**/spec.md`, and tee into `$RUN_AGENT_OUTPUT`. Unlike
      `edit` mode it must not swallow the exit status with `|| true`; `cmd_verify` needs to tell
      an infrastructure failure from an unparseable verdict, exactly as `readonly` mode does today.
- [ ] T6 – `scripts/lib/driver-copilot.sh`: add the same `draft` mode using that backend's
      equivalent flags; keep `RUN_AGENT_OUTPUT` semantics identical.
- [ ] T7 – Rewrite `.claude/agents/sdd-verify.md`: write questions into the draft spec, never to
      `spec.md`; add `Edit, Write` to `tools:`; keep the verbatim `VERIFY:` verdict-line contract.
- [ ] T8 – Create `.claude/agents/sdd-checkverify.md` with the frontmatter from §3.3 and the full
      rubric from §3.4, including the bands, both preconditions, the veto rule, and the
      `CHECKVERIFY:` verdict-line contract.
- [ ] T9 – Rewrite `cmd_verify` as the eight-step pipeline in §3. Skip Phase 2 when Phase 1 wrote
      zero questions. On an integrity-check failure: report which step mutated `spec.md`, leave
      `verify:` untouched, exit non-zero.
- [ ] T10 – Add `cmd_checkverify` (re-run Phase 2 alone against an existing draft) and wire
      `checkverify` and `unlock` into `usage` and `main`.
- [ ] T11 – Update `cmd_implement` to pass both spec paths and enforce L4; update
      `.claude/agents/sdd-implement.md` for the §3.5 precedence order and the no-main-spec-writes
      rule. Add the lock clause to `.claude/agents/sdd-align.md`.
- [ ] T12 – Extend `deny_entry_to_claude` with a tool-prefixed entry shape (e.g.
      `Edit:specs/**/spec.md`) so writes can be denied, keeping the three existing shapes intact.
      Add the new entries and header documentation to `deny-list.txt`.
- [ ] T13 – Update `artifact/manifest.txt`, `CLAUDE.md` §9.1, and `sdd-artifact-usage.md`.
- [ ] T14 – Run `./scripts/sdd sync-agents` and confirm `.github/agents/sdd-checkverify.agent.md`
      is generated with `tools: read, search, edit, write` and no `model:`/`color:` field.

## 7. Acceptance Criteria

- [ ] Existing tests pass (behaviour preserved)
- [ ] New structure conforms to CLAUDE.md
- [ ] `sdd verify` on a spec with zero verify questions sets `verify: passed` without dispatching
      Phase 2.
- [ ] `sdd verify` on a spec with resolvable questions only sets `verify: passed`, and every
      resolved question appears in `## Resolutions` with a target section.
- [ ] `sdd verify` on a spec containing one vetoed question with D1 ≥ 25 sets `verify: failed` and
      writes that question to `## Blockers`.
- [ ] Every question written in Phase 1 appears in `## Scoring` with four dimension scores, a
      total, and a band. No question is silently dropped.
- [ ] No question with D4 < 12 or D3 < 12 appears in `## Resolutions`, whatever its total.
- [ ] After `sdd verify`, `spec.md` differs from its pre-verify state only in the `lock:`,
      `lock_hash:`, `verify:`, and `updated:` front-matter lines. Verified with `git diff`.
- [ ] An agent instructed to edit a `locked` `spec.md` fails, and `sdd verify` reports the
      integrity violation rather than continuing to step 8.
- [ ] `sdd align` on a `locked` spec refuses with a message naming `sdd unlock`.
- [ ] `sdd unlock` sets `lock: open`, clears `lock_hash`, and resets `verify: pending`.
- [ ] `sdd implement` refuses to run when a locked spec's hash differs from `lock_hash`.
- [ ] A second `sdd verify` run increments `verify_round` and appends a round block without
      deleting the first round's scoring.
- [ ] `sdd sync-agents` is idempotent — a second run produces no `git diff`.
- [ ] `SDD_AGENT=claude` and `SDD_AGENT=copilot` both complete the pipeline; `SDD_AGENT=auto`
      resolves by binary presence only, with no runtime fallback (spec 002 D6).
- [ ] `SDD_MODEL_CHECKVERIFY` overrides the role's model on whichever backend resolves.
- [ ] With no agent CLI on PATH, `sdd verify` leaves `spec.md` byte-identical and prints the
      manual-fallback protocol — the same no-op guarantee `cmd_align` already makes (spec 002 D6).
- [ ] `./gradlew checkCodeQuality assembleDevDebug` green.

## 8. Open Decisions (Alignment)

<!-- Pre-filled and already answered. `sdd align` CLEARS this section — run
     `./scripts/sdd align-resolve <spec>` instead to confirm `alignment: resolved`. -->

1. **Question:** Does the `sdd-verify` agent create `spec.draft.md` itself, or does the script
   create it and the agent only fill it in?
   - **Answer:** The script creates it (step 2), the agent owns all of its content. Two reasons:
     the hash baseline in `source_sha` must be taken before any agent runs, and an agent that
     creates its own only-writable surface can just as easily create a second one. The user-facing
     behaviour is unchanged — the draft comes into existence as part of `sdd verify`.

2. **Question:** Does a resolved draft ever get merged back into `spec.md`?
   - **Answer:** Not in this spec. `## Resolutions` stays an overlay that `sdd implement` reads
     (§3.5). A `sdd promote` command that merges the overlay into an unlocked `spec.md` is
     explicitly out of scope and belongs in a follow-up spec.

3. **Question:** Is the lock enforced against `scripts/sdd` itself?
   - **Answer:** No. The script is the only writer of a locked spec's front matter, which is what
     makes step 8 possible. The lock is agent-scoped, consistent with the existing contract in
     `.claude/agents/sdd-verify.md`.

4. **Question:** What happens to Phase 1's `VERIFY: FAIL` verdict now?
   - **Answer:** It becomes advisory. It is recorded in the draft's round block for auditability
     but does not set `verify:`. Only Phase 2's `CHECKVERIFY:` verdict reaches the front matter.
     Listed as breaking change §5.1.

5. **Question:** Should CheckVerify be allowed to run `./gradlew` to test its own resolutions?
   - **Answer:** No — no `Bash` tool. Its resolutions are spec text, not code; compilation is
     `sdd-implement`'s and `sdd done`'s job. Giving it shell access would also let it call
     `scripts/sdd` and move its own gate.

6. **Question:** If Phase 2 fails mid-run, does the lock stay on?
   - **Answer:** Yes. The lock is released only by explicit `sdd unlock`, so a failed run cannot
     silently reopen the spec to agent writes. `verify: failed` plus `lock: locked` is a valid,
     recoverable state.

7. **Question:** Where does the 70% threshold come from, and is it configurable?
   - **Answer:** It is fixed in the agent definition, not an environment variable. §3.4's
     arithmetic is calibrated to it: at 70, a redundant question (D1 = 0, ceiling 65) can never
     qualify. Making the threshold tunable would silently break that property. A future spec may
     revisit the rubric; it should not expose a knob.

## 9. Deviations from CLAUDE.md

1. **No automated test net, contrary to the refactor template's requirement.** Everything this
   spec touches is Bash (`scripts/sdd`, `scripts/lib/driver-*.sh`) and Markdown agent definitions.
   The repository has no shell test harness, and CLAUDE.md's test rules (`XViewModelTest`,
   `XUseCaseTest`) address Kotlin units that this refactor does not touch. The substitute is the
   verification matrix in §7, which is written as executable checks against `git diff` and front
   matter rather than prose. Standing up a `bats` harness for `scripts/sdd` is worth a test spec
   of its own and should not gate this work.

2. **`.github/agents/*.agent.md` are listed in §4 as affected but must not be hand-edited.** They
   are generated; T14 regenerates them. Listing them is for reviewer visibility only.

## 10. Changelog

| Date | Status | Change |
|------|--------|--------|
| 2026-09-17 | draft | Refactor planned |
