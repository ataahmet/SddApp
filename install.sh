#!/usr/bin/env bash
# SDD installer — adds SDD to the project you run it in. Nothing is installed
# system-wide: no PATH changes, no files outside the project.
#
#   cd your-project
#   curl -fsSL https://raw.githubusercontent.com/ataahmet/SddApp/main/install.sh | bash
#
# Options (after `bash -s --`, or as the matching environment variables):
#   --update          refresh the kit and KEEP the files you customise:
#                       CLAUDE.md  .claude/settings.json  .claude/agents/
#                       scripts/lib/deny-list.txt
#   --force           overwrite everything, customised files included
#   --version <v>     SDD_VERSION      latest (default) | 0.2.0 | main (a branch, built from source)
#   --dir <path>      SDD_PROJECT_DIR  project to install into (default: the git repository you are in)
#   SDD_REPO          GitHub repository to install from (default: ataahmet/SddApp)
#   SDD_TARBALL       a URL or local path to install from instead (mirrors, testing)
#
# e.g. curl -fsSL …/install.sh | bash -s -- --update
#
# Inside a project that has SDD, ./scripts/sdd self-update runs this with --update.
# Everything is wrapped in main(), called on the last line, so a download cut
# off halfway through `curl | bash` runs nothing at all.
set -euo pipefail

SDD_WORK_DIR=""
say()  { printf '%s\n' "$*"; }
warn() { printf '! %s\n' "$*" >&2; }
die()  { printf '✗ %s\n' "$*" >&2; exit 1; }

# Printed from here rather than read back from the file's header: under
# `curl | bash` there is no file to read.
usage() {
  cat <<'EOF'
SDD installer — adds SDD to the git repository you run it in. Nothing is
installed system-wide.

  cd your-project
  curl -fsSL https://raw.githubusercontent.com/ataahmet/SddApp/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/ataahmet/SddApp/main/install.sh | bash -s -- <options>

Options:
  --update        refresh the kit and KEEP the files you customise:
                    CLAUDE.md  .claude/settings.json  .claude/agents/
                    scripts/lib/deny-list.txt
  --force         overwrite everything, customised files included
  --version <v>   latest (default) | 0.2.0 | main (a branch, built from source)
  --dir <path>    install into this repository instead of the one you are in
  -h, --help      this text

Environment: SDD_VERSION, SDD_PROJECT_DIR (as --version, --dir), SDD_REPO
(default ataahmet/SddApp), SDD_TARBALL (a URL or path to install from instead).

Inside a project that has SDD:  ./scripts/sdd self-update
EOF
}

download() { # <url-or-path> <file>
  case "$1" in
    http://*|https://*|file://*)
      if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 2 -o "$2" "$1"
      elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
      else
        die "curl or wget is required."
      fi
      ;;
    *) cp "$1" "$2" ;;
  esac
}

sha256_of() { # <file>
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    return 1
  fi
}

# Verifies <file> against <url>.sha256. Every release ships one, and refusing to
# install without it is what makes piping `latest` into bash reasonable. For an
# SDD_TARBALL override the checksum is optional: checked when it is there.
verify_checksum() { # <file> <tarball-url> <required: 1|0>
  local file="$1" url="$2" required="$3" expected actual
  if [ "${SDD_SKIP_CHECKSUM:-0}" = "1" ]; then
    warn "SDD_SKIP_CHECKSUM=1 — not verifying the download."
    return 0
  fi
  if ! download "$url.sha256" "$file.sha256" 2>/dev/null; then
    [ "$required" = "1" ] && die "No checksum published at $url.sha256 (set SDD_SKIP_CHECKSUM=1 to install anyway)."
    warn "No checksum next to $url — not verified."
    return 0
  fi
  expected="$(awk '{print $1; exit}' "$file.sha256")"
  actual="$(sha256_of "$file")" || { warn "No sha256sum/shasum found — cannot verify the download."; return 0; }
  [ "$expected" = "$actual" ] || die "Checksum mismatch for $url (expected $expected, got $actual)."
}

