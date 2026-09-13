# Copilot CLI instructions

@CLAUDE.md

The rules above are authoritative for this repository; do not restate or duplicate them here.

## Spec-first rule (SDD)

This repository follows Spec-Driven Development (see CLAUDE.md §9). Before writing or editing any
code:

1. Read the relevant spec under `specs/` in full.
2. Check its front matter `status`. Do not write code against a spec whose `status` is `draft` or
   `blocked`.
3. Implement only the task you were asked to implement, in the order the spec's task list defines.

If no spec covers the requested change, stop and ask for one to be created first, rather than
proceeding without it.
