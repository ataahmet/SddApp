---
task_id: 003
task_name: align-build-with-claude-md-stack
type: refactor
status: ready
branch: ~                # `scripts/sdd start` fills in: main/NNN-short-slug
alignment: resolved
verify: failed
created: 2026-09-13
updated: 2026-09-13
target_version: 1.0.0
blocked_reason: ~
dropped_reason: ~
---

# [REF-003] Align the build with the CLAUDE.md stack

> Don't repeat CLAUDE.md; reference it only. Write any deviations in §9.

> A test safety net is required for refactors; if coverage is insufficient, open a test spec first.

## 1. Motivation

CLAUDE.md declares its Technology and DI sections "non-negotiable — verified". They are not
verified: almost none of the declared stack exists in the build. The app is still a bare Compose
skeleton from the Android Studio template. Two concrete consequences are already blocking work:

- `./scripts/sdd done` shells out to `./gradlew checkCodeQuality assembleDevDebug`. Neither task
  exists, so **no spec can ever reach `status: done` through the script**. Spec 001 is stuck in
  `active` for this reason.
- `./scripts/sdd fix-ktlint` invokes `app:ktlint`. No ktlint plugin is applied, so the command
  cannot run either.

This was found while implementing spec 002 (T1), whose §7 originally asserted the gradle gate;
that criterion had to be replaced and the gap deferred here. Until this spec lands, every SDD
quality gate below `verify` is decorative.

## 2. Current State

Measured on 2026-09-13 from `app/build.gradle.kts`, `gradle/libs.versions.toml` and
`./gradlew tasks --all`.

| CLAUDE.md declares | Build actually has |
|---|---|
| Java 17 | `JavaVersion.VERSION_11`, `jvmTarget = "11"` |
| `compileSdk 35` | `compileSdk = 36` |
| `minSdk 23` | `minSdk = 24` |
| `targetSdk 35` | `targetSdk = 36` |
| Hilt (Koin forbidden) | no DI framework at all |
| RxJava2 (`Single`/`Completable`) | absent |
| Retrofit + Gson (`@SerializedName`) | absent |
| Timber (`Log.*`/`println` forbidden) | absent |
| `Source` abstraction (PaperDB) | absent |
| Navigation safeargs | absent |
| `assembleDevDebug` | no product flavours; only `debug` / `release` |
| `checkCodeQuality` | task not defined anywhere |
| `app:ktlint` | ktlint plugin not applied |

`gradle/libs.versions.toml` contains no entry matching hilt, rxjava, timber, retrofit, gson,
paperdb or ktlint. Declared dependencies are core-ktx, lifecycle-runtime-ktx, activity-compose,
the Compose BOM, material3, junit and espresso.

## 3. Target State

CLAUDE.md and the build agree, so that `./gradlew checkCodeQuality assembleDevDebug` — the §9.1
`active → done` gate — runs and passes, and `./scripts/sdd fix-ktlint` has a real task to call.

**The alignment runs both ways (D1, D8).** The spec was opened assuming CLAUDE.md is the target
and the build is wrong. Alignment rejected that for three rows: the platform levels are corrected
in CLAUDE.md rather than downgraded in the build, and the Navigation safeargs requirement is
removed rather than satisfied. Everything else in CLAUDE.md states a real intent and the build
moves to match it.

| Row | Direction | Why |
|---|---|---|
| `compileSdk` / `targetSdk` / `minSdk` | CLAUDE.md → 36/36/24 | Downgrading `compileSdk` breaks dependencies built against 36; lowering `minSdk` needs a device-reach reason nobody stated (D1) |
| Navigation safeargs | removed from CLAUDE.md | XML nav-graph tooling in a Compose-only app with no Views and no nav graph (D8) |
| Java 17 | build → 17 | A raise, and the direction CLAUDE.md states (D2) |
| Hilt, RxJava2, Retrofit+Gson, Timber, PaperDB, flavours, ktlint | build → CLAUDE.md | Real intent, simply unimplemented |

**Proving-slice contract (D4).** Deliberately minimal and throwaway — it exists to exercise
Retrofit + Gson → RxJava2 → Hilt → ViewEntity → Compose end to end, against a local fake. Nullable
DTO fields mapping to non-null entity fields are the point: they force the mapping and its error
path to be real.