# Every file the manifest installs, one per line: "<manifest entry><TAB><path>".
# A directory entry ('.claude/agents/') expands to the files inside it, so the
# install merges into an existing directory and only stops on a real collision.
payload_files() { # <kit-dir>
  local kit="$1" entry src f
  while IFS= read -r entry || [ -n "$entry" ]; do
    case "$entry" in ""|\#*) continue ;; esac
    src="$kit/payload/${entry%/}"
    if [ -d "$src" ]; then
      ( cd "$src" && find . -type f ! -name '.DS_Store' ) | sed 's|^\./||' | sort \
        | while IFS= read -r f; do printf '%s\t%s/%s\n' "$entry" "${entry%/}" "$f"; done
    elif [ -f "$src" ]; then
      printf '%s\t%s\n' "$entry" "$entry"
    else
      printf '%s\t\n' "$entry"   # empty path = missing from the kit
    fi
  done < "$kit/manifest.txt"
}

# Replaces <dst> by renaming a finished copy over it. A plain cp would rewrite
# the file in place, which corrupts a running scripts/sdd (bash reads a script
# as it executes it) — and `./scripts/sdd self-update` runs this very installer.
install_file() { # <src> <dst>
  mkdir -p "$(dirname "$2")"
  cp -p "$1" "$2.sdd-new.$$"
  mv -f "$2.sdd-new.$$" "$2"
}

