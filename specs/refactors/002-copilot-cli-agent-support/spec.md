---
task_id: 002
task_name: copilot-cli-agent-support
type: refactor
status: active
branch: main/002-copilot-cli-agent-support
alignment: resolved
verify: passed
created: 2026-09-13
updated: 2026-09-13
target_version: 1.0.0
blocked_reason: ~
dropped_reason: ~
---

# [REF-002] Copilot CLI agent support

> Don't repeat CLAUDE.md; reference it only. Write any deviations in §9.

> A test safety net is required for refactors; if coverage is insufficient, open a test spec first.

## 1. Motivation

The SDD kit (`scripts/sdd` + `.claude/agents/`) only runs against the Claude Code CLI. Four
commands (`align`, `implement`, `verify`, `fix-ktlint`) hardcode `claude -p` invocations, its
`--permission-mode` flags and its `opus|sonnet|haiku` model aliases, and dispatch subagents via
the Claude-specific `"Use the <x> subagent"` prompt convention. A developer without a Claude
subscription cannot run any agent-backed step of the workflow.

The SDD core — `specs/`, the templates, the front-matter gates (`status`, `alignment`, `verify`),
the `VERIFY: PASS|FAIL` contract and the branch/commit convention — is already tool-agnostic and
lives in shell. Only the "brain" invocation is tool-bound. Making that one seam pluggable adds
GitHub Copilot CLI as a second backend at low cost and leaves the workflow itself untouched.

## 2. Current State

**Tool-bound points in `scripts/sdd`:**

| Location | Binding |
|---|---|
| `cmd_align` (L266–280) | `command -v claude`, `claude -p "Use the sdd-align subagent…" --model --permission-mode acceptEdits` |
| `run_task` (L204–206) | `claude -p "Use the sdd-implement subagent…" --permission-mode bypassPermissions` |
| `cmd_verify` (L400–420) | `claude -p "Use the sdd-verify subagent…" --permission-mode dontAsk --allowedTools` ; parses `VERIFY:` out of stdout |
| `cmd_fix_ktlint` (L466, 490–498) | `claude -p "Use the kotlin-ktlint subagent…" --permission-mode acceptEdits` |
| `SDD_MODEL_*` (L14–17) | Claude aliases `opus` / `sonnet` / `haiku` |
| error strings | "Claude Code CLI bulunamadı" in 3 places |

**Agent definitions:** `.claude/agents/{sdd-align,sdd-implement,sdd-verify,kotlin-ktlint}.md` —
frontmatter uses Claude tool names (`Read, Grep, Glob, Edit, Write, Bash`), `model:` aliases and
`color:`. Each body contains a "How you are launched" section written in Claude Code terms.

**Permissions:** `.claude/settings.json` carries the project allow/ask/deny lists, including the
secret-file denies (`local.properties`, `secrets.properties`, `.env`, `*.jks`, `*.keystore`) and
`git push --force`.

**Known gap (pre-existing):** `README.md` documents a `.claude/commands/` directory that does not
exist in the repo. Out of scope here; see §2 of the Excluded list.

## 3. Target State

`scripts/sdd` gains a thin **driver layer**. Every agent invocation goes through one function;
each driver translates it for its own CLI. `SDD_AGENT` selects the backend (`claude` | `copilot`
| `auto`, default `auto` = prefer `claude`, fall back to `copilot`).

Copilot CLI equivalents, taken from the GitHub documentation on 2026-09-13:

- Agent file location, `.agent.md` extension and `--agent` invocation:
  <https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-custom-agents-for-cli>
- Agent frontmatter schema, `tools` aliases and model precedence:
  <https://docs.github.com/en/copilot/reference/custom-agents-configuration>
- `CLAUDE.md` discovery and `@`-reference expansion:
  <https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-custom-instructions>
- `-p`, `-s`, `--allow-tool`, `--deny-tool`, `--add-dir`, `--model` and their filter syntax:
  <https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-programmatic-reference>


| Concern | Claude Code | Copilot CLI |
|---|---|---|
| Rules file | `CLAUDE.md` | reads `CLAUDE.md` **natively** (also `.claude/CLAUDE.md`) — no duplication needed |
| Agent definition | `.claude/agents/x.md` | `.github/agents/x.agent.md` (`description` required; `name`, `tools`, `model`, `target`) |
| Agent dispatch | `"Use the x subagent"` in prompt | `--agent x` flag |
| Tools | `Read, Grep, Glob, Edit, Write, Bash` | `read, search, edit, write, shell` |
| Edit permission | `--permission-mode acceptEdits` | `--allow-tool='read,edit,write'` |
| Read-only | `--permission-mode dontAsk` + `--allowedTools` | `--allow-tool='read' --deny-tool='write,shell'` |
| Clean stdout for verdict parsing | default | `-s` (required, or the banner breaks the `VERIFY:` grep) |
| Model | `--model opus` | `--model=claude-opus-5` (agent frontmatter > `--model` > `COPILOT_MODEL`) |

