---
task_id: NNN
task_name: short-slug
type: refactor
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

# [REF-NNN] {Title}

> Don't repeat CLAUDE.md; reference it only. Write any deviations in §9.

> A test safety net is required for refactors; if coverage is insufficient, open a test spec first.

## 1. Motivation
<!-- Technical debt / performance / readability -->

## 2. Current State

## 3. Target State

## 4. Affected Files
- [ ] `path/to/file.*`

## 5. Breaking Changes
- [ ] None
- [ ] Yes:

## 6. Task List
- [ ] T1 –
- [ ] T2 –

## 7. Acceptance Criteria
- [ ] Existing tests pass (behaviour preserved)
- [ ] New structure conforms to CLAUDE.md

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
| YYYY-MM-DD | draft | Refactor planned |