```kotlin
// Request path : ProvingRequestPath("/proving/item")
// Response     : ProvingItemResponse : ViewEntityConvertible<ProvingItemViewEntity>
data class ProvingItemResponse(
    @SerializedName("id")         val id: String?,
    @SerializedName("title")      val title: String?,
    @SerializedName("updated_at") val updatedAt: String?,
)

data class ProvingItemViewEntity(
    val id: String,
    val title: String,
    val updatedAt: String,   // formatted for display
)
```

A response missing `id` or `title` maps to the ViewModel's error state rather than to an entity
with blank fields; that path is one of T9's unit tests. All user-facing text in the slice's
composable comes from `strings.xml` — no hardcoded strings, per CLAUDE.md.

**State exposure (D3).** `Single` → `LiveData` → `observeAsState`, as the single pattern every
future feature follows. Subscribing a `Single` directly into `mutableStateOf` is rejected: it puts
disposal on the composable and leaks when the lifecycle outlives the composition. CLAUDE.md is in
tension with itself here — it mandates Compose while forbidding Flow/coroutines, and Compose's
native idiom is `collectAsState`; the LiveData hop is the price of keeping the RxJava2 rule.

### Scope

**Included**
- Java raised to 17; AGP, Kotlin and the Compose BOM deliberately frozen (D2).
- CLAUDE.md corrected on the three rows above.
- Hilt (via KSP), RxJava2, Retrofit + Gson, Timber and PaperDB added to the version catalog and
  applied. Navigation safeargs is dropped, not added (D8).
- `dev` / `prod` product flavours: `applicationIdSuffix = ".dev"`, a per-flavour `BuildConfig`
  base URL, and the Timber debug tree planted in `dev` only. Build types stay `debug`/`release`
  (D5).
- The jlleitschuh ktlint plugin — it is Gradle-native and gives `ktlintFormat`, which
  `sdd fix-ktlint` already assumes — and a `checkCodeQuality` task aggregating `ktlintCheck`,
  Android `lint` and unit tests. It reports every finding rather than stopping at the first, and
  generates no baseline (D6).
- One vertical slice through the `data` / `domain` / `presentation` packages of the single `app`
  module (D7) proving the stack wires up: an `@ActivityRetainedScoped` repository behind a
  `Single`, a ViewEntity, a ViewModel, reaching Retrofit through a local fake rather than a real
  backend (D4).

**Excluded**
- Any feature work beyond the proving slice.
- Migrating the existing Compose sample screens beyond what compilation requires.
- The SDD tooling itself (spec 002 owns `scripts/`, `.claude/agents/`, `.github/`).
- Gradle module splitting: the layers are packages inside `app` (D7).
- Toolchain upgrades to AGP, Kotlin or the Compose BOM (D2).
- Introducing Views/XML navigation, which would be its own spec (D8).
- Any domain modelling beyond the proving contract below; the first real screen brings its own.

## 4. Affected Files

- [ ] `gradle/libs.versions.toml` — new library and plugin entries
- [ ] `app/build.gradle.kts` — Java/SDK levels, plugins, flavours, dependencies
- [ ] `build.gradle.kts` — ktlint / `checkCodeQuality` wiring
- [ ] `app/src/main/java/...` — the proving slice and its Hilt module
- [ ] `CLAUDE.md` — platform levels corrected to 36/36/24, Navigation safeargs row removed (D1, D8)
- [ ] `app/src/test/java/...` — unit tests for the proving slice (D9)

## 5. Breaking Changes

- [ ] None
- [x] Yes — **Java 11 → 17** changes the required JDK for every developer machine and CI runner.
      JDK 17+ availability is a precondition of T1, checked before it starts (D2).

      The platform downgrade this section previously predicted is **not** happening: alignment
      settled that CLAUDE.md's 35/35/23 is stale and the build's 36/36/24 stays (D1). Removing
      the Navigation safeargs requirement from CLAUDE.md (D8) breaks nothing, since no code uses
      it.