`.claude/agents/*.md` stays the **single source**; `sdd sync-agents` generates the `.github/agents/`
counterparts (frontmatter translated, body copied verbatim, `GENERATED — do not edit` banner).

**Model mapping** — same Anthropic models on both sides where the Copilot plan offers them:

| Role | Claude Code | Copilot CLI | Env override |
|---|---|---|---|
| align (strong) | `opus` | `claude-opus-5` | `SDD_MODEL_ALIGN` |
| implement (mid) | `sonnet` | `claude-sonnet-5` | `SDD_MODEL_IMPLEMENT` |
| verify (mid) | `sonnet` | `claude-sonnet-5` | `SDD_MODEL_VERIFY` |
| fix-ktlint (cheap) | `haiku` | `claude-haiku-4.5` | `SDD_MODEL_KTLINT` |

Model availability depends on the Copilot plan, so every value is env-overridable and `sdd doctor`
reports what the installed CLI actually accepts.

**Accepted risk.** The flags, schema and model names above are documented, not yet exercised —
Copilot CLI is not installed on the development machine as of this spec. The mitigation is
ordering, not faith: installing and authenticating the CLI is a precondition of T5 (D1), and
T11's `sdd doctor` includes a flag-support pre-flight probe, so any divergence surfaces as a
concrete failure before the dependent tasks are accepted. If a required flag turns out not to
exist, T5/T7/T10/T11 and their criteria are re-opened rather than worked around (D5 forbids
silent degradation).

### Scope

**Included**
- Driver layer in `scripts/sdd`; all four agent call sites routed through it.
- A `copilot` driver + a `claude` driver that reproduces today's behaviour byte-for-byte.
- `sdd sync-agents` generator and the generated `.github/agents/*.agent.md`.
- `.github/copilot-instructions.md` as a thin pointer to `CLAUDE.md`.
- Secret-file deny parity for the Copilot driver.
- `sdd doctor` (backend detection + agent-sync drift check).
- README section on running the kit with Copilot CLI.

**Excluded**
- VS Code / JetBrains Copilot Chat integration, `.github/prompts/`, `.github/instructions/`
  (pre-settled decision P2: CLI only).
- The missing `.claude/commands/` directory referenced by README.
- CI checks and git pre-commit hooks for `.github/agents/` drift (decision D7 — `sdd doctor` only).
- Any change to `specs/`, the templates, the front-matter gates or the lifecycle in CLAUDE.md §9.1.
- Any change to app code under `app/`.

## 4. Affected Files

- [ ] `scripts/sdd` — driver layer, model roles, `sync-agents`, `doctor`, neutral error strings
- [ ] `scripts/lib/driver-claude.sh` — new
- [ ] `scripts/lib/driver-copilot.sh` — new
- [ ] `scripts/lib/deny-list.txt` — new, shared secret-file deny source
- [ ] `.claude/agents/sdd-align.md` — "How you are launched" made tool-neutral
- [ ] `.claude/agents/sdd-implement.md` — same
- [ ] `.claude/agents/sdd-verify.md` — same
- [ ] `.claude/agents/kotlin-ktlint.md` — same
- [ ] `.github/agents/*.agent.md` — new, generated
- [ ] `.github/copilot-instructions.md` — new
- [ ] `README.md` — Copilot CLI section; remove the "convert it yourself" note (L360–361)

## 5. Breaking Changes

- [ ] None
- [x] Yes — two deliberate, narrow changes on the Claude backend, both agreed in §9:
  1. **`sdd align` exit code (D6).** When no agent CLI is found, `cmd_align` currently prints the
     manual protocol and exits **0**; it will exit **1**, like `verify` and `fix-ktlint` already do.
     Any script treating a CLI-less `align` as success must be updated. The manual-protocol text
     is preserved, printed on the error path.
  2. **`verify` front matter on infrastructure failure (D5).** A run that fails before producing
     output (missing binary, rejected flag) will no longer write `verify: failed`; it leaves the
     front matter untouched and exits non-zero. A completed run with no parseable `VERIFY:` line
     still writes `verify: failed` as today.

  Everything else on the Claude backend is unchanged: `SDD_AGENT` defaults to `auto`, which
  prefers `claude`, and all other commands, flags, prompts and front-matter writes keep their
  current behaviour. The Copilot backend is intentionally **stricter** than the Claude one on
  permissions (D4), so "no behaviour change" is a claim about the Claude backend only.

## 6. Task List

