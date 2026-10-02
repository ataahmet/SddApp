# Specification-Driven Development for Android

Claude Code CLI or GitHub Copilot CLI, a plugin-free, terminal-first SDD flow. The `SDD_AGENT`
environment variable selects which CLI is used (see "Backend Selection — SDD_AGENT" below).

## Setup

### 1. Requirements

```bash
# skip if git is already installed
brew install git                                   # macOS

# Claude Code CLI (used by align/implement/verify commands)
curl -fsSL https://claude.ai/install.sh | bash     # recommended (does not require Node)
# alternatives:
#   brew install --cask claude-code
#   npm install -g @anthropic-ai/claude-code       # Node 22+ ister

claude --version        # should be up to date
claude doctor           # diagnose installation/configuration
```

This kit uses the `claude` CLI's `--agent`, `--tools`, and `--permission-mode` flags;
Claude Code **v2.1.x** and above is required.

1. Type `claude` in the terminal (the current version is recommended).

2. Sign in: `/login` inside the CLI, or direct `claude auth login`.
   This is enough to do once during the day; you can check with `claude auth status`.

3. After login succeeds, you can close the CLI or leave it running in the background.

4. In the terminal where you will run the `scripts/sdd` commands, use this session.

*CI/pipeline:* instead of interactive login, generate a long-lived token with `claude setup-token`.

### 2. GitHub Copilot CLI (second backend)

```bash
npm i -g @github/copilot     # requires Node
copilot --version
copilot                      # prompts for GitHub sign-in on first launch
```

For detailed installation/authentication steps, see GitHub's official documentation:
<https://docs.github.com/en/copilot/how-tos/copilot-cli>.

**Status note:** The selection logic for this backend (`SDD_AGENT`, model tables, below) is implemented
in `scripts/sdd`, but the actual Copilot driver (`scripts/lib/driver-copilot.sh`) is not yet
written — spec `002-copilot-cli-agent-support` T5. Even if `copilot` is installed today, running
`SDD_AGENT=copilot` (or `SDD_AGENT=auto` when `claude` is missing) will stop with a clear error
and **exit 1**, without touching the command's front matter:

```
SDD_AGENT resolved to 'copilot', but the Copilot CLI driver is not implemented yet
(scripts/lib/driver-copilot.sh, spec 002 T5). Install 'claude', or set SDD_AGENT=claude.
```

Once the driver is complete, this note will be removed; until then, keep `claude` installed.

### 3. Backend Selection — SDD_AGENT

`scripts/sdd` routes all agent calls (`align`, `critique`, `implement`, `verify`, `fix-ktlint`) through a
single driver choice; the environment variable `SDD_AGENT` selects which CLI is used:

| Value | Behavior |
|-------|----------|
| `claude` | Looks for only the `claude` CLI; otherwise prints an error and exits 1 |
| `copilot` | Looks for only the `copilot` CLI; the driver is not implemented yet (see above) |
| `auto` (**default**) | Checks `claude` first, otherwise `copilot` — only checks whether either is on PATH |

The selection checks only whether the binaries are on PATH; it does not automatically switch to
another backend for runtime authentication/quota issues — this is a deliberate design choice to
avoid ambiguity over which model wrote the spec. If no CLI is found, all four commands print the
manual protocol and stop with **exit 1** (see the "Breaking Changes" note below, including `align`).

```bash
SDD_AGENT=claude  ./scripts/sdd verify <spec>   # explicitly use Claude
SDD_AGENT=copilot ./scripts/sdd verify <spec>   # explicitly use Copilot (once the driver is complete)
./scripts/sdd verify <spec>                     # SDD_AGENT=auto (default)
```

## Folder Structure

