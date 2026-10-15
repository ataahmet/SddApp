# Releasing SDD

Projects get SDD with `install.sh`, run from inside the project; each project keeps its own copy.
This repository is the source of that kit; this page is for maintainers. Users read
`artifact/sdd-usage.md`, which the installer puts into their project as `SDD-README.md`.

## What a release is

`scripts/sdd-release` packages the kit into one archive:

```text
sdd/
  VERSION          written to <project>/scripts/lib/VERSION on install
  manifest.txt     the paths install.sh copies into the project (= artifact/manifest.txt)
  gitignore.sdd    the rules it appends to the project's .gitignore
  payload/…        the files themselves
```

The files are taken from their real paths in this repository (`scripts/sdd`, `scripts/lib/`,
`CLAUDE.md`, `.claude/`, `.github/agents/`, `specs/templates/` …), except `SDD-README.md`, which is
`artifact/sdd-usage.md`. To ship a new file to projects, add it to `artifact/manifest.txt`.

## Publishing a version

```bash
git tag v0.2.0
git push origin v0.2.0
```

`.github/workflows/release.yml` then shellchecks the scripts, builds the archive, installs it into a
fresh repository and runs `sdd new`, `sdd list` and an `--update` there, and creates the GitHub
release with:

| Asset | Used by |
|-------|---------|
| `sdd.tar.gz` + `.sha256` | `install.sh` — `releases/latest/download/sdd.tar.gz` always means the newest release |
| `sdd-v0.2.0.tar.gz` + `.sha256` | pinned downloads |

Projects pick it up with `./scripts/sdd self-update`.

## Before the first release, or to try a branch

Without a release `latest` has nothing to download; install from a branch instead. The installer
downloads the branch's source and assembles the same kit with `scripts/sdd-release`:

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