- [x] T1 – Extract a `run_agent <agent> <mode> <model-role> <prompt>` seam in `scripts/sdd` and route `cmd_align`, `run_task`, `cmd_verify`, `cmd_fix_ktlint` through it, with the Claude driver inline. Pure extraction: today's prompts, exit codes and front-matter writes are all preserved verbatim — the two §5 changes are deliberately deferred to T3 and T4, so this task alone changes no behaviour.
- [x] T2 – Move the Claude driver to `scripts/lib/driver-claude.sh`; add `SDD_AGENT` (`claude|copilot|auto`) resolution (binary presence only, no runtime fallback — D6) and neutral "CLI not found" messaging.
- [x] T3 – **Breaking change 1 of §5 (D6):** unify the missing-CLI exit path. `cmd_align`'s CLI-not-found branch currently prints the manual protocol and falls through to exit 0; move that text into the shared `run_agent` error path so all four agent-backed commands print it and exit 1. Same task, same root cause: `cmd_align` writes `alignment: pending` and `verify: pending` *before* it checks that a backend exists, so a no-op run silently invalidates a passing verify — resolve the backend first and write nothing if it fails.
- [x] T4 – **Breaking change 2 of §5 (D5):** split infrastructure failure from an inconclusive verdict in `cmd_verify`. Today the `verify: failed` write happens whenever no `VERIFY:` line is found, including when the CLI never ran. Have `run_agent` report *why* it failed; write `verify: failed` only for a completed run with unparseable output, and on infrastructure failure leave the front matter untouched and exit non-zero.
- [ ] T5 – Add `scripts/lib/driver-copilot.sh`: `--agent`, `-p`, `-s`, `--allow-tool`/`--deny-tool` per mode, `--model` per role; `implement` mode uses the explicit allow list from D4, never `--allow-all-tools`. Before dispatching, the driver compares `.claude/agents/*.md` against `.github/agents/*.agent.md` and prints a warning naming any stale file — it then runs anyway and never regenerates (D7).
- [x] T6 – Replace `SDD_MODEL_*` literals with per-driver role→model tables (§3), keeping the existing env-var names as overrides.
- [x] T7 – Add `sdd sync-agents`: translate `.claude/agents/*.md` frontmatter and emit `.github/agents/*.agent.md` with a generated-file banner. `model:` is dropped so the driver's `--model` stays authoritative (D2); `color:` is dropped too, simply because Copilot's agent schema has no such field.
- [x] T8 – Rewrite the "How you are launched" sections of the four agent bodies in tool-neutral wording, then re-run `sdd sync-agents`.
- [ ] T9 – Add `.github/copilot-instructions.md` pointing at `CLAUDE.md` (`@CLAUDE.md`) plus the SDD "read the spec before writing code" rule.
- [ ] T10 – Add `scripts/lib/deny-list.txt` as the single deny source; generate the `deny` array of `.claude/settings.json` from it (leaving `allow`/`ask` hand-maintained), and have the Copilot driver expand literal paths into `--deny-tool` and glob entries into `--add-dir` path narrowing (D3).
- [ ] T11 – Add `sdd doctor`: resolved backend, CLI version, accepted models, a flag-support pre-flight probe (D5), per-entry deny coverage (D3), a `model:`-absence assertion on generated agents (D2), and `.github/agents/` drift detection.
- [ ] T12 – Update `README.md`: Copilot CLI setup, `SDD_AGENT` usage, the driver/model tables, the two §5 breaking changes, and drop the stale "Copilot kullanıyorsan kendin çevir" note.

## 7. Acceptance Criteria

- [ ] With `claude` installed and `SDD_AGENT` unset, `align`, `align-resolve`, `verify`,
      `implement`, `fix-ktlint` behave exactly as before this refactor — same prompts, same
      front-matter writes, same exit codes — **except** the two changes listed in §5.
- [ ] With `SDD_AGENT=copilot`, `sdd verify <spec>` runs the `sdd-verify` agent read-only, its
      verdict is parsed, and the spec's front matter is set to `verify: passed` or `failed`.
- [ ] With `SDD_AGENT=copilot`, `sdd align <spec>` writes questions into the `## Open Decisions
      (Alignment)` section in the script-parseable format, and `align-resolve` accepts them.
- [ ] With `SDD_AGENT=copilot`, `sdd implement <spec> T1` applies one task and stops.
- [ ] A run that fails before producing output (missing binary, rejected flag) leaves the spec's
      front matter byte-identical and exits non-zero; only a completed run with no parseable
      `VERIFY:` line writes `verify: failed` (D5).
- [ ] `SDD_AGENT=auto` resolves by binary presence only and never switches backend at runtime;
      a missing CLI exits 1 from all four agent-backed commands, `align` included (D6).
- [ ] `sdd align` with no backend available leaves the spec file byte-identical — in particular
      it does not reset `alignment` or `verify` (D6).
- [ ] `sdd sync-agents` is idempotent: running it twice leaves `git status` clean.
- [ ] No generated `.github/agents/*.agent.md` contains a `model:` key, and `sdd doctor` fails
      if one does (D2).
- [ ] `sdd doctor` exits non-zero when `.github/agents/` has drifted from `.claude/agents/`;
      the Copilot driver warns on drift but still runs and never auto-regenerates (D7).
