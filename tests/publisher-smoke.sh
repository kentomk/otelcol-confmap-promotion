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
grep -Eq '^##+ Installation[[:space:]]*$' README.md
installation_line=$(grep -n -m 1 -E '^##+ Installation[[:space:]]*$' README.md | cut -d: -f1)
quick_start_line=$(grep -n -m 1 -E '^##+ Quick start[[:space:]]*$' README.md | cut -d: -f1)
(( installation_line < quick_start_line )) || {
  printf '%s\n' 'publisher smoke: Installation must appear before Quick start' >&2
  exit 1
}
grep -F 'go install github.com/kentomk/otelcol-confmap-promotion/cmd/otelcol-confmap-promotion@v0.1.3' README.md >/dev/null
grep -F 'Matsuki Kento' README.md >/dev/null
grep -F '@kentomk' README.md >/dev/null
grep -F 'automated AI agent' README.md >/dev/null
grep -F 'This project is published and maintained' README.md >/dev/null
grep -F 'releases/tag/v0.1.3' README.md >/dev/null
grep -F 'sha256sum --check --strict -' README.md >/dev/null
grep -F 'curl -fsSLo SHA256SUMS' README.md >/dev/null
grep -F "mkdir -p \"\$HOME/.local/bin\"" README.md >/dev/null
grep -F 'kentomk/otelcol-confmap-promotion@fda19f6c41a2e2b27c00348abafeaa4483d91abb' README.md >/dev/null
if grep -F 'kentomk/otelcol-confmap-promotion@5a20c1aea989084458c779c3ca625469809c0a12' README.md >/dev/null; then
  printf '%s\n' 'publisher smoke: README still pins the superseded public Action revision' >&2
  exit 1
fi
if grep -F 'kentomk/otelcol-confmap-promotion@7c503b5016f7e7102d1a25d06ffdf35071e5069a' README.md >/dev/null; then
  printf '%s\n' 'publisher smoke: README still pins the superseded public Action revision' >&2
  exit 1
fi
if grep -F 'kentomk/otelcol-confmap-promotion@b522cb5f92a0d696ef7c8a9ef9a4f60353e9b9dc' README.md >/dev/null; then
  printf '%s\n' 'publisher smoke: README still pins the superseded public Action revision' >&2
  exit 1
fi
grep -Fq "test -n \"\$TAG_NAME\"" .github/workflows/release.yml
tests/quickstart-contract.sh
tests/quickstart-clean.sh
tests/vettool-quickstart.sh
grep -F 'The published' SECURITY.md >/dev/null
grep -F 'v0.1.3' SECURITY.md >/dev/null
if grep -F 'not published yet' SECURITY.md >/dev/null; then
  printf '%s\n' 'publisher smoke: SECURITY.md still claims the public project is unpublished' >&2
  exit 1
fi
if grep -F 'FULL_COMMIT_SHA' README.md >/dev/null; then
  printf '%s\n' 'README still contains the Action SHA placeholder' >&2
  exit 1
fi
if grep -F 'v0.1.2' README.md >/dev/null; then
  printf '%s\n' 'publisher smoke: README still references the previous release' >&2
  exit 1
fi
if grep -F 'not published yet' README.md >/dev/null; then
  printf '%s\n' 'publisher smoke: README still claims the public project is unpublished' >&2
  exit 1
fi
jq -e '
  .schemaVersion == 1 and
  .candidateId == "20260720T061437Z-0e92" and
  (.createdBy | contains("Matsuki Kento")) and
  (.createdBy | contains("@kentomk")) and
  (.createdBy | test("AI|automated"; "i"))
' .kento-oss.json >/dev/null

printf 'publisher smoke passed: files=%d test_paths=%d payload_bytes=%d max_file_bytes=%d\n' \
  "${#tracked_paths[@]}" "$test_path_count" "$payload_bytes" "$max_file_bytes"