main() {
  local version="${SDD_VERSION:-latest}"
  local target="${SDD_PROJECT_DIR:-}"
  local repo="${SDD_REPO:-ataahmet/SddApp}"
  local tarball="${SDD_TARBALL:-}"
  local force=0 update=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --update)  update=1; shift ;;
      --force)   force=1; shift ;;
      --version) version="${2:?--version needs a value}"; shift 2 ;;
      --dir)     target="${2:?--dir needs a path}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
  if [ "$force" -eq 1 ] && [ "$update" -eq 1 ]; then
    die "--force and --update cannot be combined: --update exists to protect exactly the files --force replaces."
  fi

  case "$(uname -s)" in
    Darwin|Linux) ;;
    *) die "SDD runs on macOS and Linux (on Windows, use WSL)." ;;
  esac
  command -v git >/dev/null 2>&1 || die "git is required."
  command -v tar >/dev/null 2>&1 || die "tar is required."

  # The project: the git repository you are in, unless --dir says otherwise.
  # Refusing to guess outside git keeps a stray `curl | bash` in ~ or / from
  # scattering CLAUDE.md and .claude/ there.
  local from_git=0
  if [ -z "$target" ]; then
    from_git=1
    target="$(git rev-parse --show-toplevel 2>/dev/null)" \
      || die "Not inside a git repository. cd into your project first (or git init it), or pass --dir <project>."
  fi
  target="$(cd "$target" 2>/dev/null && pwd)" || die "Project directory does not exist: $target"
  local here
  here="$(pwd -P)"
  case "$target" in
    "$HOME"|"$(cd "$HOME" 2>/dev/null && pwd -P)"|/)
      # Run from a folder inside a home directory that is itself a git
      # repository: git hands back ~ as the project. Say so, rather than
      # telling someone who is already in their project to cd into it.
      if [ "$from_git" -eq 1 ] && [ "$here" != "$target" ]; then
        die "$here is not a git repository of its own: git found the repository at $target
  (your home directory), so SDD would be installed there. Make this folder its own
  repository, then run the command again:
    git init
  $target/.git is probably left over from a 'git init' run in your home directory;
  check it with: git -C ~ log --oneline -3"
      fi
      die "Refusing to install into $target — cd into your project first."
      ;;
  esac
  git -C "$target" rev-parse --git-dir >/dev/null 2>&1 \
    || warn "$target is not a git repository; 'sdd start' needs one (git init)."

  # Where the kit comes from: a release tag (or `latest`) downloads the archive
  # the release workflow attached; anything else is a branch, downloaded as
  # source and assembled with scripts/sdd-release.
  local url mode ref
  if [ -n "$tarball" ]; then
    url="$tarball"; mode="auto"; ref=""
  elif [ "$version" = "latest" ]; then
    url="https://github.com/$repo/releases/latest/download/sdd.tar.gz"; mode="release"; ref=""
  else
    case "$version" in [0-9]*) version="v$version" ;; esac
    ref="$version"
    case "$version" in
      v[0-9]*) url="https://github.com/$repo/releases/download/$version/sdd.tar.gz"; mode="release" ;;
      *)       url="https://github.com/$repo/archive/refs/heads/$version.tar.gz"; mode="source" ;;
    esac
  fi

  local work
  work="$(mktemp -d)"
  SDD_WORK_DIR="$work"
  trap 'rm -rf "$SDD_WORK_DIR"' EXIT

  if [ "$mode" = "auto" ]; then say "→ Downloading SDD from $url"; else say "→ Downloading SDD ($version) from $url"; fi
  if ! download "$url" "$work/kit.tar.gz"; then
    if [ "$mode" = "release" ] && [ "$version" = "latest" ]; then
      die "Could not download sdd.tar.gz from the latest release of $repo. Either there is
  no release yet, or the latest release was created by hand on GitHub and has no
  sdd.tar.gz in it: releases are built by the release workflow when a v* tag is pushed.
  Install from the main branch meanwhile:
    curl -fsSL https://raw.githubusercontent.com/$repo/main/install.sh | bash -s -- --version main"
    fi
    die "Download failed: $url"
  fi
  case "$mode" in
    release) verify_checksum "$work/kit.tar.gz" "$url" 1 ;;
    auto)    verify_checksum "$work/kit.tar.gz" "$url" 0 ;;
  esac

  mkdir -p "$work/x"
  tar -xzf "$work/kit.tar.gz" -C "$work/x"
  local top kit="$work/kit"
  top="$(find "$work/x" -mindepth 1 -maxdepth 1 -type d | head -1)"
  [ -n "$top" ] || die "The downloaded archive is empty."
  if [ -f "$top/manifest.txt" ] && [ -d "$top/payload" ]; then
    mv "$top" "$kit"                                                            # release
  elif [ -f "$top/scripts/sdd-release" ]; then                                 # source
    # Stamp a branch build as <VERSION>-dev+<branch>.<commit>: GitHub's archive
    # carries the commit id in its tar header, which git can read back.
    local base commit
    base="$(tr -d '[:space:]' < "$top/VERSION" 2>/dev/null || true)"
    commit="$(gzip -dc "$work/kit.tar.gz" | git get-tar-commit-id 2>/dev/null || true)"
    bash "$top/scripts/sdd-release" --stage "$kit" \
      --version "${base:-0.0.0}-dev+$(printf '%s' "$version" | tr '/' '-')${commit:+.${commit:0:7}}" >/dev/null
  else
    die "The archive is neither an SDD release nor an SddApp source tree."
  fi
  local kit_version
  kit_version="$(tr -d '[:space:]' < "$kit/VERSION")"
  [ -n "$ref" ] || ref="v$kit_version"

  local previous=""
  [ -f "$target/scripts/lib/VERSION" ] && previous="$(tr -d '[:space:]' < "$target/scripts/lib/VERSION")"

  # Pass 1 — plan and check everything before writing a single file.
  local plan entry rel missing="" conflicts=""
  plan="$work/plan"
  payload_files "$kit" > "$plan"
  while IFS="$(printf '\t')" read -r entry rel; do
    if [ -z "$rel" ]; then missing="$missing $entry"; continue; fi
    [ -e "$target/$rel" ] || continue
    [ "$force" -eq 1 ] || [ "$update" -eq 1 ] || conflicts="$conflicts
  $rel"
  done < "$plan"
  [ -z "$missing" ] || die "The downloaded kit is incomplete, missing:$missing"
  if [ -n "$conflicts" ]; then
    printf '✗ Nothing was written: these files already exist in %s:%s\n\n' "$target" "$conflicts" >&2
    printf '  SDD already installed?  re-run with --update  (refresh the kit, keep CLAUDE.md, .claude/settings.json, .claude/agents/, deny-list.txt)\n' >&2
    printf '  Replace them all:       re-run with --force\n' >&2
    printf '  Or move your own CLAUDE.md aside, install, and merge it back.\n' >&2
    printf '\n  e.g. curl -fsSL https://raw.githubusercontent.com/%s/main/install.sh | bash -s -- --update\n' "$repo" >&2
    exit 1
  fi

  # Pass 2 — copy. User-owned: the files a project is expected to make its own
  # (CLAUDE.md carries its architecture rules, settings.json its local policy,
  # .claude/agents/ the hand-edited agent source, deny-list.txt the files no
  # agent may read); --update leaves them alone but still adds agents that are
  # new in the kit.
  local user_owned=" CLAUDE.md .claude/settings.json .claude/agents/ scripts/lib/deny-list.txt " owned
  local n_new=0 n_upd=0 n_kept=0 differs=""
  while IFS="$(printf '\t')" read -r entry rel; do
    case "$user_owned" in
      *" $entry "*) owned=1 ;;
      *) owned=0 ;;
    esac
    if [ -e "$target/$rel" ]; then
      if [ "$update" -eq 1 ] && [ "$owned" -eq 1 ]; then
        n_kept=$((n_kept + 1))
        cmp -s "$kit/payload/$rel" "$target/$rel" || differs="$differs $rel"
        continue
      fi
      n_upd=$((n_upd + 1))
    else
      n_new=$((n_new + 1))
    fi
    install_file "$kit/payload/$rel" "$target/$rel"
  done < "$plan"
  chmod +x "$target/scripts/sdd"
  printf '%s\n' "$kit_version" > "$target/scripts/lib/VERSION"

  # .github/agents/ is generated from .claude/agents/, and the deny array of
  # .claude/settings.json from deny-list.txt. Pass 2 copied the kit's generated
  # copies, but the sources may be the project's own (kept by --update, or its
  # own agents beside the kit's), so regenerate them from what is actually there.
  local sync_out sync_ok=1
  sync_out="$(bash "$target/scripts/sdd" sync-agents 2>&1)" || sync_ok=0

  local rule gitignore="$target/.gitignore"
  touch "$gitignore"
  while IFS= read -r rule || [ -n "$rule" ]; do
    case "$rule" in ""|\#*) continue ;; esac
    grep -Fxq "$rule" "$gitignore" || printf '%s\n' "$rule" >> "$gitignore"
  done < "$kit/gitignore.sdd"

  if [ -z "$previous" ] || [ "$update$force" = "00" ]; then
    say "✓ SDD $kit_version installed in $target — $n_new added, $n_upd replaced, $n_kept kept"
  elif [ "$previous" = "$kit_version" ]; then
    say "✓ SDD $kit_version — already up to date; kit files refreshed ($n_new added, $n_upd replaced, $n_kept kept)"
  else
    say "✓ SDD updated $previous → $kit_version in $target — $n_new added, $n_upd replaced, $n_kept kept"
  fi

  if [ "$sync_ok" -eq 0 ]; then
    say ""
    warn "Could not regenerate .github/agents/ from .claude/agents/, so Copilot may run"
    warn "different agent rules than Claude. Fix the cause and run ./scripts/sdd sync-agents:"
    printf '%s\n' "$sync_out" | grep -v '^→\|^  ·' | sed 's/^/    /' >&2
  elif [ "$update" -eq 1 ]; then
    say "  .github/agents/ and the settings' deny list regenerated from your .claude/agents/ and deny-list.txt"
  fi

  if [ -n "$differs" ]; then
    say ""
    say "Kept your version of these files; the kit's version differs:"
    for rel in $differs; do
      if [ "$mode" = "auto" ]; then say "  $rel"; else say "  $rel  → https://github.com/$repo/blob/$ref/$rel"; fi
    done
    say "Merge what you need, then run ./scripts/sdd sync-agents if you changed .claude/agents/."
  fi

  if ! command -v claude >/dev/null 2>&1 && ! command -v copilot >/dev/null 2>&1; then
    say ""
    say "No agent CLI found. SDD drives Claude Code or GitHub Copilot CLI — install one:"
    say "  curl -fsSL https://claude.ai/install.sh | bash      # Claude Code"
    say "  npm install -g @github/copilot                      # Copilot CLI"
  fi

  if [ "$update" -eq 0 ]; then
    say ""
    say "Next:"
    say "  1. Adapt CLAUDE.md to this project (see SDD-README.md)"
    say "  2. ./scripts/sdd new feature \"My first feature\""
    say "  3. git add CLAUDE.md SDD-README.md .claude .github scripts specs .gitignore"
  fi
}

main "$@"