- [ ] Every entry in `scripts/lib/deny-list.txt` is covered on the Copilot backend by either a
      `--deny-tool` flag or `--add-dir` path narrowing; `sdd doctor` reports which, and exits
      non-zero if any entry is covered by neither (D3).
- [ ] The `deny` array of `.claude/settings.json` matches `scripts/lib/deny-list.txt`, and its
      `allow`/`ask` arrays are unchanged by this refactor (D3).
- [ ] `.github/copilot-instructions.md` exists, resolves `CLAUDE.md` through an `@CLAUDE.md`
      reference rather than restating any rule, and states the spec-first rule (T9).
- [ ] `README.md` documents Copilot CLI setup, `SDD_AGENT`, the model table and both §5
      breaking changes, and no longer tells the reader to convert the `claude` calls by hand (T12).
- [ ] `bash -n scripts/sdd` and `bash -n scripts/lib/*.sh` parse cleanly after every task.
- [ ] A full `new -> ready -> align -> align-resolve -> verify -> start -> implement` round trip
      succeeds end to end on a scratch spec, once per backend (this replaces the gradle gate;
      see the third entry in §10).
- [ ] `git status --short` shows no file outside §4 modified by any task.
- [ ] No file under `app/`, `specs/templates/` or the CLAUDE.md §9.1 lifecycle is modified.

## 8. Test Plan

There is no unit-test harness for shell in this repo, so verification is scripted-manual and runs
against the already-completed spec `specs/refactors/001-change-mainactivity-title/spec.md` (a
throwaway copy, so its front matter can be reset between runs).

- [ ] Regression, Claude backend: on a copy of spec 001 reset to `verify: pending`, run
      `sdd verify` before and after the refactor; the diff of the written front matter is empty.
- [ ] Copilot backend: same copy, `SDD_AGENT=copilot sdd verify` → front matter written,
      exit code matches the verdict.
- [ ] Verdict parsing: confirm `-s` output starts with the `VERIFY:` line; assert that dropping
      `-s` is what breaks it (guards the choice in §3).
- [ ] Gate enforcement under Copilot: with `alignment: pending`, `sdd start` and `sdd implement`
      must still refuse.
- [ ] Backend resolution: `SDD_AGENT=copilot` with `copilot` absent → clear error, no spec write;
      `SDD_AGENT=auto` with both installed → picks `claude`.
- [ ] Exit-code unification (D6): temporarily hide both CLIs from `PATH`, run all four
      agent-backed commands; each prints the manual protocol and exits 1, `align` included.
- [ ] Align write-before-check (D6): with both CLIs hidden from `PATH`, snapshot the spec, run
      `sdd align`, and diff — the file must be unchanged. Confirmed failing before T3: the run
      rewrote `alignment: resolved` and `verify: passed` to `pending` and still exited 0.
- [ ] Infrastructure vs. spec failure (D5): run `verify` with a deliberately bogus `--model`;
      the spec file must be byte-identical afterwards (`git diff --quiet` on it).
- [ ] Deny parity (D3): with `SDD_AGENT=copilot`, ask an agent to read `local.properties` and a
      `*.jks` file; both must be refused, and `sdd doctor` must report how each entry is covered.
- [ ] Generated-agent hygiene (D2): `grep -L '^model:' .github/agents/*.agent.md` lists all four
      files; `SDD_MODEL_VERIFY=<other-model>` visibly changes the model the Copilot run uses.
- [ ] `sdd sync-agents` idempotence: run twice, `git status --short` empty on the second run.
- [ ] Manual: full `new → ready → align → align-resolve → verify → start → implement → done`
      round trip on a scratch spec, once per backend, on a scratch branch that is deleted after.

## 9. Open Decisions (Alignment)

<!-- `./scripts/sdd align` writes the questions here and fills in your answers.
     Format (parsed by the script):
     1. **Question:** <question>
        - **Answer:** <answer>
     LABELLING: where a task or criterion elsewhere in this spec cites a decision as D<n>, the
     <n> is this list's numbering. Not every question is cited by label: D8 (string language) is
     a writing convention rather than a design constraint, so it is honoured throughout without
     a citation. The three decisions settled with the user *before* align ran are labelled
     P1 (model mapping), P2 (CLI only) and P3 (`.claude/agents/` stays the source); they are
     recorded in §3 / Scope and are not repeated here. P-labels and D-labels are separate
     sequences — do not renumber one into the other. -->

1. **Question:** Is the GitHub Copilot CLI actually installed and authenticated on the machine where this spec will be implemented? The §7 acceptance criteria and §8 test plan require live `SDD_AGENT=copilot` runs of `align`, `verify` and `implement`; if no Copilot access exists, do we (a) postpone to `blocked`, (b) ship the driver with only the Claude-regression criteria executed and mark the Copilot criteria as untested, or (c) something else?
   - **Answer:** A Copilot subscription exists, so neither (a) nor (b) applies: the CLI is installed (`npm i -g @github/copilot`) as a prerequisite of T5 and every `SDD_AGENT=copilot` acceptance criterion in §7 and test in §8 is executed live. Installing and authenticating the CLI is a precondition of starting T5 — the first task that needs a live Copilot install — not a task in its own right; if installation turns out to be impossible the spec goes to `blocked` rather than shipping untested criteria.