```
project-root/
├── CLAUDE.md                      #  project architecture rules (tool-independent, single source)
├── .claude/                       # Claude Code backend
│   ├── settings.json              # project permissions; `deny` is GENERATED from deny-list.txt
│   └── agents/                    # agent definitions — the SINGLE SOURCE edited by hand
│       ├── sdd-align.md           # used by `sdd align`
│       ├── sdd-critique.md        # used by `sdd critique` (reviewer half)
│       ├── sdd-refine.md          # used by `sdd critique` (executor half)
│       ├── sdd-implement.md       # used by `sdd implement`
│       ├── sdd-verify.md           # used by `sdd verify`
│       └── kotlin-ktlint.md       # used by `sdd fix-ktlint`
├── .github/                       # GitHub Copilot CLI backend
│   ├── copilot-instructions.md    # thin pointer: @CLAUDE.md + spec-first rule
│   └── agents/                    # GENERATED — do not edit; run `sdd sync-agents`
│       ├── sdd-align.agent.md
│       ├── sdd-critique.agent.md
│       ├── sdd-refine.agent.md
│       ├── sdd-implement.agent.md
│       ├── sdd-verify.agent.md
│       └── kotlin-ktlint.agent.md
├── scripts/
│   ├── sdd                        # ana CLI script (chmod +x)
│   └── lib/
│       ├── critique.sh           # critique-to-action loop (sdd critique)
│       ├── driver-claude.sh       # Claude Code backend driver
│       ├── driver-copilot.sh      # Copilot CLI backend driver (T5 — not implemented yet)
│       └── deny-list.txt          # single source for secret-file/command denies
└── specs/
    ├── templates/
    │   ├── feature.md
    │   ├── bug.md
    │   ├── test.md
    │   └── refactor.md
    ├── features/
    │   └── 001-kullanici-girisi/
    │       └── spec.md
    ├── bugs/
    ├── tests/
    └── refactors/
```

After setup, run once: `chmod +x scripts/sdd`.

## Commands

> **Flow order:** `new → ready → align → align-resolve → critique → verify → start → implement → done`

First task: `./scripts/sdd doctor` — CLI, session, agent files

### Create a New Spec

```bash
./scripts/sdd new feature "User Dashboard"
./scripts/sdd new bug "Looping Token Refresh"
./scripts/sdd new test "Login Module Coverage"
./scripts/sdd new refactor "Convert Repository to Flow"
```

This command:
1. Creates `specs/{type}s/{task_id}-{task_name}/spec.md` — **it asks you for the `task_id`**
   (press Enter to use the next number by default)
2. Copies the template and fills in the front matter (`status: draft`)
3. **Does not create a branch** — the branch is created in the `sdd start` step

### Ready Gate — draft → ready

```bash
./scripts/sdd ready specs/features/{task_id}-{task_name}/spec.md
```

This checks the following sections and stops the transition if they are empty:
1. **§1 Goal / Problem / Motivation**
2. **Acceptance Criteria** — at least one item
3. **Test Plan** — (if the section exists)

Comments (`<!-- … -->`), empty bullets (`-`), empty checkboxes (`- [ ]`), and `{placeholder}` are
not considered "filled". `start` only works on a `ready` spec.

### Alignment — Questions + Answers

```bash
./scripts/sdd align specs/features/{task_id}-{task_name}/spec.md
```

This command runs in two stages, **without opening a chat window**:

1. **Step 1 — Question generation (headless):** the `sdd-align` agent runs with `claude -p`,
   reads the spec and CLAUDE.md rules, generates open decisions/questions, and writes them to the
   spec's `## Open Decisions (Alignment)` section.

2. **Step 2 — Answer collection (terminal):** the Bash script prints the questions written by the
   agent one by one in the terminal and reads your answers with `read`. It writes the answers to
   the spec, then calls `align-resolve` and sets `alignment: resolved`.

```
→ Alignment (step 1/2): generating questions ...
  5 questions generated.
→ Alignment (step 2/2): answer the questions in the terminal (empty = skip)
────────────────────────────────────────
  1. Agent question?
  →  Answer: Developer answer
  2. Agent question
  →  Answer: Developer answer
────────────────────────────────────────
✓ All alignment questions answered → alignment: resolved (2/2).
```

If the terminal is not interactive (CI, etc.), the script still generates the questions but does
not ask for answers; fill them in manually and run `./scripts/sdd align-resolve <spec>`.

### Close Alignment — align-resolve