## 6. Task List
- [ ] T1 – Raise Java to 17 (`sourceCompatibility`, `targetCompatibility`, `jvmTarget`), leaving AGP, Kotlin and the Compose BOM at their current versions. Confirm JDK 17+ on the machine first (D2).
- [ ] T2 – Correct CLAUDE.md: platform levels to `compileSdk 36` / `targetSdk 36` / `minSdk 24`, and remove the Navigation safeargs clause from the UI line (D1, D8). No build change — this row of §2 closes from the CLAUDE.md side.
- [ ] T3 – Add `dev` / `prod` flavours with `applicationIdSuffix = ".dev"` and a per-flavour `BuildConfig` base URL, so `assembleDevDebug` and `assembleProdRelease` both resolve (D5).
- [ ] T4 – Apply the jlleitschuh ktlint plugin and define `checkCodeQuality` as an aggregate of `ktlintCheck`, Android `lint` and unit tests, reporting all findings and generating no baseline (D6).
- [ ] T5 – Add Hilt with KSP, the `@HiltAndroidApp` application class and the Activity entry point (D7).
- [ ] T6 – Add RxJava2, Retrofit + Gson and Timber to the catalog and the app module; plant the Timber debug tree in `dev` only (D5).
- [ ] T7 – Add the `Source` abstraction over PaperDB.
- [ ] T8 – Build the vertical proving slice across the `data` / `domain` / `presentation` packages, against a local fake rather than a real backend, exposing state as `Single` → `LiveData` → `observeAsState` (D3, D4, D7). Blocked until the DTO and ViewEntity field lists are decided.
- [ ] T9 – Add the proving slice's unit tests: UseCase happy and error paths, ViewModel state emission (D9).
- [ ] T10 – Confirm the gates end to end: `./gradlew checkCodeQuality assembleDevDebug` green, `./gradlew assembleProdRelease` assembles, `./scripts/sdd fix-ktlint` reports violations instead of failing on a missing task, and `./scripts/sdd done` completes on a scratch spec.

## 7. Acceptance Criteria

- [ ] `./gradlew checkCodeQuality assembleDevDebug` exits 0.
- [ ] `./scripts/sdd fix-ktlint` runs and reports violations instead of failing on a missing task.
- [ ] `./scripts/sdd done` completes on a scratch spec.
- [ ] Every row of the §2 table reads the same on both sides — each closed from the direction
      §3's table assigns it, not whichever is easier.
- [ ] `CLAUDE.md` states `compileSdk 36` / `targetSdk 36` / `minSdk 24` and no longer requires
      Navigation safeargs (D1, D8).
- [ ] The proving slice exposes state as `Single` → `LiveData` → `observeAsState`, with no
      `Single` subscribed directly into `mutableStateOf` (D3).
- [ ] `./gradlew assembleProdRelease` also assembles, and `dev` installs alongside `prod`
      via `applicationIdSuffix` (D5).
- [ ] `checkCodeQuality` reports findings from `ktlintCheck`, `lint` and unit tests in one run
      rather than stopping at the first, and no ktlint baseline file exists (D6).
- [ ] Hilt generates through KSP, not kapt, and the layers are packages inside `app` rather
      than separate Gradle modules (D7).
- [ ] The proving slice honours the CLAUDE.md DI rules: feature dependencies are
      `@ActivityRetainedScoped`, the repository is bound with `@Binds` in its feature module, and
      no `@Singleton`/`@ActivityScoped` appears on a feature class.
- [ ] No `Log.*`, `println`, `suspend`, `Flow` or Koin reference exists in `app/`.
- [ ] AGP, Kotlin and the Compose BOM are at the same versions as before this spec (D2).

## 8. Test Plan

- [ ] `./gradlew checkCodeQuality assembleDevDebug` green from a clean `./gradlew clean`.
- [ ] `./gradlew assembleProdRelease` also assembles, proving the flavour axis is complete.
- [ ] Unit: the proving slice's UseCase happy path and error path.
- [ ] Unit: the proving slice's ViewModel state emission.
- [ ] Manual: install `devDebug` on a `minSdk`-level emulator and open the slice's screen.
- [ ] `./scripts/sdd done` on a scratch spec transitions it to `done` without manual editing.

## 9. Open Decisions (Alignment)

1. **Question:** Direction of alignment for the platform rows: do we move the build down to CLAUDE.md's `compileSdk 35` / `targetSdk 35` / `minSdk 23` (a downgrade of the current 36/36/24), or do we treat those numbers as stale and update CLAUDE.md to 36/36/24 instead? If the downgrade is chosen, what is the reason that justifies it (a 23-level device to support, a vendor constraint, …)?
   - **Answer:** CLAUDE.md is updated to 36/36/24; the build is not downgraded. The `compileSdk 35 / targetSdk 35 / minSdk 23` values carry a "verified" label that measurement contradicted, so they are treated as stale rather than as a target. Lowering `compileSdk` breaks dependencies compiled against 36, and lowering `minSdk` needs a device-reach justification nobody has stated. This flips part of the spec's direction: where CLAUDE.md is stale it is corrected, and only where it states a real intent is the build changed to match.
