#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
clean_root=$(mktemp -d)
cleanup() {
  chmod -R u+w "$clean_root" 2>/dev/null || true
  rm -rf "$clean_root"
}
trap cleanup EXIT HUP INT TERM

git -C "$project_root" archive --format=tar HEAD | tar -xf - -C "$clean_root"
mkdir -p "$clean_root/cache" "$clean_root/modcache" "$clean_root/bin"

set +e
output=$(cd "$clean_root" && \
  GOCACHE="$clean_root/cache" \
  GOMODCACHE="$clean_root/modcache" \
  GOTOOLCHAIN=local \
  timeout 300 bash -c '
    go build -o ./bin/otelcol-confmap-promotion ./cmd/otelcol-confmap-promotion &&
    ./bin/otelcol-confmap-promotion check ./testdata/fixtures/unsafe-anonymous
  ' 2>&1)
status=$?
set -e

[ "$status" -eq 1 ] || {
  printf 'clean quickstart: expected exit 1, got %s\n%s\n' "$status" "$output" >&2
  exit 1
}
grep -Fq 'OCP001 warning testdata/fixtures/unsafe-anonymous/fixture.go:' <<< "$output"
printf '%s\n' 'clean quickstart passed: first useful output=OCP001 exit=1'