2. **Question:** §3 states Copilot's precedence is "agent frontmatter > `--model` > `COPILOT_MODEL`", but the `.claude/agents/*.md` sources carry a `model:` alias (e.g. `model: sonnet` in `sdd-verify.md`) — if `sync-agents` translates it into the generated `.github/agents/*.agent.md`, the frontmatter will silently win over the `SDD_MODEL_*` env overrides promised in T4. Should the generator omit `model:` from the generated files so the driver's `--model` stays authoritative, keep it and treat the env vars as Claude-only, or translate it and drop `--model` for Copilot?
   - **Answer:** The generator omits `model:` from the generated `.github/agents/*.agent.md` files entirely, so the driver's `--model` stays authoritative and the `SDD_MODEL_*` overrides behave identically on both backends. The `model:` alias in `.claude/agents/*.md` is kept (Claude Code needs it) but is treated as source-only metadata that `sync-agents` deliberately drops. `sdd doctor` asserts that no generated agent file contains a `model:` key.
3. **Question:** `.claude/settings.json` denies *paths* (`local.properties`, `secrets.properties`, `.env`, `*.jks`, `*.keystore`), while Copilot's `--deny-tool` is tool-granular, not path-granular. If the installed Copilot CLI cannot express a path-level deny, what is the required behaviour: a coarser policy (deny `write`/`shell`, read-only where possible) that accepts the residual read risk, refusal to run the Copilot backend at all, or a pre-flight guard in the driver? And which of `scripts/lib/deny-list.txt` vs `.claude/settings.json` is the generated artefact in T8?
   - **Answer:** `scripts/lib/deny-list.txt` is the hand-edited source; the `deny` array of `.claude/settings.json` is generated from it (the `allow`/`ask` arrays stay hand-maintained and untouched). Copilot's `--deny-tool` accepts a plain path filter but supports wildcards only for `shell` and `url`, so the driver expands every literal path entry into `--deny-tool` and, for glob entries it cannot express (`*.jks`, `*.keystore`), narrows the agent's reachable paths with `--add-dir` instead of relying on a deny it cannot state. Refusing the Copilot backend is not acceptable, and the residual risk is not silently accepted: `sdd doctor` lists which deny entries are enforced by flag and which by path narrowing, and exits non-zero if any entry is covered by neither.
