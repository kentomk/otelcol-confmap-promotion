#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
cd "$project_root"

[[ $(uname -s) == Linux && $(uname -m) == aarch64 ]] || {
  printf '%s\n' 'publisher gate requires the Linux aarch64 broker host' >&2
  exit 1
}
[[ $(go env GOVERSION) == go1.26.5 ]] || {
  printf '%s\n' 'publisher gate requires Go 1.26.5' >&2
  exit 1
}
[[ $(zig version) == 0.16.0 ]] || {
  printf '%s\n' 'publisher gate requires Zig 0.16.0' >&2
  exit 1
}

for tool in actionlint jq shellcheck yq; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'publisher gate requires %s\n' "$tool" >&2
    exit 1
  }
done

go_path=$(go env GOPATH)
[[ -n "$go_path" && "$go_path" == /* ]] || {
  printf '%s\n' 'publisher gate requires an absolute Go workspace path' >&2
  exit 1
}
scanner="$go_path/bin/govulncheck"
[[ -x "$scanner" ]] || {
  printf '%s\n' 'publisher gate requires govulncheck v1.6.0 in the Go workspace bin directory' >&2
  exit 1
}

scanner_dir=$(dirname -- "$scanner")
export PATH="$scanner_dir:$PATH"
tests/publisher-smoke.sh
