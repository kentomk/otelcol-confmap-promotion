#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
cd "$project_root"

scripts/quality-gate.sh

mapfile -d '' tracked_paths < <(git ls-files -z)
(( ${#tracked_paths[@]} >= 9 && ${#tracked_paths[@]} <= 200 )) || {
  printf 'publisher smoke: tracked file count is outside 9..200: %d\n' "${#tracked_paths[@]}" >&2
  exit 1
}

test_path_count=0
payload_bytes=0
max_file_bytes=0
for path in "${tracked_paths[@]}"; do
  [[ "$path" != /* && "$path" != *\\* && "/$path/" != */../* ]] || {
    printf 'publisher smoke: unsafe tracked path: %s\n' "$path" >&2
    exit 1
  }
  [[ -f "$path" && ! -L "$path" ]] || {
    printf 'publisher smoke: non-regular tracked path: %s\n' "$path" >&2
    exit 1
  }
  file_bytes=$(stat -c '%s' -- "$path")
  payload_bytes=$((payload_bytes + file_bytes))
  if (( file_bytes > max_file_bytes )); then
    max_file_bytes=$file_bytes
  fi
  if [[ "$path" =~ (^|/)(tests?|spec|__tests__)(/|$)|\.(test|spec)\. ]]; then
    test_path_count=$((test_path_count + 1))
  fi
done

(( test_path_count > 0 )) || {
  printf '%s\n' 'publisher smoke: no tracked path matches the publisher test-path contract' >&2
  exit 1
}
(( max_file_bytes <= 262144 )) || {
  printf 'publisher smoke: per-file payload limit exceeded: %d > 262144 bytes\n' "$max_file_bytes" >&2
  exit 1
}
(( payload_bytes <= 3145728 )) || {
  printf 'publisher smoke: total payload limit exceeded: %d > 3145728 bytes\n' "$payload_bytes" >&2
  exit 1
}

LC_ALL=C head -n 1 README.md | grep -Eq '^# [ -~]+$'
grep -Eq '^##+ Quick start[[:space:]]*$' README.md
grep -Eq '^##+ Install([,[:space:]]|$)' README.md
grep -F 'Matsuki Kento' README.md >/dev/null
grep -F '@kentomk' README.md >/dev/null
grep -F 'automated AI agent' README.md >/dev/null
jq -e '
  .schemaVersion == 1 and
  .candidateId == "20260720T061437Z-0e92" and
  (.createdBy | contains("Matsuki Kento")) and
  (.createdBy | contains("@kentomk")) and
  (.createdBy | test("AI|automated"; "i"))
' .kento-oss.json >/dev/null

printf 'publisher smoke passed: files=%d test_paths=%d payload_bytes=%d max_file_bytes=%d\n' \
  "${#tracked_paths[@]}" "$test_path_count" "$payload_bytes" "$max_file_bytes"
