# Specification-Driven Development for Android

`scripts/sdd` is a terminal-first workflow: every change starts as a spec, an AI agent asks the
open questions, an adversarial review hardens the spec, and only then is code written, one task
at a time. The agents run through the Claude Code CLI or the GitHub Copilot CLI; no IDE plugin is
needed. Run `./scripts/sdd help` for the command summary.

## Setup

### 1. Requirements

| Requirement | Why |
|-------------|-----|
| macOS or Linux, `bash` 3.2 or newer, `git` | `scripts/sdd` is a bash script; it avoids bash 4 syntax and uses no GNU-only tool options, so BSD (macOS) and GNU (Linux) userlands both work. The target project must be a git repository — `sdd start` creates a branch in it |
| An agent CLI: Claude Code (`claude`) or GitHub Copilot CLI (`copilot`) | `align`, `critique`, `verify`, `implement` and `fix-ktlint` dispatch agents through it |
| **JDK 17** | CLAUDE.md pins Java 17, and the Gradle build and ktlint below run on it. `java -version` must print 17 (or point `JAVA_HOME`/`org.gradle.java.home` at it) |
| **Android SDK**, reachable through `local.properties` (`sdk.dir=…`) or `ANDROID_HOME` | `sdd done` and the implement agent run `assembleDevDebug`. `local.properties` is git-ignored, so a freshly cloned project has none: write it, or export `ANDROID_HOME`. On a machine without Android Studio also install `cmdline-tools` and accept the licences (`sdkmanager --licenses`) |
| Network access on the first Gradle run | `./gradlew` downloads its own distribution plus the dependencies; the first `done` is slow and cannot run offline |
| The Gradle tasks listed under [Project prerequisites](#project-prerequisites-gradle) | `implement`, `done` and `fix-ktlint` call them; a new Android project has none of them |
| A UTF-8 locale (recommended) — e.g. `LANG=en_US.UTF-8` | The templates contain non-ASCII characters (`§`, `→`), and some `awk`/`sed` builds handle multibyte input poorly under a `C` locale. macOS Terminal sets UTF-8 already; SSH sessions, cron jobs and CI runners often do not. Spec parsing was not observed to fail under `LC_ALL=C` on macOS, so treat this as a precaution, not a hard requirement |

### 2. Install the kit

The kit is not published as a package: you build a payload from the SDD repository, then install it
into your project.

```bash
git clone <sdd-repo-url> sdd-kit
cd sdd-kit

bash scripts/sdd-artifact                                  # → dist/sdd-artifact/
bash dist/sdd-artifact/install.sh /path/to/your-project
```

The build step writes `dist/sdd-artifact/`: the `install.sh` script plus a `payload/` tree holding
every file listed in `artifact/manifest.txt`. The installer then

- copies the payload into the target repository, creating directories as needed — `CLAUDE.md`,
  `SDD-README.md` (this guide), `.claude/`, `.github/`, `scripts/`, `specs/templates/`;
- appends the four `specs/` rules to the target's `.gitignore` (see [Where specs live](#where-specs-live));
- marks `scripts/sdd` executable.

**It refuses to overwrite.** If the target already has a file from the payload, the install stops
there:

```
Refusing to overwrite existing file: CLAUDE.md
Re-run with --force only if replacing this file is intentional.
```

Most projects already have a `CLAUDE.md`, so this is the usual first outcome. Either move your own
file aside and merge it afterwards, or install with `--force`:

```bash
bash dist/sdd-artifact/install.sh --force /path/to/your-project
```

`--force` also replaces `.claude/settings.json` and `.claude/agents/*.md` — together with
`CLAUDE.md` these are the three things you are expected to customise
(see [6. Adapt CLAUDE.md to your project](#6-adapt-claudemd-to-your-project)). To refresh an
existing installation without losing them, use `--update` instead of `--force`
(see [Updating the kit](#updating-the-kit)).

Check the result from the target project, which must be a git repository (`sdd start` creates a
branch in it):

```bash
cd /path/to/your-project
./scripts/sdd help            # command summary
./scripts/sdd list            # prints the header row, no specs yet
git add CLAUDE.md SDD-README.md .claude .github scripts specs .gitignore
```

### 3. Claude Code CLI

```bash
curl -fsSL https://claude.ai/install.sh | bash     # native installer, macOS/Linux (recommended)
# alternatives:
#   brew install --cask claude-code
#   npm install -g @anthropic-ai/claude-code       # requires Node.js 22 or later

claude --version        # e.g. "2.1.294 (Claude Code)"
claude doctor           # installation and settings diagnostics
```

**Version.** Use **2.1.x or newer**: the SDD runs pass `--permission-mode dontAsk` and
`--allowedTools`, which older CLIs reject (tested from 2.1.270 on). If `claude --version` fails
with `command not found` right after the native installer, add the directory it reported (usually
`~/.local/bin`) to your `PATH` — a fresh Linux shell often does not have it.

Sign in once: run `claude` and follow the browser login (or `claude auth login`); check with
`claude auth status`. On a headless machine (an SSH session, a container, CI) there is no browser:
create a long-lived token on a machine that has one with `claude setup-token`, then export it there
as `CLAUDE_CODE_OAUTH_TOKEN`.

**Trust the project once.** Open `claude` interactively *inside the project directory* and accept
the workspace trust prompt. `scripts/sdd` runs every agent with `claude -p`, which never shows that
prompt. Until the folder is trusted, each run prints
`Ignoring N permissions.allow entries from .claude/settings.json: this workspace has not been trusted`
and the `allow` list in `.claude/settings.json` is not applied. `deny` and `ask` rules apply
either way. The SDD commands still work untrusted, because each run passes the permission mode its
role needs (see [Permissions](#permissions)).

### 4. GitHub Copilot CLI (second backend)

```bash
npm i -g @github/copilot     # requires Node
copilot --version
copilot                      # prompts for GitHub sign-in on first launch
```

See <https://docs.github.com/en/copilot/how-tos/copilot-cli>. The Copilot driver
(`scripts/lib/driver-copilot.sh`) is implemented. Every role runs with model `auto`, because the
Copilot CLI rejected the named models it was tested with; set `SDD_MODEL_*` to pin one once your
plan exposes it.

### 5. Backend selection — `SDD_AGENT`

| Value | Behavior |
|-------|----------|
| `claude` | Uses `claude`; if it is not on `PATH`, prints an error and exits 1 |
| `copilot` | Uses `copilot`; if it is not on `PATH`, prints an error and exits 1 |
| `auto` (**default**) | Uses `copilot` if it is on `PATH`, otherwise `claude` |

With both CLIs installed, `auto` picks **Copilot**. Because every Copilot role currently runs on model `auto`, pin the backend whenever the per-role model table matters — `SDD_AGENT=claude` per command, or `export SDD_AGENT=claude` once in your shell profile.
Selection checks only whether the binary is on `PATH`; there is no fallback to the other backend on
an authentication or quota error, so it is always clear which model wrote the spec. When no CLI is
found, the command prints a manual fallback protocol and exits 1, pointing at this guide
(`SDD-README.md` in an installed project, `artifact/sdd-usage.md` in the kit repository).

```bash
SDD_AGENT=claude  ./scripts/sdd verify <spec>
SDD_AGENT=copilot ./scripts/sdd verify <spec>
./scripts/sdd verify <spec>                     # SDD_AGENT=auto
```

### 6. Adapt CLAUDE.md to your project

**Do this before the first spec.** The `CLAUDE.md` in the payload carries the reference project's
own architecture rules: Hilt, RxJava2 (`Single`/`Completable`, coroutines forbidden), a PaperDB
`Source` abstraction, Timber, `@ActivityRetainedScoped` feature dependencies, Java 17,
`compileSdk 35`, `minSdk 23`. Every agent in the flow reads that file and enforces it —
`sdd-verify` and `sdd-critique` FAIL a spec that contradicts it, and `sdd-implement` writes code to
match it. On a project with a different stack those rules are simply wrong, and the gates start
failing for the wrong reason.

Rewrite these sections for your project:

| Section | What belongs there |
|---------|--------------------|
| Architecture & Data Flow | Your layer names and the dependency direction between them |
| Technology | Language and JVM target, SDK levels, DI, async, network, UI, storage, logging — what the project actually uses |
| Dependency Injection | Your DI framework, the lifetime each kind of dependency gets, and the forbidden cases |

Keep as it is:

- **§9 Spec-Driven Development** and **§9.1 Spec Lifecycle.** The `scripts/sdd` commands, the status
  values and the gates are described there; rewriting them desynchronises the script, the agents and
  this guide.
- The branch convention — unless you also set `SDD_BRANCH_PREFIX`
  (see [8. Open the branch](#8-open-the-branch--start)).

Two rules of thumb: keep it short, because the longer `CLAUDE.md` gets the less reliably agents
follow it; and write rules as decisions rather than descriptions ("DI: Hilt, Koin forbidden", not
"we mostly use Hilt"). The agent definitions under `.claude/agents/` are stack-independent and
usually need no change; if you do edit one, run `./scripts/sdd sync-agents` afterwards.

## Project prerequisites (Gradle)

`scripts/sdd` and its agents call these Gradle tasks. A new Android Studio project has none of
them, so add them before the first spec, or expect the steps below to fail.

| Task | Called by | What happens when it is missing |
|------|-----------|---------------------------------|
| `checkCodeQuality` | `sdd done`; `sdd-implement` after each task | `done` fails and the spec stays `active`; the implement agent reports the failure |
| `assembleDevDebug` (a `dev` product flavor) | `sdd done`; `sdd-implement` after each task | Same as above |
| `app:ktlint` | `sdd fix-ktlint` (default task) | `fix-ktlint` exits 1 and names the task; pass another one: `./scripts/sdd fix-ktlint app:ktlintCheck` |

`sdd done` always runs `./gradlew checkCodeQuality assembleDevDebug`. A different done check agreed
in a spec (for example under "Deviations from CLAUDE.md") is not used by the script; close such a
spec by hand (see [Finish](#10-finish--done)).

### Creating them

None of the three is a standard Android task, so they have to be defined. This is a minimal way to
get exactly the names `scripts/sdd` expects; adjust the ktlint version, the flavor names and the
test task to your project. In `app/build.gradle.kts` (Kotlin DSL):

```kotlin
// 1 — ktlint through its CLI, wrapped in a task literally called `ktlint`, whose
//     output lines are `path/File.kt:line:col: message` — the format `sdd fix-ktlint` parses.
val ktlintCli: Configuration by configurations.creating

dependencies {
    ktlintCli("com.pinterest.ktlint:ktlint-cli:1.5.0")
}

tasks.register<JavaExec>("ktlint") {
    group = "verification"
    description = "Check Kotlin code style with ktlint"
    classpath = ktlintCli
    mainClass.set("com.pinterest.ktlint.Main")
    workingDir = projectDir
    jvmArgs("--add-opens=java.base/java.lang=ALL-UNNAMED")   // ktlint needs this on JDK 17+
    args("src/**/*.kt", "!**/build/**")
}

tasks.register<JavaExec>("ktlintFormat") {
    group = "formatting"
    description = "Fix what ktlint can fix on its own"
    classpath = ktlintCli
    mainClass.set("com.pinterest.ktlint.Main")
    workingDir = projectDir
    jvmArgs("--add-opens=java.base/java.lang=ALL-UNNAMED")
    args("-F", "src/**/*.kt", "!**/build/**")
}

android {
    // 2 — a `dev` flavor, which is what makes `assembleDevDebug` exist
    flavorDimensions += "environment"
    productFlavors {
        create("dev")  { dimension = "environment"; applicationIdSuffix = ".dev" }
        create("prod") { dimension = "environment" }
    }
}

// 3 — the aggregate gate that `sdd done` and `sdd-implement` run
tasks.register("checkCodeQuality") {
    group = "verification"
    description = "Style + Android lint + unit tests for the dev flavor"
    dependsOn("ktlint", "lintDevDebug", "testDevDebugUnitTest")
}
```

Verify before writing the first spec:

```bash
./gradlew app:ktlint
./gradlew checkCodeQuality assembleDevDebug     # exactly what `sdd done` runs
```

- Run these on a **JDK 17** toolchain (CLAUDE.md requires Java 17 anyway); the `--add-opens` flag
  above is what keeps ktlint working there.
- **Already have ktlint through a plugin** (`ktlintCheck`, `lintKotlin`, …)? Skip part 1 and pass
  your task name instead: `./scripts/sdd fix-ktlint app:ktlintCheck`. `fix-ktlint` only needs a task
  whose output contains `File.kt:line:col`; it fails the gate when ktlint runs on violations, which
  is the expected path.
- **Already have flavors under other names?** Then `assembleDevDebug` does not exist and `sdd done`
  cannot pass as shipped: either add a `dev` flavor, or edit the task list in `cmd_done`
  (`scripts/sdd`) and close such specs by hand.
- `checkCodeQuality` is a plain aggregate — add or drop `dependsOn` entries (detekt, a module test
  task, `connectedCheck`) as you like, but keep the name.

## Where specs live

The installer adds these rules to `.gitignore`:

```text
specs/features
specs/bugs
specs/refactors
specs/tests
```

Specs are therefore local working files: `git add specs/features/...` is refused, and the
`critique/` and `verify/` report folders next to each spec stay local too. The templates under
`specs/templates/` are committed. The commit format still names the spec path in its body, as a
reference to the local file. If your team wants specs under version control, delete those four
lines from `.gitignore` and commit each spec with its code.

## Folder structure

```
project-root/
├── SDD-README.md                  # this guide
├── CLAUDE.md                      # architecture rules (tool-independent, single source)
├── .claude/
│   ├── settings.json              # project permissions; "deny" is GENERATED from deny-list.txt
│   └── agents/                    # agent definitions — the SINGLE SOURCE, edited by hand
│       ├── sdd-align.md           # used by `sdd align`
│       ├── sdd-critique.md        # used by `sdd critique` (reviewer half)
│       ├── sdd-refine.md          # used by `sdd critique` (executor half)
│       ├── sdd-verify.md          # used by `sdd verify` and inside `sdd critique`
│       ├── sdd-implement.md       # used by `sdd implement`
│       └── kotlin-ktlint.md       # used by `sdd fix-ktlint`
├── .github/
│   ├── copilot-instructions.md    # thin pointer: @CLAUDE.md + spec-first rule
│   └── agents/*.agent.md          # GENERATED for Copilot — run `sdd sync-agents`, never edit
├── scripts/
│   ├── sdd                        # the CLI
│   └── lib/
│       ├── critique.sh            # critique-to-action loop
│       ├── driver-claude.sh       # Claude Code driver
│       ├── driver-copilot.sh      # Copilot CLI driver
│       └── deny-list.txt          # single source for secret-file / destructive-command denies
└── specs/
    ├── templates/                 # feature.md, bug.md, refactor.md, test.md (committed)
    └── features/                  # created by `sdd new`, git-ignored (see "Where specs live")
        └── 001-localized-greeting/
            ├── spec.md
            ├── critique/          # round-N.md, round-N-refine.md, round-N-verify.md
            └── verify/            # verify-<timestamp>.md
```

The installer marks `scripts/sdd` executable.

## Lifecycle

```
status:  draft ──→ ready ──→ active ──→ done
                     │          │
                     └─→ blocked / dropped ←─┘
```

`sdd start` (`ready → active`) requires all three gates in the front matter:
`alignment: resolved`, `critique: converged` (or `skipped`, or no `critique:` field at all) and
`verify: passed`. The alignment gate also looks at the section itself: it wants at least one
`**Question:**` line with a non-empty answer, so hand-writing `alignment: resolved` into a spec that
never ran `align` is refused with `✗ No questions in the Alignment section`.

Flow: `new → fill in → ready → align → answer → align-resolve → critique → (verify) → start → implement → done`

Only `ready` (from `draft`), `start` (from `ready`), `implement` (`active`, on the spec's branch) and
`done` (from `active`) check the status. `align`, `align-resolve`, `critique` and `verify` run on a
spec in any status, so keep to the order above yourself.

## Commands, step by step

### 1. Create a spec — `new`

```bash
./scripts/sdd new feature "User Dashboard"
./scripts/sdd new bug "Looping Token Refresh"
./scripts/sdd new test "Login Module Coverage"
./scripts/sdd new refactor "Convert Repository to Flow"
```

It asks for a `task_id` (press Enter for the next free number; any ID, e.g. a Jira key, is
slugified), then creates `specs/{type}s/{task_id}-{task_name}/spec.md` from the template with
`status: draft` and fills `task_id`, `task_name`, `created`, `updated` and the title. It does not
create a branch; `sdd start` does.

### 2. Fill in the spec

Open the spec in your editor.

**Replace the placeholders `sdd new` leaves behind:**

- `target_version: X.Y.Z` in the front matter. Agents never edit the front matter, and the critique
  reviewer stops the loop (`needs_user`) while this is still `X.Y.Z`.
- `[FEAT-NNN]` in the title (use the real code, e.g. `[FEAT-001]`; `BUG`, `REF`, `TEST` for the
  other types).
- The `YYYY-MM-DD` row in the Changelog.

**Fill every section**: Goal, Scope (included / excluded), Affected Layers, Contracts, ViewEntity,
Task List, Acceptance Criteria, Test Plan, Deviations from CLAUDE.md. When a section does not apply
(a presentation-only change has no Request/Response), write `None` and why, rather than leaving the
template comment. Write tasks as `- [ ] T1 – <what>`; the script finds tasks by the `T<number>`
after a checkbox. Link each acceptance criterion to its tasks, e.g. `(T1, T2)`. Leave
`## Open Decisions (Alignment)` empty; `align` fills it.

### 3. Mark it ready — `ready`

```bash
./scripts/sdd ready specs/features/{task_id}-{task_name}/spec.md
```

Sets `status: ready`; it only works from `draft`. **It does not check the sections yet** (the check
is still a `TODO` in the script): an empty template passes. Make sure Goal, Acceptance Criteria and
Test Plan are filled before you run it.

### 4. Generate the open questions — `align`

```bash
./scripts/sdd align specs/features/{task_id}-{task_name}/spec.md
```

The `sdd-align` agent reads the spec and CLAUDE.md, clears `## Open Decisions (Alignment)` and writes
3–8 questions into it, each followed by an empty answer line. It also resets `alignment`, `verify`
and `critique` to `pending`. It does not ask anything in the terminal and does not wait for input,
so it runs the same in CI.

**Re-running `align` clears every answer.** Do it only when you want new questions.

### 5. Answer, then close alignment — `align-resolve`

Write each answer on its `- **Answer:**` line, after the colon, on the same line:

```markdown
1. **Question:** Should the Turkish text be covered by an automated test?
   - **Answer:** Yes: add a Turkish case to GreetingTest with Locale("tr").
```

If an answer settles a front-matter value (for example `target_version`), change that field in
the front matter too: writing it in the answer does not update it, and no agent will.

```bash
./scripts/sdd align-resolve specs/features/{task_id}-{task_name}/spec.md
```

It checks that every question has a non-empty answer and sets `alignment: resolved`; otherwise it
lists the unanswered questions. `critique`, `start` and `implement` require `alignment: resolved`.

### 6. Harden the spec — `critique` (required gate)

```bash
./scripts/sdd critique specs/features/{task_id}-{task_name}/spec.md
./scripts/sdd critique <spec> --rounds 6 --threshold 8
```

An adversarial review loop modelled on ARIS (arXiv:2605.03042 §2.2). It requires
`alignment: resolved`. Each round:

1. **Review.** `sdd-critique` (read-only) scores the spec on a 5-axis rubric out of 10 and lists
   action items tagged CRITICAL, MAJOR, MINOR or NEEDS_USER. It is handed the spec *path*, never a
   summary.
2. **Arbitration.** When the reviewer reports a passing score with zero CRITICAL and zero MAJOR, the
   real `sdd-verify` agent runs. The loop exits only on `VERIFY: PASS`; a FAIL becomes the next
   round's action items.
3. **Action.** `sdd-refine` applies the CRITICAL and MAJOR items to the spec body. It may not edit
   `- **Answer:**` lines or the front matter; it counts such items as `USER_OWNED`, and any
   `USER_OWNED` item stops the loop.
4. **Convergence check.** Exit on score ≥ threshold, zero CRITICAL, zero MAJOR and verify PASS;
   otherwise run another round, up to the cap. A blocking item that comes back at the same place
   without the score improving (or that survives three rounds) is a **stall** and stops the loop.

**A NEEDS_USER item stops the round before `sdd-refine` runs**, so that round's other CRITICAL and
MAJOR items are not applied either. Fix what the report asks of you (a placeholder front-matter
field is the usual cause) and re-run; the next round applies the rest.

The verdict in the Critique Log is the **script's**, re-derived from the reviewer's counts; when the
reviewer's own `VERDICT` line disagrees, the loop warns and records its own.

```
→ Critique-to-action loop  (claude)
    reviewer : opus   (claude)
    executor : sonnet   (claude)
    rounds   : max 4        threshold: >= 6/10, 0 critical, 0 major
    context  : fresh           scope: spec-only
    exit gate: reviewer rubric + sdd-verify PASS
  ⚠ reviewer and executor are both 'claude' models — correlated blind spots are more likely.
════════════════ round 1 / 4 ════════════════
  score=2/10  critical=4  major=3  verdict=REVISE
→ Applying action items with sdd-refine (sonnet) ...
  applied=8  user_owned=0  unresolved=0
════════════════ round 2 / 4 ════════════════
  score=9/10  critical=0  major=0  verdict=CONVERGED
→ Reviewer satisfied — running the verify gate as final arbiter ...
  ✓ VERIFY: PASS
✓ critique: converged  (score 9/10 after 2 round(s))
```

**Outcomes** (the `critique:` front-matter field):

| Value | Meaning | What to do |
|-------|---------|------------|
| `converged` | Rubric cleared **and** verify passed | `verify: passed` is written too → go to `sdd start` |
| `needs_user` | The reviewer flagged a decision you own, the executor skipped an answer-line or front-matter item, or an item stalled | Open the report the loop names and go straight to its list: `## Needs user decision` in a reviewer report (`round-N.md`) states each decision as a question with the replacement it recommends; `## User-owned` in an executor report (`round-N-refine.md`) lists each item the executor was not allowed to touch; a stall prints the item locations in the terminal instead. Apply them to the `- **Answer:**` lines or the front matter by hand, then re-run `sdd critique`. Do **not** re-run `sdd align`: it clears every answer |
| `max_rounds` | Cap reached without convergence | Read the last report (and `round-N-verify.md`), fix by hand, re-run |
| `failed` | The reviewer or the in-loop verify produced no usable result (CLI or model error, or verify printed no `VERIFY:` line twice) | Fix the cause and re-run `sdd critique`; the report named in the error message says what the agent returned |
| `skipped` | You released the gate deliberately | Set `critique: skipped` in the front matter by hand and justify it under "Deviations from CLAUDE.md" |
| *(no field)* | Spec predates this gate | Not blocked |

**Ledger.** Each round writes `critique/round-N.md` (reviewer), each arbitration
`round-N-verify.md`, each executor turn `round-N-refine.md`, next to the spec. The spec's
`## Critique Log` gets one row per step: `N` reviewer, `N v` verify, `N r` executor. A re-run first
moves the previous run's reports into `critique/run-<timestamp>/` and repoints the old rows.

**Model families.** ARIS recommends a reviewer from a different model family than the executor. The
defaults are both Claude models (reviewer `opus`, executor `sonnet`), so the loop prints a
same-family warning on every run; that is expected and does not fail the run. On the Claude backend,
`--model` accepts only Claude models: `SDD_MODEL_CRITIQUE=gpt-4o` fails before the first review and
leaves `critique: failed`. On the Copilot backend every role currently runs on `auto`.

**Tunables:**

| Variable | Default | Effect |
|----------|---------|--------|
| `SDD_CRITIQUE_ROUNDS` / `--rounds` | `4` | Round cap |
| `SDD_CRITIQUE_THRESHOLD` / `--threshold` | `6` | Score needed out of 10 |
| `SDD_CRITIQUE_VERIFY` | `1` | `0` drops the in-loop verify arbiter (faster; `sdd verify` can then still FAIL) |
| `SDD_CRITIQUE_CONTEXT` | `fresh` | `cross-round` lets the reviewer read its earlier reports |
| `SDD_CRITIQUE_SCOPE` | `spec-only` | `repo` lets the reviewer check the spec against the codebase |
| `SDD_MODEL_CRITIQUE` / `SDD_MODEL_REFINE` | `opus` / `sonnet` | Model per half (Claude backend) |

**Cost.** Each round is one reviewer call plus one executor call, and a satisfied round adds a verify
call; four rounds can mean nine agent runs. Lower `--rounds` or set `SDD_CRITIQUE_VERIFY=0` on small
specs.

### 7. Verify on its own — `verify` (only when needed)

```bash
./scripts/sdd verify specs/features/{task_id}-{task_name}/spec.md
```

A converged critique already ran verify and wrote `verify: passed`. Run it yourself only after you
edit the spec by hand, or when you used `SDD_CRITIQUE_VERIFY=0`.

The read-only `sdd-verify` agent compares the spec with CLAUDE.md and prints `VERIFY: PASS` or
`VERIFY: FAIL` first. The script writes `verify: passed` or `verify: failed` and keeps the report in
`<spec-dir>/verify/verify-<timestamp>.md`. Any doubt is a FAIL. Verify judges the spec's content
only: the lifecycle fields the script writes (`status`, `alignment`, `verify`, `critique*`,
`updated`, …) and the Critique Log are out of its scope. If the CLI fails before producing output,
the front matter is left unchanged and the command exits non-zero.

### 8. Open the branch — `start`

```bash
./scripts/sdd start specs/features/{task_id}-{task_name}/spec.md
```

Requires `status: ready` and the three gates — including at least one answered
`**Question:**` in `## Open Decisions (Alignment)`, not just `alignment: resolved` in the front
matter. It runs `git checkout -b <prefix>/{task_id}-{task_name}`, writes the `branch:` field and
sets `status: active`.

The prefix is `sdd` by default (`sdd/001-localized-greeting`); change it with `SDD_BRANCH_PREFIX`:

```bash
SDD_BRANCH_PREFIX=feature ./scripts/sdd start <spec>     # → feature/001-localized-greeting
```

Git cannot create `X/...` while a branch named exactly `X` exists, which is why the prefix is not
`main`. If a branch named like the prefix exists, `start` stops before touching the spec and says
which prefix to use instead.

### 9. Implement the tasks — `implement`

```bash
./scripts/sdd implement specs/features/{task_id}-{task_name}/spec.md T3    # one task
./scripts/sdd implement specs/features/{task_id}-{task_name}/spec.md       # every open task
```

Requires `status: active`, the spec's branch checked out, and the three gates.

- **With a task id**, the `sdd-implement` agent implements that task only, even if it is already
  ticked.
- **Without a task id**, every task whose checkbox is still empty (`- [ ] T2`) runs in order, each in
  its own agent session; ticked tasks (`- [x]`) are skipped. At the end the script lists any task
  that is still unticked; if all are ticked already, it does nothing.

The agent runs unattended (`bypassPermissions`; deny rules still apply), edits only the files its
task needs, ticks the task's checkbox, adds a Changelog row to the spec, runs
`./gradlew checkCodeQuality assembleDevDebug`, and prints the commit command. **It never commits,
branches or pushes; you commit:**

```bash
git add <the changed files>
git commit -m "[FEAT-001] T1 – short description" -m "Spec: specs/features/001-localized-greeting/spec.md"
```

Commit format (CLAUDE.md §9.1): `[{CODE}-{task_id}] {task} – short description`, with
`Spec: specs/{type}s/{task_id}-{task_name}/spec.md` in the body. CODE: feature→`FEAT`, bug→`BUG`,
refactor→`REF`, test→`TEST`. The spec file itself is git-ignored (see
[Where specs live](#where-specs-live)).

### 10. Finish — `done`

```bash
./scripts/sdd done specs/features/{task_id}-{task_name}/spec.md
```

Requires `status: active`. Runs `./gradlew checkCodeQuality assembleDevDebug`; if it succeeds, sets
`status: done`. If Gradle fails, the spec stays `active`. `done` does not check that every task is
ticked or that the Changelog has a row; check those yourself. Merge the branch yourself.

When the project lacks those Gradle tasks (see
[Project prerequisites](#project-prerequisites-gradle)) and you have finished the spec with
another check, set `status: done` in the front matter by hand.

## Other commands

### `fix-ktlint`

```bash
./scripts/sdd fix-ktlint                  # runs ./gradlew app:ktlint
./scripts/sdd fix-ktlint app:ktlintCheck  # another Gradle task
```

1. Runs the Gradle task and collects `File.kt:line:col` violations from its output.
2. If there are none and Gradle succeeded, prints `✓ No ktlint violations found`.
3. If there are none but Gradle failed (the task does not exist, or the build or download failed),
   prints the last lines of the Gradle output and exits 1.
4. Otherwise it sends the files and violations to the `kotlin-ktlint` agent, which fixes style and
   formatting only (no logic changes, no new files). Re-run the Gradle task afterwards.

It is not part of the lifecycle and can run at any stage.

### `list`

```bash
./scripts/sdd list              # all specs
./scripts/sdd list feature      # one type: feature | bug | test | refactor
```

Columns: `TYPE`, `STATUS`, `ID-NAME`, `BRANCH`. The gate fields are not shown; read them from the
front matter:

```bash
grep -E '^(alignment|critique|verify):' specs/features/001-localized-greeting/spec.md
```

### `block`, `drop` and coming back

```bash
./scripts/sdd block <spec.md> "waiting for the API contract"   # → status: blocked + blocked_reason
./scripts/sdd drop  <spec.md> "superseded by 004"              # → status: dropped + dropped_reason
```

There is no command to leave `blocked`. When the blocker is gone, edit the front matter by hand:
set `status:` back to `ready` (no branch yet) or `active` (the branch exists; check it out), and
reset `blocked_reason: ~`.

### `sync-agents`

```bash
./scripts/sdd sync-agents
```

Run it after editing `.claude/agents/*.md` or `scripts/lib/deny-list.txt`. It regenerates
`.github/agents/*.agent.md` for Copilot (tool names translated, `model:` and `color:` dropped) and
the `deny` array of `.claude/settings.json`; `allow` and `ask` are left as they are. A second run
changes nothing. The Copilot driver warns when `.github/agents/` is out of date.

## Typical workflow

```bash
# 0. Once per machine and project
claude --version && claude auth status
claude                      # inside the project: accept the trust prompt, then exit

# 1. New spec (status: draft, no branch)
./scripts/sdd new feature "Localized Greeting"
SPEC=specs/features/001-localized-greeting/spec.md

# 2. Fill every section; replace target_version X.Y.Z, [FEAT-NNN] and the YYYY-MM-DD row
$EDITOR $SPEC

# 3. draft → ready (no section check yet: re-read the spec first)
./scripts/sdd ready $SPEC

# 4. Questions, then your answers on the "- **Answer:**" lines, then close alignment
./scripts/sdd align $SPEC
$EDITOR $SPEC
./scripts/sdd align-resolve $SPEC

# 5. Required gate: review loop until the rubric and verify are clear
./scripts/sdd critique $SPEC

# 5b. Only if you edited the spec by hand after the loop
./scripts/sdd verify $SPEC

# 6. Branch + status: active  (sdd/001-localized-greeting)
./scripts/sdd start $SPEC

# 7. Implement and commit task by task
./scripts/sdd implement $SPEC T1
git add <files> && git commit -m "[FEAT-001] T1 – ..." -m "Spec: $SPEC"
# … or implement every open task in one go: ./scripts/sdd implement $SPEC

# (optional) style fixes
./scripts/sdd fix-ktlint

# 8. Quality gates + status: done, then merge the branch
./scripts/sdd done $SPEC
```

## Agents

`.claude/agents/*.md` is the single source; `sdd sync-agents` generates the Copilot copies. On
Claude Code, the script starts `claude -p "Use the <agent> subagent …"` and Claude Code runs that
subagent with the tools in its definition. On Copilot, it passes `--agent <agent>`. The model always
comes from the driver's `--model` flag, never from the agent file.

| Agent | Used by | Model — Claude | Model — Copilot | Override | Tools | Run mode |
|-------|---------|----------------|-----------------|----------|-------|----------|
| `sdd-align` | `align` | `opus` | `auto` | `SDD_MODEL_ALIGN` | Read, Grep, Glob, Edit, Write | edit |
| `sdd-critique` | `critique` (reviewer) | `opus` | `auto` | `SDD_MODEL_CRITIQUE` | Read, Grep, Glob | read-only |
| `sdd-refine` | `critique` (executor) | `sonnet` | `auto` | `SDD_MODEL_REFINE` | Read, Grep, Glob, Edit | edit |
| `sdd-verify` | `verify`, `critique` | `sonnet` | `auto` | `SDD_MODEL_VERIFY` | Read, Grep, Glob | read-only |
| `sdd-implement` | `implement` | `sonnet` | `auto` | `SDD_MODEL_IMPLEMENT` | Read, Grep, Glob, Edit, Write, Bash | full |
| `kotlin-ktlint` | `fix-ktlint` | `haiku` | `auto` | `SDD_MODEL_KTLINT` | Read, Grep, Glob, Edit | edit |

A set `SDD_MODEL_*` wins on whichever backend runs. On Claude Code use an alias (`opus`, `sonnet`,
`haiku`) or a full Claude model ID.

```bash
SDD_MODEL_KTLINT=haiku ./scripts/sdd fix-ktlint
SDD_MODEL_VERIFY=opus  ./scripts/sdd verify <spec>
```

To use an agent interactively, ask for it by name in a `claude` session in the project, e.g.
"Use the sdd-verify subagent on specs/features/001-localized-greeting/spec.md". Interactive runs do
not update the front-matter gates; only `scripts/sdd` writes those.

## Permissions

`.claude/settings.json` allows `Read`, `Grep`, `Glob`, `./gradlew …`, `./scripts/sdd …` and read-only
git commands; asks before `git push/commit/checkout/reset`; and denies reading `secrets.properties`,
`local.properties`, `.env`, keystores, and `git push --force`. The `deny` list is generated from
`scripts/lib/deny-list.txt` by `sdd sync-agents`. Deny rules are evaluated before anything else, so
they hold in every mode. The `allow` list applies only once the project is trusted (see
[Claude Code CLI](#3-claude-code-cli)).

Each agent run gets the permission mode of its role (Claude Code flags):

| Run mode | Roles | Claude Code | Copilot |
|----------|-------|-------------|---------|
| read-only | critique, verify | `--permission-mode dontAsk --allowedTools "Task,Read,Grep,Glob"` | `--allow-tool read,search --deny-tool write,shell` |
| edit | align, refine, ktlint | `--permission-mode acceptEdits` | `--allow-tool read,search,edit,write` |
| full | implement | `--permission-mode bypassPermissions` | `--allow-tool read,search,edit,write,shell` |

On Copilot every mode also gets `--no-ask-user` and one `--deny-tool` per `deny-list.txt` entry.
Agent runs never read from your terminal: their standard input is closed.

## Updating the kit

The kit has no self-update command, and `scripts/sdd-artifact` is not part of the payload: updates
are built in the kit repository and installed over your project.

```bash
cd sdd-kit && git pull
bash scripts/sdd-artifact                                      # → dist/sdd-artifact/
bash dist/sdd-artifact/install.sh --update /path/to/your-project
```

`--update` refreshes the kit's own files and keeps the three you are expected to own, printing each
one it kept:

| Path | `--update` | Why |
|------|-----------|-----|
| `scripts/sdd`, `scripts/lib/*`, `specs/templates/*`, `SDD-README.md`, `.github/` | replaced | the kit's own files; your changes here are lost, so keep local changes in a fork of the kit repository instead |
| `CLAUDE.md` | kept | your project's architecture rules |
| `.claude/settings.json` | kept | your `allow`/`ask` policy (`deny` is regenerated by `sdd sync-agents`) |
| `.claude/agents/*.md` | kept | the hand-edited single source |

Because the agent definitions are kept, a kit update that changed them does not reach your project
on its own. The command prints the `diff -ru` line to compare, and `sdd sync-agents` regenerates
`.github/agents/` and the settings' `deny` array after you merge anything.

`--force` replaces everything in the payload, `CLAUDE.md` included; use it only on a project whose
`CLAUDE.md` you have not adapted yet. The two flags cannot be combined.

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `claude: command not found` right after installing the CLI | The installer's directory (usually `~/.local/bin`) is not on `PATH`; add it. See [3. Claude Code CLI](#3-claude-code-cli) |
| `No agent CLI found: … is not on PATH` + a manual protocol, exit 1 | No `claude`/`copilot` on `PATH`, or `SDD_AGENT` names the one that is missing. The spec is left untouched |
| `Ignoring N permissions.allow entries … this workspace has not been trusted` | The project folder was never trusted interactively. Run `claude` once inside it and accept the prompt; the commands still work meanwhile |
| `Refusing to overwrite existing file: …` during install | A first install over existing files. Use `--update` (keeps your `CLAUDE.md`, settings and agents) or `--force` |
| `Already ready.` / `ready only works from draft (current: done)` | `ready` only moves a `draft` forward; on `ready`/`active` it is a no-op, and from `done`/`blocked`/`dropped` it refuses. Edit `status:` in the front matter to redo a step |
| `✗ No questions in the Alignment section` | `align` was never run on this spec, or its questions were deleted. Run `sdd align`, answer the lines, then `sdd align-resolve` |
| `✗ Cannot proceed until Open Decisions are answered (answered n/m)` | An `- **Answer:**` line is still empty; the message names which question |
| `✗ alignment is 'pending' — answers look filled but 'sdd align-resolve' was never run` | Run `sdd align-resolve <spec>` |
| `critique: needs_user` | A decision only you can make, or an item that lives in an answer line or the front matter. Read the named report, edit by hand, re-run `sdd critique`. **Never** re-run `sdd align` for this: it clears every answer |
| `critique: failed` | The CLI or the model failed, or verify printed no `VERIFY:` line twice. Check the report named in the message, then re-run |
| `verify: failed` | A real finding in the spec: read `verify/verify-<timestamp>.md`, fix the spec, re-run `sdd verify` |
| `✗ Cannot create 'sdd/001-x': a branch named 'sdd' already exists` | Git cannot hold both `sdd` and `sdd/…`. Use another prefix: `SDD_BRANCH_PREFIX=feature ./scripts/sdd start <spec>` |
| `Wrong branch (main). Expected: sdd/001-x` on `implement` | Check out the spec's branch, or fix the `branch:` field if you renamed it |
| `implement` prints `⚠ Still unticked after this run: …` | The agent did not tick those checkboxes — read its report above, then re-run `implement` (ticked tasks are skipped) or tick them by hand |
| `✓ Every task … already ticked — nothing to implement` | Every checkbox is `[x]`. To redo one: `./scripts/sdd implement <spec> T2` |
| `✗ ./gradlew app:ktlint failed (exit 1) without reporting any ktlint violation` | The task does not exist, or Gradle failed before ktlint ran. See [Project prerequisites](#project-prerequisites-gradle), or pass your own task: `./scripts/sdd fix-ktlint app:ktlintCheck` |
| `SDK location not found` / `Task 'assembleDevDebug' not found` from `done` | Missing Android SDK (`local.properties`) or no `dev` flavor. See [Requirements](#1-requirements) and [Project prerequisites](#project-prerequisites-gradle) |
| A spec is stuck in `blocked` | There is no command out of it: set `status:` back to `ready` or `active` by hand and reset `blocked_reason: ~` |
| A command parses a spec oddly in an SSH/CI shell | Set a UTF-8 locale: `export LANG=en_US.UTF-8` |

## Changes in this version

1. **Linux is supported.** Front-matter writes no longer use the BSD-only `sed -i ''`; `new`,
   `ready`, `start`, `done`, `block` and `drop` now work with GNU sed too.
2. **Branch prefix.** Branches are `sdd/{task_id}-{task_name}` by default (was `main/…`, which git
   refuses while a `main` branch exists). Set `SDD_BRANCH_PREFIX` to change it.
3. **`implement` without a task id** runs only unticked tasks, one agent session per task. Before,
   the first agent read the rest of the task list from standard input, ran those tasks in the same
   session, and ended the loop.
4. **`fix-ktlint`** exits 1 when Gradle fails without reporting any violation, instead of printing
   "No ktlint violations found".

From the Copilot support change (spec 002): `align` exits 1 when no agent CLI is found (it used to
exit 0) and leaves the spec untouched; `verify` leaves the front matter untouched when the CLI fails
before producing output, but still writes `verify: failed` when it ran and printed no verdict.

## When to use which spec type

| Situation | Type |
|-----------|------|
| I am adding new behavior | feature |
| Existing behavior is wrong | bug |
| I am preserving existing behavior | test |
| Behavior is the same but the code structure changes | refactor |
| Cleanup shorter than 1 hour | spec-less commit |

## Tips

**One spec, one type.** For hybrid cases, create two specs and link them to each other.

**Keep tasks small.** If a task takes more than 2 days, split the spec.

**Refactors require a test safety net.** If coverage is insufficient, create a test spec first.

**Do not restate CLAUDE.md.** Reference it from specs; explain any deviation under "Deviations from
CLAUDE.md".

**Do not bloat CLAUDE.md.** The longer it gets, the less reliably agents follow it; add a rule only
when it is needed.

## Limitations

- `ready` does not check the spec's sections yet.
- `done` always runs `checkCodeQuality assembleDevDebug`; a spec cannot choose another check.
- There is no command to leave `blocked`; edit the front matter.
- Specs are git-ignored by default, so they are not shared through the repository.
- Writing specs adds overhead; do not force it for very small tasks.
- The critique loop costs tokens, and its rubric score is advisory: `critique: converged` also
  requires `VERIFY: PASS`.
- `critique` hardens what is written; it cannot tell you the feature is the wrong thing to build.
- Changes to CLAUDE.md need team approval, unless it is a solo project.
