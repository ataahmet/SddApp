#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--force] <target-repository>\n' "$0" >&2
}

force=0
if [ "${1:-}" = "--force" ]; then
  force=1
  shift
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
  if [ -e "$destination" ] && [ "$force" -ne 1 ]; then
    echo "Refusing to overwrite existing file: $path" >&2
    echo "Re-run with --force only if replacing this file is intentional." >&2
    exit 1
  fi

  mkdir -p "$(dirname "$destination")"
  cp -pR "$source" "$destination"
done < "$artifact_dir/manifest.txt"

chmod +x "$target/scripts/sdd"
echo "Installed SDD artifact into $target"
