#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

scripts/scan-tracked-secrets.sh "$project_root"

if ! command -v govulncheck >/dev/null 2>&1; then
  echo 'policy gate: govulncheck v1.6.0 is required' >&2
  exit 2
fi
scanner_version=$(govulncheck -version 2>&1 | awk '/^Scanner: / {print $2}')
if [[ "$scanner_version" != 'govulncheck@v1.6.0' ]]; then
  printf 'policy gate: expected govulncheck@v1.6.0, got %s\n' "${scanner_version:-unknown}" >&2
  exit 2
fi

if bad_uses=$(awk '
  /^[[:space:]]*uses:/ {
    ref=$0
    sub(/^.*@/, "", ref)
    sub(/[[:space:]#].*$/, "", ref)
    if (ref !~ /^[0-9a-f]{40}$/) print FILENAME ":" FNR ":" $0
  }
' .github/workflows/*.yml); [[ -n "$bad_uses" ]]; then
  printf 'policy gate: workflow action is not pinned to a full commit SHA:\n%s\n' "$bad_uses" >&2
  exit 1
fi

build_root=$(mktemp -d)
trap 'rm -rf -- "$build_root"' EXIT
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off GOWORK=off \
  go build -trimpath -buildvcs=false -o "$build_root/analyzer" ./cmd/otelcol-confmap-promotion

awk -F '\t' '!/^#/ && NF {print $1 "\t" $2}' policy/runtime-dependencies.tsv | sort >"$build_root/expected"
go version -m "$build_root/analyzer" |
  awk -F '\t' '$2 == "dep" {print $3 "\t" $4}' | sort >"$build_root/actual"
if ! cmp -s "$build_root/expected" "$build_root/actual"; then
  echo 'policy gate: embedded runtime dependency inventory changed' >&2
  diff -u "$build_root/expected" "$build_root/actual" >&2 || true
  exit 1
fi

module_cache=$(go env GOMODCACHE)
while IFS=$'\t' read -r module version license expected_hash; do
  [[ "$module" == \#* || -z "$module" ]] && continue
  if [[ "$license" != 'BSD-3-Clause' ]]; then
    printf 'policy gate: unapproved license for %s@%s\n' "$module" "$version" >&2
    exit 1
  fi
  license_file="$module_cache/$module@$version/LICENSE"
  if [[ ! -f "$license_file" ]]; then
    printf 'policy gate: missing license file for %s@%s\n' "$module" "$version" >&2
    exit 1
  fi
  actual_hash=$(sha256sum "$license_file" | awk '{print $1}')
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    printf 'policy gate: license text changed for %s@%s\n' "$module" "$version" >&2
    exit 1
  fi
done <policy/runtime-dependencies.tsv

govulncheck -mode=source -scan=symbol ./...
printf 'policy gate passed: runtime_modules=3 licenses=BSD-3-Clause workflow_pins=full-sha scanner=%s\n' "$scanner_version"