Normally, `sdd align` calls this automatically. If you filled in the answers manually or changed
them later:

```bash
./scripts/sdd align-resolve specs/features/{task_id}-{task_name}/spec.md
```

If any answer is missing, it stops and prints **which question** is empty. `start`/`implement` will
not work until `alignment: resolved` is set.

### Critique — Critique-to-Action Loop (required gate)

```bash
./scripts/sdd critique specs/features/{task_id}-{task_name}/spec.md
./scripts/sdd critique <spec> --rounds 6 --threshold 8
```

An adversarial review loop modelled on ARIS (arXiv:2605.03042 §2.2). It runs on an **aligned**
spec — `alignment: resolved` is a precondition — and each round does four things:

1. **Review.** The `sdd-critique` agent runs read-only (`--tools "Read,Grep,Glob"`), scores the
   spec on a 5-axis rubric, and returns severity-tagged action items. It is handed the spec
   *path*, never a summary: summarising first would have it grade the executor's framing instead
   of the artifact.
2. **Arbitration.** As soon as the reviewer reports `CRITICAL=0 MAJOR=0` with a passing score,
   the real `sdd-verify` agent runs as the round's final arbiter. **The loop exits only on
   `VERIFY: PASS`.** A FAIL is not a dead end — its findings become the next round's action
   items, so the same zero-tolerance bar that blocks `start` is enforced *inside* the loop
   rather than discovered after it.
3. **Action.** The `sdd-refine` agent applies the items to the spec. It has no `Write` or `Bash`
   tool and is explicitly forbidden from filling in or rewriting any `- **Answer:**` line and
   from editing the front matter — alignment answers and front-matter fields belong to you, not
   the agent. It reports what it applied, and how many items it had to skip because they live
   in one of those places (`REFINE: USER_OWNED=n`); any such item stops the loop.
4. **Convergence check.** Exit when score ≥ threshold, zero CRITICAL, zero MAJOR, and verify
   PASSes; otherwise run another round, up to the cap. A blocking item that comes back at the
   same location after the executor's turn without the score improving (or that survives
   three rounds) is a **stall** and also stops the loop — another round would only re-raise it.

The verdict in the Critique Log is the **script's**, re-derived from the reviewer's counts. The
reviewer also prints its own `VERDICT` line; when the two disagree (say `CONVERGED` with
`MAJOR=2`), the loop warns and records its own.

```
→ Critique-to-action loop  (claude)
    reviewer : gpt-4o   (gpt)
    executor : sonnet   (claude)
    rounds   : max 4        threshold: >= 6/10, 0 critical, 0 major
    context  : fresh           scope: spec-only
    exit gate: reviewer rubric + sdd-verify PASS

════════════════ round 2 / 4 ════════════════
  score=7/10  critical=0  major=0  verdict=CONVERGED
→ Reviewer satisfied — running the verify gate as final arbiter ...
  ✗ VERIFY: FAIL — feeding its findings back into the loop.
→ Applying verify findings with sdd-refine (sonnet) ...
════════════════ round 3 / 4 ════════════════
  score=9/10  critical=0  major=0  verdict=CONVERGED
  ✓ VERIFY: PASS
✓ Converged: score 9/10, no critical/major items, and verify passed.
```

**Outcomes** (written to the `critique:` front-matter field):

| Value | Meaning | What to do |
|-------|---------|------------|
| `converged` | Rubric cleared **and** verify PASSed | `verify: passed` is written too → go straight to `sdd start` |
| `needs_user` | No agent in the loop may make the next change: the reviewer flagged a decision you own, the executor skipped an answer-line / front-matter item, or an item stalled | Read the report the loop names (`round-N.md` or `round-N-refine.md`), edit the answer lines / front matter by hand, re-run `sdd critique`. Do **not** re-run `sdd align` — it clears every answer |
| `max_rounds` | Cap reached without convergence | Read the last report (and `round-N-verify.md`), fix by hand, re-run |
| `failed` | The reviewer or the in-loop verify could not produce a usable result (CLI failure, or verify printed no `VERIFY:` line twice) | Fix the CLI / read `round-N-verify.md`, re-run |
| `skipped` | You deliberately released the gate | Justify it under "Deviations from CLAUDE.md" |
| *(absent)* | Spec predates this gate | Not blocked — backwards compatible |

