---
task_id: NNN
task_name: short-slug
type: feature
status: draft            # draft → ready → active → done | blocked | dropped
branch: ~                # `scripts/sdd start` fills in: main/NNN-short-slug
alignment: pending       # `scripts/sdd align` → pending, `align-resolve` → resolved
verify: pending          # `scripts/sdd verify` → passed | failed (gate for start/implement)
critique: pending        # `scripts/sdd critique` → converged | needs_user | max_rounds | skipped
critique_score: ~        # last reviewer score, 0-10
critique_rounds: 0       # rounds spent in the critique-to-action loop
created: YYYY-MM-DD
updated: YYYY-MM-DD
target_version: X.Y.Z
blocked_reason: ~        # only when status=blocked
dropped_reason: ~        # only when status=dropped
---

# [FEAT-NNN] {Title}

> Don't repeat CLAUDE.md; reference it only. Write any deviations in §10.

## 1. Goal
<!-- Single paragraph: what does it do, why is it needed? -->

## 2. Scope
### Included
-
### Excluded
-

## 3. Affected Layers
- [ ] `data/` — Repository, DataSource, Request/Response
- [ ] `domain/` — UseCase, Observer, ViewEntity
- [ ] `presentation/` — ViewModel, Activity/Fragment, Layout
- [ ] `di/` — Hilt Module

## 4. Contracts
```kotlin
// Request Path :<Name>RequestPath
// Request: <Name>Request.*
// Response: <Name>Response.* : ViewEntityConvertible<XViewEntity>
```

## 5. ViewEntity

## 6. Task List
<!-- Applied one by one with `./scripts/sdd implement <spec> T1` -->
- [ ] T1 –
- [ ] T2 –
- [ ] T3 –

## 7. Acceptance Criteria
- [ ]
- [ ]

## 8. Test Plan
- [ ] Unit: `XViewModelTest` happy path
- [ ] Unit: `XViewModelTest` error path
- [ ] Unit: `XUseCaseTest`
- [ ] Manual:

## 9. Open Decisions (Alignment)
<!-- `./scripts/sdd align` writes the questions here and fills in your answers.
     Format (parsed by the script):
     1. **Question:** <question>
        - **Answer:** <answer> -->

## 10. Deviations from CLAUDE.md
None

## 11. Changelog
| Date | Status | Change |
|------|--------|--------|
| YYYY-MM-DD | draft | Spec created |

## Critique Log
<!-- `./scripts/sdd critique` appends one row per round. Reports: ./critique/round-N.md -->

| Round | Score | Critical | Major | Verdict | Report |
|-------|-------|----------|-------|---------|--------|
