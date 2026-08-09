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
mkdir -p "$clean_root/bin" "$clean_root/cache" "$clean_root/modcache"

set +e
output=$(cd "$clean_root" && \
  timeout 300 env GOCACHE="$clean_root/cache" GOMODCACHE="$clean_root/modcache" GOTOOLCHAIN=local \
    go build -o ./bin/otelcol-confmap-promotion-vet ./cmd/otelcol-confmap-promotion-vet && \
  timeout 300 env GOCACHE="$clean_root/cache" GOMODCACHE="$clean_root/modcache" GOPROXY=off GOTOOLCHAIN=local \
    go vet -vettool="$(pwd)/bin/otelcol-confmap-promotion-vet" ./testdata/fixtures/unsafe-anonymous 2>&1)
status=$?
set -e

[ "$status" -eq 1 ] || {
  printf 'vettool quickstart: expected exit 1, got %s\n%s\n' "$status" "$output" >&2
  exit 1
}
grep -Fq 'OCP001' <<< "$output"
printf '%s\n' 'vettool quickstart passed: first useful output=OCP001 exit=1'