**Ledger.** Every round writes `<spec-dir>/critique/round-N.md` (reviewer), every arbitration
writes `round-N-verify.md`, and every executor turn writes `round-N-refine.md`. The spec's
`## Critique Log` gets one row per step: `N` for the reviewer, `N v` for the verify gate and
`N r` for the executor (`APPLIED= USER_OWNED= UNRESOLVED=`). A standalone `sdd verify` keeps
its report in `<spec-dir>/verify/verify-<timestamp>.md`. Rejected directions stay on the
record, so a later run does not re-propose them.

Every run numbers its rounds from 1, so a re-run of `sdd critique` first moves the previous
run's `round-*.md` files into `critique/run-<timestamp>/`, repoints the older Critique Log rows
at that folder, and adds a `new run` separator row. The cross-round reviewer therefore only
ever sees the current run's reports.

**Cross-family review.** ARIS's first design principle is that reviewer and executor should not
share a model family — a same-family pair shares its blind spots. Here that is a **model-level**
choice resolved by `model_for_role`, so no second CLI is needed:

```bash
SDD_MODEL_CRITIQUE=gpt-4o ./scripts/sdd critique <spec>   # reviewer: gpt, executor: claude
```

The loop prints the family of each half and warns (never fails) when both land in the same one.
Make it the default by changing the `critique:claude` row in `model_default` inside `scripts/sdd`.

**Tunables:**

| Variable | Default | Effect |
|----------|---------|--------|
| `SDD_CRITIQUE_ROUNDS` / `--rounds` | `4` | Round cap |
| `SDD_CRITIQUE_THRESHOLD` / `--threshold` | `6` | Score needed out of 10 |
| `SDD_CRITIQUE_VERIFY` | `1` | `0` drops the in-loop verify arbiter (faster; `sdd verify` can then still FAIL on a converged spec) |
| `SDD_CRITIQUE_CONTEXT` | `fresh` | `cross-round` lets the reviewer read its earlier reports and confirm items were addressed |
| `SDD_CRITIQUE_SCOPE` | `spec-only` | `repo` lets the reviewer check the spec's contracts against the actual codebase |
| `SDD_MODEL_CRITIQUE` / `SDD_MODEL_REFINE` | `opus` / `sonnet` | Model per half |

> **Re-running `sdd align` resets `critique` to `pending`** — new questions mean the reviewed
> artifact no longer exists, so an earlier convergence no longer describes it.

### Verify (required gate)

```bash
./scripts/sdd verify specs/features/{task_id}-{task_name}/spec.md
```

The `sdd-verify` agent runs in read-only mode (`--tools "Read,Grep,Glob"`), compares the spec
against CLAUDE.md, and prints `VERIFY: PASS` / `VERIFY: FAIL` on the first line. The script
captures this verdict, writes `verify: passed` / `verify: failed` to the front matter, and keeps
the full report in `<spec-dir>/verify/verify-<timestamp>.md`.

Verify judges the spec's **content** only. The lifecycle fields the script writes (`status`,
`alignment`, `verify`, `critique*`, `updated`, …) and the `## Critique Log` are out of its
scope: `sdd start` / `sdd implement` enforce those gates themselves, and inside `sdd critique`
the front matter reads `critique: pending` by design while verify runs as the arbiter. A verify
report that FAILs on those fields is a tool bug, not something to fix in the spec.

**`verify: passed` is required before `start` and `implement` run.** If the agent finds a
contradiction or even a minor ambiguity, it returns FAIL; clarify the issue and rerun. If
`sdd align` runs again, the spec changes and `verify` returns to `pending`.

> **Running it standalone is usually redundant.** `sdd critique` runs this same agent as its
> arbiter and writes `verify: passed` on success, so a converged spec arrives here already
> green. Run `sdd verify` by itself when you edited the spec by hand after the loop, or when
> you used `SDD_CRITIQUE_VERIFY=0`.