4. **Question:** `run_task` currently uses `--permission-mode bypassPermissions` (full shell, including gradle and git). What is the Copilot-side equivalent for `implement` — blanket `--allow-all-tools`, or an explicit allow list `read,edit,write,shell` combined with denies for destructive commands (`git push --force`, `rm`)? Must the two backends have identical effective permission breadth, or is the Copilot path allowed to be stricter (which would make T1's "no behaviour change" claim backend-dependent)?
   - **Answer:** Not `--allow-all-tools`. The Copilot `implement` mode uses an explicit allow list (`read,edit,write,shell`) plus the denies derived from `deny-list.txt`, including destructive shell commands (`git push --force`, `rm`). The two backends are therefore deliberately *not* identical in permission breadth: the Copilot path is stricter. T1's "no behaviour change" claim is scoped to the Claude backend only and §5 / §7 are worded accordingly.
5. **Question:** What should the driver do when the installed Copilot CLI rejects a flag the design depends on (`--agent`, `-s`, `--allow-tool`/`--deny-tool`) or produces no parseable `VERIFY:` line? Options: fail fast with a clear error and leave the front matter untouched, keep today's `cmd_verify` behaviour of writing `verify: failed` on an inconclusive run, or degrade by inlining the agent body into the prompt instead of using `--agent`.
   - **Answer:** Infrastructure failure and spec failure are separated. If the installed CLI rejects a required flag, or the process fails before producing output, the driver fails fast with a clear error and leaves the front matter **untouched** (today's code wrongly records `verify: failed` for this case). Only a run that actually completed but produced no parseable `VERIFY:` line keeps the current behaviour of writing `verify: failed`. No silent degradation to prompt-inlining: `--agent` is required, and a pre-flight capability probe in `sdd doctor` reports flag support up front.
6. **Question:** How exactly should `SDD_AGENT=auto` resolve, and should the missing-CLI behaviour be unified? Today `cmd_align` degrades to a printed manual protocol and exits 0, while `cmd_verify`/`cmd_fix_ktlint` exit 1. Should `auto` only check for the binary, or also fall back to `copilot` when `claude` is present but unauthenticated/quota-exhausted at runtime — and should the manual-protocol fallback survive in the driver layer for all four commands or be dropped?
   - **Answer:** `auto` resolves by binary presence only (`claude` first, then `copilot`); no runtime fallback on auth or quota failure, because switching backends mid-flow hides the real problem and changes which model wrote the spec without the user knowing. Missing-CLI behaviour is unified to exit 1 across all four commands — `cmd_align`'s current exit 0 is treated as a bug fixed by this refactor. The manual-protocol text survives, but as part of the error path (printed before the non-zero exit) for all four commands rather than as a success path for `align` alone.
7. **Question:** How strictly should `.github/agents/` drift be enforced? §7 only requires `sdd doctor` to exit non-zero on drift. Should the Copilot driver additionally refuse to run (or auto-regenerate) on drift, and is any CI check or git pre-commit hook in scope for this spec, or explicitly out of scope?
   - **Answer:** `sdd doctor` exits non-zero on drift; the Copilot driver prints a warning naming the stale files but still runs, and never auto-regenerates (a silent rewrite during `implement` would mix generated output into a task's diff). CI checks and git hooks are explicitly out of scope and are added to the §3 Excluded list.
8. **Question:** What language should the new/neutralised user-facing strings use? The script currently mixes Turkish ("Claude Code CLI bulunamadı") and English, and T10 removes a Turkish README note. Should T2/T9/T10 standardise all `sdd` output, `doctor` output and README on English, keep Turkish for user-facing errors, or leave existing strings untouched except for the tool name?
   - **Answer:** Every new or touched string in `sdd` and `doctor` is English, matching CLAUDE.md, the agent definitions and the rest of the script. Strings this refactor does not otherwise touch are left alone — no sweeping translation pass. `README.md` stays Turkish (it is the human-facing document); only its content is updated per T10.

## 10. Deviations from CLAUDE.md

- **§9 requires every spec to declare affected layers, DTO/entity contracts and
  environment/flavour notes.** This refactor touches only the SDD tooling (`scripts/`,
  `.claude/agents/`, `.github/`), not `app/`, so all three are inapplicable for the same reason:
  there is no data/domain/presentation layer, no Hilt scope and no Request/Response contract to
  state, and nothing is built, signed or shipped per flavour — the changed files are developer
  tooling that never enters an APK, so `dev`/`prod` behave identically. The real "contracts" of
  this change are the CLI invocation surface and the front-matter fields, documented in §3.
  Nothing in CLAUDE.md §1–§8 is weakened: the Copilot backend loads the same `CLAUDE.md`, so the
  rules the agents enforce are unchanged.
- **§9.1 makes `./gradlew checkCodeQuality assembleDevDebug` the `active -> done` gate; this
  spec cannot satisfy it, and substitutes shell and round-trip checks instead (§7).** Neither
  task exists in this project: `checkCodeQuality` is not defined anywhere in the build, there is
  no `dev` flavour (only `debug`/`release`), and no ktlint plugin is applied, so `sdd fix-ktlint`
  has no `app:ktlint` task either. Verified by running the command with this branch's changes
  stashed — it fails identically, so the failure is pre-existing and unrelated to this refactor.
  More broadly, most of the CLAUDE.md "non-negotiable - verified" stack (Java 17, compileSdk 35 /
  minSdk 23 / targetSdk 35, Hilt, RxJava2, Retrofit+Gson, Timber, PaperDB) is absent from
  `app/build.gradle.kts` and `gradle/libs.versions.toml`; the app is still a bare Compose
  skeleton on Java 11 / SDK 36. Closing that gap is spec 003, not this one. Consequence to be
  aware of: `./scripts/sdd done` shells out to the same gradle command, so it cannot be used to
  close this spec until 003 lands - `status: done` is set by hand here, with the §7 criteria
  above standing in as the evidence.

- **§9.1 requires a Test Plan, but `specs/templates/refactor.md` has no such section.** This spec
  adds `## 8. Test Plan` and shifts the following sections to §9–§11. The template itself is
  deliberately left untouched (out of scope per §3); if the gap should be fixed at the template
  level, that is a separate spec.

## 11. Changelog

| Date | Status | Change |
|------|--------|--------|
| 2026-09-13 | draft | Refactor planned; P1–P3 settled with the user up front |
| 2026-09-13 | ready | Mandatory sections filled |
| 2026-09-13 | ready | `sdd align` raised 8 decisions; all answered. §3/§5/§6/§7/§8 updated to match — two breaking changes now declared in §5 (D5, D6) |
| 2026-09-13 | ready | verify FAIL: D2/D3 labels collided with the pre-align decisions. Pre-align set relabelled P1–P3; §10 extended with the flavour and Test-Plan-section justifications |
| 2026-09-13 | ready | verify FAIL: §5 declared two breaking changes that no task implemented. §6 rewritten to 12 tasks — D6 and D5 are now T3 and T4 — plus acceptance criteria for T9/T12 and a corrected §9 labelling note |
| 2026-09-13 | ready | verify FAIL: the driver-side drift warning (D7) was asserted in §7 but tasked nowhere — folded into T5. §3 now cites the Copilot docs it relies on and states the untested-flags risk explicitly |
| 2026-09-13 | ready | Hotfix to `scripts/sdd`: `cmd_verify` now requires the wrapper session to relay the subagent's `VERIFY:` line verbatim — it was summarising the verdict away, so a genuine PASS was recorded as `verify: failed`. Permanently addressed by T4 |
| 2026-09-13 | ready | verify FAIL: renumbering leftovers — D1's answer still named T3 as the Copilot-install precondition (now T5), and the §9 note wrongly claimed D1 is never cited by label |
| 2026-09-13 | active | T1 implemented: added `run_agent <agent> <mode> <model> <prompt>` (modes `edit`/`full`/`readonly`) to `scripts/sdd` and routed `cmd_align`, `run_task`, `cmd_verify`, `cmd_fix_ktlint` through it; Claude driver stays inline, prompts/flags/exit codes/front-matter writes unchanged |
| 2026-09-13 | active | T1 done. Gradle gate found unsatisfiable: `checkCodeQuality`, the `dev` flavour and the ktlint plugin do not exist in this project. §7 criterion replaced with shell/round-trip checks, justified in §10; the build-vs-CLAUDE.md gap is deferred to spec 003 |
| 2026-09-13 | active | T2 implemented: moved the Claude driver out of `scripts/sdd` into `scripts/lib/driver-claude.sh` (`driver_claude_available`, `driver_claude_run_agent`); added `SDD_AGENT` (`claude\|copilot\|auto`, default `auto`) resolved by binary presence only via `resolve_agent_backend`, no runtime fallback (D6); replaced the 3 Turkish "Claude Code CLI bulunamadı" strings with a neutral English "no agent CLI found" message naming the checked backend(s); a `copilot` resolution fails clearly as "driver not implemented yet (T5)" rather than faking support. `cmd_align`'s exit-0 manual-protocol fallback is unchanged (still T3's job) — only its wording is now neutral/English. Verified `bash -n` on `scripts/sdd` and `scripts/lib/*.sh`, and confirmed the Claude backend's exit codes/messages are unaffected with `claude` present |
| 2026-09-13 | active | T2 done. Testing T2's exit codes surfaced a third bug in the same family as D5/D6: `cmd_align` resets `alignment`/`verify` to `pending` before checking that a backend exists, so a no-op run invalidates a passing verify. Folded into T3 with a criterion and a test |
| 2026-09-13 | active | T3 implemented: `cmd_align` now resolves the agent backend *before* touching the spec (skeleton insert + `alignment`/`verify: pending` writes moved after the check), so a no-CLI run leaves the file byte-identical and exits 1 instead of resetting front matter and exiting 0. Extracted the align-only manual-protocol text into a shared `print_manual_protocol()`, called from `agent_not_found_message`/`copilot_not_implemented_message` inside `resolve_agent_backend`, so all four agent-backed commands (`align`, `implement`, `verify`, `fix-ktlint`) print it and exit 1 on a missing CLI. Verified with `bash -n`, and manually with both CLIs hidden from `PATH`: `align`/`verify`/`fix-ktlint` each print the protocol and exit 1, and a scratch copy of spec 001's front matter diffs byte-identical before/after the failed `align` run |
| 2026-09-13 | active | T4 implemented: `driver-claude.sh`'s `readonly` branch dropped the unconditional `\|\| true` after `claude -p ... \| tee`, so `driver_claude_run_agent` (and `run_agent`, unchanged) now returns the real exit status of the `claude` invocation instead of always reporting success (pipefail, already set in `scripts/sdd` and sourced into this file, makes the pipeline's status the `claude` process's status even through `tee`). `cmd_verify` now guards the `run_agent` call with `if ! run_agent ...; then ...; fi`: on non-zero it prints a distinct infrastructure-failure message, removes the temp file, and exits 1 without calling `fm_upsert`/`fm_set`, leaving the front matter byte-identical; on zero it keeps the existing PASS/FAIL/inconclusive-as-FAIL logic verbatim. Verified with `bash -n` on `scripts/sdd` and `scripts/lib/*.sh`, and empirically on a scratch copy of spec 001 with `claude` installed: (1) `SDD_MODEL_VERIFY=this-model-does-not-exist sdd verify` — `claude` rejects the model, `sdd` prints the new infrastructure-failure message, exits 1, and the spec file's md5/diff is byte-identical before/after (D5); (2) an unmodified run genuinely completed with `VERIFY: FAIL` and still wrote `verify: failed` correctly; (3) a run whose prompt was swapped for one that never emits a `VERIFY:` line still completed successfully and still wrote `verify: failed` (the unparseable-but-completed carve-out, unchanged) |
| 2026-09-13 | active | T6 implemented: replaced the top-level `SDD_MODEL_ALIGN/IMPLEMENT/VERIFY/KTLINT` literal-default assignments with two new functions in `scripts/sdd` — `model_default <role> <backend>` (a case-table encoding §3's mapping: `align`→`opus`/`claude-opus-5`, `implement`/`verify`→`sonnet`/`claude-sonnet-5`, `ktlint`→`haiku`/`claude-haiku-4.5`; case table used instead of an associative array since the shipped macOS bash is 3.2) and `model_for_role <role> <backend>` (returns the role's `SDD_MODEL_*` env var if set, else `model_default`). `run_agent`'s third argument changed from a pre-resolved model literal to a role name (`align`/`implement`/`verify`/`ktlint`); it now calls `model_for_role "$role" "$backend"` itself after resolving the backend, so the four call sites (`cmd_align`, `run_task`, `cmd_verify`, `cmd_fix_ktlint`) now pass a role string instead of `"$SDD_MODEL_*"`. The `copilot` half of `model_default`'s table is data only — `resolve_agent_backend` cannot return `"copilot"` yet (T5 not implemented), so those branches are unreachable today and ready for T5 to start exercising; no copilot dispatch logic was added, matching T5's boundary. Verified with `bash -n` on `scripts/sdd` and `scripts/lib/*.sh`; sourced the script to confirm `model_for_role` returns the correct default for all 4 roles × 2 backends and that an `SDD_MODEL_VERIFY` override still wins; ran a live `sdd verify` against a scratch copy of spec 001 with the Claude backend (as in T1–T4's precedent) — dispatched with the `sonnet` default, completed, and wrote `verify: failed` correctly for a genuine FAIL verdict. `git status --short` shows only `scripts/sdd` changed |
| 2026-09-13 | active | T7 implemented: added `sdd sync-agents` to `scripts/sdd`, plus helper functions `agent_fm_get` (frontmatter-block-scoped field reader, unlike the body-unaware `fm_get`), `agent_body` (verbatim body after the closing `---`), `translate_tools` (Claude→Copilot tool-name mapping from §3: `Read`→`read`, `Grep`/`Glob`→`search` deduplicated, `Edit`→`edit`, `Write`→`write`, `Bash`→`shell`), `sync_one_agent` and `cmd_sync_agents`. For each `.claude/agents/*.md`, it emits `.github/agents/<name>.agent.md` with `name`/`description`/`tools` translated, a `GENERATED — do not edit by hand` banner naming the source file and the regeneration command, and the body copied verbatim; `model:` and `color:` are dropped entirely — never emitted — per D2. Wired into `main()`'s dispatcher and `usage()`. Verified with `bash -n` on `scripts/sdd` and `scripts/lib/*.sh`; ran `sdd sync-agents` to generate all four `.github/agents/*.agent.md` from the four existing `.claude/agents/*.md`, confirmed `grep -n '^model:\|^color:' .github/agents/*.agent.md` matches nothing, confirmed each file's `tools:` line matches the mapping (e.g. `sdd-verify.agent.md` → `read, search` only, `sdd-implement.agent.md` → `read, search, edit, write, shell`), and confirmed idempotency by running it twice with `git add -A` in between — `git status --short` was identical before and after the second run. `git status --short` shows only `scripts/sdd` (modified) and the four new `.github/agents/*.agent.md` files (added) — nothing under `app/`, `specs/templates/` or the CLAUDE.md §9.1 lifecycle touched |
| 2026-09-13 | active | T8 implemented: rewrote the "How you are launched" section in all four `.claude/agents/*.md` bodies so none of them names Claude Code or its Task tool as the only dispatch path. `sdd-align.md`, `sdd-implement.md` and `sdd-verify.md` had an existing section that hardcoded "calls the main Claude session ... Claude Code dispatches to you via the Task tool" — each is now phrased as "dispatches you through whichever agent CLI backend is active (`SDD_AGENT=claude` or `SDD_AGENT=copilot`)", followed by one sentence naming both concrete mechanisms (the `Use the <agent> subagent ...` prompt routed through a subagent tool on Claude, the `--agent <agent>` flag on Copilot) so the wording stays accurate rather than vague. `kotlin-ktlint.md` had no such section at all (it is dispatched by `cmd_fix_ktlint`'s `run_agent` call the same as the other three, so the omission was an inconsistency, not a deliberate exclusion) — added one in the same tool-neutral phrasing, placed after the agent's one-line role summary and before `## Input`. No other section of any of the four files was touched. Re-ran `./scripts/sdd sync-agents`, which regenerated all four `.github/agents/*.agent.md` files with the new body wording (bodies are copied verbatim by T7's generator, frontmatter unaffected). Verified with `bash -n` on `scripts/sdd` and `scripts/lib/*.sh`; `grep -n "How you are launched" -A5` on the regenerated `.github/agents/*.agent.md` files confirms the new wording landed; `git status --short` shows exactly the four `.claude/agents/*.md` files and the four `.github/agents/*.agent.md` files as modified — nothing under `app/`, `specs/templates/` or the CLAUDE.md §9.1 lifecycle |
