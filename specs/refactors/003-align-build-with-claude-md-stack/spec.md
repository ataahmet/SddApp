---
task_id: 003
task_name: align-build-with-claude-md-stack
type: refactor
status: draft
branch: ~                # `scripts/sdd start` fills in: main/NNN-short-slug
alignment: pending       # `scripts/sdd align` → pending, `align-resolve` → resolved
verify: pending          # `scripts/sdd verify` → passed | failed (gate for start/implement)
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

The build satisfies every claim CLAUDE.md's Technology and DI sections make, so that
`./gradlew checkCodeQuality assembleDevDebug` — the §9.1 `active → done` gate — runs and passes,
and `./scripts/sdd fix-ktlint` has a real task to call.

### Scope

**Included**
- Java/SDK levels brought to the declared values.
- Hilt, RxJava2, Retrofit + Gson, Timber, PaperDB and Navigation safeargs added to the version
  catalog and applied.
- `dev` / `prod` product flavours, so `assembleDevDebug` resolves.
- A ktlint plugin and a `checkCodeQuality` aggregate task.
- One vertical slice through `data` → `domain` → `presentation` proving the stack wires up
  (an `@ActivityRetainedScoped` repository behind a `Single`, a ViewEntity, a ViewModel).

**Excluded**
- Any feature work beyond the proving slice.
- Migrating the existing Compose sample screens beyond what compilation requires.
- The SDD tooling itself (spec 002 owns `scripts/`, `.claude/agents/`, `.github/`).
- Deciding whether CLAUDE.md's declared values are the right ones — see the Open Decisions note
  below; this spec assumes CLAUDE.md is the target and the build is wrong.

## 4. Affected Files

- [ ] `gradle/libs.versions.toml` — new library and plugin entries
- [ ] `app/build.gradle.kts` — Java/SDK levels, plugins, flavours, dependencies
- [ ] `build.gradle.kts` — ktlint / `checkCodeQuality` wiring
- [ ] `app/src/main/java/...` — the proving slice and its Hilt module
- [ ] `CLAUDE.md` — only if a declared value is changed rather than implemented (see §9)

## 5. Breaking Changes

- [ ] None
- [x] Yes — `minSdk` moves 24 → 23 and `compileSdk`/`targetSdk` move 36 → 35 to match CLAUDE.md,
      which is a downgrade of the compile and target platform. Java 11 → 17 changes the required
      JDK for every developer and CI runner. Scale and risk to be confirmed during `sdd align`.

## 6. Task List
<!-- Filled in after `sdd align`; the ordering below is provisional. -->
- [ ] T1 – Raise Java to 17 and set `compileSdk`/`minSdk`/`targetSdk` to the declared values.
- [ ] T2 – Add `dev` / `prod` product flavours so `assembleDevDebug` resolves.
- [ ] T3 – Apply a ktlint plugin and define the `checkCodeQuality` aggregate task.
- [ ] T4 – Add Hilt and wire the application class.
- [ ] T5 – Add RxJava2, Retrofit + Gson and Timber to the catalog and the app module.
- [ ] T6 – Add the `Source`/PaperDB abstraction and Navigation safeargs.
- [ ] T7 – Build the vertical proving slice across the three layers.
- [ ] T8 – Confirm `./gradlew checkCodeQuality assembleDevDebug` is green and `sdd done` works.

## 7. Acceptance Criteria

- [ ] `./gradlew checkCodeQuality assembleDevDebug` exits 0.
- [ ] `./scripts/sdd fix-ktlint` runs and reports violations instead of failing on a missing task.
- [ ] `./scripts/sdd done` completes on a scratch spec.
- [ ] Every row of the §2 table reads the same on both sides.
- [ ] The proving slice honours the CLAUDE.md DI rules: feature dependencies are
      `@ActivityRetainedScoped`, the repository is bound with `@Binds` in its feature module, and
      no `@Singleton`/`@ActivityScoped` appears on a feature class.
- [ ] No `Log.*`, `println`, `suspend`, `Flow` or Koin reference exists in `app/`.

## 8. Test Plan

- [ ] `./gradlew checkCodeQuality assembleDevDebug` green from a clean `./gradlew clean`.
- [ ] `./gradlew assembleProdRelease` also assembles, proving the flavour axis is complete.
- [ ] Unit: the proving slice's UseCase happy path and error path.
- [ ] Unit: the proving slice's ViewModel state emission.
- [ ] Manual: install `devDebug` on a `minSdk`-level emulator and open the slice's screen.
- [ ] `./scripts/sdd done` on a scratch spec transitions it to `done` without manual editing.

## 9. Open Decisions (Alignment)
<!-- `./scripts/sdd align` writes the questions here and fills in your answers.
     Seed for that step: the central question is direction. CLAUDE.md's values may be the
     intended target (implement them), or stale (correct CLAUDE.md instead). The SDK and Java
     rows in particular are downgrades, which is unusual for a target. -->

## 10. Deviations from CLAUDE.md
None

## 11. Changelog

| Date | Status | Change |
|------|--------|--------|
| 2026-09-13 | draft | Opened from spec 002 T1, which found the CLAUDE.md stack unimplemented and the `active → done` gradle gate unrunnable |