### Start a Branch (start)

```bash
./scripts/sdd start specs/features/{task_id}-{task_name}/spec.md
```

1. `git checkout -b main/{task_id}-{task_name}`
2. Fills in the `branch:` field in the spec front matter
3. Sets `status: active`

> **Note:** If a branch named `main` already exists, Git cannot create the `main/...` ref. In that
> case, use `SDD_BRANCH_PREFIX=feature ./scripts/sdd start …` (or update the CLAUDE.md §9.1 rule).

> **Gates:** `alignment: resolved` + `critique: converged` + `verify: passed` are required
> before branch creation. The order is always `align → critique → verify → start`.

### Implement Tasks

```bash
./scripts/sdd implement specs/features/{task_id}-{task_name}/spec.md T3
```

If no task is given, all tasks in `## Task List` are applied in sequence.

By default, it runs headless (`claude -p --agent sdd-implement`). If you want to watch the agent
and intervene:

```bash
SDD_IMPLEMENT_INTERACTIVE=1 ./scripts/sdd implement <spec> T3
```

> **Commit format (CLAUDE.md §9.1):** `[{CODE}-{task_id}] {task} – short description` + in the
> body: `Spec: specs/{type}s/{task_id}-{task_name}/spec.md`. CODE: feature→`FEAT`, bug→`BUG`,
> refactor→`REF`, test→`TEST`. `sdd implement` prints the correct command when it finishes.
> The agent does not create the commit; you do.

### List

```bash
./scripts/sdd list              # all (with status + alignment + verify columns)
./scripts/sdd list feature
./scripts/sdd list bug
```

### Fix ktlint (fix-ktlint)

```bash
./scripts/sdd fix-ktlint                  # default: ./gradlew app:ktlint
./scripts/sdd fix-ktlint checkCodeQuality # use a different Gradle task
```

1. Runs `./gradlew app:ktlint` and collects the violations
2. Extracts the `.kt` files containing violations (if there are no violations, it prints "clean")
3. Sends the file list + violations to the `kotlin-ktlint` agent; the agent only fixes style/format
   (it has no Bash tool, does not touch business logic, and does not create new files)

It is not part of the lifecycle; it can be called at any stage.

### Status Transitions

```bash
./scripts/sdd ready          <spec.md>          # draft → ready (required section gate)
./scripts/sdd align          <spec.md>          # generate/ask alignment questions (interactive)
./scripts/sdd align-resolve  <spec.md>          # all answers filled? → alignment: resolved
./scripts/sdd critique       <spec.md>          # required gate → critique: converged (loop)
./scripts/sdd verify         <spec.md>          # required gate → verify: passed/failed
./scripts/sdd start          <spec.md>          # ready → active (+branch)
./scripts/sdd done           <spec.md>          # quality gates + active → done
./scripts/sdd block          <spec.md> "reason" # → blocked
./scripts/sdd drop           <spec.md> "reason" # → dropped
./scripts/sdd doctor                            # environment check
```

## Typical Workflow

```bash
# 0. Environment check (once after initial setup)
./scripts/sdd doctor

# 1. Start a new feature (status: draft, no branch)
./scripts/sdd new feature "Biometric Login"

# 2. Open the spec in an editor and fill in Goal / Scope / Acceptance Criteria
$EDITOR specs/features/001-biometric-login/spec.md

# 3. Required section gate: draft → ready
./scripts/sdd ready specs/features/001-biometric-login/spec.md

# 4. Alignment: the agent generates questions, asks you, writes the answers, and resolves them
./scripts/sdd align specs/features/001-biometric-login/spec.md

# 5. Required gate: adversarial review loop until the rubric AND verify are clear
SDD_MODEL_CRITIQUE=gpt-4o ./scripts/sdd critique specs/features/001-biometric-login/spec.md

# 5b. Only needed if you hand-edited the spec after the loop (critique writes verify: passed)
./scripts/sdd verify specs/features/001-biometric-login/spec.md

# 6. Commit the spec
git add specs/features/001-biometric-login/
git commit -m "docs(spec): Biometric Login spec"

# 7. Create a branch and start coding (status: active)
./scripts/sdd start specs/features/001-biometric-login/spec.md

# 8. Implement tasks in order
./scripts/sdd implement specs/features/001-biometric-login/spec.md T1
./gradlew checkCodeQuality
git add . && git commit -m "[FEAT-001] T1 – ..." -m "Spec: specs/features/001-biometric-login/spec.md"
# … repeat for each task

# (Optional) fix ktlint violations with the agent
./scripts/sdd fix-ktlint

# 9. Finish: quality gates + status: done
./scripts/sdd done specs/features/001-biometric-login/spec.md
```

