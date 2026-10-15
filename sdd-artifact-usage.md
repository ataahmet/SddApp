# SDD Artifact

This repository is the source for the portable SDD artifact used in Android projects.
Run `scripts/sdd` to use the existing SDD workflow in this repository.

## Creating the artifact

```bash
./scripts/sdd-artifact
```

Default output:

```text
dist/sdd-artifact/
```

Custom output path:

```bash
./scripts/sdd-artifact /tmp/sdd-artifact
```

The artifact package's installation documentation is in `dist/sdd-artifact/README.md`, which is
the copy of this file inside the artifact. This document is not installed in the target project.

## Installing into another Android project

```bash
dist/sdd-artifact/install.sh /path/to/target-android-project
```

The installation adds `CLAUDE.md`, `SDD-README.md`, `.claude/`, `.github/`, `scripts/`, and
`specs/templates/` to the target project. It does not overwrite existing files by default.

To intentionally update existing SDD files:

```bash
dist/sdd-artifact/install.sh --force /path/to/target-android-project
```

The installation preserves the existing contents of the target `.gitignore` and adds missing SDD
rules:

```text
dist
specs/features
specs/bugs
specs/refactors
specs/tests
```

The installation also adds `SDD-README.md` to the target project. This file explains daily SDD
usage in the target project.
