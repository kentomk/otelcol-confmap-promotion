#!/usr/bin/env bash
set -euo pipefail

scan_root=${1:-.}
scan_root=$(cd -- "$scan_root" && pwd)
git -C "$scan_root" rev-parse --is-inside-work-tree >/dev/null

private_key_marker='-----BEGIN '"PRIVATE KEY"'-----'
patterns=(
  'AKIA[0-9A-Z]{16}'
  'gh[pousr]_[A-Za-z0-9]{36,}'
  'github_pat_[A-Za-z0-9_]{40,}'
  'https?://[^/@[:space:]]+:[^/@[:space:]]+@'
)

failed=0
while IFS= read -r -d '' file; do
  path="$scan_root/$file"
  if [[ ! -f "$path" ]] || ! LC_ALL=C grep -Iq . "$path"; then
    continue
  fi
  if LC_ALL=C grep -Fq -- "$private_key_marker" "$path"; then
    printf 'secret policy: private key marker in %s\n' "$file" >&2
    failed=1
  fi
  for pattern in "${patterns[@]}"; do
    if LC_ALL=C grep -Eq -- "$pattern" "$path"; then
      printf 'secret policy: credential-like value in %s\n' "$file" >&2
      failed=1
      break
    fi
  done
done < <(git -C "$scan_root" ls-files -z)

exit "$failed"