## Special Agents (.claude/agents/)

Claude Code **automatically recognizes** agents under `.claude/agents/*.md`; however, they do not
activate on their own — they must be explicitly selected with `--agent <name>`. `scripts/sdd`
makes this selection for you. In an interactive session, you can also invoke them with
`@agent-sdd-verify`.

`.claude/agents/*.md` is the single source of truth; `./scripts/sdd sync-agents` generates the
Copilot-readable `.github/agents/*.agent.md` files from them (front matter is translated, the body
is copied verbatim, and the "GENERATED — do not edit by hand" heading is added). The generated
files intentionally omit the `model:` field — model selection always comes from the driver's
`--model` flag; otherwise, the agent front matter would override `SDD_MODEL_*` settings.

| Agent | Command using it | Model — Claude | Model — Copilot | Env override | Tools (Claude) | Task |
|-------|---------------|-----------------|-------------------|---------------|--------------------|-------|
| `sdd-align` | `sdd align` | `opus` (strongest) | `claude-opus-5` | `SDD_MODEL_ALIGN` | Read, Grep, Glob, Edit, Write, AskUserQuestion, Bash | Generates open decisions, asks the user, and writes the answers |
| `sdd-critique` | `sdd critique` | `opus` (strongest) | `claude-opus-5` | `SDD_MODEL_CRITIQUE` | Read, Grep, Glob | Scores the spec on a 5-axis rubric and returns severity-tagged action items (read-only) |
| `sdd-refine` | `sdd critique` | `sonnet` (mid) | `claude-sonnet-5` | `SDD_MODEL_REFINE` | Read, Grep, Glob, Edit | Applies the reviewer's action items to the spec; cannot write code or answer alignment questions |
| `sdd-implement` | `sdd implement` | `sonnet` (mid) | `claude-sonnet-5` | `SDD_MODEL_IMPLEMENT` | Read, Grep, Glob, Edit, Write, Bash | Implements the single task from the spec according to CLAUDE.md rules |
| `sdd-verify` | `sdd verify` | `sonnet` (mid) | `claude-sonnet-5` | `SDD_MODEL_VERIFY` | Read, Grep, Glob | Compares the spec against CLAUDE.md in a read-only review |
| `kotlin-ktlint` | `sdd fix-ktlint` | `haiku` (cheapest) | `claude-haiku-4.5` | `SDD_MODEL_KTLINT` | Read, Grep, Glob, Edit | Fixes ktlint style/format violations (mechanically) |

Actual model access in Copilot depends on the plan; the Copilot column above shows the intended
mapping once the driver is complete (T5). Environment overrides work with the same names regardless
of the backend — whichever backend is selected, a set `SDD_MODEL_*` value wins; otherwise, the
default in the table is used:

```bash
SDD_MODEL_KTLINT=haiku   ./scripts/sdd fix-ktlint
SDD_MODEL_VERIFY=opus    ./scripts/sdd verify <spec>
SDD_MODEL_CRITIQUE=gpt-4o ./scripts/sdd critique <spec>   # cross-family review
```

On the Claude side, aliases (`opus` / `sonnet` / `haiku`) or a full model ID
(`claude-sonnet-5`) can be used. Spend premium quota only where it adds value (align = strongest);
run mechanical work (ktlint) with the cheapest model.

## Permissions