2. **Question:** Java 17 is a raise from the current `VERSION_11` / `jvmTarget = "11"`. Is every developer machine and any CI runner already on JDK 17+, and does this spec also bump AGP 8.11.2 / Kotlin 2.0.21 / the 2024.09 Compose BOM, or are versions frozen and only the Java level changes?
   - **Answer:** Java moves 11 -> 17 (a raise, and the direction CLAUDE.md states). AGP 8.11.2, Kotlin 2.0.21 and the 2024.09 Compose BOM are frozen for this spec — only the Java/jvmTarget level changes, so a break has one possible cause. Toolchain upgrades are a separate spec. JDK 17+ availability on every machine and runner is a precondition of the Java task, checked before it starts.
3. **Question:** CLAUDE.md forbids coroutines/suspend/Flow but mandates Compose. How should the proving slice's ViewModel expose state to Compose — RxJava2 `Single` subscribed into a `mutableStateOf`, into `LiveData` + `observeAsState`, or another bridge? Please name the one pattern every future feature must copy, plus where the `Disposable` is cleared.
   - **Answer:** `Single` -> `LiveData` (RxJava2's supported bridge) -> `observeAsState` in the composable. This is the one pattern every future feature follows. Subscribing a `Single` straight into `mutableStateOf` is rejected: it puts disposal on the composable and leaks when the lifecycle outlives the composition. Worth recording that CLAUDE.md is in tension with itself here — it mandates Compose while forbidding Flow/coroutines, and Compose's native idiom is `collectAsState`; the LiveData hop is the cost of keeping the RxJava2 rule.
4. **Question:** What does the proving slice actually do end to end: which Retrofit endpoint/base URL does it call (a real backend, a public stub like httpbin, or a local fake), and what are the concrete DTO fields and the ViewEntity fields it maps to? CLAUDE.md §9 requires DTO + entity contracts in the spec, and §4 currently has none.
   - **Answer:** A local fake, not a real backend and not a public stub: the slice proves the stack wires up, so a network dependency would only make it flaky. Retrofit is pointed at a `MockWebServer` (or a `Source`-backed fake returning a fixed payload) with the base URL coming from the flavour's `BuildConfig`. The concrete DTO and ViewEntity fields are still open and are set when the first real screen is known; The contract is therefore fixed here rather than deferred (see the block in §3), since the slice's job is to prove the wiring, not to model a real domain: whatever the first real screen turns out to need, it will be its own spec's contract. Nothing in this spec is blocked.
5. **Question:** What distinguishes the `dev` and `prod` flavours beyond making `assembleDevDebug` resolve — `applicationIdSuffix`, per-flavour `BuildConfig` base URL, logging/Timber tree, signing config? And do the build types stay `debug` / `release` only?
   - **Answer:** `dev` gets `applicationIdSuffix = ".dev"` so both variants install side by side, a per-flavour `BuildConfig` base URL, and the Timber debug tree planted only in `dev`. `prod` plants no tree. Build types stay `debug` / `release` only — no third type.
6. **Question:** Which ktlint integration do we apply (jlleitschuh Gradle plugin, pinterest CLI wrapper, or detekt instead), and exactly which tasks does the `checkCodeQuality` aggregate depend on (ktlint + Android `lint` + unit tests, or only static analysis)? Should it fail the build on the first violation in the existing template sources, or start with a baseline?
   - **Answer:** The jlleitschuh Gradle plugin: it is Gradle-native and provides `ktlintFormat`, which `sdd fix-ktlint` already assumes exists. `checkCodeQuality` aggregates `ktlintCheck` + Android `lint` + unit tests. It does not stop at the first failure; every check runs and all findings are reported together. No baseline is generated — the codebase is small enough to start clean, and a baseline would hide exactly the violations this spec exists to surface.
7. **Question:** Where does the layered structure live: packages (`data` / `domain` / `presentation`) inside the single `app` module, or new Gradle modules? And for Hilt code generation, do we add KSP or use kapt with Kotlin 2.0.21?
   - **Answer:** Packages (`data` / `domain` / `presentation`) inside the single `app` module. Splitting into Gradle modules is premature at this size, and CLAUDE.md's dependency rule (presentation -> domain <- data) is enforceable by package just as well. Hilt code generation uses KSP, not kapt: kapt is slow and in maintenance mode under Kotlin 2.0.21.
8. **Question:** `Navigation safeargs` is a plugin for XML nav graphs, while the app today is Compose-only with no Views or nav graph. Do we introduce a Views/XML navigation host to make safeargs meaningful, defer it to a later feature spec, or record it as a deviation in §10 and drop the row from §2?
   - **Answer:** Neither introduce XML navigation nor keep the requirement: the Navigation safeargs row is removed from CLAUDE.md and the change is recorded as a deviation in §10. safeargs generates type-safe args for XML nav graphs, and the app is Compose-only with no Views and no nav graph, so adding a nav host purely to satisfy the line would be building something to justify a rule rather than the reverse. If Views-based navigation is ever wanted, that is its own spec.
9. **Question:** This spec's header requires a test safety net for a refactor, and the module currently has only the template `junit`/espresso stubs. Is unit coverage of the new proving slice alone sufficient to proceed, or must a separate test spec land first before this one moves to `active`?
   - **Answer:** Unit coverage of the proving slice itself is sufficient; no separate test spec has to land first. The refactor-template's safety-net rule guards existing behaviour against regression, and there is no behaviour here to regress — the slice is new code, and the build changes are verified by the build itself. The rule applies again as soon as a spec touches existing app code.

## 10. Deviations from CLAUDE.md

- **§9 assumes a spec justifies its deviations from CLAUDE.md; T2 instead edits CLAUDE.md.**
  This is deliberate. `sdd verify` declined to certify it on its own and asked for a human call,
  so it was put to the repository owner explicitly on 2026-09-13, with the alternatives spelled
  out — keep T2 and correct CLAUDE.md, drop T2 and record D1/D8 as permanent deviations, or split
  T2 into its own spec — and the owner chose to correct CLAUDE.md. That decision is recorded here,
  in the spec, and is what authorises T2; no agent granted it to itself. The deviation process exists for "this spec needs to break the rule *here*". It
  is the wrong instrument when the rule is simply wrong: logging D1 and D8 as deviations would
  leave `compileSdk 35` / `minSdk 23` and the Navigation safeargs requirement standing, so §2's
  table could never close and every future spec would have to re-justify the same difference in
  its own §10. Reconciling the two documents is this spec's whole purpose, so the correction goes
  where the error is.
  The scope of the edit is narrow and evidence-backed. T2 changes only the three platform numbers
  — measured from `app/build.gradle.kts` on 2026-09-13 and recorded in §2 — and removes the
  Navigation safeargs clause, which requires XML nav-graph tooling of an app that has no Views and
  no nav graph. Every other CLAUDE.md rule is left exactly as written, and the build moves to meet
  it. Nothing in the DI section (§ Dependency Injection) is touched at all.
  Two things CLAUDE.md says are recorded here rather than changed, because they are intent rather
  than error: it mandates Compose while forbidding Flow and coroutines (D3 pays for this with the
  `LiveData` hop), and it labels the Technology section "non-negotiable — verified" (the label was
  wrong, not the intent; T2 makes it true rather than removing it).

## 11. Changelog

| Date | Status | Change |
|------|--------|--------|
| 2026-09-13 | draft | Opened from spec 002 T1, which found the CLAUDE.md stack unimplemented and the `active → done` gradle gate unrunnable |
| 2026-09-13 | ready | `sdd align` raised 9 decisions; all answered. Direction is now bidirectional: D1 and D8 correct CLAUDE.md rather than the build. §3/§4/§5/§6/§7 rewritten to match, task list 8 → 10 |
| 2026-09-13 | ready | verify FAIL: D4's answer still named T7 after the task list grew (now T8). Also, verify would not self-certify T2 editing CLAUDE.md; confirmed as a human decision and justified in §10 |
| 2026-09-13 | ready | verify FAIL: the deferred DTO/ViewEntity fields were an unowned blocker that also contradicted `status: ready`. Contract fixed concretely in §3 instead, since a proving slice needs wiring rather than a real domain. T2's authorisation now records the owner's explicit decision, and T10 covers the two criteria no task confirmed |
