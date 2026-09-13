---
task_id: NNN
task_name: short-slug
type: test
status: draft            # draft → ready → active → done | blocked | dropped
branch: ~                # `scripts/sdd start` fills in: main/NNN-short-slug
alignment: pending       # `scripts/sdd align` → pending, `align-resolve` → resolved
verify: pending          # `scripts/sdd verify` → passed | failed (gate for start/implement)
created: YYYY-MM-DD
updated: YYYY-MM-DD
target_version: X.Y.Z
blocked_reason: ~
dropped_reason: ~
---

# [TEST-NNN] {Title}

> Don't repeat CLAUDE.md; reference it only. Write any deviations in §9.

## 1. Goal
<!-- What is being tested and why? -->

## 2. Scope
### Included
-
### Excluded
-

## 3. Units Under Test
- [ ] `XViewModel`
- [ ] `XUseCase`
- [ ] `XRepository`

## 4. Test Scenarios
- [ ] Happy path:
- [ ] Error path:
- [ ] Edge case:

## 5. Task List
<!-- Applied one by one with `./scripts/sdd implement <spec> T1` -->
- [ ] T1 –
- [ ] T2 –

## 6. Acceptance Criteria
- [ ] Target coverage met
- [ ] `./gradlew checkCodeQuality` green
- [ ] Behaviour unchanged (tests only added)

## 7. Test Plan
- [ ] Unit: `XViewModelTest` happy path
- [ ] Unit: `XViewModelTest` error path
- [ ] Unit: `XUseCaseTest`

## 8. Open Decisions (Alignment)
<!-- `./scripts/sdd align` writes the questions here and fills in your answers.
     Format (parsed by the script):
     1. **Question:** <question>
        - **Answer:** <answer> -->

## 9. Deviations from CLAUDE.md
None

## 10. Changelog
| Date | Status | Change |
|------|--------|--------|
| YYYY-MM-DD | draft | Test spec created |