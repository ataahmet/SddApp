---
task_id: NNN
task_name: short-slug
type: bug
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

# [BUG-NNN] {Title}

> Don't repeat CLAUDE.md; reference it only. Write any deviations in §10.

## 1. Problem
<!-- Expected vs actual behaviour -->

## 2. Reproduction Steps
1.
2.
3.

## 3. Root Cause
<!-- Which code/flow is responsible? -->

## 4. Affected Files
- [ ] `path/to/file.*`

## 5. Fix Approach

## 6. Task List
- [ ] T1 –
- [ ] T2 –

## 7. Acceptance Criteria
- [ ] Bug cannot be reproduced
- [ ] Regression test added

## 8. Test Plan
- [ ] Unit: Regression test
- [ ] Manual: Repeat reproduction steps

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
| YYYY-MM-DD | draft | Bug reported |