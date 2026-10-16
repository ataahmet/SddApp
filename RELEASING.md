# Releasing SDD

Projects get SDD with `install.sh`, run from inside the project; each project keeps its own copy.
This repository is the source of that kit; this page is for maintainers. Users read
`kit/sdd-usage.md`, which the installer puts into their project as `SDD-README.md`.

## Versions

`VERSION` in the repository root is the single source of the version number (`X.Y.Z`). What a
project's `./scripts/sdd --version` prints tells you where its copy came from:

| Shown | Installed from |
|-------|----------------|
| `sdd 0.2.0` | the release tagged `v0.2.0` |
| `sdd 0.2.0-dev+main.3f2a9c1` | branch `main` at commit `3f2a9c1`, between releases — `VERSION` still says what the next release will be |
| `sdd 0.2.0-dev+3f2a9c1` | this repository's own checkout (`.dirty` if it has uncommitted changes) |

Bump `VERSION` as part of the release (below), not in feature work: `patch` for fixes, `minor` for
new commands or behaviour, `major` for changes that need projects to act (a renamed command, a
moved file).

## What a release is

`scripts/sdd-release` packages the kit into one archive:

```text
sdd/
  VERSION          written to <project>/scripts/lib/VERSION on install
  manifest.txt     the paths install.sh copies into the project (= kit/manifest.txt)
  gitignore.sdd    the rules it appends to the project's .gitignore
  payload/…        the files themselves
```

The files are taken from their real paths in this repository (`scripts/sdd`, `scripts/lib/`,
`.claude/`, `.github/agents/`, `specs/templates/` …), except `SDD-README.md`, which is
`kit/sdd-usage.md`, and `CLAUDE.md`, which is `kit/claude-template.md` (the repository's own
`CLAUDE.md` holds this Android project's rules and is not shipped). To ship a new file to projects,
add it to `kit/manifest.txt`.

## Publishing a version

From a clean `main`:

```bash
scripts/sdd-release bump minor        # or patch | major | 0.3.0 — writes VERSION, commits, tags v0.3.0
git push origin HEAD v0.3.0
```

`.github/workflows/release.yml` runs on the tag. It stops if the tag does not match `VERSION`, then
shellchecks the scripts, builds the archive, installs it into a fresh repository and checks that
`./scripts/sdd --version` prints exactly the new version, runs `sdd new`, `sdd list` and an
`--update`, and creates the GitHub release with:

| Asset | Used by |
|-------|---------|
| `sdd.tar.gz` + `.sha256` | `install.sh` — `releases/latest/download/sdd.tar.gz` always means the newest release |
| `install.sh` | `./scripts/sdd self-update`, so a project runs the installer that shipped with the kit it installs |

Never create a release by hand on GitHub: it gets no `sdd.tar.gz`, `install.sh` then cannot install
`latest`, and the workflow cannot publish the tag's own release over it.

Projects pick it up with `./scripts/sdd self-update` (latest) or `./scripts/sdd self-update 0.3.0`,
which reports `SDD updated 0.2.0 → 0.3.0`.

## Trying a branch

To install unreleased code, name the branch. The installer downloads the branch's source and
assembles the same kit with `scripts/sdd-release`, stamped `<VERSION>-dev+<branch>.<commit>`:

```bash
cd some-test-project
curl -fsSL https://raw.githubusercontent.com/ataahmet/SddApp/<branch>/install.sh | bash -s -- --version <branch>
```

## Trying a build locally

```bash
bash scripts/sdd-release --version v0.0.0-test --out /tmp/sdd-dist
cd some-test-project
SDD_TARBALL=/tmp/sdd-dist/sdd.tar.gz bash /path/to/SddApp/install.sh
```