`.claude/settings.json` defines project-level permissions: `./gradlew` and `./scripts/sdd` are
allowed, `git push/commit/checkout/reset` prompt, and reads of `secrets.properties` /
`local.properties` / keystores are **forbidden**.

```bash
SDD_PERM_IMPLEMENT=acceptEdits ./scripts/sdd implement <spec> T1
```

The `deny` rules apply in every mode; even `bypassPermissions` cannot override them.

## Breaking Changes (Copilot support, spec 002)

When the Copilot backend was added, two deliberate, narrow behavior changes also occurred on the
Claude side:

1. **`sdd align`, if the CLI is missing, now exits 1 (previously exit 0).** Previously, when no
   agent CLI was available, `align` printed the manual protocol and exited successfully (exit 0);
   any script that treated this as "success" must now be updated. The manual protocol text remains
   unchanged; it is only printed on the error path now. In addition, `align` now writes the front
   matter (`alignment`/`verify: pending`) **after**, not before, backend validation — if the CLI is
   missing, the spec file is not modified.
2. **`sdd verify`, on infrastructure failure, no longer writes to the front matter.** A run that
   ends before the command executes (missing binary, a rejected flag such as `--model`, etc.) no
   longer writes `verify: failed`; it leaves the front matter unchanged and returns a non-zero
   exit. In contrast, if the CLI actually runs and completes but its output contains no parseable
   `VERIFY:` line, it continues to write `verify: failed` as before.

Both are behavior changes only on the Claude backend; the Copilot backend is designed to run with
stricter permissions than Claude (see Permissions), so the claim that "behavior stayed the same"
applies only to Claude.

## Slash Commands (interactive session)

When you enter `claude` from the terminal:

```
/sdd-align      specs/features/001-x/spec.md
/sdd-critique   specs/features/001-x/spec.md
/sdd-verify     specs/features/001-x/spec.md
/sdd-implement  specs/features/001-x/spec.md T1
/sdd-fix-ktlint app:ktlint
```

These are convenience commands; **they do not update front matter gates**. To write fields such as
`verify: passed`, run the command through `scripts/sdd`.

## When to Use Spec Types

| Situation | Type |
|-------|-----|
| I am adding new behavior | feature |
| Existing behavior is wrong | bug |
| I am preserving existing behavior | test |
| Behavior is the same but the code structure changes | refactor |
| Cleanup shorter than 1 hour | spec-less commit |

## Tips

**One spec, one type.** For hybrid cases, create two separate specs and link them to each other.

**Keep tasks small.** If a task takes more than 2 days, split the spec.

**Refactors require a test safety net.** If coverage is insufficient, create a test spec before the
refactor.

**Do not restate CLAUDE.md.** In specs, only reference it. If there is a deviation, explain it in
the "Deviations from CLAUDE.md" section.

**Start with a clean session before implementing.** Every `sdd implement` call opens its own
session; start with `/clear` in long conversations.

**Do not bloat CLAUDE.md.** As the content grows, compliance with the rules declines; if a rule
must be added, add it to CLAUDE.md and keep CLAUDE.md limited to imports and Claude-specific notes.

## Limitations

- `sdd align` requires an interactive terminal; it does not work in CI (it prints a manual protocol).
- Changes to CLAUDE.md require team approval — if this is not a solo project.
- Writing specs adds overhead. Do not force it for very small tasks.
- **The alignment gate applies to all types.** All templates contain a `## Open Decisions (Alignment)`
  section, so `start`/`implement` always expects the answers to be filled in.
- **The critique loop costs tokens.** Each round is one reviewer call plus one executor call, and
  a satisfied round adds a verify call on top; four rounds can mean nine agent invocations. Lower
  `--rounds`, or set `SDD_CRITIQUE_VERIFY=0`, on small specs.
- **The reviewer's score is advisory; verify is the real bar.** A high rubric score does not by
  itself release the gate — `critique: converged` additionally requires `VERIFY: PASS`.
- **`critique` is not a substitute for reading the spec.** The loop hardens what is written; it
  cannot tell you the feature itself is the wrong thing to build.
