#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: install.sh [--force|--update] <target-repository>

  (no flag)   First install. Stops rather than overwrite any existing file.
  --update    Refresh the kit (scripts, templates, guide, generated agents) and
              KEEP the files you are expected to customise:
                CLAUDE.md  .claude/settings.json  .claude/agents/
  --force     Overwrite everything in the payload, customised files included.
EOF
}

force=0
update=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)   force=1; shift ;;
    --update)  update=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --)        shift; break ;;
    -*)        echo "Unknown option: $1" >&2; usage; exit 2 ;;
    *)         break ;;
  esac
done

if [ "$force" -eq 1 ] && [ "$update" -eq 1 ]; then
  echo "--force and --update cannot be combined: --update exists to protect exactly" >&2
  echo "the files --force replaces." >&2
  exit 2
fi

target="${1:-}"
if [ -z "$target" ] || [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

artifact_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="$(cd "$target" 2>/dev/null && pwd)" || {
  echo "Target repository does not exist: $target" >&2
  exit 1
}

# Paths the installing project is expected to make its own: CLAUDE.md carries
# that project's architecture rules, the settings' allow/ask lists are local
# policy, and .claude/agents/ is the hand-edited single source. --update leaves
# these alone once they exist; --force replaces them like anything else.
user_owned=" CLAUDE.md .claude/settings.json .claude/agents/ "
is_user_owned() {
  case "$user_owned" in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

gitignore="$target/.gitignore"
touch "$gitignore"
while IFS= read -r rule || [ -n "$rule" ]; do
  case "$rule" in
    ""|\#*) continue ;;
  esac
  if ! grep -Fxq "$rule" "$gitignore"; then
    printf '%s\n' "$rule" >> "$gitignore"
  fi
done < "$artifact_dir/gitignore.sdd"

kept=0
while IFS= read -r path || [ -n "$path" ]; do
  case "$path" in
    ""|\#*) continue ;;
  esac

  source="$artifact_dir/payload/$path"
  destination="$target/$path"
  if [ ! -e "$source" ]; then
    echo "Artifact payload is incomplete: $path" >&2
    exit 1
  fi
  if [ -e "$destination" ]; then
    if [ "$update" -eq 1 ] && is_user_owned "$path"; then
      echo "kept (yours): $path"
      kept=$((kept + 1))
      continue
    fi
    if [ "$force" -ne 1 ] && [ "$update" -ne 1 ]; then
      echo "Refusing to overwrite existing file: $path" >&2
      echo "Re-run with --force only if replacing this file is intentional." >&2
      echo "To refresh the kit but keep your CLAUDE.md, .claude/settings.json and" >&2
      echo ".claude/agents/, use --update instead." >&2
      exit 1
    fi
  fi

  # Directories are copied by their CONTENTS ('src/.' → 'dst'), which means the
  # same thing to BSD cp (macOS) and GNU cp (Linux). 'cp -R src/ dst' does not:
  # with an existing dst, GNU cp would nest it as 'dst/agents'.
  if [ -d "$source" ]; then
    mkdir -p "$destination"
    cp -pR "$source/." "$destination/"
  else
    mkdir -p "$(dirname "$destination")"
    cp -p "$source" "$destination"
  fi
done < "$artifact_dir/manifest.txt"

chmod +x "$target/scripts/sdd"
if [ "$update" -eq 1 ]; then
  echo "Updated SDD artifact in $target ($kept customised path(s) kept)"
  echo "Compare them against the new payload if the kit's rules changed:"
  echo "  diff -ru $target/.claude/agents $artifact_dir/payload/.claude/agents"
else
  echo "Installed SDD artifact into $target"
fi
