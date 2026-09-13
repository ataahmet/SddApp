---
task_id: 001
task_name: change-mainactivity-title
type: refactor
status: active
branch: main/001-change-mainactivity-title
alignment: resolved
verify: passed
created: 2026-09-13
updated: 2026-09-13
target_version: 1.0.0
blocked_reason: ~
dropped_reason: ~
---

# [REF-NNN] Change MainActivity Title

> Don't repeat CLAUDE.md; reference it only. Write any deviations in §9.

> A test safety net is required for refactors; if coverage is insufficient, open a test spec first.

## 1. Motivation
<!-- Technical debt / performance / readability -->
- Add title in MainActivity toolbar

## 2. Current State
- There is nothing name for MainActivity

## 3. Target State
- The goal is for "SDD DEMO" to appear in the main activity. 

## 4. Affected Files
- [ ] `MainActivity.kt`
- [ ] `res/values/strings.xml`

## 5. Breaking Changes
- [x] None
- [ ] Yes:

## 6. Task List
- [ ] T1 - Add title value from `res/values/strings.xml`
- [ ] T2 – Use this title in MainActivity toolbar

## 7. Acceptance Criteria
- [ ] Correct MainActivity toolbar title
- [ ] Success `/gradlew checkCodeQuality assembleDevDebug`

## 8. Open Decisions (Alignment)
<!-- `./scripts/sdd align` writes the questions here and fills in your answers.
     Format (parsed by the script):
     1. **Question:** <question>
        - **Answer:** <answer> -->

1. **Question:** §3 says `"SSD DEMO"` but the app/module is named `SddApp` — what is the exact, literal title string to render (including spelling `SSD` vs `SDD`, casing, and spacing)?
   - **Answer:** it must be `"SDD DEMO"`
2. **Question:** `MainActivity` is currently a Compose-only `ComponentActivity` whose `Scaffold` has **no** `topBar` and no Views toolbar at all — how should the title be shown: a Material3 `TopAppBar` passed to `Scaffold(topBar = ...)`, an Android Views `Toolbar`/`setSupportActionBar`, or just `android:label` in the manifest / `setTitle()`?
   - **Answer:**  `TopAppBar` passed to `Scaffold(topBar = ...)`
3. **Question:** Must the title come from a string resource (e.g. a new `main_toolbar_title` in `res/values/strings.xml`) rather than a hardcoded literal, does the existing `app_name` ("SddApp") stay unchanged, and is any localized variant (e.g. `values-tr`) required now?
   - **Answer:**  Get it from a new `main_toolbar_title` in `res/values/strings.xml`
4. **Question:** Is the title identical across all flavours/build types, or must dev/debug builds show a suffixed variant (e.g. "SDD DEMO (dev)") given the `assembleDevDebug` verification target in CLAUDE.md §9.1?
   - **Answer:**  identical across all flavours/build types
5. **Question:** Is a UI-only constant/resource title acceptable for this refactor, or must the title be delivered through a state/ViewEntity from a ViewModel to satisfy the presentation→domain data-flow rule in CLAUDE.md §Architecture (and if UI-only, should that be recorded under §9 Deviations)?
   - **Answer:** UI-only constant/resource title
6. **Question:** The refactor note at the top of this spec requires a test safety net, but the spec has no Test Plan and no test currently asserts any MainActivity UI — which test proves the title (Compose UI test assertion vs. instrumented vs. manual check), and is writing it part of this spec's Task List and Acceptance Criteria?
   - **Answer:** Do not perform any test assertion.
7. **Question:** §4 lists only `MainActivity.kt` — may the change also touch `res/values/strings.xml`, `AndroidManifest.xml`, or introduce a reusable top-bar composable, and do the existing `enableEdgeToEdge()` inset handling and the placeholder `Greeting`/`GreetingPreview` stay exactly as they are (i.e. explicitly out of scope)?
   - **Answer:** change also touch `res/values/strings.xml` and stay exactly as they are scope

## 9. Deviations from CLAUDE.md
- Just change the UI; since the data is static, there is no need to use an entity or a ViewModel.
- single static string literal, no branching logic — no behavior to regression-test

## 10. Changelog
| Date | Status | Change |
|------|--------|--------|
| YYYY-MM-DD | draft | Refactor planned |
